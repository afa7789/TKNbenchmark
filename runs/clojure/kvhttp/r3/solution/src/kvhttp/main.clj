(ns kvhttp.main
  "Entry point: `app <port>` serves the kvhttp API on 127.0.0.1:<port>."
  (:require [kvhttp.handler :as handler]
            [kvhttp.store :as store]
            [org.httpkit.server :as http])
  (:gen-class))

(def ^:private max-body-bytes
  "Values are capped at 1 MiB; leave headroom so oversized bodies are not cut mid-read."
  (* 8 1024 1024))

(defn- usage-exit []
  (binding [*out* *err*]
    (println "usage: app <port>"))
  (System/exit 2))

(defn- parse-port [s]
  (let [port (parse-long (str s))]
    (when (and port (< 0 port 65536)) port)))

(defn -main [& args]
  (let [port (or (some-> args first parse-port) (usage-exit))]
    (http/run-server (handler/make-handler (store/create))
                     {:ip "127.0.0.1"
                      :port port
                      :thread (max 8 (.availableProcessors (Runtime/getRuntime)))
                      :max-body max-body-bytes
                      :legacy-return-value? false})
    @(promise)))
