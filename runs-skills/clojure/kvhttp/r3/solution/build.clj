(ns build
  (:require [clojure.tools.build.api :as b]))

(def class-dir "target/classes")
(def uber-file "target/kvhttp-standalone.jar")
(def basis (delay (b/create-basis {:project "deps.edn"})))

(defn clean [_]
  (b/delete {:path "target"}))

(defn uber [_]
  (clean nil)
  (b/copy-dir {:src-dirs ["src"] :target-dir class-dir})
  (b/compile-clj {:basis        @basis
                  :ns-compile   '[kvhttp.core]
                  :class-dir    class-dir
                  :compile-opts {:direct-linking true}})
  (b/uber {:class-dir class-dir
           :uber-file uber-file
           :basis     @basis
           :main      'kvhttp.core}))
