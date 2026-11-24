-- | A mutable, fixed-capacity LRU cache with O(1) expected-time operations.
--
-- All storage is preallocated when the cache is created. Entries live in
-- numbered nodes; a separately chained hash table maps keys to nodes, and a
-- circular doubly linked list threaded through the same nodes keeps them in
-- recency order. Node index @capacity@ is the list sentinel: its successor is
-- the most recently used node and its predecessor the least recently used.
module LRU
  ( Cache
  , new
  , insert
  , lookup
  , delete
  , size
  ) where

import Prelude hiding (lookup)

import Control.Monad (when)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.IO (IOArray, IOUArray, newArray)
import Data.Bits (shiftL, shiftR, xor, (.&.))
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Word (Word64, Word8)

data Cache = Cache
  { cCapacity :: !Int
  , cMask     :: !Int                    -- ^ bucket count minus one (a power of two)
  , cBuckets  :: !(IOUArray Int Int)     -- ^ bucket -> first node in its chain
  , cChain    :: !(IOUArray Int Int)     -- ^ node -> next node in bucket chain or free list
  , cOlder    :: !(IOUArray Int Int)     -- ^ node -> next less recently used node
  , cNewer    :: !(IOUArray Int Int)     -- ^ node -> next more recently used node
  , cKeys     :: !(IOArray Int ByteString)
  , cVals     :: !(IOArray Int ByteString)
  , cSize     :: !(IORef Int)
  , cFree     :: !(IORef Int)            -- ^ head of the list of released nodes
  , cFresh    :: !(IORef Int)            -- ^ lowest node index never handed out
  }

-- | Null link.
nil :: Int
nil = -1

-- | Create an empty cache holding at most the given number of keys (>= 1).
new :: Int -> IO Cache
new capacity
  | capacity < 1 = ioError (userError "LRU.new: capacity must be positive")
  | otherwise = do
      let buckets = until (>= capacity) (`shiftL` 1) 1
      Cache capacity (buckets - 1)
        <$> newArray (0, buckets - 1) nil
        <*> newArray (0, capacity - 1) nil
        <*> newArray (0, capacity) capacity
        <*> newArray (0, capacity) capacity
        <*> newArray (0, capacity - 1) BS.empty
        <*> newArray (0, capacity - 1) BS.empty
        <*> newIORef 0
        <*> newIORef nil
        <*> newIORef 0

-- | Number of keys currently held.
size :: Cache -> IO Int
size = readIORef . cSize

-- | Look up a key, marking it most recently used on a hit.
lookup :: Cache -> ByteString -> IO (Maybe ByteString)
lookup c key = do
  node <- find c key
  if node == nil
    then pure Nothing
    else do
      touch c node
      Just <$> unsafeRead (cVals c) node

-- | Insert or overwrite a key, making it the most recently used. If the cache
-- is full, the least recently used key is evicted to make room.
insert :: Cache -> ByteString -> ByteString -> IO ()
insert c key val = do
  node <- find c key
  if node /= nil
    then do
      unsafeWrite (cVals c) node val
      touch c node
    else do
      n <- readIORef (cSize c)
      when (n >= cCapacity c) $
        unsafeRead (cOlder c) (sentinel c) >>= release c
      fresh <- allocate c
      unsafeWrite (cKeys c) fresh key
      unsafeWrite (cVals c) fresh val
      let b = bucketOf c key
      unsafeRead (cBuckets c) b >>= unsafeWrite (cChain c) fresh
      unsafeWrite (cBuckets c) b fresh
      linkFront c fresh
      modifyIORef' (cSize c) (+ 1)

-- | Remove a key, reporting whether it was present.
delete :: Cache -> ByteString -> IO Bool
delete c key = do
  node <- find c key
  if node == nil
    then pure False
    else True <$ release c node

-- Internals -------------------------------------------------------------------

sentinel :: Cache -> Int
sentinel = cCapacity

-- | FNV-1a with a final fold of the high bits, reduced to a bucket index.
bucketOf :: Cache -> ByteString -> Int
bucketOf c = (.&. cMask c) . fromIntegral . mix . BS.foldl' step 0xcbf29ce484222325
  where
    step :: Word64 -> Word8 -> Word64
    step h w = (h `xor` fromIntegral w) * 0x100000001b3
    mix h = h `xor` (h `shiftR` 29) `xor` (h `shiftR` 47)

-- | Node holding the key, or 'nil'.
find :: Cache -> ByteString -> IO Int
find c key = unsafeRead (cBuckets c) (bucketOf c key) >>= go
  where
    go node
      | node == nil = pure nil
      | otherwise = do
          k <- unsafeRead (cKeys c) node
          if k == key then pure node else unsafeRead (cChain c) node >>= go

-- | Take an unused node, preferring previously released ones.
allocate :: Cache -> IO Int
allocate c = do
  free <- readIORef (cFree c)
  if free /= nil
    then do
      unsafeRead (cChain c) free >>= writeIORef (cFree c)
      pure free
    else do
      fresh <- readIORef (cFresh c)
      writeIORef (cFresh c) $! fresh + 1
      pure fresh

-- | Remove a node from the hash table and recency list and recycle it.
release :: Cache -> Int -> IO ()
release c node = do
  key <- unsafeRead (cKeys c) node
  unchain (bucketOf c key)
  unlink c node
  -- Drop references so evicted data can be collected.
  unsafeWrite (cKeys c) node BS.empty
  unsafeWrite (cVals c) node BS.empty
  readIORef (cFree c) >>= unsafeWrite (cChain c) node
  writeIORef (cFree c) node
  modifyIORef' (cSize c) (subtract 1)
  where
    unchain b = do
      first <- unsafeRead (cBuckets c) b
      after <- unsafeRead (cChain c) node
      if first == node
        then unsafeWrite (cBuckets c) b after
        else skip first after
    skip prev after = do
      cur <- unsafeRead (cChain c) prev
      if cur == node
        then unsafeWrite (cChain c) prev after
        else skip cur after

-- | Mark a node as most recently used.
touch :: Cache -> Int -> IO ()
touch c node = do
  newest <- unsafeRead (cNewer c) (sentinel c)
  when (newest /= node) $ do
    unlink c node
    linkFront c node

-- | Detach a node from the recency list.
unlink :: Cache -> Int -> IO ()
unlink c node = do
  older <- unsafeRead (cOlder c) node
  newer <- unsafeRead (cNewer c) node
  unsafeWrite (cNewer c) older newer
  unsafeWrite (cOlder c) newer older

-- | Attach a detached node as the most recently used.
linkFront :: Cache -> Int -> IO ()
linkFront c node = do
  let s = sentinel c
  newest <- unsafeRead (cNewer c) s
  unsafeWrite (cOlder c) node s
  unsafeWrite (cNewer c) node newest
  unsafeWrite (cOlder c) newest node
  unsafeWrite (cNewer c) s node
