(ns wordfreq.core
  "Prints the 10 most frequent ASCII words read from standard input."
  (:import (java.io InputStream OutputStreamWriter BufferedWriter)
           (java.nio.charset StandardCharsets)
           (java.util HashMap Map$Entry))
  (:gen-class))

(set! *warn-on-reflection* true)
(set! *unchecked-math* :warn-on-boxed)

(def ^:private top-n 10)
(def ^:private buffer-size (* 64 1024))

(defn- lower-ascii-letter
  "Returns the lowercase byte for an ASCII letter, or -1 for any separator."
  ^long [^long b]
  (cond
    (<= 97 b 122) b
    (<= 65 b 90) (+ b 32)
    :else -1))

(defn- count-words
  "Streams `in`, returning a HashMap of lowercase word -> long[1] count."
  ^HashMap [^InputStream in]
  (let [counts (HashMap.)
        buf (byte-array buffer-size)
        word (java.io.ByteArrayOutputStream. 32)
        flush-word! (fn [^java.io.ByteArrayOutputStream w]
                      (when (pos? (.size w))
                        (let [k (.toString w StandardCharsets/ISO_8859_1)
                              ^longs c (.get counts k)]
                          (if c
                            (aset c 0 (inc (aget c 0)))
                            (.put counts k (long-array [1]))))
                        (.reset w)))]
    (loop []
      (let [n (.read in buf)]
        (when (pos? n)
          (dotimes [i n]
            (let [c (lower-ascii-letter (bit-and (aget buf i) 0xff))]
              (if (neg? c)
                (flush-word! word)
                (.write word (int c)))))
          (recur))))
    (flush-word! word)
    counts))

(defn- entry-count ^long [^Map$Entry e]
  (aget ^longs (.getValue e) 0))

(defn- by-count-then-word
  "Orders entries by count descending, then word ascending."
  [^Map$Entry a ^Map$Entry b]
  (let [c (Long/compare (entry-count b) (entry-count a))]
    (if (zero? c)
      (compare (.getKey a) (.getKey b))
      c)))

(defn top-words
  "Returns up to `n` [word count] pairs from `counts`, most frequent first."
  [^HashMap counts n]
  (->> (.entrySet counts)
       (sort by-count-then-word)
       (take n)
       (map (fn [^Map$Entry e] [(.getKey e) (entry-count e)]))))

(defn -main [& _]
  (let [out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1))]
    (doseq [[word cnt] (top-words (count-words System/in) top-n)]
      (.write out (str cnt " " word "\n")))
    (.flush out))
  (shutdown-agents))
