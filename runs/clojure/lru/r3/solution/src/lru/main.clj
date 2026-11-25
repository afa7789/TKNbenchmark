(ns lru.main
  "LRU cache simulator: reads a capacity and a stream of commands from stdin,
  writes command results to stdout."
  (:gen-class)
  (:import (java.io BufferedReader BufferedWriter InputStreamReader
                    OutputStreamWriter Writer)
           (java.nio.charset StandardCharsets)
           (java.util LinkedHashMap Map$Entry)))

(set! *warn-on-reflection* true)

(defn- new-cache
  "An access-ordered LinkedHashMap: every get/put moves the key to the
  most-recently-used end, so the eldest entry is the LRU one."
  ^LinkedHashMap [^long capacity]
  (LinkedHashMap. (int (min (inc capacity) 1048576)) (float 0.75) true))

(defn- evict-if-full!
  [^LinkedHashMap cache ^long capacity]
  (when (> (.size cache) capacity)
    (let [it (.iterator (.entrySet cache))]
      (.next it)
      (.remove it))))

(defn- emit! [^Writer out ^String s]
  (.write out s)
  (.write out "\n"))

(defn- run-command!
  "Executes one command line against the cache, writing any output."
  [^LinkedHashMap cache ^long capacity ^Writer out ^String line]
  (let [sp1 (.indexOf line " ")
        op  (if (neg? sp1) line (subs line 0 sp1))]
    (case op
      "SET"  (let [sp2 (.indexOf line " " (inc sp1))
                   k   (subs line (inc sp1) sp2)
                   v   (subs line (inc sp2))]
               (.put cache k v)
               (evict-if-full! cache capacity))
      "GET"  (emit! out (or (.get cache (subs line (inc sp1))) "NULL"))
      "DEL"  (emit! out (if (nil? (.remove cache (subs line (inc sp1)))) "0" "1"))
      "SIZE" (emit! out (str (.size cache)))
      nil)))

(defn run
  "Processes the whole input from `in`, writing results to `out`."
  [^BufferedReader in ^Writer out]
  (when-let [first-line (.readLine in)]
    (let [capacity (Long/parseLong (.trim ^String first-line))
          cache    (new-cache capacity)]
      (loop []
        (when-let [line (.readLine in)]
          (let [line (.trim ^String line)]
            (when-not (.isEmpty line)
              (run-command! cache capacity out line)))
          (recur)))))
  (.flush out))

(defn -main [& _]
  (let [in  (BufferedReader. (InputStreamReader. System/in StandardCharsets/ISO_8859_1) 65536)
        out (BufferedWriter. (OutputStreamWriter. System/out StandardCharsets/ISO_8859_1) 65536)]
    (run in out)
    (shutdown-agents)))
