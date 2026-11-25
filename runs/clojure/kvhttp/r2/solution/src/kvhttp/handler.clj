(ns kvhttp.handler
  "Ring handler implementing the kvhttp routes."
  (:require [clojure.string :as str]
            [kvhttp.store :as store])
  (:import (java.io ByteArrayOutputStream InputStream)))

(def ^:private key-pattern #"[A-Za-z0-9_-]{1,64}")

(def ^:private max-value-bytes (* 1024 1024))

(defn- response
  ([status] (response status ""))
  ([status body] {:status status :headers {} :body body}))

(def ^:private method-not-allowed (response 405))
(def ^:private not-found (response 404))

(defn- read-body ^bytes [body]
  (cond
    (nil? body) (byte-array 0)
    (bytes? body) body
    (string? body) (.getBytes ^String body "UTF-8")
    :else (let [out (ByteArrayOutputStream.)]
            (.transferTo ^InputStream body out)
            (.toByteArray out))))

(defn- keys->json
  "Encodes keys as a JSON array. Keys are validated against `key-pattern`,
  so they never need escaping."
  [ks]
  (str "[" (str/join "," (map #(str \" % \") ks)) "]"))

(defn- health [{:keys [request-method]}]
  (if (= :get request-method)
    (response 200 "ok")
    method-not-allowed))

(defn- list-all [db {:keys [request-method]}]
  (if (= :get request-method)
    {:status 200
     :headers {"Content-Type" "application/json"}
     :body (keys->json (store/list-keys db))}
    method-not-allowed))

(defn- item [db k {:keys [request-method body]}]
  (if-not (re-matches key-pattern k)
    (response 400)
    (case request-method
      :get (if-some [v (store/fetch db k)]
             {:status 200
              :headers {"Content-Type" "application/octet-stream"}
              :body v}
             not-found)
      :put (let [v (read-body body)]
             (if (> (alength v) max-value-bytes)
               (response 413)
               (response (case (store/put! db k v) :created 201 :replaced 200))))
      :delete (if (store/delete! db k) (response 204) not-found)
      method-not-allowed)))

(defn make-handler
  "Returns a Ring handler backed by the store `db`."
  [db]
  (fn [{:keys [uri] :as req}]
    (cond
      (= uri "/health") (health req)
      (= uri "/kv") (list-all db req)
      (str/starts-with? uri "/kv/") (item db (subs uri 4) req)
      :else not-found)))
