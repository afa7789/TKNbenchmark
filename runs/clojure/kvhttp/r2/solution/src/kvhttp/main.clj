(ns kvhttp.main
  (:require [kvhttp.handler :as handler]
            [kvhttp.store :as store]
            [org.httpkit.server :as http])
  (:gen-class))

(defn- usage-exit []
  (binding [*out* *err*]
    (println "usage: app <port>"))
  (System/exit 2))

(defn -main [& args]
  (let [port (some-> (first args) parse-long)]
    (when-not (and port (< 0 port 65536))
      (usage-exit))
    (http/run-server (handler/make-handler (store/create))
                     {:ip "127.0.0.1"
                      :port port
                      :thread (max 8 (.availableProcessors (Runtime/getRuntime)))
                      :max-body (* 2 1024 1024)
                      :legacy-return-value? false})))
