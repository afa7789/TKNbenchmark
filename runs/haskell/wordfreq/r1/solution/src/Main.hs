{-# LANGUAGE BangPatterns #-}
-- | wordfreq: print the 10 most frequent ASCII words read from stdin.
module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as B
import Data.List (foldl', sortBy)
import qualified Data.Map.Strict as M
import Data.Ord (Down (..), comparing)
import Data.Word (Word8)
import System.IO (stdout)

-- | Number of entries to report.
topN :: Int
topN = 10

isAsciiLetter :: Word8 -> Bool
isAsciiLetter w = (w - 0x41) < 26 || (w - 0x61) < 26
{-# INLINE isAsciiLetter #-}

toLowerAscii :: Word8 -> Word8
toLowerAscii w
  | (w - 0x41) < 26 = w + 0x20
  | otherwise = w
{-# INLINE toLowerAscii #-}

-- | Split input into lowercase words. Folding case once over the whole
-- input keeps each token a zero-copy slice of the same buffer.
tokenize :: BS.ByteString -> [BS.ByteString]
tokenize = go . BS.map toLowerAscii
  where
    go s
      | BS.null rest = []
      | otherwise = let (w, s') = BS.span isAsciiLetter rest in w : go s'
      where
        rest = BS.dropWhile (not . isAsciiLetter) s

-- | Count occurrences of each word.
countWords :: [BS.ByteString] -> M.Map BS.ByteString Int
countWords = foldl' step M.empty
  where
    step !m w = M.alter bump w m
      where
        bump Nothing = Just 1
        bump (Just !n) = Just (n + 1)

-- | Highest count first, ties by word ascending.
rank :: M.Map BS.ByteString Int -> [(BS.ByteString, Int)]
rank = take topN . sortBy (comparing (\(w, n) -> (Down n, w))) . M.toList

render :: [(BS.ByteString, Int)] -> B.Builder
render = foldMap line
  where
    line (w, n) = B.intDec n <> B.char7 ' ' <> B.byteString w <> B.char7 '\n'

main :: IO ()
main = do
  input <- BS.getContents
  B.hPutBuilder stdout . render . rank . countWords . tokenize $ input
