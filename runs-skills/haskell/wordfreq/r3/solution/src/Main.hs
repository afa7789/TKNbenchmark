-- | wordfreq: print the ten most frequent ASCII words on standard input.
module Main (main) where

import Data.ByteString qualified as BS
import Data.ByteString.Builder qualified as B
import Data.List (sortBy)
import Data.Map.Strict qualified as Map
import Data.Ord (Down (..), comparing)
import Data.Word (Word8)
import System.IO (stdout)

-- | How many entries to report.
topN :: Int
topN = 10

isUpper', isLower' :: Word8 -> Bool
isUpper' w = w >= 0x41 && w <= 0x5A
isLower' w = w >= 0x61 && w <= 0x7A

-- | Fold ASCII upper-case letters to lower case; all other bytes are untouched.
toLowerAscii :: Word8 -> Word8
toLowerAscii w
  | isUpper' w = w + 0x20
  | otherwise = w

-- | Split already-lowercased input into words (maximal runs of @a-z@).
tokenize :: BS.ByteString -> [BS.ByteString]
tokenize = filter (not . BS.null) . BS.splitWith (not . isLower')

-- | Count occurrences of each word.
countWords :: [BS.ByteString] -> Map.Map BS.ByteString Int
countWords = foldl' (\m w -> Map.insertWith (+) w 1 m) Map.empty

-- | The @n@ most frequent words, by count descending then word ascending.
topWords :: Int -> Map.Map BS.ByteString Int -> [(BS.ByteString, Int)]
topWords n = take n . sortBy (comparing (\(w, c) -> (Down c, w))) . Map.toList

render :: [(BS.ByteString, Int)] -> B.Builder
render = foldMap line
  where
    line (w, c) = B.intDec c <> B.char7 ' ' <> B.byteString w <> B.char7 '\n'

main :: IO ()
main = do
  input <- BS.getContents
  let counts = countWords . tokenize $ BS.map toLowerAscii input
  B.hPutBuilder stdout . render $ topWords topN counts
