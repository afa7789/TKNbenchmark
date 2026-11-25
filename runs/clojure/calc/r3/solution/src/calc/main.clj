(ns calc.main
  "Line-oriented evaluator for signed 64-bit integer expressions.

  Grammar:
    expr    := term    (('+' | '-') term)*
    term    := unary   (('*' | '/' | '%') unary)*
    unary   := '-' unary | primary
    primary := NUMBER | '(' expr ')'"
  (:import (java.io BufferedReader InputStreamReader OutputStreamWriter
                    BufferedWriter Reader Writer)
           (java.nio.charset StandardCharsets))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn- fail
  "Signals that the current line cannot be evaluated."
  [msg]
  (throw (ex-info msg {::error true})))

;; ---------------------------------------------------------------------------
;; Lexer

(defn- digit? [c] (<= (int \0) (int (char c)) (int \9)))

(defn- blank-char? [c] (or (= c \space) (= c \tab)))

(defn- parse-literal
  "Parses a run of ASCII digits as a long, failing on overflow."
  [^String digits]
  (try
    (Long/parseLong digits)
    (catch NumberFormatException _
      (fail "literal out of range"))))

(defn tokenize
  "Splits a line into tokens: longs for literals, characters for operators
  and parentheses."
  [^String line]
  (let [n (.length line)]
    (loop [i 0
           tokens (transient [])]
      (if (>= i n)
        (persistent! tokens)
        (let [c (.charAt line i)]
          (cond
            (blank-char? c)
            (recur (inc i) tokens)

            (#{\+ \- \* \/ \% \( \)} c)
            (recur (inc i) (conj! tokens c))

            (digit? c)
            (let [end (loop [j (inc i)]
                        (if (and (< j n) (digit? (.charAt line j)))
                          (recur (inc j))
                          j))]
              (recur end (conj! tokens (parse-literal (subs line i end)))))

            :else
            (fail (str "unexpected character " (pr-str c)))))))))

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

(defn- apply-op ^long [op ^long a ^long b]
  (try
    (case op
      \+ (Math/addExact a b)
      \- (Math/subtractExact a b)
      \* (Math/multiplyExact a b)
      \/ (checked-quot a b)
      \% (checked-rem a b))
    (catch ArithmeticException _
      (fail "overflow"))))

(defn- negate ^long [^long a]
  (try
    (Math/negateExact a)
    (catch ArithmeticException _
      (fail "overflow"))))

;; ---------------------------------------------------------------------------
;; Recursive-descent evaluator
;;
;; Each parse function takes the token vector and a position, and returns
;; [value next-position].

(declare parse-expr)

(defn- parse-primary [tokens ^long pos]
  (let [tok (get tokens pos)]
    (cond
      (int? tok) [tok (inc pos)]

      (= tok \()
      (let [[v p] (parse-expr tokens (inc pos))]
        (if (= (get tokens p) \))
          [v (inc p)]
          (fail "expected ')'")))

      (nil? tok) (fail "unexpected end of input")
      :else (fail (str "unexpected token " (pr-str tok))))))

(defn- parse-unary [tokens ^long pos]
  ;; Collect consecutive minus signs iteratively so long chains such as
  ;; "-----1" do not consume stack depth.
  (let [start pos
        pos (long (loop [p pos]
                    (if (= (get tokens p) \-) (recur (inc p)) p)))
        [v p] (parse-primary tokens pos)]
    [(loop [v (long v) k (- pos start)]
       (if (pos? k) (recur (negate v) (dec k)) v))
     p]))

(defn- parse-left-assoc
  "Parses `operand (op operand)*` for the operator set `ops`, folding
  left-associatively."
  [parse-operand ops tokens pos]
  (let [[v p] (parse-operand tokens pos)]
    (loop [acc (long v) p (long p)]
      (let [op (get tokens p)]
        (if (contains? ops op)
          (let [[rhs p'] (parse-operand tokens (inc p))]
            (recur (apply-op op acc rhs) (long p')))
          [acc p])))))

(defn- parse-term [tokens pos]
  (parse-left-assoc parse-unary #{\* \/ \%} tokens pos))

(defn- parse-expr [tokens pos]
  (parse-left-assoc parse-term #{\+ \-} tokens pos))

(defn evaluate
  "Evaluates an expression line. Returns the long result, or throws an
  ex-info carrying ::error when the line is invalid."
  ^long [line]
  (let [tokens (tokenize line)
        [v p] (parse-expr tokens 0)]
    (when (< (long p) (count tokens))
      (fail (str "unexpected token " (pr-str (get tokens p)))))
    v))

(defn eval-line
  "Returns the output for one input line: the value as a string, \"error\",
  or nil for a blank line."
  [^String line]
  (when-not (every? blank-char? line)
    (try
      (str (evaluate line))
      (catch clojure.lang.ExceptionInfo e
        (if (::error (ex-data e)) "error" (throw e)))
      (catch StackOverflowError _
        "error"))))

;; ---------------------------------------------------------------------------
;; Entry point

(defn- lines
  "Lazy sequence of lines split on newline characters only. A carriage
  return stays part of its line and is therefore reported as a syntax error."
  [^Reader in]
  (lazy-seq
   (let [sb (StringBuilder.)]
     (loop []
       (let [c (.read in)]
         (cond
           (= c -1) (when (pos? (.length sb)) (list (str sb)))
           (= c (int \newline)) (cons (str sb) (lines in))
           :else (do (.append sb (char c)) (recur))))))))

(defn- run [^Reader in ^Writer out]
  (doseq [line (lines in)
          :let [result (eval-line line)]
          :when result]
    (.write out ^String result)
    (.write out "\n"))
  (.flush out))

(defn -main [& _]
  (let [in (BufferedReader. (InputStreamReader. System/in StandardCharsets/ISO_8859_1)
                            65536)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1)
                             65536)
        ;; Deeply nested parentheses recurse; give the parser a roomy stack.
        worker (Thread. nil #(run in out) "calc" (* 1024 1024 1024))]
    (.start worker)
    (.join worker)
    (shutdown-agents)
    (System/exit 0)))
