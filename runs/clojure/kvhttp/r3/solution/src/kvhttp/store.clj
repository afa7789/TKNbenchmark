(ns kvhttp.store
  "Thread-safe in-memory key-value store backed by an atom holding a sorted map.")

(defn create
  "Returns a new, empty store."
  []
  (atom (sorted-map)))

(defn fetch
  "Returns the value stored under `k`, or nil."
  [store k]
  (get @store k))

(defn put!
  "Stores `v` under `k`. Returns :created if the key was new, :replaced otherwise."
  [store k v]
  (let [[old _] (swap-vals! store assoc k v)]
    (if (contains? old k) :replaced :created)))

(defn delete!
  "Removes `k`. Returns true if the key was present."
  [store k]
  (let [[old _] (swap-vals! store dissoc k)]
    (contains? old k)))

(defn list-keys
  "Returns every key, sorted ascending."
  [store]
  (keys @store))
