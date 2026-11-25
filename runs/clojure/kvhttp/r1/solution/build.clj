(ns build
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/kvhttp.jar")
(def basis (delay (b/create-basis {:project "deps.edn"})))

(defn clean [_]
  (b/delete {:path "target"}))

(defn uber [_]
  (clean nil)
  (b/compile-clj {:basis @basis
                  :ns-compile '[kvhttp.main]
                  :class-dir class-dir
                  :compile-opts {:direct-linking true
                                 :elide-meta [:doc :file :line :added]}})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :basis @basis
           :main 'kvhttp.main}))
