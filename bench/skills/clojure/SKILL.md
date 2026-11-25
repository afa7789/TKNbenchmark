---
name: clojure
description: "Version-correct, idiomatic Clojure for the installed toolchain (Clojure CLI version 1.12.7.1681): API, build commands, idioms and pitfalls. Use whenever writing, building, testing or fixing Clojure code."
---

# Clojure 1.12 (JVM) with the Clojure CLI

Target: Clojure **1.12.7** (latest stable), deps.edn, tools.build. 1.13 is alpha, so **don't use** `req!`, `merge-deep`, `transform-keys`, or `:select`/`:missing`/`:excess` destructuring. Use Leiningen only if `project.clj` exists.

## Project layout
```
deps.edn  build.clj  src/acme/my_app/core.clj  test/acme/my_app/core_test.clj  resources/
```
Namespace `acme.my-app.core` goes in `acme/my_app/core.clj` (dashes become underscores, 2+ segments). Test namespaces end in `-test`.

```clojure
;; deps.edn: pin exact versions, never RELEASE/LATEST
{:paths ["src" "resources"]
 :deps {org.clojure/clojure {:mvn/version "1.12.7"}}
 :aliases
 {:run   {:main-opts ["-m" "acme.my-app.core"]}
  :test  {:extra-paths ["test"]
          :extra-deps {io.github.cognitect-labs/test-runner
                       {:git/tag "v0.5.1" :git/sha "dfb30dd"}}
          :main-opts ["-m" "cognitect.test-runner"]
          :exec-fn cognitect.test-runner.api/test}
  :build {:deps {io.github.clojure/tools.build
                 {:git/tag "v0.10.14" :git/sha "1176afd"}}
          :ns-default build}}}
```

## Commands
| Task | Command |
|---|---|
| Run main | `clojure -M:run arg1` or `clojure -M -m acme.my-app.core` |
| Call fn with a map arg | `clojure -X acme.my-app.core/run :port 8080 :name '"Bo Bo"'` |
| All tests | `clojure -X:test` or `clojure -M:test` |
| One test var | `clojure -M:test -v acme.my-app.core-test/foo` (`-n ns`, `-i :tag`) |
| Uberjar | `clojure -T:build uber` then `java -jar target/my-app-0.1.0-standalone.jar` |
| Fetch deps / dep tree | `clojure -P -M:test` / `clojure -Stree` |
| Latest versions | `clojure -X:deps find-versions :lib org.clojure/data.json` |

`-X`/`-T` values are EDN, so strings need double quoting (`'"text"'`) and collections need single quotes (`:dirs '["test"]'`). `-T` leaves out project `:deps`/`:paths`.

```clojure
;; build.clj
(ns build (:require [clojure.tools.build.api :as b]))
(def lib 'acme/my-app)
(def version "0.1.0")
(def class-dir "target/classes")
(def basis (delay (b/create-basis {:project "deps.edn"})))
(def uber-file (format "target/%s-%s-standalone.jar" (name lib) version))
(defn clean [_] (b/delete {:path "target"}))
(defn uber [_]
  (clean nil)
  (b/copy-dir {:src-dirs ["src" "resources"] :target-dir class-dir})
  (b/compile-clj {:basis @basis :ns-compile '[acme.my-app.core] :class-dir class-dir})
  (b/uber {:class-dir class-dir :uber-file uber-file :basis @basis
           :main 'acme.my-app.core}))
;; lib jar: b/write-pom {:class-dir :lib :version :basis :src-dirs}, copy-dir, b/jar {:class-dir :jar-file}
```
The uberjar main ns **must** have `(:gen-class)` plus `(defn -main [& args] ...)`, or you get `Could not find or load main class`. `-M -m` doesn't need it.

## Java interop: new in 1.12
```clojure
(map Long/parseLong ["1" "2"])          ; static method as a fn value
(map String/.toUpperCase ["a" "b"])     ; instance method as a fn value: Class/.method
(map ^[String] StringBuilder/new ["x"]) ; constructor as a value; ^[...] = :param-tags
(map ^[long] Long/toString [1 2])       ; pick an overload; use _ for "any"
String/1  long/2                        ; array classes (replaces "[Ljava.lang.String;")
(defn n ^long [^String/1 xs] (alength xs))
(.removeIf (java.util.ArrayList. [1 2 3]) even?) ; fns auto-convert to functional interfaces
(let [^java.util.function.Predicate p even?] ...)  ; hint once to avoid re-adapting
(.get ^java.util.function.Supplier (delay 5))     ; delay/future/atom are Suppliers
(stream-into! [] (map inc) (.stream [1 2 3]))     ; also stream-seq! stream-reduce! stream-transduce!
```
Without param-tags, an overloaded method value uses **reflection**. Instance fields are `(.-x obj)`. Static fields take no parens: `System/out`.

## Core APIs that agents forget (1.11+/1.12)
- `parse-long` `parse-double` `parse-boolean` `parse-uuid` return `nil` on bad input instead of throwing.
- `update-vals` `update-keys` `abs` `random-uuid` `iteration` (paginated APIs: `:initk :kf :vf :somef`)
- `partitionv` `partitionv-all` `splitv-at` return vectors, but `(splitv-at 2 [1 2 3 4])` gives `[[1 2] (3 4)]`.
- Prefer `clojure.math` over `Math/`.
- `clojure.java.process`: `(p/exec "git" "status")` returns stdout *including the trailing newline*, so wrap it in `str/trim`. Use `p/start` for a `Process`.
- REPL only: `(add-lib 'org.clojure/data.json {:mvn/version "2.5.2"})`, `add-libs`, `sync-deps`. Auto-referred in the `clj` REPL's `user` ns. Also add the dep to deps.edn.
- `(requiring-resolve 'ns/sym)` loads and resolves lazily.

## Performance idioms
- Put `(set! *warn-on-reflection* true)` after `ns` and fix each warning with a hint (`^String s`, or a return hint before the args: `(defn f ^long [^long x] ...)`). Primitive args can only be `long`/`double`, with at most 4 args.
- During development, `(set! *unchecked-math* :warn-on-boxed)` reports boxed arithmetic.
- In hot paths, use transducers (`(into [] (comp (filter odd?) (map inc)) xs)`, `transduce`) rather than chained lazy seqs. Use `reduce`/`reduce-kv` for folds and `transient` for big local builds.
- Use `case` for constant dispatch (O(1)). Note that `count` realizes lazy seqs.

## Laziness traps
- `(with-open [r (io/reader f)] (line-seq r))` throws **`IOException: Stream closed`** because the seq escapes. Realize it inside with `(into [] (line-seq r))` or `reduce`.
- `binding` + lazy `map` loses the binding once the seq is realized outside. Use `mapv`/`doall`.
- `map`/`for` with side effects do nothing if not consumed. Use `run!`/`doseq`.

## Reloading gotchas
- Redefining `defmulti` keeps the old dispatch fn, so `(ns-unmap *ns* 'm)` first.
- Re-evaluating `defrecord`/`deftype` makes a new class, so old instances fail `instance?`/protocols.
- `(require 'my.ns :reload)` after editing files. Restart the JVM after changing deps.edn (or use `add-lib`).

## Error → fix
| Message | Fix |
|---|---|
| `Could not locate a/b_c__init.class, a/b_c.clj...` | file path/underscore mismatch, missing `:paths`, or missing dep |
| `Syntax error (ClassNotFoundException) ... clojure.set` | namespace used but not `require`d |
| `No such namespace: str` / `No such var: str/x` | add the alias to `:require`; fix the name |
| `Unable to resolve symbol: foo` | define before use, `declare`, or require |
| `Wrong number of args (2) passed to: user/f` | arity; check `->` vs `->>` |
| `... cannot be cast to class clojure.lang.IFn` | extra parens, or calling a non-fn value |
| `Don't know how to create ISeq from: java.lang.Long` | scalar where a coll is expected |
| `Can only recur from tail position` / `Mismatched argument count to recur` | recur only in tail position, matching the arity |
| `failed: even-number-of-forms?` | odd `let`/`loop` bindings |
| `No matching ctor found` / `No matching method X found taking N args` | Java arg count/types; hint or coerce |
| `cannot be cast to class clojure.lang.IAtom` | `swap!` on a plain map; wrap with `(atom ...)` |
| `No method in multimethod 'm' for dispatch value` | add a `:default` method |

## Style (community guide + agent rules)
- `ns` order: `:refer-clojure`, `:require`, `:import`. Use `:as` aliases (`str`, `set`, `io`, `edn`) and never `:use`. Always require `clojure.edn`, even though the REPL preloads it.
- The docstring goes **before** the arg vector. Name things `kebab-case`, `pred?`, `effect!`, `a->b`, and keep `*earmuffs*` for `^:dynamic` only.
- Throw `(ex-info "msg" {...})`, catch `clojure.lang.ExceptionInfo`, and read it with `ex-message`/`ex-data`. Don't catch `Throwable`.
- Don't shadow core names (`name`, `count`, `map`, `key`, `type`, `str`) in locals or destructuring.
- Model data as plain maps with keywords. Use records only for protocol dispatch. Never `def` inside functions.
- Verify edits by evaluating them (REPL or `clojure -M -e`). If delimiters break, rewrite the whole top-level form instead of patching parens. Run `clj-kondo --lint src test` if it's installed.
