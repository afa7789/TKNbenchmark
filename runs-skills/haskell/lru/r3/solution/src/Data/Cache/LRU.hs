-- | A mutable, fixed-capacity LRU cache from 'ByteString' keys to
-- 'ByteString' values, with O(1) expected time per operation.
--
-- Entries live in a pool of preallocated nodes, threaded onto a circular
-- doubly linked list ordered by recency (a sentinel node marks both ends).
-- An open-addressing hash table with linear probing and backward-shift
-- deletion maps keys to nodes; it is sized to stay at most half full.
module Data.Cache.LRU
  ( LRU
  , new
  , lookup
  , insert
  , delete
  , size
  ) where

import Prelude hiding (lookup)

import Control.Monad (when)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.IO (IOArray, IOUArray, newArray, newListArray)
import Data.Bits (shiftR, xor, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.Word (Word8)

-- | Node index used to mark an empty hash-table slot and the end of the
-- free list.
nil :: Int
nil = -1

data LRU = LRU
  { lruCapacity :: !Int
  , lruSentinel :: !Int
  -- ^ Index of the list sentinel: its next is the most recently used
  -- node, its prev the least recently used one.
  , lruMask :: !Int
  , lruSlots :: !(IOUArray Int Int)
  -- ^ Hash table: node index, or 'nil' for an empty slot.
  , lruHashes :: !(IOUArray Int Int)
  , lruPrev :: !(IOUArray Int Int)
  , lruNext :: !(IOUArray Int Int)
  -- ^ Recency links for live nodes; free-list links for free nodes.
  , lruKeys :: !(IOArray Int ByteString)
  , lruVals :: !(IOArray Int ByteString)
  , lruMeta :: !(IOUArray Int Int)
  -- ^ Mutable counters, see 'metaSize' and 'metaFree'.
  }

metaSize, metaFree :: Int
metaSize = 0
metaFree = 1

-- | Result of probing the hash table for a key.
data Probe
  = Found !Int !Int
  -- ^ Slot index and node index holding the key.
  | Vacant !Int
  -- ^ Empty slot where the key would be inserted.

-- | Create an empty cache holding at most the given number of keys
-- (clamped to at least one).
new :: Int -> IO LRU
new requested = do
  let cap = max 1 requested
      sentinel = cap
      tableSize = until (>= 2 * cap) (* 2) 2
  slots <- newArray (0, tableSize - 1) nil
  hashes <- newArray (0, cap - 1) 0
  prev <- newArray (0, cap) sentinel
  -- Initially every node is free, chained 0 -> 1 -> ... -> cap-1 -> nil;
  -- the sentinel points to itself.
  next <- newListArray (0, cap) ([1 .. cap - 1] ++ [nil, sentinel])
  keys <- newArray (0, cap - 1) BS.empty
  vals <- newArray (0, cap - 1) BS.empty
  meta <- newListArray (0, 1) [0, 0]
  pure
    LRU
      { lruCapacity = cap
      , lruSentinel = sentinel
      , lruMask = tableSize - 1
      , lruSlots = slots
      , lruHashes = hashes
      , lruPrev = prev
      , lruNext = next
      , lruKeys = keys
      , lruVals = vals
      , lruMeta = meta
      }

-- | Number of keys currently held.
size :: LRU -> IO Int
size c = unsafeRead (lruMeta c) metaSize

-- | Look up a key; a hit makes it the most recently used.
lookup :: LRU -> ByteString -> IO (Maybe ByteString)
lookup c key =
  probe c (hashKey key) key >>= \case
    Vacant _ -> pure Nothing
    Found _ node -> do
      touch c node
      Just <$> unsafeRead (lruVals c) node

-- | Insert or overwrite a key, making it the most recently used. If the
-- cache is full and the key is new, the least recently used key is evicted.
insert :: LRU -> ByteString -> ByteString -> IO ()
insert c key val =
  probe c h key >>= \case
    Found _ node -> do
      unsafeWrite (lruVals c) node val
      touch c node
    Vacant slot -> do
      n <- size c
      if n < lruCapacity c
        then add slot
        else do
          evict c
          -- Eviction may shift entries in the table; probe again.
          probe c h key >>= \case
            Vacant slot' -> add slot'
            Found _ _ -> pure () -- unreachable: the key was absent
  where
    h = hashKey key
    add slot = do
      node <- allocNode c
      unsafeWrite (lruKeys c) node key
      unsafeWrite (lruVals c) node val
      unsafeWrite (lruHashes c) node h
      unsafeWrite (lruSlots c) slot node
      pushFront c node
      adjustSize c 1

-- | Remove a key, reporting whether it was present.
delete :: LRU -> ByteString -> IO Bool
delete c key =
  probe c (hashKey key) key >>= \case
    Vacant _ -> pure False
    Found slot node -> True <$ removeEntry c slot node

------------------------------------------------------------------------
-- Entries

evict :: LRU -> IO ()
evict c = do
  node <- unsafeRead (lruPrev c) (lruSentinel c)
  when (node /= lruSentinel c) $ do
    h <- unsafeRead (lruHashes c) node
    slot <- slotOf c h node
    removeEntry c slot node

removeEntry :: LRU -> Int -> Int -> IO ()
removeEntry c slot node = do
  clearSlot c slot
  unlink c node
  -- Drop references so the key and value can be collected.
  unsafeWrite (lruKeys c) node BS.empty
  unsafeWrite (lruVals c) node BS.empty
  freeNode c node
  adjustSize c (-1)

adjustSize :: LRU -> Int -> IO ()
adjustSize c d = do
  n <- unsafeRead (lruMeta c) metaSize
  unsafeWrite (lruMeta c) metaSize (n + d)

------------------------------------------------------------------------
-- Node pool

-- | Take a node from the free list. Callers ensure the cache is not full,
-- so the free list is non-empty.
allocNode :: LRU -> IO Int
allocNode c = do
  node <- unsafeRead (lruMeta c) metaFree
  unsafeRead (lruNext c) node >>= unsafeWrite (lruMeta c) metaFree
  pure node

freeNode :: LRU -> Int -> IO ()
freeNode c node = do
  unsafeRead (lruMeta c) metaFree >>= unsafeWrite (lruNext c) node
  unsafeWrite (lruMeta c) metaFree node

------------------------------------------------------------------------
-- Recency list

unlink :: LRU -> Int -> IO ()
unlink c node = do
  p <- unsafeRead (lruPrev c) node
  n <- unsafeRead (lruNext c) node
  unsafeWrite (lruNext c) p n
  unsafeWrite (lruPrev c) n p

pushFront :: LRU -> Int -> IO ()
pushFront c node = do
  let s = lruSentinel c
  first <- unsafeRead (lruNext c) s
  unsafeWrite (lruPrev c) node s
  unsafeWrite (lruNext c) node first
  unsafeWrite (lruPrev c) first node
  unsafeWrite (lruNext c) s node

-- | Mark a live node as the most recently used.
touch :: LRU -> Int -> IO ()
touch c node = unlink c node >> pushFront c node

------------------------------------------------------------------------
-- Hash table

probe :: LRU -> Int -> ByteString -> IO Probe
probe c h key = go (h .&. lruMask c)
  where
    go !i = do
      node <- unsafeRead (lruSlots c) i
      if node == nil
        then pure (Vacant i)
        else do
          h' <- unsafeRead (lruHashes c) node
          if h' /= h
            then go (succ i .&. lruMask c)
            else do
              k <- unsafeRead (lruKeys c) node
              if k == key then pure (Found i node) else go (succ i .&. lruMask c)

-- | Slot holding a node known to be in the table.
slotOf :: LRU -> Int -> Int -> IO Int
slotOf c h node = go (h .&. lruMask c)
  where
    go !i = do
      n <- unsafeRead (lruSlots c) i
      if n == node then pure i else go (succ i .&. lruMask c)

-- | Empty a slot, shifting later entries of the probe run back so that no
-- tombstones are needed.
clearSlot :: LRU -> Int -> IO ()
clearSlot c = \hole -> go hole (next hole)
  where
    mask = lruMask c
    next i = succ i .&. mask
    go !hole !j = do
      node <- unsafeRead (lruSlots c) j
      if node == nil
        then unsafeWrite (lruSlots c) hole nil
        else do
          home <- (.&. mask) <$> unsafeRead (lruHashes c) node
          -- The entry may move into the hole only if the hole lies on its
          -- probe path, i.e. between its home slot and its current slot.
          if (j - home) .&. mask >= (j - hole) .&. mask
            then unsafeWrite (lruSlots c) hole node >> go j (next j)
            else go hole (next j)

-- | FNV-1a followed by a 64-bit finalizer so the low bits used for
-- indexing are well mixed.
hashKey :: ByteString -> Int
hashKey = fromIntegral . finalize . BS.foldl' step 0xcbf29ce484222325
  where
    step :: Word -> Word8 -> Word
    step h w = (h `xor` fromIntegral w) * 0x100000001b3
    finalize :: Word -> Word
    finalize = mix 33 . (* 0xc4ceb9fe1a85ec53) . mix 33 . (* 0xff51afd7ed558ccd) . mix 33
    mix n h = h `xor` (h `shiftR` n)
