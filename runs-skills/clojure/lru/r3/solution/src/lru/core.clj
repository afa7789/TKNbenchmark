(ns lru.core
  "LRU cache simulator: reads a capacity and a stream of commands from stdin,
  writes command results to stdout."
  (:import (java.io BufferedReader BufferedWriter InputStreamReader
                    OutputStreamWriter)
           (java.nio.charset StandardCharsets)
           (java.util LinkedHashMap))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn make-cache
  "Returns an access-ordered LinkedHashMap: iteration order runs from least
  to most recently used, and get/put move the touched key to the end."
  ^LinkedHashMap [^long capacity]
  (LinkedHashMap. (int (min (inc capacity) 1048576)) (float 0.75) true))

(defn- evict-eldest!
  "Removes the least recently used entry."
  [^LinkedHashMap cache]
  (let [it (.iterator (.keySet cache))]
    (.next it)
    (.remove it)))

(defn cache-set!
  "Inserts or overwrites key, evicting the LRU entry if over capacity."
  [^LinkedHashMap cache ^long capacity k v]
  (.put cache k v)
  (when (> (.size cache) capacity)
    (evict-eldest! cache)))

(defn execute!
  "Runs one command line against the cache. Returns the output string, or
  nil when the command produces no output."
  [^LinkedHashMap cache ^long capacity ^String line]
  (let [sp1 (.indexOf line (int \space))
        cmd (if (neg? sp1) line (subs line 0 sp1))]
    (case cmd
      "SET" (let [sp2 (.indexOf line (int \space) (inc sp1))]
              (cache-set! cache capacity
                          (subs line (inc sp1) sp2)
                          (subs line (inc sp2)))
              nil)
      "GET" (or (.get cache (subs line (inc sp1))) "NULL")
      "DEL" (if (some? (.remove cache (subs line (inc sp1)))) "1" "0")
      "SIZE" (String/valueOf (.size cache))
      nil)))

(defn process!
  "Processes the whole input from reader, writing results to writer."
  [^BufferedReader in ^BufferedWriter out]
  (when-let [first-line (.readLine in)]
    (let [capacity (parse-long (.trim ^String first-line))
          cache (make-cache capacity)]
      (loop []
        (when-let [line (.readLine in)]
          (when-let [^String result (execute! cache capacity line)]
            (.write out result)
            (.write out "\n"))
          (recur)))))
  (.flush out))

(defn -main
  [& _args]
  (let [in (BufferedReader. (InputStreamReader. System/in StandardCharsets/ISO_8859_1)
                            (* 1 1024 1024))
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1)
                             (* 1 1024 1024))]
    (process! in out)))
