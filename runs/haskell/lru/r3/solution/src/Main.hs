{-# LANGUAGE OverloadedStrings #-}

-- | Simulates an LRU cache driven by commands on standard input.
--
-- The first line holds the capacity; each later line is one of
-- @SET key value@, @GET key@, @DEL key@ or @SIZE@. Malformed or empty lines
-- are ignored.
module Main (main) where

import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder, byteString, hPutBuilder, intDec, char7)
import qualified Data.ByteString.Char8 as BC
import System.Exit (die)
import System.IO (BufferMode (BlockBuffering), hSetBinaryMode, hSetBuffering, stdin, stdout)

import qualified LRU

data Command
  = Set !BS.ByteString !BS.ByteString
  | Get !BS.ByteString
  | Del !BS.ByteString
  | Size

parseCommand :: BS.ByteString -> Maybe Command
parseCommand line = case BC.split ' ' line of
  ["SET", k, v] -> Just (Set k v)
  ["GET", k]    -> Just (Get k)
  ["DEL", k]    -> Just (Del k)
  ["SIZE"]      -> Just Size
  _             -> Nothing

-- | Run one command, producing the line to print, if any.
execute :: LRU.LRU -> Command -> IO (Maybe Builder)
execute cache cmd = case cmd of
  Set k v -> Nothing <$ LRU.set cache k v
  Get k   -> Just . maybe (byteString "NULL") byteString <$> LRU.get cache k
  Del k   -> Just . boolDigit <$> LRU.delete cache k
  Size    -> Just . intDec <$> LRU.size cache
  where
    boolDigit present = char7 (if present then '1' else '0')

-- | Split input into lines, tolerating CRLF endings.
inputLines :: BS.ByteString -> [BS.ByteString]
inputLines = map stripCR . BC.lines
  where
    stripCR l = case BS.unsnoc l of
      Just (l', 13) -> l'
      _             -> l

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering (Just 65536))
  input <- BS.getContents
  case inputLines input of
    capLine : rest
      | Just (cap, trailing) <- BC.readInt (BC.strip capLine)
      , BS.null trailing
      , cap >= 1 -> do
          cache <- LRU.new cap
          mapM_ (step cache) rest
    _ -> die "expected a positive capacity on the first line"
  where
    step cache line = case parseCommand line of
      Nothing  -> pure ()
      Just cmd -> execute cache cmd
        >>= maybe (pure ()) (\b -> hPutBuilder stdout (b <> char7 '\n'))
