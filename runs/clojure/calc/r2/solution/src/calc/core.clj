(ns calc.core
  "Line-oriented evaluator for signed 64-bit integer expressions.

  Grammar:
    expr    := term    (('+' | '-') term)*
    term    := unary   (('*' | '/' | '%') unary)*
    unary   := '-' unary | primary
    primary := NUMBER | '(' expr ')'"
  (:import (java.io BufferedReader InputStreamReader PrintWriter
                    BufferedWriter OutputStreamWriter)
           (java.nio.charset StandardCharsets))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn- fail
  "Signals that the current line cannot be evaluated."
  [reason]
  (throw (ex-info reason {::error true})))

;; ---------------------------------------------------------------------------
;; Lexing

(defn- whitespace? [c] (or (= c \space) (= c \tab)))
(defn- digit? [c] (<= (int \0) (int c) (int \9)))

(defn- parse-literal ^long [^String digits]
  (try
    (Long/parseLong digits)
    (catch NumberFormatException _
      (fail "integer literal out of range"))))

(defn tokenize
  "Splits a line into tokens: longs for numbers, characters for operators
  and parentheses. Throws on any character outside the grammar."
  [^String s]
  (let [n (.length s)]
    (loop [i 0, tokens (transient [])]
      (if (>= i n)
        (persistent! tokens)
        (let [c (.charAt s i)]
          (cond
            (whitespace? c) (recur (inc i) tokens)
            (digit? c) (let [end (long (loop [j (inc i)]
                                         (if (and (< j n) (digit? (.charAt s j)))
                                           (recur (inc j))
                                           j)))]
                         (recur end (conj! tokens (parse-literal (subs s i end)))))
            (#{\+ \- \* \/ \% \( \)} c) (recur (inc i) (conj! tokens c))
            :else (fail (str "unexpected character " (pr-str c)))))))))

;; ---------------------------------------------------------------------------
;; Checked 64-bit arithmetic

(defn- checked-quot ^long [^long a ^long b]
  (cond
    (zero? b) (fail "division by zero")
    (and (= a Long/MIN_VALUE) (= b -1)) (fail "overflow")
    :else (quot a b)))

(defn- checked-rem ^long [^long a ^long b]
  (if (zero? b)
    (fail "division by zero")
    (rem a b)))

(def ^:private binary-ops
  {\+ (fn [^long a ^long b] (Math/addExact a b))
   \- (fn [^long a ^long b] (Math/subtractExact a b))
   \* (fn [^long a ^long b] (Math/multiplyExact a b))
   \/ checked-quot
   \% checked-rem})

;; ---------------------------------------------------------------------------
;; Recursive-descent parser/evaluator.
;; Each rule takes the token vector and a position and returns [value pos].

(declare parse-expr)

(defn- parse-primary [tokens ^long pos]
  (let [t (get tokens pos)]
    (cond
      (int? t) [t (inc pos)]
      (= t \() (let [[v p] (parse-expr tokens (inc pos))]
                 (if (= (get tokens p) \))
                   [v (inc (long p))]
                   (fail "expected )")))
      :else (fail "expected operand"))))

(defn- parse-unary [tokens ^long pos]
  (if (= (get tokens pos) \-)
    (let [[v p] (parse-unary tokens (inc pos))]
      [(Math/negateExact (long v)) p])
    (parse-primary tokens pos)))

(defn- left-assoc
  "Builds a parser for a left-associative chain of `operand` joined by any
  operator in `ops`."
  [operand ops]
  (fn [tokens pos]
    (let [[v p] (operand tokens pos)]
      (loop [acc v, p p]
        (let [op (get tokens p)]
          (if (contains? ops op)
            (let [[rhs p'] (operand tokens (inc (long p)))]
              (recur ((binary-ops op) acc rhs) p'))
            [acc p]))))))

(def ^:private parse-term (left-assoc parse-unary #{\* \/ \%}))
(def ^:private parse-expr* (left-assoc parse-term #{\+ \-}))

(defn- parse-expr [tokens pos] (parse-expr* tokens pos))

(defn evaluate
  "Evaluates an expression string, returning its value as a long.
  Throws ex-info (syntax, division by zero, literal overflow) or
  ArithmeticException (arithmetic overflow) on failure."
  ^long [s]
  (let [tokens (tokenize s)
        [v p] (parse-expr tokens 0)]
    (if (= p (count tokens))
      v
      (fail "unexpected trailing input"))))

(defn eval-line
  "Returns the output for one input line: the value as a string, \"error\",
  or nil for a blank line."
  [^String line]
  (when-not (every? whitespace? line)
    (try
      (str (evaluate line))
      (catch ArithmeticException _ "error")
      (catch clojure.lang.ExceptionInfo e
        (if (::error (ex-data e)) "error" (throw e))))))

(defn run
  "Reads expressions from stdin line by line and writes results to stdout."
  []
  (let [in (BufferedReader. (InputStreamReader. System/in StandardCharsets/ISO_8859_1)
                            65536)
        out (PrintWriter. (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1)
                                           65536)
                          false)]
    (doseq [line (line-seq in)]
      (when-let [result (eval-line line)]
        (.print out ^String result)
        (.print out \newline)))
    (.flush out)))

(defn -main [& _]
  ;; Deeply nested input recurses deeply; run on a thread with a large stack.
  (let [t (Thread. nil ^Runnable run "calc" (* 1024 1024 1024))]
    (.start t)
    (.join t))
  (shutdown-agents)
  (System/exit 0))
