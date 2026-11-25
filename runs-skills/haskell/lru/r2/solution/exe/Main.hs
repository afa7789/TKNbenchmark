{-# LANGUAGE OverloadedStrings #-}

-- | LRU cache simulator: reads a capacity and a list of commands from stdin
-- and writes one line per command that produces output.
module Main (main) where

import Control.Monad ((>=>))
import Data.ByteString (ByteString)
import Data.ByteString.Builder (Builder, byteString, char7, intDec, hPutBuilder)
import Data.ByteString.Char8 qualified as BS8
import Data.Foldable (for_, traverse_)
import Data.LRU (Cache)
import Data.LRU qualified as LRU
import System.Exit (exitFailure)
import System.IO (BufferMode (BlockBuffering), hPutStrLn, hSetBinaryMode, hSetBuffering, stderr, stdin, stdout)

data Command
  = Set !ByteString !ByteString
  | Get !ByteString
  | Del !ByteString
  | Size
  deriving stock (Show)

parseCommand :: ByteString -> Maybe Command
parseCommand line = case BS8.words line of
  ["SET", k, v] -> Just (Set k v)
  ["GET", k]    -> Just (Get k)
  ["DEL", k]    -> Just (Del k)
  ["SIZE"]      -> Just Size
  _             -> Nothing

-- | Execute a command, returning the line to print, if any.
run :: Cache -> Command -> IO (Maybe Builder)
run cache = \case
  Set k v -> Nothing <$ LRU.insert cache k v
  Get k   -> Just . maybe (byteString "NULL") byteString <$> LRU.lookup cache k
  Del k   -> Just . (\hit -> char7 (if hit then '1' else '0')) <$> LRU.delete cache k
  Size    -> Just . intDec <$> LRU.size cache

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering (Just (1024 * 1024)))
  input <- BS8.getContents
  let (header, rest) = BS8.break (== '\n') input
  case BS8.readInt (BS8.strip header) of
    Just (capacity, trailing) | BS8.null trailing, capacity >= 1 -> do
      cache <- LRU.new capacity
      let emit = traverse_ (\b -> hPutBuilder stdout (b <> char7 '\n'))
      for_ (BS8.lines (BS8.drop 1 rest)) $ \line ->
        traverse_ (run cache >=> emit) (parseCommand line)
    _ -> hPutStrLn stderr "invalid capacity on first line" >> exitFailure
