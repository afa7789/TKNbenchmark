-- | Simulates an LRU cache driven by commands on standard input.
module Main (main) where

import qualified Data.ByteString as BS
import Data.ByteString.Builder (Builder, byteString, char7, hPutBuilder, intDec)
import qualified Data.ByteString.Char8 as BC
import System.Exit (exitFailure)
import System.IO

import qualified LRU

main :: IO ()
main = do
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering (Just 65536))
  input <- BS.getContents
  case BC.lines input of
    [] -> pure ()
    header : commands -> case BC.readInt (BC.strip header) of
      Just (capacity, rest)
        | BS.null rest, capacity >= 1 -> do
            cache <- LRU.new capacity
            mapM_ (execute cache . BC.words) commands
      _ -> do
        hPutStrLn stderr "invalid capacity on first line"
        exitFailure
  hFlush stdout

-- | Run one tokenised command; malformed lines are ignored.
execute :: LRU.Cache -> [BS.ByteString] -> IO ()
execute cache tokens = case tokens of
  [cmd, key, val] | cmd == BC.pack "SET" -> LRU.insert cache key val
  [cmd, key]
    | cmd == BC.pack "GET" -> LRU.lookup cache key >>= emit . maybe nullB byteString
    | cmd == BC.pack "DEL" -> LRU.delete cache key >>= emit . bool
  [cmd] | cmd == BC.pack "SIZE" -> LRU.size cache >>= emit . intDec
  _ -> pure ()
  where
    nullB = byteString (BC.pack "NULL")
    bool present = char7 (if present then '1' else '0')

emit :: Builder -> IO ()
emit b = hPutBuilder stdout (b <> char7 '\n')
