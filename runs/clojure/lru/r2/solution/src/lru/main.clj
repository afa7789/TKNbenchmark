(ns lru.main
  "LRU cache simulator: reads a capacity and a stream of commands from stdin."
  (:import (java.io BufferedReader BufferedWriter InputStreamReader OutputStreamWriter)
           (java.nio.charset StandardCharsets)
           (java.util Iterator LinkedHashMap))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn- new-cache
  "An access-ordered map: iteration order runs from least to most recently used."
  ^LinkedHashMap [^long capacity]
  (LinkedHashMap. (int (min (inc capacity) 1048576)) (float 0.75) true))

(defn- evict-eldest!
  "Removes the least recently used entry."
  [^LinkedHashMap cache]
  (let [^Iterator it (.iterator (.keySet cache))]
    (.next it)
    (.remove it)))

(defn- emit! [^BufferedWriter out ^String s]
  (.write out s)
  (.write out "\n"))

(defn- execute!
  "Runs one command line against the cache, writing any output to `out`."
  [^LinkedHashMap cache ^long capacity ^BufferedWriter out ^String line]
  (let [sp1 (.indexOf line " ")
        cmd (if (neg? sp1) line (subs line 0 sp1))]
    (case cmd
      "SET" (let [sp2 (.indexOf line " " (inc sp1))
                  k   (subs line (inc sp1) sp2)
                  v   (subs line (inc sp2))]
              (.put cache k v)
              (when (> (.size cache) capacity)
                (evict-eldest! cache)))
      "GET" (emit! out (or (.get cache (subs line (inc sp1))) "NULL"))
      "DEL" (emit! out (if (some? (.remove cache (subs line (inc sp1)))) "1" "0"))
      "SIZE" (emit! out (str (.size cache)))
      nil)))

(defn run
  "Processes the whole input from `in`, writing results to `out`."
  [^BufferedReader in ^BufferedWriter out]
  (when-let [first-line (.readLine in)]
    (let [capacity (Long/parseLong (.trim ^String first-line))
          cache    (new-cache capacity)]
      (loop []
        (when-let [line (.readLine in)]
          (let [line (.trim ^String line)]
            (when-not (.isEmpty line)
              (execute! cache capacity out line)))
          (recur)))))
  (.flush out))

(defn -main [& _]
  (let [in  (BufferedReader. (InputStreamReader. System/in StandardCharsets/US_ASCII) 65536)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/US_ASCII) 65536)]
    (run in out)
    (shutdown-agents)))
