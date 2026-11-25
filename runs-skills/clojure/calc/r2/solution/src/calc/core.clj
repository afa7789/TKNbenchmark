(ns calc.core
  "Line-oriented evaluator for signed 64-bit integer expressions."
  (:require [clojure.string :as str])
  (:import (java.io BufferedWriter OutputStreamWriter)
           (java.nio.charset StandardCharsets))
  (:gen-class))

(set! *warn-on-reflection* true)

;; ---------------------------------------------------------------------------
;; Lexing

(defn- syntax-error [msg]
  (throw (ex-info msg {:type ::syntax})))

(defn- digit-at? [^String s ^long i]
  (and (< i (.length s))
       (let [c (.charAt s i)] (and (<= (int \0) (int c)) (<= (int c) (int \9))))))

(defn tokenize
  "Splits `line` into a vector of tokens: Long literals and operator chars.
  Throws on characters outside the grammar or out-of-range literals."
  [^String line]
  (let [n (.length line)]
    (loop [i 0, tokens (transient [])]
      (if (>= i n)
        (persistent! tokens)
        (let [c (.charAt line i)]
          (case c
            (\space \tab) (recur (inc i) tokens)
            (\+ \- \* \/ \% \( \)) (recur (inc i) (conj! tokens c))
            (if (digit-at? line i)
              (let [end (long (loop [j i] (if (digit-at? line j) (recur (inc j)) j)))
                    lit (or (parse-long (subs line i end))
                            (throw (ex-info "literal out of range" {:type ::overflow})))]
                (recur end (conj! tokens lit)))
              (syntax-error (str "unexpected character: " c)))))))))

;; ---------------------------------------------------------------------------
;; Arithmetic

(defn- checked-div ^long [^long a ^long b]
  (cond
    (zero? b) (throw (ArithmeticException. "division by zero"))
    (and (= a Long/MIN_VALUE) (= b -1)) (throw (ArithmeticException. "overflow"))
    :else (quot a b)))

(defn- checked-rem ^long [^long a ^long b]
  (if (zero? b)
    (throw (ArithmeticException. "division by zero"))
    (rem a b)))

(def ^:private binary-ops
  {\+ #(Math/addExact (long %1) (long %2))
   \- #(Math/subtractExact (long %1) (long %2))
   \* #(Math/multiplyExact (long %1) (long %2))
   \/ checked-div
   \% checked-rem})

;; ---------------------------------------------------------------------------
;; Parsing (recursive descent, evaluating as it goes)
;; Each parse fn takes the token vector and a position, returning [value pos].

(declare parse-expr)

(defn- parse-primary [tokens pos]
  (let [tok (get tokens pos)]
    (cond
      (int? tok) [tok (inc pos)]
      (= tok \() (let [[v p] (parse-expr tokens (inc pos))]
                   (if (= (get tokens p) \))
                     [v (inc p)]
                     (syntax-error "expected )")))
      :else (syntax-error "expected operand"))))

(defn- parse-unary [tokens pos]
  (if (= (get tokens pos) \-)
    (let [[v p] (parse-unary tokens (inc pos))]
      [(Math/negateExact (long v)) p])
    (parse-primary tokens pos)))

(defn- left-assoc
  "Parses `operand (op operand)*` for the operator chars in `ops`."
  [operand ops tokens pos]
  (loop [[acc p] (operand tokens pos)]
    (let [op (get tokens p)]
      (if (contains? ops op)
        (let [[rhs p'] (operand tokens (inc p))]
          (recur [((binary-ops op) acc rhs) p']))
        [acc p]))))

(defn- parse-term [tokens pos]
  (left-assoc parse-unary #{\* \/ \%} tokens pos))

(defn- parse-expr [tokens pos]
  (left-assoc parse-term #{\+ \-} tokens pos))

(defn evaluate
  "Evaluates an expression line. Returns a Long, or throws on any error."
  [line]
  (let [tokens (tokenize line)
        [v p] (parse-expr tokens 0)]
    (when (< p (count tokens))
      (syntax-error "trailing input"))
    v))

(defn eval-line
  "Returns the output text for `line`, or nil when the line is blank."
  [^String line]
  (when-not (re-matches #"[ \t]*" line)
    (try
      (str (evaluate line))
      (catch clojure.lang.ExceptionInfo _ "error")
      (catch ArithmeticException _ "error")
      (catch StackOverflowError _ "error"))))

(defn -main [& _]
  ;; Lines are terminated by \n only; a stray \r is part of the line (and a syntax error).
  (let [input (String. (.readAllBytes System/in) StandardCharsets/ISO_8859_1)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1) 65536)]
    (doseq [line (str/split input #"\n")]
      (when-let [result (eval-line line)]
        (.write out ^String result)
        (.write out "\n")))
    (.flush out)))
