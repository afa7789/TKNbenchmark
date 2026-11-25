{-# LANGUAGE OverloadedStrings #-}

-- | HTTP routing for the key-value server.
module KvHttp
  ( application
  , isValidKey
  , module KvHttp.Store
  ) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder (Builder)
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.List (intersperse)
import Network.HTTP.Types
import Network.Wai

import KvHttp.Store

data Route
  = Health
  | KeyList
  | KeyItem ByteString
  | BadKey
  | NoRoute

route :: ByteString -> Route
route path = case path of
  "/health" -> Health
  "/kv" -> KeyList
  _ | Just key <- BS.stripPrefix "/kv/" path ->
        if isValidKey key then KeyItem key else BadKey
    | otherwise -> NoRoute

-- | A key matches @[A-Za-z0-9_-]{1,64}@.
isValidKey :: ByteString -> Bool
isValidKey k = not (BS.null k) && BS.length k <= 64 && BC.all keyChar k
  where
    keyChar c =
      (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'

application :: Store -> Application
application store req respond =
  case (route (rawPathInfo req), parseMethod (requestMethod req)) of
    (Health, Right GET) -> respond $ plain status200 "ok"
    (Health, _) -> respond methodNotAllowed
    (KeyList, Right GET) -> do
      keys <- listKeys store
      respond $ bytes status200 "application/json" (BL.toStrict (B.toLazyByteString (jsonArray keys)))
    (KeyList, _) -> respond methodNotAllowed
    (KeyItem key, Right GET) ->
      getValue store key >>= \case
        Just v -> respond $ bytes status200 "application/octet-stream" v
        Nothing -> respond notFound
    (KeyItem key, Right PUT) -> do
      body <- BL.toStrict <$> strictRequestBody req
      putValue store key body >>= \case
        Created -> respond $ empty status201
        Replaced -> respond $ empty status200
    (KeyItem key, Right DELETE) -> do
      deleted <- deleteValue store key
      respond $ if deleted then empty status204 else notFound
    (KeyItem _, _) -> respond methodNotAllowed
    (BadKey, _) -> respond $ plain status400 "invalid key"
    (NoRoute, _) -> respond notFound
  where
    plain s = bytes s "text/plain"
    empty s = responseLBS s [(hContentLength, "0")] ""
    notFound = plain status404 "not found"
    methodNotAllowed = plain status405 "method not allowed"

-- | A response with an explicit @Content-Length@, so Warp never falls back to
-- chunked transfer encoding.
bytes :: Status -> ByteString -> ByteString -> Response
bytes s contentType body =
  responseLBS
    s
    [ (hContentType, contentType)
    , (hContentLength, BC.pack (show (BS.length body)))
    ]
    (BL.fromStrict body)

-- | Keys are restricted to JSON-safe characters, so no escaping is needed.
jsonArray :: [ByteString] -> Builder
jsonArray keys =
  B.char7 '[' <> mconcat (intersperse (B.char7 ',') (map quote keys)) <> B.char7 ']'
  where
    quote k = B.char7 '"' <> B.byteString k <> B.char7 '"'
