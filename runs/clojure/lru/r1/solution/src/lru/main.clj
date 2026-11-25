(ns lru.main
  "LRU cache simulator: reads a capacity and a stream of commands from stdin,
  writes command results to stdout."
  (:import (java.io BufferedReader BufferedWriter InputStreamReader
                    OutputStreamWriter)
           (java.nio.charset StandardCharsets)
           (java.util Iterator LinkedHashMap))
  (:gen-class))

(set! *warn-on-reflection* true)

(defn- new-cache
  "An access-ordered LinkedHashMap: every get/put moves the key to the
  most-recently-used end, so the eldest entry is always the LRU key."
  ^LinkedHashMap [capacity]
  (LinkedHashMap. (int (min (inc capacity) 1048576)) (float 0.75) true))

(defn- evict-lru!
  [^LinkedHashMap cache]
  (let [^Iterator it (.iterator (.keySet cache))]
    (.next it)
    (.remove it)))

(defn- write-line!
  [^BufferedWriter out ^String s]
  (.write out s)
  (.write out "\n"))

(defn- execute!
  "Runs one command line against the cache, writing any output."
  [^LinkedHashMap cache capacity ^BufferedWriter out ^String line]
  (let [sp1 (.indexOf line " ")
        cmd (if (neg? sp1) line (subs line 0 sp1))]
    (case cmd
      "SET" (let [sp2   (.indexOf line " " (inc sp1))
                  k     (subs line (inc sp1) sp2)
                  v     (subs line (inc sp2))]
              (.put cache k v)
              (when (> (.size cache) capacity)
                (evict-lru! cache)))
      "GET" (let [v (.get cache (subs line (inc sp1)))]
              (write-line! out (if (nil? v) "NULL" v)))
      "DEL" (write-line! out (if (nil? (.remove cache (subs line (inc sp1))))
                               "0"
                               "1"))
      "SIZE" (write-line! out (str (.size cache)))
      nil)))

(defn run
  "Processes the whole input from `in`, writing results to `out`."
  [^BufferedReader in ^BufferedWriter out]
  (when-let [first-line (.readLine in)]
    (let [capacity (Long/parseLong (.trim ^String first-line))
          cache    (new-cache capacity)]
      (loop []
        (when-let [line (.readLine in)]
          (let [^String line (if (.endsWith line "\r")
                               (subs line 0 (dec (count line)))
                               line)]
            (when-not (.isEmpty line)
              (execute! cache capacity out line)))
          (recur)))))
  (.flush out))

(defn -main
  [& _]
  (run (BufferedReader. (InputStreamReader. System/in StandardCharsets/US_ASCII)
                        (* 1 1024 1024))
       (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/US_ASCII)
                        (* 1 1024 1024)))
  (flush)
  (System/exit 0))
