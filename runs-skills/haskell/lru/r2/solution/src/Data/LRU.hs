-- | A fixed-capacity, mutable LRU cache with 'ByteString' keys and values.
--
-- Every operation runs in O(1) expected time. The cache is backed by
-- preallocated arrays:
--
--   * a node pool of @capacity@ slots holding key, value and cached hash;
--   * an intrusive doubly linked recency list over the slots, closed into a
--     ring through a sentinel slot (index @capacity@);
--   * a separately chained hash table whose chains are threaded through the
--     slots as well. Unused slots are kept on a free list that reuses the
--     chain links.
module Data.LRU
  ( Cache
  , new
  , lookup
  , insert
  , delete
  , size
  ) where

import Prelude hiding (lookup)

import Control.Monad (when)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.IO (IOArray, IOUArray, newArray, newArray_)
import Data.Bits (shiftR, xor, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Word (Word64, Word8)

-- | Marks the end of a hash chain or of the free list.
nil :: Int
nil = -1

data Cache = Cache
  { cCapacity :: !Int
  , cMask     :: !Int                     -- ^ bucket count minus one
  , cBuckets  :: !(IOUArray Int Int)      -- ^ head slot of each chain
  , cChain    :: !(IOUArray Int Int)      -- ^ next slot in chain / free list
  , cPrev     :: !(IOUArray Int Int)      -- ^ recency list, towards MRU
  , cNext     :: !(IOUArray Int Int)      -- ^ recency list, towards LRU
  , cHashes   :: !(IOUArray Int Int)
  , cKeys     :: !(IOArray Int ByteString)
  , cValues   :: !(IOArray Int ByteString)
  , cSize     :: !(IORef Int)
  , cFree     :: !(IORef Int)             -- ^ head of the free list
  }

-- | Create an empty cache holding at most the given (positive) number of keys.
new :: Int -> IO Cache
new capacity
  | capacity < 1 = ioError (userError "Data.LRU.new: capacity must be positive")
  | otherwise = do
      let nBuckets = until (>= capacity) (* 2) 16
          sentinel = capacity
      buckets <- newArray (0, nBuckets - 1) nil
      chain   <- newArray_ (0, capacity - 1)
      -- Thread every slot onto the free list: 0 -> 1 -> ... -> nil.
      mapM_ (\i -> unsafeWrite chain i (if i + 1 < capacity then i + 1 else nil))
            [0 .. capacity - 1]
      prev    <- newArray (0, sentinel) sentinel
      next    <- newArray (0, sentinel) sentinel
      hashes  <- newArray_ (0, capacity - 1)
      keys    <- newArray (0, capacity - 1) BS.empty
      values  <- newArray (0, capacity - 1) BS.empty
      sz      <- newIORef 0
      free    <- newIORef 0
      pure Cache
        { cCapacity = capacity
        , cMask     = nBuckets - 1
        , cBuckets  = buckets
        , cChain    = chain
        , cPrev     = prev
        , cNext     = next
        , cHashes   = hashes
        , cKeys     = keys
        , cValues   = values
        , cSize     = sz
        , cFree     = free
        }

-- | Number of keys currently held.
size :: Cache -> IO Int
size = readIORef . cSize

-- | Look up a key; a hit makes it the most recently used.
lookup :: Cache -> ByteString -> IO (Maybe ByteString)
lookup c key = do
  slot <- findSlot c (hashKey key) key
  if slot == nil
    then pure Nothing
    else do
      touch c slot
      Just <$> unsafeRead (cValues c) slot

-- | Insert or overwrite a key, making it the most recently used. Evicts the
-- least recently used key if the cache would exceed its capacity.
insert :: Cache -> ByteString -> ByteString -> IO ()
insert c key value = do
  let h = hashKey key
  slot <- findSlot c h key
  if slot /= nil
    then do
      unsafeWrite (cValues c) slot value
      touch c slot
    else do
      n <- readIORef (cSize c)
      -- The new key is never the eviction victim, so evicting first is
      -- equivalent to inserting and then evicting.
      when (n == cCapacity c) $
        unsafeRead (cPrev c) (sentinelOf c) >>= removeSlot c
      fresh <- readIORef (cFree c)
      unsafeRead (cChain c) fresh >>= writeIORef (cFree c)
      unsafeWrite (cKeys c) fresh key
      unsafeWrite (cValues c) fresh value
      unsafeWrite (cHashes c) fresh h
      let b = h .&. cMask c
      unsafeRead (cBuckets c) b >>= unsafeWrite (cChain c) fresh
      unsafeWrite (cBuckets c) b fresh
      linkFront c fresh
      modifyIORef' (cSize c) (+ 1)

-- | Remove a key, reporting whether it was present.
delete :: Cache -> ByteString -> IO Bool
delete c key = do
  slot <- findSlot c (hashKey key) key
  if slot == nil
    then pure False
    else True <$ removeSlot c slot

-- Internals -------------------------------------------------------------------

sentinelOf :: Cache -> Int
sentinelOf = cCapacity

-- | FNV-1a followed by an avalanche finaliser so the low bits are well mixed.
hashKey :: ByteString -> Int
hashKey = fromIntegral . mix . BS.foldl' step 0xcbf29ce484222325
  where
    step :: Word64 -> Word8 -> Word64
    step acc w = (acc `xor` fromIntegral w) * 0x100000001b3
    {-# INLINE step #-}
    mix :: Word64 -> Word64
    mix x0 =
      let x1 = (x0 `xor` (x0 `shiftR` 33)) * 0xff51afd7ed558ccd
          x2 = (x1 `xor` (x1 `shiftR` 33)) * 0xc4ceb9fe1a85ec53
       in x2 `xor` (x2 `shiftR` 33)

findSlot :: Cache -> Int -> ByteString -> IO Int
findSlot c h key = unsafeRead (cBuckets c) (h .&. cMask c) >>= go
  where
    go slot
      | slot == nil = pure nil
      | otherwise = do
          h' <- unsafeRead (cHashes c) slot
          hit <- if h' /= h then pure False else (== key) <$> unsafeRead (cKeys c) slot
          if hit then pure slot else unsafeRead (cChain c) slot >>= go

-- | Fully remove an occupied slot and return it to the free list.
removeSlot :: Cache -> Int -> IO ()
removeSlot c slot = do
  unlink c slot
  h <- unsafeRead (cHashes c) slot
  let b = h .&. cMask c
  after <- unsafeRead (cChain c) slot
  first <- unsafeRead (cBuckets c) b
  if first == slot
    then unsafeWrite (cBuckets c) b after
    else
      let go p = do
            q <- unsafeRead (cChain c) p
            if q == slot then unsafeWrite (cChain c) p after else go q
       in go first
  -- Drop references so the GC can reclaim the old key and value.
  unsafeWrite (cKeys c) slot BS.empty
  unsafeWrite (cValues c) slot BS.empty
  readIORef (cFree c) >>= unsafeWrite (cChain c) slot
  writeIORef (cFree c) slot
  modifyIORef' (cSize c) (subtract 1)

-- | Make an occupied slot the most recently used.
touch :: Cache -> Int -> IO ()
touch c slot = do
  front <- unsafeRead (cNext c) (sentinelOf c)
  when (front /= slot) $ unlink c slot >> linkFront c slot

unlink :: Cache -> Int -> IO ()
unlink c slot = do
  p <- unsafeRead (cPrev c) slot
  n <- unsafeRead (cNext c) slot
  unsafeWrite (cNext c) p n
  unsafeWrite (cPrev c) n p

linkFront :: Cache -> Int -> IO ()
linkFront c slot = do
  let s = sentinelOf c
  front <- unsafeRead (cNext c) s
  unsafeWrite (cPrev c) slot s
  unsafeWrite (cNext c) slot front
  unsafeWrite (cPrev c) front slot
  unsafeWrite (cNext c) s slot
