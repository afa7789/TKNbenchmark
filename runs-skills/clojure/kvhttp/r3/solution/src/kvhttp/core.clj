(ns kvhttp.core
  "In-memory HTTP/1.1 key-value server."
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
  ^bytes [body]
  (if (instance? InputStream body)
    (with-open [^InputStream in body] (.readAllBytes in))
    (byte-array 0)))

;; ---------------------------------------------------------------- handlers

(defn- health [{:keys [request-method]}]
  (case request-method
    :get (response 200 "ok")
    (response 405)))

(defn- list-keys [store {:keys [request-method]}]
  (case request-method
    :get {:status  200
          :headers {"Content-Type" "application/json"}
          :body    (json/write-str (keys @store))}
    (response 405)))

(defn- put-value [store k body]
  (let [v (read-body body)]
    (if (> (alength v) max-value-bytes)
      (response 413)
      (let [[old _] (swap-vals! store assoc k v)]
        (response (if (contains? old k) 200 201))))))

(defn- delete-value [store k]
  (let [[old _] (swap-vals! store dissoc k)]
    (response (if (contains? old k) 204 404))))

(defn- get-value [store k]
  (if-some [v (get @store k)]
    {:status  200
     :headers {"Content-Type" "application/octet-stream"}
     :body    (java.io.ByteArrayInputStream. ^bytes v)}
    (response 404)))

(defn- entry [store {:keys [request-method body]} k]
  (cond
    (not (#{:get :put :delete} request-method)) (response 405)
    (not (re-matches key-pattern k))            (response 400)
    :else (case request-method
            :get    (get-value store k)
            :put    (put-value store k body)
            :delete (delete-value store k))))

(defn make-handler
  "Returns a ring handler backed by `store`, an atom holding a sorted map of
  key -> byte array."
  [store]
  (fn [{:keys [^String uri] :as req}]
    (cond
      (= uri "/health")              (health req)
      (= uri "/kv")                  (list-keys store req)
      (str/starts-with? uri "/kv/")  (entry store req (subs uri 4))
      :else                          (response 404))))

;; ---------------------------------------------------------------- entry point

(defn start!
  "Starts the server on 127.0.0.1:`port`; returns the http-kit server."
  [port]
  (http/run-server (make-handler (atom (sorted-map)))
                   {:ip                   "127.0.0.1"
                    :port                 port
                    :thread               (max 8 (* 2 (.availableProcessors (Runtime/getRuntime))))
                    :max-body             (* 2 max-value-bytes)
                    :legacy-return-value? false}))

(defn -main [& [port]]
  (if-let [p (some-> port parse-long)]
    (do (start! p)
        @(promise))
    (binding [*out* *err*]
      (println "usage: app <port>")
      (System/exit 2))))
