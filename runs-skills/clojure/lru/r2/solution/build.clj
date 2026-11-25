(ns build
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/lru-standalone.jar")
(def basis (delay (b/create-basis {:project "deps.edn"})))

(defn clean [_]
  (b/delete {:path "target"}))

(defn uber [_]
  (clean nil)
  (b/compile-clj {:basis @basis
                  :src-dirs ["src"]
                  :ns-compile '[lru.core]
                  :class-dir class-dir
                  :compiler-options {:direct-linking true
                                     :elide-meta [:doc :file :line :added]}})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :basis @basis
           :main 'lru.core}))
