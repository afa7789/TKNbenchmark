-- | Reads one expression per line from standard input and prints its value,
-- or @error@. Blank lines (only spaces/tabs) produce no output.
module Main (main) where

import Calc (evaluate)
import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BS
import Data.ByteString.Lazy.Char8 qualified as BL
import System.IO (stdout)

main :: IO ()
main = do
  input <- BL.getContents
  B.hPutBuilder stdout . foldMap (render . BL.toStrict) $ BL.lines input

render :: BS.ByteString -> B.Builder
render line
  | BS.all isBlank line = mempty
  | otherwise = either (const (B.string7 "error")) B.int64Dec (evaluate line) <> B.char7 '\n'
  where
    isBlank c = c == ' ' || c == '\t'
