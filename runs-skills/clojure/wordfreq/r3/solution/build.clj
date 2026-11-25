(ns build
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/wordfreq-standalone.jar")
(def basis (delay (b/create-basis {:project "deps.edn"})))

(defn clean [_]
  (b/delete {:path "target"}))

(defn uber [_]
  (clean nil)
  (b/compile-clj {:basis @basis
                  :ns-compile '[wordfreq.core]
                  :class-dir class-dir
                  :compiler-options {:direct-linking true}})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :basis @basis
           :main 'wordfreq.core}))
