(ns kvhttp.main
  "Entry point: `app <port>` serves the key-value API on 127.0.0.1."
  (:require [kvhttp.handler :as handler]
            [kvhttp.store :as store]
            [org.httpkit.server :as http])
  (:gen-class))

(def ^:private max-body
  "Largest accepted request body: 1 MiB values plus generous headroom."
  (* 8 1024 1024))

(defn- parse-port [s]
  (when-let [n (some-> s parse-long)]
    (when (<= 1 n 65535) n)))

(defn -main [& args]
  (if-let [port (parse-port (first args))]
    (do
      (http/run-server (handler/make-handler (store/create))
                       {:ip "127.0.0.1"
                        :port port
                        :thread (max 8 (.availableProcessors (Runtime/getRuntime)))
                        :max-body max-body
                        :legacy-return-value? false})
      (println (str "kvhttp listening on 127.0.0.1:" port)))
    (binding [*out* *err*]
      (println "usage: app <port>")
      (System/exit 2))))
