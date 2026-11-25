(ns kvhttp.handler
  "Ring handler implementing the kvhttp routes."
  (:require [clojure.data.json :as json]
            [kvhttp.store :as store])
  (:import (java.io InputStream)))

(def ^:private key-pattern #"[A-Za-z0-9_-]{1,64}")

(def ^:private kv-prefix "/kv/")

(defn- response
  ([status] (response status nil))
  ([status body] {:status status :headers {} :body body}))

(def ^:private method-not-allowed (response 405))
(def ^:private not-found (response 404))

(defn- read-body
  ^bytes [{:keys [body]}]
  (cond
    (nil? body) (byte-array 0)
    (instance? InputStream body) (with-open [^InputStream in body] (.readAllBytes in))
    (string? body) (.getBytes ^String body "UTF-8")
    :else (byte-array 0)))

(defn- health [{:keys [request-method]}]
  (if (= :get request-method)
    (response 200 "ok")
    method-not-allowed))

(defn- list-keys [store {:keys [request-method]}]
  (if (= :get request-method)
    {:status 200
     :headers {"Content-Type" "application/json"}
     :body (json/write-str (vec (store/list-keys store)))}
    method-not-allowed))

(defn- entry [store k {:keys [request-method] :as req}]
  (case request-method
    :get (if-some [v (store/fetch store k)]
           {:status 200
            :headers {"Content-Type" "application/octet-stream"}
            :body (java.io.ByteArrayInputStream. ^bytes v)}
           not-found)
    :put (case (store/put! store k (read-body req))
           :created (response 201)
           :replaced (response 200))
    :delete (if (store/delete! store k)
              (response 204)
              not-found)
    method-not-allowed))

(defn make-handler
  "Returns a Ring handler serving the kvhttp API from `store`."
  [store]
  (fn [{:keys [^String uri] :as req}]
    (cond
      (= uri "/health") (health req)
      (= uri "/kv") (list-keys store req)
      (.startsWith uri kv-prefix)
      (let [k (subs uri (count kv-prefix))]
        (if (re-matches key-pattern k)
          (entry store k req)
          (response 400)))
      :else not-found)))
