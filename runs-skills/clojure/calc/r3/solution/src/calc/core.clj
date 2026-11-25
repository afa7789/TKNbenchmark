(ns calc.core
  "Line-oriented evaluator for signed 64-bit integer expressions.

  Grammar:
    expr    := term    (('+' | '-') term)*
    term    := unary   (('*' | '/' | '%') unary)*
    unary   := '-' unary | primary
    primary := NUMBER | '(' expr ')'"
  (:import (java.io BufferedReader BufferedWriter InputStreamReader OutputStreamWriter Reader)
           (java.nio.charset StandardCharsets))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn- fail!
  [reason]
  (throw (ex-info "evaluation error" {::reason reason})))

;; ---------------------------------------------------------------------------
;; Checked 64-bit arithmetic

(defn- apply-op
  ^long [op ^long a ^long b]
  (try
    (case op
      \+ (Math/addExact a b)
      \- (Math/subtractExact a b)
      \* (Math/multiplyExact a b)
      \/ (cond
           (zero? b)                           (fail! :division-by-zero)
           (and (= a Long/MIN_VALUE) (= b -1)) (fail! :overflow)
           :else                               (quot a b))
      \% (if (zero? b)
           (fail! :division-by-zero)
           (rem a b)))
    (catch ArithmeticException _
      (fail! :overflow))))

(defn- negate
  ^long [^long a]
  (if (= a Long/MIN_VALUE)
    (fail! :overflow)
    (- a)))

;; ---------------------------------------------------------------------------
;; Recursive-descent parser/evaluator.
;; Each parse function takes the source and a position and returns
;; [value next-position], where next-position is past trailing whitespace.

(defn- blank-char?
  [c]
  (or (= c \space) (= c \tab)))

(defn- skip-blanks
  ^long [^String s ^long pos]
  (let [n (.length s)]
    (loop [i pos]
      (if (and (< i n) (blank-char? (.charAt s i)))
        (recur (inc i))
        i))))

(defn- char-at
  "Character at `pos`, or nil past the end."
  [^String s ^long pos]
  (when (< pos (.length s))
    (.charAt s pos)))

(defn- digit?
  [c]
  (and c (<= (int \0) (int c) (int \9))))

(declare parse-expr)

(defn- parse-number
  [^String s ^long pos]
  (let [end (loop [i pos]
              (if (digit? (char-at s i)) (recur (inc i)) i))]
    (when (= end pos)
      (fail! :syntax))
    (if-let [v (parse-long (subs s pos end))]
      [v (skip-blanks s end)]
      (fail! :overflow))))

(defn- parse-primary
  [^String s ^long pos]
  (if (= \( (char-at s pos))
    (let [[v ^long pos] (parse-expr s (skip-blanks s (inc pos)))]
      (if (= \) (char-at s pos))
        [v (skip-blanks s (inc pos))]
        (fail! :syntax)))
    (parse-number s pos)))

(defn- parse-unary
  [^String s ^long pos]
  (if (= \- (char-at s pos))
    (let [[v pos] (parse-unary s (skip-blanks s (inc pos)))]
      [(negate v) pos])
    (parse-primary s pos)))

(defn- parse-left-assoc
  "Parses `operand (op operand)*` for the operator characters in `ops`,
  folding left to right."
  [ops parse-operand ^String s ^long pos]
  (let [[init pos] (parse-operand s pos)]
    (loop [acc init
           pos ^long pos]
      (let [c (char-at s pos)]
        (if (contains? ops c)
          (let [[v pos] (parse-operand s (skip-blanks s (inc pos)))]
            (recur (apply-op c acc v) pos))
          [acc pos])))))

(def ^:private additive-ops #{\+ \-})
(def ^:private multiplicative-ops #{\* \/ \%})

(defn- parse-term
  [s pos]
  (parse-left-assoc multiplicative-ops parse-unary s pos))

(defn- parse-expr
  [s pos]
  (parse-left-assoc additive-ops parse-term s pos))

(defn evaluate
  "Evaluates expression `line`, returning its long value.
  Throws ex-info carrying ::reason on syntax, division-by-zero or overflow."
  ^long [^String line]
  (let [[v ^long pos] (parse-expr line (skip-blanks line 0))]
    (if (= pos (.length line))
      v
      (fail! :syntax))))

(defn result-line
  "Output for one input line: the value, \"error\", or nil for a blank line."
  [^String line]
  (when-not (re-matches #"[ \t]*" line)
    (try
      (str (evaluate line))
      (catch clojure.lang.ExceptionInfo _
        "error")
      (catch StackOverflowError _
        "error"))))

;; ---------------------------------------------------------------------------
;; Entry point

(defn- newline-lines
  "Lazy seq of the lines of `rdr`, split on \\n only (so a stray \\r stays
  part of its line and is rejected by the parser)."
  [^Reader rdr]
  (lazy-seq
    (let [sb (StringBuilder.)]
      (loop []
        (let [c (.read rdr)]
          (cond
            (= c -1)           (when (pos? (.length sb))
                                 (list (str sb)))
            (= c (int \newline)) (cons (str sb) (newline-lines rdr))
            :else              (do (.append sb (char c))
                                   (recur))))))))

(def ^:private stack-bytes
  "Thread stack size for evaluation, so deeply nested input does not overflow."
  (* 1024 1024 1024))

(defn- run!*
  []
  (let [in  (BufferedReader. (InputStreamReader. System/in StandardCharsets/UTF_8) 65536)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/UTF_8) 65536)]
    (doseq [line (newline-lines in)]
      (when-let [result (result-line line)]
        (.write out ^String result)
        (.write out "\n")))
    (.flush out)))

(defn -main
  [& _]
  (let [worker (Thread. nil ^Runnable run!* "calc" (long stack-bytes))]
    (.start worker)
    (.join worker))
  (shutdown-agents))
