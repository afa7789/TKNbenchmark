{-# LANGUAGE BangPatterns #-}

-- | A fixed-capacity, mutable LRU cache with O(1) expected-time operations.
--
-- Entries live in preallocated slots @0 .. capacity-1@. Each slot participates
-- in two intrusive linked structures, both expressed as unboxed index arrays:
--
--   * a hash bucket chain (singly linked, via 'chain'), used for lookup;
--   * a circular doubly linked recency list (via 'prev' / 'next') whose
--     sentinel is slot @capacity@. @next sentinel@ is the most recently used
--     entry and @prev sentinel@ the least recently used one.
--
-- Unused slots are kept on a free list threaded through 'chain'.
--
-- All array indices used internally are maintained within bounds by
-- construction, which is why unchecked reads and writes are used.
module LRU
  ( LRU
  , new
  , get
  , set
  , delete
  , size
  ) where

import Control.Monad (when)
import Data.Array.Base (unsafeRead, unsafeWrite)
import Data.Array.IO (IOArray, IOUArray, newArray, newListArray)
import Data.Bits (shiftL, shiftR, xor, (.&.))
import qualified Data.ByteString as BS
import Data.IORef (IORef, modifyIORef', newIORef, readIORef, writeIORef)
import Data.Word (Word64, Word8)

data LRU = LRU
  { capacity :: !Int
  , mask     :: !Int                 -- ^ bucket count minus one (power of two)
  , buckets  :: !(IOUArray Int Int)  -- ^ first slot of each chain, or 'nil'
  , chain    :: !(IOUArray Int Int)  -- ^ next slot in bucket chain / free list
  , prev     :: !(IOUArray Int Int)  -- ^ recency list, towards MRU
  , next     :: !(IOUArray Int Int)  -- ^ recency list, towards LRU
  , hashes   :: !(IOUArray Int Int)  -- ^ cached hash of each slot's key
  , keys     :: !(IOArray Int BS.ByteString)
  , vals     :: !(IOArray Int BS.ByteString)
  , freeHead :: !(IORef Int)         -- ^ first free slot, or 'nil'
  , count    :: !(IORef Int)         -- ^ number of occupied slots
  }

nil :: Int
nil = -1

sentinel :: LRU -> Int
sentinel = capacity

-- | Create an empty cache holding at most @cap@ keys (@cap >= 1@).
new :: Int -> IO LRU
new cap = do
  let nBuckets = until (>= cap) (`shiftL` 1) 1
  bs <- newArray (0, nBuckets - 1) nil
  ch <- newListArray (0, cap - 1) ([1 .. cap - 1] ++ [nil])
  pv <- newArray (0, cap) cap
  nx <- newArray (0, cap) cap
  hs <- newArray (0, cap - 1) 0
  ks <- newArray (0, cap - 1) BS.empty
  vs <- newArray (0, cap - 1) BS.empty
  LRU cap (nBuckets - 1) bs ch pv nx hs ks vs <$> newIORef 0 <*> newIORef 0

-- | Number of keys currently held.
size :: LRU -> IO Int
size = readIORef . count

-- | Look up a key, marking it most recently used on a hit.
get :: LRU -> BS.ByteString -> IO (Maybe BS.ByteString)
get c key = do
  i <- findSlot c (hashKey key) key
  if i == nil
    then pure Nothing
    else do
      touch c i
      Just <$> unsafeRead (vals c) i

-- | Insert or overwrite a key, making it most recently used and evicting the
-- least recently used key if the capacity would be exceeded.
set :: LRU -> BS.ByteString -> BS.ByteString -> IO ()
set c key val = do
  let !h = hashKey key
  i <- findSlot c h key
  if i /= nil
    then do
      unsafeWrite (vals c) i val
      touch c i
    else do
      n <- readIORef (count c)
      when (n >= capacity c) $
        unsafeRead (prev c) (sentinel c) >>= remove c
      j <- allocSlot c
      unsafeWrite (hashes c) j h
      unsafeWrite (keys c) j key
      unsafeWrite (vals c) j val
      let !b = h .&. mask c
      unsafeRead (buckets c) b >>= unsafeWrite (chain c) j
      unsafeWrite (buckets c) b j
      pushFront c j
      modifyIORef' (count c) (+ 1)

-- | Remove a key, reporting whether it was present.
delete :: LRU -> BS.ByteString -> IO Bool
delete c key = do
  i <- findSlot c (hashKey key) key
  if i == nil
    then pure False
    else True <$ remove c i

------------------------------------------------------------------------------
-- Internals

-- | FNV-1a over the key bytes, followed by a final avalanche step so that the
-- low bits used for bucket selection are well mixed.
hashKey :: BS.ByteString -> Int
hashKey = fromIntegral . finalize . BS.foldl' step 0xcbf29ce484222325
  where
    step :: Word64 -> Word8 -> Word64
    step !acc w = (acc `xor` fromIntegral w) * 0x100000001b3
    finalize :: Word64 -> Word64
    finalize x0 =
      let x1 = (x0 `xor` (x0 `shiftR` 33)) * 0xff51afd7ed558ccd
          x2 = (x1 `xor` (x1 `shiftR` 33)) * 0xc4ceb9fe1a85ec53
       in x2 `xor` (x2 `shiftR` 33)

-- | Find the slot holding @key@ (whose hash is @h@), or 'nil'.
findSlot :: LRU -> Int -> BS.ByteString -> IO Int
findSlot c !h key = unsafeRead (buckets c) (h .&. mask c) >>= go
  where
    go !i
      | i == nil = pure nil
      | otherwise = do
          hi <- unsafeRead (hashes c) i
          if hi /= h
            then unsafeRead (chain c) i >>= go
            else do
              ki <- unsafeRead (keys c) i
              if ki == key then pure i else unsafeRead (chain c) i >>= go

-- | Take a slot off the free list. Only called when one is available.
allocSlot :: LRU -> IO Int
allocSlot c = do
  i <- readIORef (freeHead c)
  unsafeRead (chain c) i >>= writeIORef (freeHead c)
  pure i

-- | Evict an occupied slot: detach it from its bucket and the recency list,
-- release its contents, and return it to the free list.
remove :: LRU -> Int -> IO ()
remove c i = do
  unlinkBucket c i
  unlinkList c i
  unsafeWrite (keys c) i BS.empty
  unsafeWrite (vals c) i BS.empty
  readIORef (freeHead c) >>= unsafeWrite (chain c) i
  writeIORef (freeHead c) i
  modifyIORef' (count c) (subtract 1)

-- | Detach slot @i@ from its hash bucket chain.
unlinkBucket :: LRU -> Int -> IO ()
unlinkBucket c i = do
  b <- (.&. mask c) <$> unsafeRead (hashes c) i
  after <- unsafeRead (chain c) i
  first <- unsafeRead (buckets c) b
  if first == i
    then unsafeWrite (buckets c) b after
    else go after first
  where
    go !after !p = do
      q <- unsafeRead (chain c) p
      if q == i then unsafeWrite (chain c) p after else go after q

-- | Mark slot @i@ as most recently used.
touch :: LRU -> Int -> IO ()
touch c i = do
  mru <- unsafeRead (next c) (sentinel c)
  when (mru /= i) $ unlinkList c i >> pushFront c i

unlinkList :: LRU -> Int -> IO ()
unlinkList c i = do
  p <- unsafeRead (prev c) i
  n <- unsafeRead (next c) i
  unsafeWrite (next c) p n
  unsafeWrite (prev c) n p

pushFront :: LRU -> Int -> IO ()
pushFront c i = do
  let s = sentinel c
  mru <- unsafeRead (next c) s
  unsafeWrite (next c) i mru
  unsafeWrite (prev c) i s
  unsafeWrite (prev c) mru i
  unsafeWrite (next c) s i
