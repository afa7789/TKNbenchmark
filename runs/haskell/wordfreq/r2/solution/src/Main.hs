{-# LANGUAGE BangPatterns #-}
-- | wordfreq: print the 10 most frequent ASCII words read from stdin.
module Main (main) where

import qualified Data.ByteString as BS
import qualified Data.ByteString.Builder as B
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.Ord (Down (..))
import Data.Word (Word8)
import System.IO (stdout, hSetBinaryMode, stdin)

-- | Number of entries to report.
topN :: Int
topN = 10

isAsciiLetter :: Word8 -> Bool
isAsciiLetter w = (w >= 0x41 && w <= 0x5A) || (w >= 0x61 && w <= 0x7A)
{-# INLINE isAsciiLetter #-}

-- | Lowercase ASCII uppercase letters; leave every other byte untouched.
toLowerAscii :: Word8 -> Word8
toLowerAscii w
  | w >= 0x41 && w <= 0x5A = w + 0x20
  | otherwise = w
{-# INLINE toLowerAscii #-}

-- | Split input into lowercase words (maximal runs of ASCII letters).
tokenize :: BS.ByteString -> [BS.ByteString]
tokenize = filter (not . BS.null) . BS.splitWith (not . isAsciiLetter) . BS.map toLowerAscii

-- | Count occurrences of each word.
countWords :: [BS.ByteString] -> M.Map BS.ByteString Int
countWords = foldl' (\m w -> M.insertWith (+) w 1 m) M.empty

-- | Select the @n@ best entries ordered by count descending, then word
-- ascending, without sorting the whole table.
topEntries :: Int -> M.Map BS.ByteString Int -> [(Int, BS.ByteString)]
topEntries n = map unKey . S.toAscList . M.foldlWithKey' step S.empty
  where
    step !acc w c =
      let acc' = S.insert (Down c, w) acc
       in if S.size acc' > n then S.deleteMax acc' else acc'
    unKey (Down c, w) = (c, w)

render :: [(Int, BS.ByteString)] -> B.Builder
render = foldMap line
  where
    line (c, w) = B.intDec c <> B.char7 ' ' <> B.byteString w <> B.char7 '\n'

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  input <- BS.getContents
  B.hPutBuilder stdout . render . topEntries topN . countWords $ tokenize input
