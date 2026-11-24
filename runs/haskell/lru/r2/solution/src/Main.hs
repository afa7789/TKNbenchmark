-- | LRU cache simulator: reads a capacity and a stream of commands from
-- standard input and prints the results of GET, DEL and SIZE.
module Main (main) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Builder as BB
import qualified Data.ByteString.Char8 as BC
import System.IO

import qualified LRU

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering (Just 65536))
  input <- B.getContents
  case BC.lines input of
    [] -> pure ()
    (capLine : cmds) -> case BC.readInt (stripCR capLine) of
      Just (cap, _) | cap >= 1 -> do
        cache <- LRU.new cap
        mapM_ (run cache . BC.words . stripCR) cmds
      _ -> hPutStrLn stderr "invalid capacity"
  hFlush stdout

stripCR :: B.ByteString -> B.ByteString
stripCR l = case BC.unsnoc l of
  Just (rest, '\r') -> rest
  _ -> l

run :: LRU.LRU -> [B.ByteString] -> IO ()
run cache cmd = case cmd of
  [op, k, v] | op == BC.pack "SET" -> LRU.set cache (B.copy k) (B.copy v)
  [op, k]
    | op == BC.pack "GET" -> LRU.get cache k >>= emit . maybe (BB.string7 "NULL") BB.byteString
    | op == BC.pack "DEL" -> LRU.delete cache k >>= emit . BB.char7 . (\b -> if b then '1' else '0')
  [op] | op == BC.pack "SIZE" -> LRU.size cache >>= emit . BB.intDec
  _ -> pure ()
  where
    emit b = BB.hPutBuilder stdout (b <> BB.char7 '\n')
