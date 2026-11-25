{-# LANGUAGE OverloadedStrings #-}

-- | An in-memory key-value store exposed over HTTP as a WAI application.
module KvHttp
  ( Store
  , newStore
  , app
  , isValidKey
  ) where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, stateTVar)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.List (intersperse)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Network.HTTP.Types
import Network.Wai

-- | Shared, thread-safe key-value storage.
newtype Store = Store (TVar (Map ByteString ByteString))

newStore :: IO Store
newStore = Store <$> newTVarIO Map.empty

-- | Largest accepted value, in bytes.
maxValueSize :: Int
maxValueSize = 1024 * 1024

-- | A key matches @[A-Za-z0-9_-]{1,64}@.
isValidKey :: ByteString -> Bool
isValidKey k = n >= 1 && n <= 64 && BC.all keyChar k
  where
    n = BS.length k
    keyChar c =
      (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'

data Route
  = Health
  | KeyList
  | KeyItem ByteString
  | BadKey
  | NotFound

route :: ByteString -> Route
route path = case path of
  "/health" -> Health
  "/kv" -> KeyList
  _ | Just rest <- BS.stripPrefix "/kv/" path ->
        if isValidKey rest then KeyItem rest else BadKey
    | otherwise -> NotFound

app :: Store -> Application
app store req respond = case route (rawPathInfo req) of
  NotFound -> respond (plain status404 "not found")
  BadKey -> respond (plain status400 "invalid key")
  Health
    | method == methodGet -> respond (plain status200 "ok")
    | otherwise -> respond notAllowed
  KeyList
    | method == methodGet -> listKeys store >>= respond
    | otherwise -> respond notAllowed
  KeyItem key
    | method == methodGet -> getKey store key >>= respond
    | method == methodPut -> putKey store key req >>= respond
    | method == methodDelete -> deleteKey store key >>= respond
    | otherwise -> respond notAllowed
  where
    method = requestMethod req

-- | A response with an explicit @Content-Length@, so Warp never falls back
-- to chunked transfer encoding.
sized :: Status -> ResponseHeaders -> BL.ByteString -> Response
sized st hs body =
  responseLBS st ((hContentLength, BC.pack (show (BL.length body))) : hs) body

plain :: Status -> BL.ByteString -> Response
plain st = sized st [(hContentType, "text/plain; charset=utf-8")]

empty :: Status -> Response
empty st = sized st [] BL.empty

notAllowed :: Response
notAllowed = plain status405 "method not allowed"

listKeys :: Store -> IO Response
listKeys (Store var) = do
  m <- readTVarIO var
  pure $
    sized status200 [(hContentType, "application/json")] . B.toLazyByteString $
      B.char7 '[' <> mconcat (intersperse (B.char7 ',') (map quote (Map.keys m))) <> B.char7 ']'
  where
    -- Valid keys contain no characters that need JSON escaping.
    quote k = B.char7 '"' <> B.byteString k <> B.char7 '"'

getKey :: Store -> ByteString -> IO Response
getKey (Store var) key = do
  m <- readTVarIO var
  pure $ case Map.lookup key m of
    Just v -> sized status200 [(hContentType, "application/octet-stream")] (BL.fromStrict v)
    Nothing -> plain status404 "not found"

putKey :: Store -> ByteString -> Request -> IO Response
putKey (Store var) key req = do
  body <- readBodyUpTo (maxValueSize + 1) req
  case body of
    Nothing -> pure (plain status413 "value too large")
    Just v -> do
      existed <- atomically . stateTVar var $ \m ->
        (Map.member key m, Map.insert key v m)
      pure (empty (if existed then status200 else status201))

deleteKey :: Store -> ByteString -> IO Response
deleteKey (Store var) key = do
  existed <- atomically . stateTVar var $ \m ->
    (Map.member key m, Map.delete key m)
  pure $ if existed then empty status204 else plain status404 "not found"

-- | Read the whole request body, giving up once it reaches @limit@ bytes.
readBodyUpTo :: Int -> Request -> IO (Maybe ByteString)
readBodyUpTo limit req = go 0 []
  where
    go !n acc = do
      chunk <- getRequestBodyChunk req
      if BS.null chunk
        then pure (Just (BS.concat (reverse acc)))
        else
          let n' = n + BS.length chunk
           in if n' >= limit then pure Nothing else go n' (chunk : acc)
