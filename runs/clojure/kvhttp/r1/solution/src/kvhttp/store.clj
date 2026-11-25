(ns kvhttp.store
  "In-memory key-value store. Keys are kept sorted so listing is cheap.")

(defn create
  "Returns a new, empty store."
  []
  (atom (sorted-map)))

(defn put!
  "Stores `value` under `k`. Returns true if the key was new."
  [store k value]
  (let [[old _] (swap-vals! store assoc k value)]
    (not (contains? old k))))

(defn lookup
  "Returns the value stored under `k`, or nil."
  [store k]
  (get @store k))

(defn delete!
  "Removes `k`. Returns true if it was present."
  [store k]
  (let [[old _] (swap-vals! store dissoc k)]
    (contains? old k)))

(defn list-keys
  "Returns every key in ascending order."
  [store]
  (vec (keys @store)))
