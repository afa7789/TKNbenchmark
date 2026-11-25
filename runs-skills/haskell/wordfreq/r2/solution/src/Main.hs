-- | wordfreq: print the ten most frequent ASCII words read from standard input.
--
-- A word is a maximal run of ASCII letters, folded to lowercase. Every other
-- byte is a separator, so the input is processed as raw bytes and never
-- decoded.
module Main (main) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.List (sortBy)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..), comparing)
import Data.Word (Word8)
import System.IO (stdout)

-- | Number of lines to print.
topN :: Int
topN = 10

main :: IO ()
main = do
  input <- BS.getContents
  B.hPutBuilder stdout . render . topWords topN . countWords $ input

-- | Count occurrences of each lowercased word.
countWords :: ByteString -> Map.Map ByteString Int
countWords =
  foldl' (\m w -> Map.insertWith (+) w 1 m) Map.empty
    . filter (not . BS.null)
    . BS.splitWith (not . isLower)
    . BS.map toLowerAscii

-- | The @n@ most frequent words: count descending, then word ascending.
topWords :: Int -> Map.Map ByteString Int -> [(ByteString, Int)]
topWords n = take n . sortBy (comparing (Down . snd) <> comparing fst) . Map.toList

render :: [(ByteString, Int)] -> B.Builder
render = foldMap line
  where
    line (w, c) = B.intDec c <> B.char7 ' ' <> B.byteString w <> B.char7 '\n'

isLower :: Word8 -> Bool
isLower b = b >= 0x61 && b <= 0x7a
{-# INLINE isLower #-}

toLowerAscii :: Word8 -> Word8
toLowerAscii b
  | b >= 0x41 && b <= 0x5a = b + 0x20
  | otherwise = b
{-# INLINE toLowerAscii #-}
