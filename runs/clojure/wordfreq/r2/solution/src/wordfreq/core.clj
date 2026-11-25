(ns wordfreq.core
  "Prints the 10 most frequent ASCII words read from standard input."
  (:import (java.io InputStream OutputStreamWriter BufferedWriter)
           (java.nio.charset StandardCharsets)
           (java.util HashMap Map$Entry))
  (:gen-class))

(set! *warn-on-reflection* true)
(set! *unchecked-math* :warn-on-boxed)

(def ^:private ^:const top-n 10)
(def ^:private ^:const buffer-size 65536)

(defn- letter->lower
  "Returns the lowercase byte for an ASCII letter, or -1 for any separator byte."
  ^long [^long b]
  (cond
    (and (>= b 97) (<= b 122)) b
    (and (>= b 65) (<= b 90))  (+ b 32)
    :else -1))

(defn count-words
  "Reads `in` to exhaustion and returns a HashMap of lowercase word -> long[1] count."
  ^HashMap [^InputStream in]
  (let [counts (HashMap.)
        buf    (byte-array buffer-size)
        word   (java.io.ByteArrayOutputStream. 64)
        flush! (fn []
                 (when (pos? (.size word))
                   (let [w (.toString word StandardCharsets/ISO_8859_1)
                         ^longs c (.get counts w)]
                     (if c
                       (aset c 0 (inc (aget c 0)))
                       (.put counts w (long-array [1]))))
                   (.reset word)))]
    (loop []
      (let [n (.read in buf)]
        (if (neg? n)
          (flush!)
          (do (dotimes [i n]
                (let [lc (letter->lower (aget buf i))]
                  (if (neg? lc)
                    (flush!)
                    (.write word (unchecked-int lc)))))
              (recur)))))
    counts))

(defn- entry-order
  "Count descending, then word ascending."
  ^long [^Map$Entry a ^Map$Entry b]
  (let [ca (aget ^longs (.getValue a) 0)
        cb (aget ^longs (.getValue b) 0)]
    (if (== ca cb)
      (long (compare (.getKey a) (.getKey b)))
      (if (> ca cb) -1 1))))

(defn top-words
  "Returns up to `n` [word count] pairs, most frequent first."
  [^HashMap counts n]
  (->> (.entrySet counts)
       (sort entry-order)
       (take n)
       (mapv (fn [^Map$Entry e] [(.getKey e) (aget ^longs (.getValue e) 0)]))))

(defn -main [& _]
  (let [out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1))]
    (doseq [[word cnt] (top-words (count-words System/in) top-n)]
      (.write out (str cnt " " word "\n")))
    (.flush out))
  (shutdown-agents)
  (System/exit 0))
