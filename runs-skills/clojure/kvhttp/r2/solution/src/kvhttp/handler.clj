(ns kvhttp.handler
  "Ring handler implementing the kvhttp routes."
  (:require [clojure.data.json :as json]
            [kvhttp.store :as store])
  (:import (java.io ByteArrayInputStream InputStream)))

(set! *warn-on-reflection* true)

(def ^:private key-pattern #"[A-Za-z0-9_-]{1,64}")

(def ^:private empty-bytes (byte-array 0))

(defn valid-key?
  "True if `s` is a syntactically valid key."
  [s]
  (boolean (re-matches key-pattern s)))

(defn- response
  ([status] (response status nil))
  ([status body] {:status status :headers {} :body body}))

(defn- bytes-response [^bytes value]
  {:status 200
   :headers {"Content-Type" "application/octet-stream"
             "Content-Length" (str (alength value))}
   :body (ByteArrayInputStream. value)})

(defn- read-body ^bytes [{:keys [body]}]
  (if body
    (.readAllBytes ^InputStream body)
    empty-bytes))

(defn- method-not-allowed [allowed]
  (assoc-in (response 405) [:headers "Allow"] allowed))

(defn- health [{:keys [request-method]}]
  (if (= :get request-method)
    {:status 200 :headers {"Content-Type" "text/plain"} :body "ok"}
    (method-not-allowed "GET")))

(defn- list-keys [kv {:keys [request-method]}]
  (if (= :get request-method)
    {:status 200
     :headers {"Content-Type" "application/json"}
     :body (json/write-str (store/all-keys kv))}
    (method-not-allowed "GET")))

(defn- item [kv k {:keys [request-method] :as req}]
  (cond
    (not (valid-key? k))
    (response 400)

    (= :get request-method)
    (if-let [value (store/fetch kv k)]
      (bytes-response value)
      (response 404))

    (= :put request-method)
    (case (store/put! kv k (read-body req))
      :created (response 201)
      :replaced (response 200))

    (= :delete request-method)
    (response (if (store/delete! kv k) 204 404))

    :else
    (method-not-allowed "GET, PUT, DELETE")))

(def ^:private item-prefix "/kv/")

(defn make-handler
  "Returns a Ring handler serving the routes over the store `kv`."
  [kv]
  (fn [{:keys [^String uri] :as req}]
    (cond
      (= "/health" uri) (health req)
      (= "/kv" uri) (list-keys kv req)
      (.startsWith uri item-prefix) (item kv (subs uri (count item-prefix)) req)
      :else (response 404))))
