(ns wordfreq.core
  "Prints the ten most frequent ASCII words read from standard input."
  (:gen-class)
  (:import (java.io BufferedOutputStream PrintStream)
           (java.nio.charset StandardCharsets)
           (java.util HashMap Map$Entry)))

(set! *warn-on-reflection* true)
(set! *unchecked-math* :warn-on-boxed)

(def ^:private top-n 10)

(def ^:private ^:const lower-a 97)
(def ^:private ^:const lower-z 122)
(def ^:private ^:const upper-a 65)
(def ^:private ^:const upper-z 90)
(def ^:private ^:const case-offset 32)

(defn- count-words
  "Scans `buf` and returns a HashMap from lowercased word to a one-element
  long array holding its count. A word is a maximal run of ASCII letters."
  ^HashMap [^bytes buf]
  (let [n      (alength buf)
        counts (HashMap.)
        word   (byte-array (max 1 n))
        flush! (fn [^long len]
                 (when (pos? len)
                   (let [k (String. word 0 (int len) StandardCharsets/ISO_8859_1)
                         ^longs c (.get counts k)]
                     (if c
                       (aset c 0 (inc (aget c 0)))
                       (.put counts k (long-array 1 1))))))]
    (loop [i 0 len 0]
      (if (< i n)
        (let [b (aget buf i)]
          (cond
            (and (>= b lower-a) (<= b lower-z))
            (do (aset word len b) (recur (inc i) (inc len)))

            (and (>= b upper-a) (<= b upper-z))
            (do (aset word len (unchecked-byte (+ b case-offset))) (recur (inc i) (inc len)))

            :else
            (do (flush! len) (recur (inc i) 0))))
        (flush! len)))
    counts))

(defn- entry-count ^long [^Map$Entry e]
  (aget ^longs (.getValue e) 0))

(defn- by-frequency
  "Orders entries by count descending, then word ascending."
  [^Map$Entry a ^Map$Entry b]
  (let [c (Long/compare (entry-count b) (entry-count a))]
    (if (zero? c)
      (compare (.getKey a) (.getKey b))
      c)))

(defn top-words
  "Returns up to `n` [word count] pairs for the words in `buf`."
  [n ^bytes buf]
  (->> (.entrySet (count-words buf))
       (sort by-frequency)
       (take n)
       (mapv (fn [^Map$Entry e] [(.getKey e) (entry-count e)]))))

(defn -main [& _]
  (let [input (.readAllBytes System/in)
        out   (PrintStream. (BufferedOutputStream. System/out) false "US-ASCII")]
    (doseq [[word cnt] (top-words top-n input)]
      (.print out (str cnt " " word "\n")))
    (.flush out)
    (shutdown-agents)))
