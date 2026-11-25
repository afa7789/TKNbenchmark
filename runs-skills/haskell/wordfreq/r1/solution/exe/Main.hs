-- | wordfreq: print the 10 most frequent ASCII-letter words on stdin.
module Main (main) where

import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.List (sortBy)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..), comparing)
import Data.Word (Word8)
import System.IO (stdout)

-- | Number of entries to report.
topN :: Int
topN = 10

isAsciiLetter :: Word8 -> Bool
isAsciiLetter w = (w >= 0x61 && w <= 0x7a) || (w >= 0x41 && w <= 0x5a)

-- | Fold ASCII upper-case letters to lower case; other bytes are untouched.
toLowerAscii :: Word8 -> Word8
toLowerAscii w
  | w >= 0x41 && w <= 0x5a = w + 0x20
  | otherwise = w

-- | Split input into maximal runs of ASCII letters (the input is assumed
-- already case-folded; the slices share its buffer).
tokenize :: ByteString -> [ByteString]
tokenize s
  | BS.null rest = []
  | otherwise = word : tokenize rest'
  where
    rest = BS.dropWhile (not . isAsciiLetter) s
    (word, rest') = BS.span isAsciiLetter rest

countWords :: [ByteString] -> Map.Map ByteString Int
countWords = foldl' (\m w -> Map.insertWith (+) w 1 m) Map.empty

-- | Order by count descending, then word ascending (byte order).
rank :: Map.Map ByteString Int -> [(ByteString, Int)]
rank = sortBy (comparing (Down . snd) <> comparing fst) . Map.toList

render :: [(ByteString, Int)] -> B.Builder
render = foldMap line
  where
    line (w, c) = B.intDec c <> B.char7 ' ' <> B.byteString w <> B.char7 '\n'

main :: IO ()
main = do
  input <- BS.map toLowerAscii <$> BS.getContents
  B.hPutBuilder stdout . render . take topN . rank . countWords $ tokenize input
