(ns kvhttp.main
  "Entry point: `app <port>` serves the key-value API on 127.0.0.1."
  (:require [kvhttp.handler :as handler]
            [kvhttp.store :as store]
            [org.httpkit.server :as http])
  (:gen-class))

(def ^:private max-body-bytes
  "Values may be up to 1 MiB; leave headroom for the transport."
  (* 8 1024 1024))

(defn start!
  "Starts the server on `port` and returns the http-kit server instance."
  [port]
  (http/run-server (handler/make-handler (store/create))
                   {:ip "127.0.0.1"
                    :port port
                    :thread 64
                    :max-body max-body-bytes
                    :legacy-return-value? false}))

(defn- usage! []
  (binding [*out* *err*]
    (println "usage: app <port>"))
  (System/exit 2))

(defn -main [& args]
  (if-let [port (some-> (first args) parse-long)]
    (do (start! port)
        @(promise))
    (usage!)))
