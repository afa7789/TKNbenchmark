(ns kvhttp.store
  "In-memory key-value store backed by an atom holding a sorted map.")

(defn create
  "Returns a new, empty store."
  []
  (atom (sorted-map)))

(defn put!
  "Stores `value` under `k`. Returns `:created` if the key was new,
  `:replaced` otherwise."
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

(defn all-keys
  "Returns every key, sorted ascending."
  [store]
  (vec (keys @store)))
