-- | A mutable, fixed-capacity LRU (least-recently-used) cache with
-- 'ByteString' keys and values.
--
-- Every operation runs in O(1) expected time. The implementation combines
--
--   * a node pool of @capacity@ slots holding keys, values and hashes,
--   * an intrusive doubly-linked recency list threaded through the pool
--     (with a sentinel node at index @capacity@), and
--   * an open-addressing hash index (linear probing, backward-shift
--     deletion) mapping keys to pool nodes.
module Data.LRU
  ( LRU
  , new
  , set
  , get
  , delete
  , size
  ) where

import Control.Monad (void, when)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.IO (IOArray, IOUArray, newArray)
import Data.Bits (shiftR, xor, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Word (Word64, Word8)

-- | Mutable LRU cache living in 'IO'.
data LRU = LRU
  { lruCapacity :: !Int
  , lruKeys     :: !(IOArray Int ByteString)
  , lruValues   :: !(IOArray Int ByteString)
  , lruHashes   :: !(IOUArray Int Int)
  , lruPrev     :: !(IOUArray Int Int)
  , lruNext     :: !(IOUArray Int Int)
    -- ^ Recency links; also threads the free list.
  , lruTable    :: !(IOUArray Int Int)
    -- ^ Hash index: @node + 1@ per slot, @0@ marks an empty slot.
  , lruMask     :: !Int
  , lruSize     :: !(IORef Int)
  , lruFresh    :: !(IORef Int)
    -- ^ Next never-used pool node.
  , lruFree     :: !(IORef Int)
    -- ^ Head of the free list of released nodes, or @-1@.
  }

-- | Index of the sentinel node: its 'lruNext' is the most recently used
-- node and its 'lruPrev' the least recently used one.
sentinel :: LRU -> Int
sentinel = lruCapacity

-- | Create an empty cache holding at most @capacity@ keys (at least one).
new :: Int -> IO LRU
new requested = do
  let capacity = max 1 requested
      slots    = until (>= 2 * capacity) (* 2) 16
  keys   <- newArray (0, capacity - 1) BS.empty
  values <- newArray (0, capacity - 1) BS.empty
  hashes <- newArray (0, capacity - 1) 0
  prev   <- newArray (0, capacity) capacity
  next   <- newArray (0, capacity) capacity
  table  <- newArray (0, slots - 1) 0
  LRU capacity keys values hashes prev next table (slots - 1)
    <$> newIORef 0
    <*> newIORef 0
    <*> newIORef (-1)

-- | Number of keys currently held.
size :: LRU -> IO Int
size = readIORef . lruSize

-- | Look up a key, marking it as most recently used on a hit.
get :: LRU -> ByteString -> IO (Maybe ByteString)
get lru key = do
  (_, node) <- locate lru key (hashKey key)
  if node < 0
    then pure Nothing
    else do
      touch lru node
      Just <$> unsafeRead (lruValues lru) node

-- | Insert or overwrite a key, making it the most recently used and
-- evicting the least recently used key if the capacity is exceeded.
set :: LRU -> ByteString -> ByteString -> IO ()
set lru key value = do
  let h = hashKey key
  (_, node) <- locate lru key h
  if node >= 0
    then do
      unsafeWrite (lruValues lru) node value
      touch lru node
    else do
      count <- size lru
      when (count >= lruCapacity lru) $ do
        victim <- unsafeRead (lruPrev lru) (sentinel lru)
        victimKey <- unsafeRead (lruKeys lru) victim
        void (delete lru victimKey)
      -- Deleting may shift entries, so probe again for a free slot.
      (slot, _) <- locate lru key h
      fresh <- allocate lru
      unsafeWrite (lruKeys lru) fresh key
      unsafeWrite (lruValues lru) fresh value
      unsafeWrite (lruHashes lru) fresh h
      unsafeWrite (lruTable lru) slot (fresh + 1)
      pushFront lru fresh
      modifyIORef' (lruSize lru) (+ 1)

-- | Remove a key, reporting whether it was present.
delete :: LRU -> ByteString -> IO Bool
delete lru key = do
  (slot, node) <- locate lru key (hashKey key)
  if node < 0
    then pure False
    else do
      unlink lru node
      release lru node
      removeSlot lru slot
      modifyIORef' (lruSize lru) (subtract 1)
      pure True

------------------------------------------------------------------------------
-- Hash index

-- | 64-bit FNV-1a followed by a final avalanche step, so that the low
-- bits used for slot selection depend on every input byte.
hashKey :: ByteString -> Int
hashKey = fromIntegral . avalanche . BS.foldl' step 0xcbf29ce484222325
  where
    step :: Word64 -> Word8 -> Word64
    step acc byte = (acc `xor` fromIntegral byte) * 0x100000001b3
    avalanche :: Word64 -> Word64
    avalanche x0 =
      let x1 = (x0 `xor` (x0 `shiftR` 33)) * 0xff51afd7ed558ccd
          x2 = (x1 `xor` (x1 `shiftR` 33)) * 0xc4ceb9fe1a85ec53
       in x2 `xor` (x2 `shiftR` 33)

-- | Find the slot for a key: returns the slot index together with the
-- matching node, or the first empty slot and @-1@ if the key is absent.
locate :: LRU -> ByteString -> Int -> IO (Int, Int)
locate lru key h = go (h .&. lruMask lru)
  where
    go !slot = do
      entry <- unsafeRead (lruTable lru) slot
      if entry == 0
        then pure (slot, -1)
        else do
          let node = entry - 1
          nodeHash <- unsafeRead (lruHashes lru) node
          matches <-
            if nodeHash /= h
              then pure False
              else (== key) <$> unsafeRead (lruKeys lru) node
          if matches
            then pure (slot, node)
            else go ((slot + 1) .&. lruMask lru)

-- | Empty a slot using backward-shift deletion, so that probe sequences
-- stay unbroken without tombstones.
removeSlot :: LRU -> Int -> IO ()
removeSlot lru = shift
  where
    mask = lruMask lru
    table = lruTable lru
    shift !hole = scan hole ((hole + 1) .&. mask)
    scan !hole !j = do
      entry <- unsafeRead table j
      if entry == 0
        then unsafeWrite table hole 0
        else do
          home <- (.&. mask) <$> unsafeRead (lruHashes lru) (entry - 1)
          -- The entry may fill the hole unless its home lies cyclically
          -- within (hole, j].
          let stays
                | hole <= j = hole < home && home <= j
                | otherwise = hole < home || home <= j
          if stays
            then scan hole ((j + 1) .&. mask)
            else do
              unsafeWrite table hole entry
              shift j

------------------------------------------------------------------------------
-- Node pool and recency list

allocate :: LRU -> IO Int
allocate lru = do
  free <- readIORef (lruFree lru)
  if free >= 0
    then do
      unsafeRead (lruNext lru) free >>= writeIORef (lruFree lru)
      pure free
    else do
      fresh <- readIORef (lruFresh lru)
      writeIORef (lruFresh lru) (fresh + 1)
      pure fresh

release :: LRU -> Int -> IO ()
release lru node = do
  readIORef (lruFree lru) >>= unsafeWrite (lruNext lru) node
  writeIORef (lruFree lru) node
  -- Drop references so released keys and values can be collected.
  unsafeWrite (lruKeys lru) node BS.empty
  unsafeWrite (lruValues lru) node BS.empty

unlink :: LRU -> Int -> IO ()
unlink lru node = do
  p <- unsafeRead (lruPrev lru) node
  n <- unsafeRead (lruNext lru) node
  unsafeWrite (lruNext lru) p n
  unsafeWrite (lruPrev lru) n p

pushFront :: LRU -> Int -> IO ()
pushFront lru node = do
  let s = sentinel lru
  first <- unsafeRead (lruNext lru) s
  unsafeWrite (lruPrev lru) node s
  unsafeWrite (lruNext lru) node first
  unsafeWrite (lruPrev lru) first node
  unsafeWrite (lruNext lru) s node

touch :: LRU -> Int -> IO ()
touch lru node = unlink lru node >> pushFront lru node
