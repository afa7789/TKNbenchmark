{-# LANGUAGE OverloadedStrings #-}

-- | kvhttp: an in-memory HTTP/1.1 key-value server.
module Main (main) where

import Control.Exception (Exception, throwIO, try)
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BC
import qualified Data.ByteString.Lazy as BL
import Data.IORef
import Data.List (intersperse)
import qualified Data.Map.Strict as Map
import Network.HTTP.Types
import Network.Wai
import qualified Network.Wai.Handler.Warp as Warp
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

-- | Keys are kept in a 'Map' so listing them in ascending order is cheap.
type Store = IORef (Map.Map ByteString ByteString)

maxValueSize :: Int
maxValueSize = 1024 * 1024

main :: IO ()
main = do
  args <- getArgs
  case args of
    [p] | Just port <- readMaybe p, port > 0, port < 65536 -> serve port
    _ -> do
      prog <- getProgName
      hPutStrLn stderr ("usage: " <> prog <> " <port>")
      exitFailure

serve :: Int -> IO ()
serve port = do
  store <- newIORef Map.empty
  let settings =
        Warp.setHost "127.0.0.1"
          . Warp.setPort port
          . Warp.setServerName ""
          $ Warp.defaultSettings
  Warp.runSettings settings (app store)

-- Routing ---------------------------------------------------------------------

data Route
  = Health
  | KeyList
  | Key ByteString
  | BadKey
  | NotFound

route :: ByteString -> Route
route path = case path of
  "/health" -> Health
  "/kv" -> KeyList
  _
    | Just key <- BS.stripPrefix "/kv/" path ->
        if validKey key then Key key else BadKey
    | otherwise -> NotFound

validKey :: ByteString -> Bool
validKey k = not (BS.null k) && BS.length k <= 64 && BC.all keyChar k
  where
    keyChar c =
      (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'

app :: Store -> Application
app store req respond = respond =<< case route (rawPathInfo req) of
  Health
    | method == methodGet -> pure (bytes status200 "text/plain" "ok")
    | otherwise -> pure (empty status405)
  KeyList
    | method == methodGet -> listKeys store
    | otherwise -> pure (empty status405)
  Key key
    | method == methodGet -> getKey store key
    | method == methodPut -> putKey store key req
    | method == methodDelete -> deleteKey store key
    | otherwise -> pure (empty status405)
  BadKey -> pure (empty status400)
  NotFound -> pure (empty status404)
  where
    method = requestMethod req

-- Handlers --------------------------------------------------------------------

listKeys :: Store -> IO Response
listKeys store = do
  keys <- Map.keys <$> readIORef store
  -- Valid keys never need JSON escaping.
  let quoted k = B.char7 '"' <> B.byteString k <> B.char7 '"'
      body = B.char7 '[' <> mconcat (intersperse (B.char7 ',') (map quoted keys)) <> B.char7 ']'
  pure (bytes status200 "application/json" (BL.toStrict (B.toLazyByteString body)))

getKey :: Store -> ByteString -> IO Response
getKey store key = do
  found <- Map.lookup key <$> readIORef store
  pure $ case found of
    Just v -> bytes status200 "application/octet-stream" v
    Nothing -> empty status404

putKey :: Store -> ByteString -> Request -> IO Response
putKey store key req
  | KnownLength n <- requestBodyLength req, n > fromIntegral maxValueSize =
      pure (empty status413)
  | otherwise = do
      body <- try (readBodyLimited maxValueSize req)
      case body of
        Left TooLarge -> pure (empty status413)
        Right value -> do
          existed <- atomicModifyIORef' store $ \m ->
            (Map.insert key value m, Map.member key m)
          pure (empty (if existed then status200 else status201))

deleteKey :: Store -> ByteString -> IO Response
deleteKey store key = do
  existed <- atomicModifyIORef' store $ \m ->
    (Map.delete key m, Map.member key m)
  pure (empty (if existed then status204 else status404))

-- Helpers ---------------------------------------------------------------------

data TooLarge = TooLarge
  deriving (Show)

instance Exception TooLarge

-- | Read the whole request body, failing with 'TooLarge' past @limit@ bytes.
readBodyLimited :: Int -> Request -> IO ByteString
readBodyLimited limit req = go 0 []
  where
    go !size acc = do
      chunk <- getRequestBodyChunk req
      if BS.null chunk
        then pure (BS.concat (reverse acc))
        else do
          let size' = size + BS.length chunk
          if size' > limit then throwIO TooLarge else go size' (chunk : acc)

-- | A response with an explicit @Content-Length@ (Warp would otherwise
-- fall back to chunked encoding for streamed bodies).
bytes :: Status -> ByteString -> ByteString -> Response
bytes s ctype body =
  responseBuilder
    s
    [ (hContentType, ctype),
      (hContentLength, BC.pack (show (BS.length body)))
    ]
    (B.byteString body)

empty :: Status -> Response
empty s = responseLBS s [(hContentLength, "0")] BL.empty
