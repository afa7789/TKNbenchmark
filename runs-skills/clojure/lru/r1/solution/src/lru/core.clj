(ns lru.core
  "LRU cache simulator: reads a capacity and commands from stdin,
  writes command results to stdout."
  (:gen-class)
  (:import (java.io BufferedReader BufferedWriter InputStreamReader
                    OutputStreamWriter Writer)
           (java.nio.charset StandardCharsets)
           (java.util Iterator LinkedHashMap)))

(set! *warn-on-reflection* true)

(defn new-cache
  "Returns an empty access-ordered LinkedHashMap: iteration order runs from
  least to most recently used, and get/put move a key to the MRU end."
  ^LinkedHashMap [^long capacity]
  (LinkedHashMap. (int (min (inc capacity) 1048576)) (float 0.75) true))

(defn- evict-eldest!
  "Removes the least recently used entry."
  [^LinkedHashMap cache]
  (let [^Iterator it (.iterator (.keySet cache))]
    (.next it)
    (.remove it)))

(defn- emit! [^Writer out ^String s]
  (.write out s)
  (.write out "\n"))

(defn execute!
  "Applies one command line to the cache, writing any output to `out`.
  Blank or unrecognised lines are ignored."
  [^LinkedHashMap cache ^long capacity ^Writer out ^String line]
  (let [sp1 (.indexOf line " ")
        cmd (if (neg? sp1) line (subs line 0 sp1))]
    (case cmd
      "SET"  (let [sp2 (.indexOf line " " (inc sp1))]
               (when (pos? sp2)
                 (.put cache (subs line (inc sp1) sp2) (subs line (inc sp2)))
                 (when (> (.size cache) capacity)
                   (evict-eldest! cache))))
      "GET"  (emit! out (or (.get cache (subs line (inc sp1))) "NULL"))
      "DEL"  (emit! out (if (some? (.remove cache (subs line (inc sp1)))) "1" "0"))
      "SIZE" (emit! out (str (.size cache)))
      nil)))

(defn process!
  "Reads the capacity and commands from `in`, writing results to `out`."
  [^BufferedReader in ^Writer out]
  (when-let [first-line (.readLine in)]
    (let [capacity (parse-long (.trim ^String first-line))
          cache    (new-cache capacity)]
      (loop []
        (when-let [line (.readLine in)]
          (execute! cache capacity out line)
          (recur)))))
  (.flush out))

(defn -main [& _]
  (let [in  (BufferedReader. (InputStreamReader. System/in StandardCharsets/ISO_8859_1) 65536)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1) 65536)]
    (process! in out)))
