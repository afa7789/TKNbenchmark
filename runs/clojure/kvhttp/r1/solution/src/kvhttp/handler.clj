(ns kvhttp.handler
  "Ring handler implementing the kvhttp routes."
  (:require [clojure.data.json :as json]
            [kvhttp.store :as store])
  (:import (java.io InputStream)))

(def ^:private key-pattern #"[A-Za-z0-9_-]{1,64}")

(def ^:private empty-body (byte-array 0))

(defn- response
  ([status] (response status empty-body))
  ([status body] {:status status :headers {} :body body}))

(defn- text [status ^String s]
  (-> (response status (.getBytes s "UTF-8"))
      (assoc-in [:headers "Content-Type"] "text/plain; charset=utf-8")))

(defn- method-not-allowed [allowed]
  (-> (response 405)
      (assoc-in [:headers "Allow"] allowed)))

(defn- read-body ^bytes [body]
  (cond
    (nil? body) empty-body
    (instance? InputStream body) (.readAllBytes ^InputStream body)
    (bytes? body) body
    :else (.getBytes (str body) "UTF-8")))

(defn- health [{:keys [request-method]}]
  (if (= :get request-method)
    (text 200 "ok")
    (method-not-allowed "GET")))

(defn- list-keys [db {:keys [request-method]}]
  (if (= :get request-method)
    (-> (response 200 (.getBytes ^String (json/write-str (store/list-keys db)) "UTF-8"))
        (assoc-in [:headers "Content-Type"] "application/json"))
    (method-not-allowed "GET")))

(defn- item [db k {:keys [request-method body]}]
  (cond
    (not (re-matches key-pattern k)) (response 400)

    (= :get request-method)
    (if-some [v (store/lookup db k)]
      (-> (response 200 v)
          (assoc-in [:headers "Content-Type"] "application/octet-stream"))
      (response 404))

    (= :put request-method)
    (response (if (store/put! db k (read-body body)) 201 200))

    (= :delete request-method)
    (response (if (store/delete! db k) 204 404))

    :else (method-not-allowed "GET, PUT, DELETE")))

(defn make-handler
  "Returns a Ring handler backed by the store `db`."
  [db]
  (fn [{:keys [uri] :as req}]
    (cond
      (= uri "/health") (health req)
      (= uri "/kv") (list-keys db req)
      (.startsWith ^String uri "/kv/") (item db (subs uri 4) req)
      :else (response 404))))
