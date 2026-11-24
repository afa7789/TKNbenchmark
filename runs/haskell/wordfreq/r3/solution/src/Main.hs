{-# LANGUAGE BangPatterns #-}
-- | wordfreq: print the ten most frequent ASCII words read from stdin.
module Main (main) where

import qualified Data.ByteString as B
import qualified Data.ByteString.Builder as BB
import Data.List (sortBy)
import qualified Data.Map.Strict as M
import Data.Ord (Down (..), comparing)
import Data.Word (Word8)
import System.IO (stdout)

-- | How many entries to report.
topN :: Int
topN = 10

isAsciiLetter :: Word8 -> Bool
isAsciiLetter w = (w >= 0x61 && w <= 0x7a) || (w >= 0x41 && w <= 0x5a)

toLowerAscii :: Word8 -> Word8
toLowerAscii w
  | w >= 0x41 && w <= 0x5a = w + 0x20
  | otherwise = w

-- | Split input into maximal runs of ASCII letters, lowercased.
words' :: B.ByteString -> [B.ByteString]
words' = go
  where
    go s
      | B.null rest = []
      | otherwise = let (w, s') = B.span isAsciiLetter rest in B.map toLowerAscii w : go s'
      where
        rest = B.dropWhile (not . isAsciiLetter) s

countWords :: [B.ByteString] -> M.Map B.ByteString Int
countWords = foldl' bump M.empty
  where
    bump !m w = M.insertWith (+) w 1 m

-- | Highest counts first; ties broken by ascending byte order of the word.
topWords :: Int -> M.Map B.ByteString Int -> [(B.ByteString, Int)]
topWords n = take n . sortBy (comparing (\(w, c) -> (Down c, w))) . M.toList

render :: [(B.ByteString, Int)] -> BB.Builder
render = foldMap line
  where
    line (w, c) = BB.intDec c <> BB.char7 ' ' <> BB.byteString w <> BB.char7 '\n'

main :: IO ()
main = do
  input <- B.getContents
  BB.hPutBuilder stdout . render . topWords topN . countWords $ words' input
