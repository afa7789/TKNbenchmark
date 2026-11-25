(ns wordfreq.core
  "Prints the ten most frequent ASCII words read from standard input.

  Words are counted without allocating a String per occurrence: the input
  buffer is lowercased in place and an open-addressing hash table refers to
  the first occurrence of each distinct word by offset and length."
  (:gen-class)
  (:import (java.io BufferedOutputStream PrintStream)
           (java.nio.charset StandardCharsets)
           (java.util Arrays Comparator PriorityQueue)))

(set! *warn-on-reflection* true)
(set! *unchecked-math* :warn-on-boxed)

(def ^:private top-n 10)

(defn- letter-lower
  "Returns the lowercase form of byte `b` if it is an ASCII letter, else -1."
  ^long [^long b]
  (cond
    (<= 97 b 122) b
    (<= 65 b 90) (+ b 32)
    :else -1))

(definterface ^:private WordCounter
  (^void add [^long start ^long end ^long hash]
   "Counts the word buf[start, end) whose 32-bit hash is `hash`.")
  (entries []
   "Returns a vector of [word count] for every distinct word."))

(defn- grow-ints ^ints [^ints a]
  (Arrays/copyOf a (* 2 (alength a))))

(defn- rehash
  "Returns a slot array of `cap` entries indexing the first `size` hashes."
  ^ints [^ints hashes ^long size ^long cap]
  (let [slots (int-array cap)
        mask (dec cap)]
    (dotimes [e size]
      (loop [j (bit-and (aget hashes e) mask)]
        (if (zero? (aget slots j))
          (aset slots j (int (inc e)))
          (recur (bit-and (inc j) mask)))))
    slots))

;; Entry e lives at index e of the parallel arrays; `slots` holds e + 1, 0 = empty.
(deftype ^:private WordTable [^bytes buf
                              ^:unsynchronized-mutable ^ints slots
                              ^:unsynchronized-mutable ^ints starts
                              ^:unsynchronized-mutable ^ints lens
                              ^:unsynchronized-mutable ^ints hashes
                              ^:unsynchronized-mutable ^longs counts
                              ^:unsynchronized-mutable ^long size]
  WordCounter
  (add [_ start end hash]
    (let [len (- end start)
          mask (dec (alength slots))]
      (loop [i (bit-and hash mask)]
        (let [slot (aget slots i)]
          (if (zero? slot)
            (do
              (when (= size (alength starts))
                (set! starts (grow-ints starts))
                (set! lens (grow-ints lens))
                (set! hashes (grow-ints hashes))
                (set! counts (Arrays/copyOf counts (* 2 (alength counts)))))
              (aset starts size (int start))
              (aset lens size (int len))
              (aset hashes size (unchecked-int hash))
              (aset counts size 1)
              (set! size (inc size))
              (aset slots i (int size))
              (when (> (* 2 size) (alength slots))
                (set! slots (rehash hashes size (* 2 (alength slots))))))
            (let [e (dec slot)
                  s (aget starts e)]
              (if (and (= (unchecked-int hash) (aget hashes e))
                       (= len (aget lens e))
                       (Arrays/equals buf s (+ s (int len)) buf (int start) (int end)))
                (aset counts e (inc (aget counts e)))
                (recur (bit-and (inc i) mask)))))))))
  (entries [_]
    (mapv (fn [^long e]
            [(String. buf (aget starts e) (aget lens e) StandardCharsets/ISO_8859_1)
             (aget counts e)])
          (range size))))

(defn- word-table ^WordTable [^bytes buf]
  (let [cap 1024]
    (WordTable. buf (int-array (* 4 cap)) (int-array cap) (int-array cap)
                (int-array cap) (long-array cap) 0)))

(defn- finish-hash ^long [^long h]
  (bit-xor h (unsigned-bit-shift-right h 16)))

(defn count-words
  "Counts the ASCII-letter words in `buf` case-insensitively, folding its
  letters to lowercase in place. Returns [word count] pairs in no order."
  [^bytes buf]
  (let [table (word-table buf)
        n (alength buf)]
    (loop [i 0, start -1, h 0]
      (if (< i n)
        (let [c (letter-lower (aget buf i))]
          (cond
            (not (neg? c))
            (do (aset buf i (unchecked-byte c))
                (recur (inc i)
                       (if (neg? start) i start)
                       (bit-and (+ (* 31 h) c) 0xffffffff)))

            (neg? start) (recur (inc i) -1 0)

            :else (do (.add table start i (finish-hash h))
                      (recur (inc i) -1 0))))
        (when-not (neg? start)
          (.add table start n (finish-hash h)))))
    (.entries table)))

(def ^:private by-rank
  "Orders [word count] pairs by count descending, then word ascending."
  (reify Comparator
    (compare [_ a b]
      (let [[^String wa ^long na] a
            [^String wb ^long nb] b
            c (Long/compare nb na)]
        (if (zero? c) (.compareTo wa wb) c)))))

(defn top-words
  "Returns up to `k` [word count] pairs, ranked by count descending then word
  ascending, using a bounded heap whose head is the weakest pair kept."
  [pairs ^long k]
  (let [heap (PriorityQueue. (max 1 k) (.reversed ^Comparator by-rank))]
    (doseq [p pairs]
      (.offer heap p)
      (when (> (.size heap) k)
        (.poll heap)))
    (sort by-rank (vec heap))))

(defn -main [& _]
  (let [buf (.readAllBytes System/in)
        out (PrintStream. (BufferedOutputStream. System/out) false "US-ASCII")]
    (doseq [[word n] (top-words (count-words buf) top-n)]
      (.print out (str n " " word "\n")))
    (.flush out)))
