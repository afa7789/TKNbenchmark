{-# LANGUAGE BangPatterns #-}

-- | A mutable, fixed-capacity LRU cache with O(1) expected-time operations.
--
-- Entries live in preallocated slots.  Recency is tracked by an intrusive
-- doubly linked list over slot indices (with a sentinel), and keys are
-- located through an open-addressing hash table with linear probing and
-- backward-shift deletion, so no tombstones accumulate.
module LRU
  ( LRU
  , new
  , set
  , get
  , delete
  , size
  ) where

import Control.Monad (when)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.IO (IOArray, IOUArray, newArray)
import Data.Bits (shiftR, xor, (.&.))
import qualified Data.ByteString as B
import qualified Data.ByteString.Unsafe as BU
import Data.IORef
import Data.Word (Word64)

type Key = B.ByteString
type Value = B.ByteString

data LRU = LRU
  { lruCap    :: !Int
  , lruMask   :: !Int                 -- ^ hash table size minus one
  , lruTable  :: !(IOUArray Int Int)  -- ^ slot index, or 'emptyCell'
  , lruKeys   :: !(IOArray Int Key)
  , lruVals   :: !(IOArray Int Value)
  , lruHashes :: !(IOUArray Int Int)  -- ^ cached hash of each slot's key
  , lruPrev   :: !(IOUArray Int Int)
  , lruNext   :: !(IOUArray Int Int)  -- ^ also threads the free list
  , lruFree   :: !(IORef Int)         -- ^ head of free list, or 'nil'
  , lruSize   :: !(IORef Int)
  }

emptyCell, nil :: Int
emptyCell = -1
nil = -1

-- | Index of the list sentinel: @next sentinel@ is the most recently used
-- slot, @prev sentinel@ the least recently used.
sentinel :: LRU -> Int
sentinel = lruCap

-- | Create an empty cache holding at most @cap@ (>= 1) keys.
new :: Int -> IO LRU
new cap = do
  let tableSize = until (>= 2 * cap) (* 2) 16
  table  <- newArray (0, tableSize - 1) emptyCell
  keys   <- newArray (0, cap - 1) B.empty
  vals   <- newArray (0, cap - 1) B.empty
  hashes <- newArray (0, cap - 1) 0
  prev   <- newArray (0, cap) cap
  next   <- newArray (0, cap) cap
  -- Free list: 0 -> 1 -> ... -> cap-1 -> nil.
  mapM_ (\i -> unsafeWrite next i (if i + 1 < cap then i + 1 else nil)) [0 .. cap - 1]
  unsafeWrite next cap cap
  free <- newIORef 0
  sz   <- newIORef 0
  pure LRU
    { lruCap = cap, lruMask = tableSize - 1, lruTable = table
    , lruKeys = keys, lruVals = vals, lruHashes = hashes
    , lruPrev = prev, lruNext = next, lruFree = free, lruSize = sz
    }

-- | Number of keys currently held.
size :: LRU -> IO Int
size = readIORef . lruSize

-- | Look up a key, marking it most recently used on a hit.
get :: LRU -> Key -> IO (Maybe Value)
get c k = do
  (_, slot) <- findKey c (hashKey k) k
  if slot == nil
    then pure Nothing
    else do
      touch c slot
      Just <$> unsafeRead (lruVals c) slot

-- | Insert or overwrite a key, making it most recently used and evicting
-- the least recently used key if capacity would be exceeded.
set :: LRU -> Key -> Value -> IO ()
set c k v = do
  let !h = hashKey k
  (pos, slot) <- findKey c h k
  if slot /= nil
    then do
      unsafeWrite (lruVals c) slot v
      touch c slot
    else do
      n <- readIORef (lruSize c)
      -- Evicting may shift table cells, so re-probe for the insert position.
      pos' <- if n >= lruCap c
                then evictLru c >> fst <$> findKey c h k
                else pure pos
      fresh <- allocSlot c
      unsafeWrite (lruKeys c) fresh k
      unsafeWrite (lruVals c) fresh v
      unsafeWrite (lruHashes c) fresh h
      unsafeWrite (lruTable c) pos' fresh
      linkFront c fresh
      modifyIORef' (lruSize c) (+ 1)

-- | Remove a key, reporting whether it was present.
delete :: LRU -> Key -> IO Bool
delete c k = do
  (pos, slot) <- findKey c (hashKey k) k
  if slot == nil
    then pure False
    else removeAt c pos slot >> pure True

------------------------------------------------------------------------
-- Internals

-- | FNV-1a over the key bytes, finished with a 64-bit mixer so that the
-- low bits used for indexing are well distributed.
hashKey :: Key -> Int
hashKey bs = fromIntegral (mix (go 0 14695981039346656037))
  where
    !len = B.length bs
    go :: Int -> Word64 -> Word64
    go !i !acc
      | i >= len  = acc
      | otherwise =
          go (i + 1) ((acc `xor` fromIntegral (BU.unsafeIndex bs i)) * 1099511628211)
    mix :: Word64 -> Word64
    mix x0 =
      let x1 = (x0 `xor` (x0 `shiftR` 33)) * 0xff51afd7ed558ccd
          x2 = (x1 `xor` (x1 `shiftR` 33)) * 0xc4ceb9fe1a85ec53
      in x2 `xor` (x2 `shiftR` 33)

-- | Probe for a key.  Returns the table position where the probe stopped
-- and the slot holding the key, or 'nil' (the position is then the empty
-- cell where the key would be inserted).
findKey :: LRU -> Int -> Key -> IO (Int, Int)
findKey c h k = go (h .&. lruMask c)
  where
    go !pos = do
      slot <- unsafeRead (lruTable c) pos
      if slot == emptyCell
        then pure (pos, nil)
        else do
          sh <- unsafeRead (lruHashes c) slot
          hit <- if sh /= h then pure False else (== k) <$> unsafeRead (lruKeys c) slot
          if hit then pure (pos, slot) else go ((pos + 1) .&. lruMask c)

-- | Table position of a slot known to be present.
positionOf :: LRU -> Int -> IO Int
positionOf c slot = do
  h <- unsafeRead (lruHashes c) slot
  let go !pos = do
        s <- unsafeRead (lruTable c) pos
        if s == slot then pure pos else go ((pos + 1) .&. lruMask c)
  go (h .&. lruMask c)

evictLru :: LRU -> IO ()
evictLru c = do
  victim <- unsafeRead (lruPrev c) (sentinel c)
  when (victim /= sentinel c) $ do
    pos <- positionOf c victim
    removeAt c pos victim

-- | Remove the entry at table position @pos@ occupying @slot@.
removeAt :: LRU -> Int -> Int -> IO ()
removeAt c pos slot = do
  unlink c slot
  shiftBack c pos
  -- Drop references so the old key/value can be collected.
  unsafeWrite (lruKeys c) slot B.empty
  unsafeWrite (lruVals c) slot B.empty
  readIORef (lruFree c) >>= unsafeWrite (lruNext c) slot
  writeIORef (lruFree c) slot
  modifyIORef' (lruSize c) (subtract 1)

-- | Backward-shift deletion for linear probing: vacate @hole@ and pull
-- later cells of the same cluster back so every key stays reachable.
shiftBack :: LRU -> Int -> IO ()
shiftBack c = go
  where
    mask = lruMask c
    table = lruTable c
    go !hole = scan hole ((hole + 1) .&. mask)
      where
        scan !_ !j = do
          s <- unsafeRead table j
          if s == emptyCell
            then unsafeWrite table hole emptyCell
            else do
              home <- (.&. mask) <$> unsafeRead (lruHashes c) s
              -- Can the entry at j move into the hole?  Only if its home
              -- position is not cyclically within (hole, j].
              let dist a b = (b - a) .&. mask
              if dist home j >= dist hole j
                then unsafeWrite table hole s >> go j
                else scan hole ((j + 1) .&. mask)

allocSlot :: LRU -> IO Int
allocSlot c = do
  slot <- readIORef (lruFree c)
  unsafeRead (lruNext c) slot >>= writeIORef (lruFree c)
  pure slot

unlink :: LRU -> Int -> IO ()
unlink c slot = do
  p <- unsafeRead (lruPrev c) slot
  n <- unsafeRead (lruNext c) slot
  unsafeWrite (lruNext c) p n
  unsafeWrite (lruPrev c) n p

linkFront :: LRU -> Int -> IO ()
linkFront c slot = do
  let s = sentinel c
  first <- unsafeRead (lruNext c) s
  unsafeWrite (lruPrev c) slot s
  unsafeWrite (lruNext c) slot first
  unsafeWrite (lruPrev c) first slot
  unsafeWrite (lruNext c) s slot

-- | Mark a present slot as most recently used.
touch :: LRU -> Int -> IO ()
touch c slot = do
  first <- unsafeRead (lruNext c) (sentinel c)
  when (first /= slot) $ unlink c slot >> linkFront c slot
