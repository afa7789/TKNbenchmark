-- | Command-line LRU cache simulator.
--
-- Reads the capacity on the first line of standard input, then one command
-- per line (@SET k v@, @GET k@, @DEL k@, @SIZE@), writing one output line
-- for every command that produces output.
{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Monad (forM_)
import Data.ByteString.Builder (Builder, byteString, char7, hPutBuilder, intDec)
import Data.ByteString.Char8 qualified as BC
import Data.Foldable (traverse_)
import Data.LRU (LRU)
import Data.LRU qualified as LRU
import System.IO (BufferMode (BlockBuffering), hSetBinaryMode, hSetBuffering, stdin, stdout)

data Command
  = Set !BC.ByteString !BC.ByteString
  | Get !BC.ByteString
  | Del !BC.ByteString
  | Size
  deriving stock (Show)

parseCommand :: BC.ByteString -> Maybe Command
parseCommand line = case BC.words line of
  ["SET", key, value] -> Just (Set key value)
  ["GET", key]        -> Just (Get key)
  ["DEL", key]        -> Just (Del key)
  ["SIZE"]            -> Just Size
  _                   -> Nothing

-- | Execute one command, returning its output line, if any.
run :: LRU -> Command -> IO (Maybe Builder)
run cache = \case
  Set key value -> Nothing <$ LRU.set cache key value
  Get key -> Just . maybe (byteString "NULL") byteString <$> LRU.get cache key
  Del key -> Just . (\hit -> char7 (if hit then '1' else '0')) <$> LRU.delete cache key
  Size -> Just . intDec <$> LRU.size cache

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering Nothing)
  input <- BC.getContents
  case BC.lines input of
    [] -> pure ()
    header : commands -> do
      let capacity = maybe 1 fst (BC.readInt (BC.strip header))
      cache <- LRU.new capacity
      forM_ [c | Just c <- map parseCommand commands] $ \command ->
        run cache command >>= traverse_ (\out -> hPutBuilder stdout (out <> char7 '\n'))
