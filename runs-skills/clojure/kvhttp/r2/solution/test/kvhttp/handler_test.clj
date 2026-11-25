(ns kvhttp.handler-test
  (:require [clojure.test :refer [deftest is testing]]
            [kvhttp.handler :as handler]
            [kvhttp.store :as store])
  (:import (java.io ByteArrayInputStream InputStream)))

(defn- req
  ([method uri] (req method uri nil))
  ([method uri ^String body]
   {:request-method method
    :uri uri
    :body (some-> body .getBytes ByteArrayInputStream.)}))

(defn- body-str [{:keys [body]}]
  (if (instance? InputStream body)
    (String. (.readAllBytes ^InputStream body))
    body))

(deftest routes
  (let [h (handler/make-handler (store/create))]
    (testing "health"
      (is (= "ok" (body-str (h (req :get "/health")))))
      (is (= 405 (:status (h (req :post "/health"))))))
    (testing "crud"
      (is (= 201 (:status (h (req :put "/kv/a" "hello")))))
      (is (= 200 (:status (h (req :put "/kv/a" "world")))))
      (is (= "world" (body-str (h (req :get "/kv/a")))))
      (is (= 204 (:status (h (req :delete "/kv/a")))))
      (is (= 404 (:status (h (req :delete "/kv/a")))))
      (is (= 404 (:status (h (req :get "/kv/a"))))))
    (testing "listing"
      (h (req :put "/kv/b" "2"))
      (h (req :put "/kv/a" "1"))
      (is (= "[\"a\",\"b\"]" (:body (h (req :get "/kv"))))))
    (testing "errors"
      (is (= 400 (:status (h (req :get "/kv/bad.key")))))
      (is (= 400 (:status (h (req :get "/kv/")))))
      (is (= 400 (:status (h (req :get "/kv/a/b")))))
      (is (= 400 (:status (h (req :get (str "/kv/" (apply str (repeat 65 "x"))))))))
      (is (= 405 (:status (h (req :patch "/kv/a")))))
      (is (= 405 (:status (h (req :post "/kv")))))
      (is (= 404 (:status (h (req :get "/nope"))))))))
