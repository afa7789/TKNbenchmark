(ns lru.core
  "Simulates an LRU cache driven by commands read from standard input."
  (:require [clojure.string :as str])
  (:import (java.io BufferedReader BufferedWriter InputStreamReader
                    OutputStreamWriter Writer)
           (java.nio.charset StandardCharsets)
           (java.util Iterator LinkedHashMap))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn new-cache
  "Returns an empty access-ordered map: iteration starts at the least
  recently used entry, and both `get` and `put` refresh recency."
  ^LinkedHashMap [^long capacity]
  (LinkedHashMap. (int (min (inc capacity) 1048576)) (float 0.75) true))

(defn- evict-eldest!
  [^LinkedHashMap cache]
  (let [^Iterator it (.iterator (.entrySet cache))]
    (.next it)
    (.remove it)))

(defn cache-set!
  "Inserts or overwrites `k`, evicting the least recently used entry when
  the cache grows beyond `capacity`."
  [^LinkedHashMap cache ^long capacity k v]
  (.put cache k v)
  (when (> (.size cache) capacity)
    (evict-eldest! cache)))

(defn- write-line!
  [^Writer out ^String s]
  (.write out s)
  (.write out "\n"))

(defn execute!
  "Runs a single command line against `cache`, writing any output to `out`."
  [^LinkedHashMap cache ^long capacity ^Writer out ^String line]
  (let [sp1  (.indexOf line " ")
        op   (if (neg? sp1) line (subs line 0 sp1))]
    (case op
      "SET"  (let [sp2 (.indexOf line " " (inc sp1))]
               (cache-set! cache capacity
                           (subs line (inc sp1) sp2)
                           (subs line (inc sp2))))
      "GET"  (write-line! out (or (.get cache (subs line (inc sp1))) "NULL"))
      "DEL"  (write-line! out (if (nil? (.remove cache (subs line (inc sp1)))) "0" "1"))
      "SIZE" (write-line! out (String/valueOf (.size cache)))
      nil)))

(defn process!
  "Reads the capacity and commands from `in`, writing results to `out`."
  [^BufferedReader in ^Writer out]
  (when-let [first-line (.readLine in)]
    (let [capacity (parse-long (str/trim first-line))
          cache    (new-cache capacity)]
      (loop []
        (when-let [line (.readLine in)]
          (let [line (str/trimr line)]
            (when-not (str/blank? line)
              (execute! cache capacity out line)))
          (recur))))
    (.flush out)))

(defn -main
  [& _args]
  (let [in  (BufferedReader. (InputStreamReader. System/in StandardCharsets/US_ASCII) 65536)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/US_ASCII) 65536)]
    (process! in out)
    (.flush out)))
