{-# LANGUAGE OverloadedStrings #-}

-- | kvhttp: an in-memory HTTP/1.1 key-value server.
module Main (main) where

import Control.Concurrent.MVar (MVar, modifyMVar, newMVar, readMVar)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.List (intersperse)
import Data.Map.Strict (Map)
import qualified Data.Map.Strict as Map
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Handler.Warp (defaultSettings, runSettings, setHost, setPort)
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

type Store = MVar (Map ByteString ByteString)

-- | Largest accepted value, in bytes.
maxValueSize :: Int
maxValueSize = 1024 * 1024

main :: IO ()
main = do
  args <- getArgs
  case args of
    [p] | Just port <- readMaybe p, port > 0, port < 65536 -> do
      store <- newMVar Map.empty
      let settings = setHost "127.0.0.1" . setPort port $ defaultSettings
      runSettings settings (app store)
    _ -> do
      prog <- getProgName
      hPutStrLn stderr ("usage: " <> prog <> " <port>")
      exitFailure

data Route
  = Health
  | List
  | Item ByteString
  | BadKey
  | NotFound

route :: ByteString -> Route
route path
  | path == "/health" = Health
  | path == "/kv" = List
  | Just key <- BS.stripPrefix "/kv/" path =
      if validKey key then Item key else BadKey
  | otherwise = NotFound

validKey :: ByteString -> Bool
validKey k = not (BS.null k) && BS.length k <= 64 && BC.all keyChar k
  where
    keyChar c =
      (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'

app :: Store -> Application
app store req respond = respond =<< handle (route (rawPathInfo req)) (requestMethod req)
  where
    handle Health m
      | m == methodGet = pure (text status200 "ok")
      | otherwise = pure (methodNotAllowed "GET")
    handle List m
      | m == methodGet = do
          keys <- Map.keys <$> readMVar store
          pure (bytes status200 "application/json" (BL.toStrict (B.toLazyByteString (jsonKeys keys))))
      | otherwise = pure (methodNotAllowed "GET")
    handle (Item key) m
      | m == methodGet = do
          found <- Map.lookup key <$> readMVar store
          pure $ case found of
            Just v -> bytes status200 "application/octet-stream" v
            Nothing -> notFound
      | m == methodPut = do
          body <- readBody req
          case body of
            Nothing -> pure (text status413 "value too large")
            Just v -> do
              existed <- modifyMVar store $ \kv ->
                let (old, kv') = Map.insertLookupWithKey (\_ new _ -> new) key v kv
                 in pure (kv', maybe False (const True) old)
              pure (empty (if existed then status200 else status201))
      | m == methodDelete = do
          existed <- modifyMVar store $ \kv ->
            pure (Map.delete key kv, Map.member key kv)
          pure (if existed then empty status204 else notFound)
      | otherwise = pure (methodNotAllowed "GET, PUT, DELETE")
    handle BadKey _ = pure (text status400 "invalid key")
    handle NotFound _ = pure notFound

-- | Read the whole request body, giving up once it exceeds 'maxValueSize'.
readBody :: Request -> IO (Maybe ByteString)
readBody req = case requestBodyLength req of
  KnownLength n | n > fromIntegral maxValueSize -> pure Nothing
  _ -> go 0 []
  where
    go !size acc = do
      chunk <- getRequestBodyChunk req
      if BS.null chunk
        then pure (Just (BS.concat (reverse acc)))
        else
          let size' = size + BS.length chunk
           in if size' > maxValueSize then pure Nothing else go size' (chunk : acc)

-- | Keys are restricted to @[A-Za-z0-9_-]@, so they never need JSON escaping.
jsonKeys :: [ByteString] -> B.Builder
jsonKeys keys = B.char7 '[' <> mconcat (intersperse (B.char7 ',') (map quote keys)) <> B.char7 ']'
  where
    quote k = B.char7 '"' <> B.byteString k <> B.char7 '"'

-- | A response with an explicit @Content-Length@ (Warp would otherwise
-- fall back to chunked transfer encoding).
bytesWith :: Status -> ResponseHeaders -> ByteString -> Response
bytesWith s hs body =
  responseLBS s ((hContentLength, BC.pack (show (BS.length body))) : hs) (BL.fromStrict body)

bytes :: Status -> ByteString -> ByteString -> Response
bytes s ctype = bytesWith s [(hContentType, ctype)]

text :: Status -> ByteString -> Response
text s = bytes s "text/plain; charset=utf-8"

-- | An empty-bodied response. 204 must not carry a Content-Length.
empty :: Status -> Response
empty s
  | s == status204 = responseLBS s [] BL.empty
  | otherwise = bytesWith s [] BS.empty

notFound :: Response
notFound = text status404 "not found"

methodNotAllowed :: ByteString -> Response
methodNotAllowed allowed =
  bytesWith
    status405
    [(hContentType, "text/plain; charset=utf-8"), (hAllow, allowed)]
    "method not allowed"
