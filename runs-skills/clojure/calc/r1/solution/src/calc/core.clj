(ns calc.core
  "Line-oriented evaluator for 64-bit signed integer arithmetic expressions."
  (:require [clojure.string :as str])
  (:import (java.io BufferedWriter OutputStreamWriter)
           (java.nio.charset StandardCharsets))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn- fail!
  [reason]
  (throw (ex-info reason {::calc-error true})))

;; ---------------------------------------------------------------------------
;; Lexer

(def ^:private max-literal (biginteger Long/MAX_VALUE))

(defn- whitespace? [c]
  (or (= c \space) (= c \tab)))

(defn- digit? [c]
  (<= (int \0) (int c) (int \9)))

(defn- tokenize
  "Splits `line` into a vector of tokens: longs for literals and characters
  for operators/parentheses. Throws on any character outside the grammar or
  on a literal that does not fit in a signed 64-bit integer."
  [^String line]
  (let [n (.length line)]
    (loop [i 0, tokens (transient [])]
      (if (>= i n)
        (persistent! tokens)
        (let [c (.charAt line i)]
          (cond
            (whitespace? c) (recur (inc i) tokens)

            (digit? c)
            (let [end (loop [j i]
                        (if (and (< j n) (digit? (.charAt line j))) (recur (inc j)) j))
                  value (BigInteger. (subs line i end))]
              (when (pos? (.compareTo value max-literal))
                (fail! "literal out of range"))
              (recur end (conj! tokens (.longValue value))))

            (#{\+ \- \* \/ \% \( \)} c) (recur (inc i) (conj! tokens c))

            :else (fail! "unexpected character")))))))

;; ---------------------------------------------------------------------------
;; Checked 64-bit arithmetic

(defn- checked-div ^long [^long a ^long b]
  (cond
    (zero? b) (fail! "division by zero")
    (and (= a Long/MIN_VALUE) (= b -1)) (fail! "overflow")
    :else (quot a b)))

(defn- checked-rem ^long [^long a ^long b]
  (if (zero? b)
    (fail! "division by zero")
    (rem a b)))

(defn- apply-op ^long [op ^long a ^long b]
  (case op
    \+ (Math/addExact a b)
    \- (Math/subtractExact a b)
    \* (Math/multiplyExact a b)
    \/ (checked-div a b)
    \% (checked-rem a b)))

;; ---------------------------------------------------------------------------
;; Recursive-descent parser/evaluator.
;; Each rule takes the token vector and a position and returns [value pos].

(declare parse-expr)

(defn- parse-primary [tokens pos]
  (let [tok (get tokens pos)]
    (cond
      (int? tok) [tok (inc pos)]

      (= tok \()
      (let [[value pos'] (parse-expr tokens (inc pos))]
        (if (= (get tokens pos') \))
          [value (inc pos')]
          (fail! "expected ')'")))

      :else (fail! "expected operand"))))

(defn- parse-unary [tokens pos]
  (if (= (get tokens pos) \-)
    (let [[value pos'] (parse-unary tokens (inc pos))]
      [(Math/negateExact (long value)) pos'])
    (parse-primary tokens pos)))

(defn- parse-binary
  "Parses a left-associative chain of `operand` separated by `ops`."
  [ops operand tokens pos]
  (loop [[acc pos] (operand tokens pos)]
    (let [op (get tokens pos)]
      (if (contains? ops op)
        (let [[rhs pos'] (operand tokens (inc pos))]
          (recur [(apply-op op acc rhs) pos']))
        [acc pos]))))

(defn- parse-term [tokens pos]
  (parse-binary #{\* \/ \%} parse-unary tokens pos))

(defn- parse-expr [tokens pos]
  (parse-binary #{\+ \-} parse-term tokens pos))

(defn evaluate
  "Evaluates an expression string, returning its long value.
  Throws ex-info for syntax errors, division by zero, and overflow."
  [line]
  (let [tokens (tokenize line)
        [value pos] (parse-expr tokens 0)]
    (when (< pos (count tokens))
      (fail! "unexpected trailing input"))
    value))

(defn eval-line
  "Returns the output for one input line: the value as a string, \"error\",
  or nil when the line is blank."
  [^String line]
  (when-not (re-matches #"[ \t]*" line)
    (try
      (str (evaluate line))
      (catch ArithmeticException _ "error")
      (catch clojure.lang.ExceptionInfo e
        (if (::calc-error (ex-data e)) "error" (throw e))))))

;; ---------------------------------------------------------------------------
;; I/O

(defn- input-lines
  "Reads all of stdin and splits it on \\n only. Bytes are decoded as
  ISO-8859-1 so every byte maps to one character and invalid input is
  rejected by the lexer rather than by the decoder."
  []
  (let [text (String. (.readAllBytes System/in) StandardCharsets/ISO_8859_1)]
    (str/split text #"\n")))

(defn- run []
  (let [out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1)
                             65536)]
    (doseq [line (input-lines)
            :let [result (eval-line line)]
            :when result]
      (.write out ^String result)
      (.write out "\n"))
    (.flush out)))

(defn -main [& _]
  ;; Deeply nested parentheses recurse; give the evaluator a generous stack.
  (let [t (Thread. nil ^Runnable run "calc" (* 1024 1024 1024))]
    (.start t)
    (.join t))
  (shutdown-agents))
