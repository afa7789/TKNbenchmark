-- | A thread-safe, in-memory key-value store.
module KvHttp.Store
  ( Store
  , PutResult (..)
  , newStore
  , putValue
  , getValue
  , deleteValue
  , listKeys
  ) where

import Data.ByteString (ByteString)
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map

newtype Store = Store (IORef (Map ByteString ByteString))

data PutResult = Created | Replaced
  deriving stock (Eq, Show)

newStore :: IO Store
newStore = Store <$> newIORef Map.empty

-- | Insert or replace a value, reporting which happened.
putValue :: Store -> ByteString -> ByteString -> IO PutResult
putValue (Store ref) key value =
  atomicModifyIORef' ref $ \m ->
    let (old, m') = Map.insertLookupWithKey (\_ new _ -> new) key value m
     in (m', maybe Created (const Replaced) old)

getValue :: Store -> ByteString -> IO (Maybe ByteString)
getValue (Store ref) key = Map.lookup key <$> readIORef ref

-- | Delete a key, returning whether it was present.
deleteValue :: Store -> ByteString -> IO Bool
deleteValue (Store ref) key =
  atomicModifyIORef' ref $ \m ->
    case Map.updateLookupWithKey (\_ _ -> Nothing) key m of
      (Just _, m') -> (m', True)
      (Nothing, _) -> (m, False)

-- | All keys in ascending order.
listKeys :: Store -> IO [ByteString]
listKeys (Store ref) = Map.keys <$> readIORef ref
