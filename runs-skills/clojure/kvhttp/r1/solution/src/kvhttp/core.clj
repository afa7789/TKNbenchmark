(ns kvhttp.core
  "In-memory HTTP key-value server."
  (:require [clojure.data.json :as json]
            [clojure.string :as str]
            [org.httpkit.server :as http])
  (:import (java.io InputStream))
  (:gen-class))

(set! *warn-on-reflection* true)

(def ^:private key-pattern #"[A-Za-z0-9_-]{1,64}")

(def ^:private max-value-bytes (* 1024 1024))

(defn- response
  ([status] (response status nil))
  ([status body] {:status status :headers {} :body body}))

(defn- read-body
  "Returns the request body as a byte array (empty when absent)."
  ^bytes [{:keys [body]}]
  (if (instance? InputStream body)
    (with-open [^InputStream in body] (.readAllBytes in))
    (byte-array 0)))

;; ---------------------------------------------------------------------------
;; Store operations: `store` is an atom holding a sorted map of key -> bytes.

(defn- put-value!
  "Stores `value` under `k`; returns true if the key was new."
  [store k value]
  (let [[before _] (swap-vals! store assoc k value)]
    (not (contains? before k))))

(defn- delete-value!
  "Removes `k`; returns true if it was present."
  [store k]
  (let [[before _] (swap-vals! store dissoc k)]
    (contains? before k)))

;; ---------------------------------------------------------------------------
;; Handlers

(defn- health [{:keys [request-method]}]
  (if (= :get request-method)
    (response 200 "ok")
    (response 405)))

(defn- list-keys [store {:keys [request-method]}]
  (if (= :get request-method)
    {:status 200
     :headers {"Content-Type" "application/json"}
     :body (json/write-str (vec (keys @store)))}
    (response 405)))

(defn- key-op [store k {:keys [request-method] :as req}]
  (case request-method
    :get (if-some [v (get @store k)]
           {:status 200
            :headers {"Content-Type" "application/octet-stream"}
            :body v}
           (response 404))
    :put (let [v (read-body req)]
           (cond
             (> (alength v) max-value-bytes) (response 413)
             (put-value! store k v) (response 201)
             :else (response 200)))
    :delete (if (delete-value! store k)
              (response 204)
              (response 404))
    (response 405)))

(defn make-handler
  "Returns a Ring handler backed by the atom `store`."
  [store]
  (fn [{:keys [uri] :as req}]
    (cond
      (= uri "/health") (health req)
      (= uri "/kv") (list-keys store req)
      (str/starts-with? uri "/kv/")
      (let [k (subs uri 4)]
        (if (re-matches key-pattern k)
          (key-op store k req)
          (response 400)))
      :else (response 404))))

(defn start!
  "Starts the server on 127.0.0.1:`port`; returns the http-kit server."
  [port]
  (http/run-server (make-handler (atom (sorted-map)))
                   {:ip "127.0.0.1"
                    :port port
                    :thread (max 8 (* 2 (.availableProcessors (Runtime/getRuntime))))
                    :max-body (* 2 max-value-bytes)
                    :legacy-return-value? false}))

(defn -main [& args]
  (let [port (some-> (first args) parse-long)]
    (when-not (and port (< 0 port 65536))
      (binding [*out* *err*] (println "usage: app <port>"))
      (System/exit 2))
    (start! port)
    @(promise)))
