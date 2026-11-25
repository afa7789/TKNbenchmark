(ns calc.main
  "64-bit signed integer expression evaluator.
  Reads one expression per line from stdin and prints its value or `error`."
  (:gen-class))

(set! *warn-on-reflection* true)

;; ---------------------------------------------------------------------------
;; Errors

(defn- fail!
  [reason]
  (throw (ex-info "calc error" {::error reason})))

;; ---------------------------------------------------------------------------
;; Lexer

(defn- blank-char? [c] (or (= c \space) (= c \tab)))

(defn- digit-char? [c] (<= (int \0) (int c) (int \9)))

(defn- parse-literal
  "Parses a decimal digit string as a long, failing on overflow."
  [^String digits]
  (try
    (Long/parseLong digits)
    (catch NumberFormatException _
      (fail! :overflow))))

(defn- tokenize
  "Returns a vector of tokens: longs for numbers, characters for operators
  and parentheses. Fails on any character outside the grammar."
  [^String line]
  (let [n (.length line)]
    (loop [i 0, tokens (transient [])]
      (if (>= i n)
        (persistent! tokens)
        (let [c (.charAt line i)]
          (cond
            (blank-char? c)
            (recur (inc i) tokens)

            (digit-char? c)
            (let [end (loop [j i]
                        (if (and (< j n) (digit-char? (.charAt line j)))
                          (recur (inc j))
                          j))]
              (recur end (conj! tokens (parse-literal (subs line i end)))))

            (#{\+ \- \* \/ \% \( \)} c)
            (recur (inc i) (conj! tokens c))

            :else
            (fail! :syntax)))))))

;; ---------------------------------------------------------------------------
;; Arithmetic with exact 64-bit semantics

(defn- checked-div ^long [^long a ^long b]
  (cond
    (zero? b) (fail! :division-by-zero)
    (and (= a Long/MIN_VALUE) (= b -1)) (fail! :overflow)
    :else (quot a b)))

(defn- checked-rem ^long [^long a ^long b]
  (if (zero? b)
    (fail! :division-by-zero)
    ;; JVM remainder already follows the dividend's sign and yields 0 for
    ;; MIN_VALUE % -1, as the spec requires.
    (rem a b)))

(def ^:private binary-ops
  {\+ (fn [^long a ^long b] (Math/addExact a b))
   \- (fn [^long a ^long b] (Math/subtractExact a b))
   \* (fn [^long a ^long b] (Math/multiplyExact a b))
   \/ checked-div
   \% checked-rem})

(defn- negate ^long [^long a]
  (Math/negateExact a))

;; ---------------------------------------------------------------------------
;; Recursive-descent parser / evaluator
;;
;; Each parse function takes the token vector and a position and returns
;; [value next-position].

(declare parse-expr)

(defn- token-at [tokens ^long pos]
  (nth tokens pos nil))

(defn- parse-primary [tokens pos]
  (let [tok (token-at tokens pos)]
    (cond
      (int? tok)
      [tok (inc pos)]

      (= tok \()
      (let [[v pos'] (parse-expr tokens (inc pos))]
        (if (= (token-at tokens pos') \))
          [v (inc pos')]
          (fail! :syntax)))

      :else
      (fail! :syntax))))

(defn- parse-unary [tokens pos]
  (if (= (token-at tokens pos) \-)
    (let [[v pos'] (parse-unary tokens (inc pos))]
      [(negate v) pos'])
    (parse-primary tokens pos)))

(defn- left-assoc
  "Builds a parser for a left-associative chain of `operand` separated by
  any operator in `ops`."
  [operand ops]
  (fn [tokens pos]
    (let [[v pos'] (operand tokens pos)]
      (loop [acc v, pos pos']
        (let [op (token-at tokens pos)]
          (if (contains? ops op)
            (let [[rhs pos''] (operand tokens (inc pos))]
              (recur ((binary-ops op) acc rhs) pos''))
            [acc pos]))))))

(def ^:private parse-term (left-assoc parse-unary #{\* \/ \%}))

(def ^:private parse-expr* (left-assoc parse-term #{\+ \-}))

(defn- parse-expr [tokens pos]
  (parse-expr* tokens pos))

(defn evaluate
  "Evaluates an expression string. Returns the long result, or throws
  ex-info carrying ::error on syntax, division-by-zero or overflow."
  [line]
  (let [tokens (tokenize line)
        [v pos] (parse-expr tokens 0)]
    (if (= pos (count tokens))
      v
      (fail! :syntax))))

(defn- blank-line? [^String line]
  (every? blank-char? line))

(defn line-result
  "Returns the output for one input line, or nil for a blank line."
  [line]
  (when-not (blank-line? line)
    (try
      (str (evaluate line))
      (catch clojure.lang.ExceptionInfo e
        (if (::error (ex-data e)) "error" (throw e)))
      (catch ArithmeticException _
        ;; Raised by the Math/*Exact operations on 64-bit overflow.
        "error")
      (catch StackOverflowError _
        "error"))))

;; ---------------------------------------------------------------------------
;; I/O

(defn- run []
  (let [in  (java.io.BufferedReader.
             (java.io.InputStreamReader. System/in java.nio.charset.StandardCharsets/ISO_8859_1)
             65536)
        out (java.io.BufferedWriter.
             (java.io.OutputStreamWriter. System/out java.nio.charset.StandardCharsets/ISO_8859_1)
             65536)
        sb  (StringBuilder.)
        emit (fn []
               (when-let [r (line-result (.toString sb))]
                 (.write out ^String r)
                 (.write out "\n"))
               (.setLength sb 0))]
    ;; Lines are split on \n only, so a stray \r is reported as a syntax error.
    (loop []
      (let [c (.read in)]
        (cond
          (neg? c)         (when (pos? (.length sb)) (emit))
          (= c (int \newline)) (do (emit) (recur))
          :else            (do (.append sb (char c)) (recur)))))
    (.flush out)))

(defn -main [& _]
  ;; Run on a thread with a large stack so deeply nested input is handled.
  (let [t (Thread. nil ^Runnable run "calc" (* 512 1024 1024))]
    (.start t)
    (.join t))
  (shutdown-agents)
  (System/exit 0))
