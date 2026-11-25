{-# LANGUAGE OverloadedStrings #-}

-- | Simulate an LRU cache driven by commands on standard input.
module Main (main) where

import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder, byteString, char7, hPutBuilder, intDec)
import Data.ByteString.Char8 qualified as BC
import Data.Cache.LRU (LRU)
import Data.Cache.LRU qualified as LRU
import Data.Foldable (traverse_)
import System.IO (BufferMode (BlockBuffering), hSetBinaryMode, hSetBuffering, stdin, stdout)

data Command
  = Set !ByteString !ByteString
  | Get !ByteString
  | Del !ByteString
  | Size

parseCommand :: ByteString -> Maybe Command
parseCommand line = case BC.words line of
  ["SET", k, v] -> Just (Set k v)
  ["GET", k] -> Just (Get k)
  ["DEL", k] -> Just (Del k)
  ["SIZE"] -> Just Size
  _ -> Nothing

-- | Run one command, returning the line to print, if any.
run :: LRU -> Command -> IO (Maybe Builder)
run cache = \case
  Set k v -> Nothing <$ LRU.insert cache k v
  Get k -> Just . maybe (byteString "NULL") byteString <$> LRU.lookup cache k
  Del k -> Just . (\hit -> char7 (if hit then '1' else '0')) <$> LRU.delete cache k
  Size -> Just . intDec <$> LRU.size cache

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering (Just 65536))
  input <- BC.getContents
  case BC.lines input of
    [] -> pure ()
    header : rest -> do
      let capacity = maybe 1 fst (BC.readInt (BC.strip header))
          commands = [cmd | Just cmd <- map parseCommand rest]
          -- The cache can never hold more keys than there are SETs, so
          -- there is no point preallocating beyond that.
          sets = length [() | Set _ _ <- commands]
      cache <- LRU.new (min capacity sets)
      traverse_ (\cmd -> run cache cmd >>= traverse_ (emit . (<> char7 '\n'))) commands
  where
    emit = hPutBuilder stdout
