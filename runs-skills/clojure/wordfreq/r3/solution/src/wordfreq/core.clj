(ns wordfreq.core
  "Prints the ten most frequent ASCII words read from standard input."
  (:gen-class)
  (:import (java.nio.charset StandardCharsets)
           (java.util ArrayList Comparator HashMap Map$Entry PriorityQueue)))

(set! *warn-on-reflection* true)

(def ^:private top-n 10)

(defn- ascii-letter->lower
  "Returns the lowercase form of an ASCII letter byte, or -1 for any other byte."
  ^long [^long b]
  (cond
    (<= 97 b 122) b
    (<= 65 b 90)  (+ b 32)
    :else         -1))

(defn count-words
  "Counts lowercase words (maximal runs of ASCII letters) in a byte array.
  Returns a java.util.HashMap of word -> long[1] counter. Lowercasing is done
  in place, so `bs` is mutated."
  ^HashMap [^bytes bs]
  (let [counts (HashMap.)
        n      (alength bs)
        add!   (fn [^long start ^long end]
                 (let [w (String. bs (int start) (int (- end start))
                                  StandardCharsets/ISO_8859_1)
                       ^longs c (.get counts w)]
                   (if c
                     (aset c 0 (inc (aget c 0)))
                     (.put counts w (long-array [1])))))]
    (loop [i 0, start -1]
      (if (< i n)
        (let [lower (ascii-letter->lower (aget bs i))]
          (if (neg? lower)
            (do (when-not (neg? start) (add! start i))
                (recur (inc i) -1))
            (do (aset bs i (unchecked-byte lower))
                (recur (inc i) (if (neg? start) i start)))))
        (when-not (neg? start) (add! start n))))
    counts))

(defn- entry-count ^long [^Map$Entry e]
  (aget ^longs (.getValue e) 0))

(def ^:private ^Comparator rank-order
  "Orders entries by count descending, then word ascending."
  (reify Comparator
    (compare [_ a b]
      (let [c (Long/compare (entry-count b) (entry-count a))]
        (if (zero? c)
          (.compareTo ^String (.getKey ^Map$Entry a) ^String (.getKey ^Map$Entry b))
          c)))))

(defn top-words
  "Returns up to `k` [word count] pairs from `counts`, highest rank first."
  [^HashMap counts ^long k]
  ;; Min-heap on rank: the head is the worst of the current best k.
  (let [heap (PriorityQueue. (inc k) (.reversed rank-order))]
    (doseq [e (.entrySet counts)]
      (.offer heap e)
      (when (> (.size heap) k)
        (.poll heap)))
    (let [best (ArrayList. heap)]
      (.sort best rank-order)
      (mapv (fn [^Map$Entry e] [(.getKey e) (entry-count e)]) best))))

(defn format-report
  "Renders [word count] pairs as `<count> <word>` lines."
  ^String [pairs]
  (let [sb (StringBuilder.)]
    (doseq [[w c] pairs]
      (-> sb (.append (long c)) (.append \space) (.append ^String w) (.append \newline)))
    (str sb)))

(defn -main [& _]
  (let [input (.readAllBytes System/in)
        out   System/out]
    (.print out (format-report (top-words (count-words input) top-n)))
    (.flush out)))
