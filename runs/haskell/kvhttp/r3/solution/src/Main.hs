-- | kvhttp: an in-memory HTTP/1.1 key-value server.
--
-- Usage: @app <port>@ — listens on 127.0.0.1:<port> until killed.
module Main (main) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BC
import Data.ByteString.Lazy qualified as BL
import Data.IORef
import Data.Int (Int64)
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

-- | The key-value store. Keys are validated before they reach the map.
type Store = IORef (Map ByteString ByteString)

-- | Maximum accepted value size: 1 MiB.
maxValueSize :: Int64
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
        Warp.setPort port
          . Warp.setHost "127.0.0.1"
          . Warp.setServerName ""
          $ Warp.defaultSettings
  Warp.runSettings settings (app store)

-- | Parsed route of a request path.
data Route
  = Health
  | KeyList
  | KeyItem ByteString
  | BadKey
  | NotFound

route :: ByteString -> Route
route path
  | path == "/health" = Health
  | path == "/kv" = KeyList
  | Just rest <- BS.stripPrefix "/kv/" path =
      if validKey rest then KeyItem rest else BadKey
  | otherwise = NotFound

-- | A key matches @[A-Za-z0-9_-]{1,64}@.
validKey :: ByteString -> Bool
validKey k = n >= 1 && n <= 64 && BC.all ok k
  where
    n = BS.length k
    ok c =
      (c >= 'A' && c <= 'Z')
        || (c >= 'a' && c <= 'z')
        || (c >= '0' && c <= '9')
        || c == '_'
        || c == '-'

app :: Store -> Application
app store req respond = respond =<< handle (requestMethod req) (route (rawPathInfo req))
  where
    handle :: Method -> Route -> IO Response
    handle _ NotFound = pure (status404 `withBody` "not found")
    handle _ BadKey = pure (status400 `withBody` "invalid key")
    handle m Health
      | m == methodGet = pure (status200 `withBody` "ok")
      | otherwise = pure methodNotAllowed
    handle m KeyList
      | m == methodGet = do
          keys <- Map.keys <$> readIORef store
          pure $
            responseBuilder
              status200
              [(hContentType, "application/json")]
              (jsonKeyArray keys)
      | otherwise = pure methodNotAllowed
    handle m (KeyItem key)
      | m == methodGet = do
          found <- Map.lookup key <$> readIORef store
          pure $ case found of
            Just v ->
              responseLBS status200 [(hContentType, "application/octet-stream")] (BL.fromStrict v)
            Nothing -> status404 `withBody` "not found"
      | m == methodPut = do
          body <- readBodyLimited maxValueSize req
          case body of
            Nothing -> pure (status413 `withBody` "value too large")
            Just v -> do
              existed <- atomicModifyIORef' store $ \mp ->
                (Map.insert key v mp, Map.member key mp)
              pure (responseLBS (if existed then status200 else status201) [] "")
      | m == methodDelete = do
          existed <- atomicModifyIORef' store $ \mp ->
            (Map.delete key mp, Map.member key mp)
          pure $
            if existed
              then responseLBS status204 [] ""
              else status404 `withBody` "not found"
      | otherwise = pure methodNotAllowed

    methodNotAllowed = status405 `withBody` "method not allowed"

withBody :: Status -> BL.ByteString -> Response
withBody s = responseLBS s [(hContentType, "text/plain")]

-- | Render keys as a JSON array of strings. Valid keys contain only
-- @[A-Za-z0-9_-]@, so no JSON escaping is ever required.
jsonKeyArray :: [ByteString] -> B.Builder
jsonKeyArray keys =
  B.char7 '[' <> mconcat (intersperse (B.char7 ',') (map quote keys)) <> B.char7 ']'
  where
    quote k = B.char7 '"' <> B.byteString k <> B.char7 '"'

-- | Read the whole request body, giving up with 'Nothing' once it
-- exceeds the given number of bytes.
readBodyLimited :: Int64 -> Request -> IO (Maybe ByteString)
readBodyLimited limit req
  | KnownLength n <- requestBodyLength req, fromIntegral n > limit = pure Nothing
  | otherwise = go 0 []
  where
    go !size acc = do
      chunk <- getRequestBodyChunk req
      if BS.null chunk
        then pure (Just (BS.concat (reverse acc)))
        else do
          let size' = size + fromIntegral (BS.length chunk)
          if size' > limit
            then pure Nothing
            else go size' (chunk : acc)
