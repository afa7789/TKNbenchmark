(ns kvhttp.handler-test
  (:require [clojure.test :refer [deftest is testing]]
            [kvhttp.handler :as handler]
            [kvhttp.store :as store])
  (:import (java.io ByteArrayInputStream)))

(defn- request
  ([handler method uri] (request handler method uri nil))
  ([handler method uri ^String body]
   (handler {:request-method method
             :uri uri
             :body (some-> body (.getBytes "UTF-8") ByteArrayInputStream.)})))

(defn- body-str [resp] (String. ^bytes (:body resp) "UTF-8"))

(deftest crud
  (let [h (handler/make-handler (store/create))]
    (is (= 201 (:status (request h :put "/kv/a" "hello"))))
    (is (= "hello" (body-str (request h :get "/kv/a"))))
    (is (= 200 (:status (request h :put "/kv/a" "world"))))
    (is (= "world" (body-str (request h :get "/kv/a"))))
    (is (= 204 (:status (request h :delete "/kv/a"))))
    (is (= 404 (:status (request h :get "/kv/a"))))
    (is (= 404 (:status (request h :delete "/kv/a"))))))

(deftest listing
  (let [h (handler/make-handler (store/create))]
    (doseq [k ["b" "a" "c"]] (request h :put (str "/kv/" k) k))
    (let [resp (request h :get "/kv")]
      (is (= 200 (:status resp)))
      (is (= "application/json" (get-in resp [:headers "Content-Type"])))
      (is (= "[\"a\",\"b\",\"c\"]" (body-str resp))))))

(deftest errors
  (let [h (handler/make-handler (store/create))]
    (testing "invalid keys"
      (doseq [uri ["/kv/" "/kv/a/b" "/kv/bad.key" (str "/kv/" (apply str (repeat 65 "a")))]]
        (is (= 400 (:status (request h :get uri))) uri)))
    (testing "unknown paths"
      (doseq [uri ["/" "/nope" "/health/" "/kvx"]]
        (is (= 404 (:status (request h :get uri))) uri)))
    (testing "unsupported methods"
      (is (= 405 (:status (request h :post "/health"))))
      (is (= 405 (:status (request h :put "/kv"))))
      (is (= 405 (:status (request h :patch "/kv/a")))))))
