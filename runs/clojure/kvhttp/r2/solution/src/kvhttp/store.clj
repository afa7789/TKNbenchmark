(ns kvhttp.store
  "Thread-safe in-memory key-value store. Keys are kept sorted so listing
  is a cheap traversal.")

(defn create
  "Returns a new, empty store."
  []
  (atom (sorted-map)))

(defn put!
  "Stores `value` under `k`. Returns :created if the key was new,
  :replaced otherwise."
  [store k value]
  (let [[old _] (swap-vals! store assoc k value)]
    (if (contains? old k) :replaced :created)))

(defn fetch
  "Returns the value stored under `k`, or nil."
  [store k]
  (get @store k))

(defn delete!
  "Removes `k`. Returns true if it was present."
  [store k]
  (let [[old _] (swap-vals! store dissoc k)]
    (contains? old k)))

(defn list-keys
  "Returns all keys in ascending order."
  [store]
  (keys @store))
