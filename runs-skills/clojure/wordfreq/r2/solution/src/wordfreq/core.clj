(ns wordfreq.core
  "Prints the 10 most frequent ASCII words read from standard input."
  (:require [clojure.string :as str])
  (:import (java.io InputStream)
           (java.nio.charset StandardCharsets)
           (java.util HashMap Map$Entry))
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:private top-n 10)
(def ^:private chunk-size (* 1024 1024))

(defn- lower-ascii-letter
  "Returns the lowercase form of byte `b` if it is an ASCII letter, else -1."
  ^long [^long b]
  (cond
    (<= 97 b 122) b
    (<= 65 b 90) (+ b 32)
    :else -1))

(defn count-words
  "Reads `in` to exhaustion and returns a HashMap of lowercase word -> long[1] count."
  ^HashMap [^InputStream in]
  (let [counts (HashMap.)
        buf    (byte-array chunk-size)
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
        (when (pos? n)
          (dotimes [i n]
            (let [ch (lower-ascii-letter (aget buf i))]
              (if (neg? ch)
                (flush!)
                (.write word (unchecked-int ch)))))
          (recur))))
    (flush!)
    counts))

(defn top-words
  "Returns up to `n` [word count] pairs, by count descending then word ascending."
  [^HashMap counts n]
  (->> (.entrySet counts)
       (map (fn [^Map$Entry e] [(.getKey e) (aget ^longs (.getValue e) 0)]))
       (sort (fn [[wa ca] [wb cb]]
                           (let [c (compare cb ca)]
                             (if (zero? c) (compare wa wb) c))))
       (take n)))

(defn -main
  [& _]
  (let [lines (for [[w c] (top-words (count-words System/in) top-n)]
                (str c " " w))]
    (when (seq lines)
      (print (str (str/join "\n" lines) "\n")))
    (flush)))
