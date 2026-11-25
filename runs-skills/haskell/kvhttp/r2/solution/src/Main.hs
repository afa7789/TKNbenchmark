{-# LANGUAGE OverloadedStrings #-}

-- | kvhttp: an in-memory HTTP/1.1 key-value server.
--
-- Usage: @kvhttp <port>@ — listens on 127.0.0.1.
module Main (main) where

import Control.Concurrent.STM (TVar, atomically, newTVarIO, readTVarIO, stateTVar)
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BS8
import Data.ByteString.Lazy qualified as BL
import Data.List (intersperse)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Network.HTTP.Types
import Network.Wai
import Network.Wai.Handler.Warp qualified as Warp
import System.Environment (getArgs, getProgName)
import System.Exit (exitFailure)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

-- | The key-value store shared by all connections.
type Store = TVar (Map ByteString ByteString)

-- | Largest accepted value, in bytes.
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
  store <- newTVarIO Map.empty
  let settings =
        Warp.setPort port
          . Warp.setHost "127.0.0.1"
          . Warp.setServerName ""
          $ Warp.defaultSettings
  Warp.runSettings settings (app store)

-- | Routing target, derived from the raw request path.
data Route
  = Health
  | List
  | Item ByteString
  | BadKey
  | NotFound
  deriving stock (Eq, Show)

route :: ByteString -> Route
route path
  | path == "/health" = Health
  | path == "/kv" = List
  | Just rest <- BS.stripPrefix "/kv/" path =
      if validKey rest then Item rest else BadKey
  | otherwise = NotFound

-- | A key matches @[A-Za-z0-9_-]{1,64}@.
validKey :: ByteString -> Bool
validKey k = not (BS.null k) && BS.length k <= 64 && BS8.all keyChar k
  where
    keyChar c =
      (c >= 'a' && c <= 'z')
        || (c >= 'A' && c <= 'Z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'

app :: Store -> Application
app store req respond =
  case (route (rawPathInfo req), parseMethod (requestMethod req)) of
    (NotFound, _) -> respond (empty status404)
    (BadKey, _) -> respond (empty status400)
    (Health, Right GET) -> respond (plain status200 "ok")
    (Health, _) -> respond (empty status405)
    (List, Right GET) -> do
      m <- readTVarIO store
      respond (json status200 (keysJson (Map.keys m)))
    (List, _) -> respond (empty status405)
    (Item key, Right GET) -> do
      m <- readTVarIO store
      respond $ maybe (empty status404) (plain status200 . BL.fromStrict) (Map.lookup key m)
    (Item key, Right PUT) ->
      readBodyLimited req >>= \case
        Nothing -> respond (empty status413)
        Just value -> do
          existed <- atomically . stateTVar store $ \m ->
            (Map.member key m, Map.insert key value m)
          respond (empty (if existed then status200 else status201))
    (Item key, Right DELETE) -> do
      existed <- atomically . stateTVar store $ \m ->
        (Map.member key m, Map.delete key m)
      respond (empty (if existed then status204 else status404))
    (Item _, _) -> respond (empty status405)

-- | Read the whole request body, giving up once it exceeds 'maxValueSize'.
readBodyLimited :: Request -> IO (Maybe ByteString)
readBodyLimited req =
  case requestBodyLength req of
    KnownLength n | n > fromIntegral maxValueSize -> pure Nothing
    _ -> go 0 []
  where
    go !size chunks = do
      chunk <- getRequestBodyChunk req
      if BS.null chunk
        then pure (Just (BS.concat (reverse chunks)))
        else
          let size' = size + BS.length chunk
           in if size' > maxValueSize then pure Nothing else go size' (chunk : chunks)

-- | Keys only contain @[A-Za-z0-9_-]@, so they need no JSON escaping.
keysJson :: [ByteString] -> BL.ByteString
keysJson ks =
  B.toLazyByteString $
    B.char7 '['
      <> mconcat (intersperse (B.char7 ',') [B.char7 '"' <> B.byteString k <> B.char7 '"' | k <- ks])
      <> B.char7 ']'

-- Response helpers; every response carries an explicit Content-Length.

withBody :: Status -> ResponseHeaders -> BL.ByteString -> Response
withBody st hs body =
  responseLBS st ((hContentLength, BS8.pack (show (BL.length body))) : hs) body

empty :: Status -> Response
empty st = withBody st [] BL.empty

plain :: Status -> BL.ByteString -> Response
plain st = withBody st [(hContentType, "application/octet-stream")]

json :: Status -> BL.ByteString -> Response
json st = withBody st [(hContentType, "application/json")]
