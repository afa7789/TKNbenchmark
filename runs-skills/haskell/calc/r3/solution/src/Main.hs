-- | calc: a 64-bit signed integer expression evaluator.
--
-- Reads one expression per line from standard input and prints its value,
-- or @error@ on a syntax error, division by zero or 64-bit overflow.
-- Blank lines (only spaces/tabs) produce no output.
module Main (main) where

import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BS
import Data.Char (isDigit)
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import System.IO (stdout)

-- * Tokens

data Op = Add | Sub | Mul | Div | Mod
  deriving stock (Eq, Show)

data Token
  = TNum !Integer
  | TOp !Op
  | TOpen
  | TClose
  deriving stock (Eq, Show)

-- | Why evaluation failed. All failures print the same, but keeping them
-- distinct documents intent and helps debugging.
data CalcError
  = SyntaxError
  | DivideByZero
  | Overflow
  deriving stock (Eq, Show)

isBlank :: Char -> Bool
isBlank c = c == ' ' || c == '\t'

tokenize :: BS.ByteString -> Either CalcError [Token]
tokenize s = case BS.uncons s of
  Nothing -> Right []
  Just (c, rest)
    | isBlank c -> tokenize rest
    | isDigit c ->
        let (digits, rest') = BS.span isDigit s
         in (TNum (digitsValue digits) :) <$> tokenize rest'
    | otherwise -> do
        t <- symbol c
        (t :) <$> tokenize rest
  where
    symbol = \case
      '+' -> Right (TOp Add)
      '-' -> Right (TOp Sub)
      '*' -> Right (TOp Mul)
      '/' -> Right (TOp Div)
      '%' -> Right (TOp Mod)
      '(' -> Right TOpen
      ')' -> Right TClose
      _ -> Left SyntaxError

digitsValue :: BS.ByteString -> Integer
digitsValue = BS.foldl' (\acc d -> acc * 10 + toInteger (fromEnum d - fromEnum '0')) 0

-- * Checked 64-bit arithmetic (computed exactly, then range-checked)

inRange :: Integer -> Either CalcError Integer
inRange n
  | n < toInteger (minBound :: Int64) || n > toInteger (maxBound :: Int64) = Left Overflow
  | otherwise = Right n

applyOp :: Op -> Integer -> Integer -> Either CalcError Integer
applyOp op a b = case op of
  Add -> inRange (a + b)
  Sub -> inRange (a - b)
  Mul -> inRange (a * b)
  Div -> nonZero >> inRange (a `quot` b)
  Mod -> nonZero >> Right (a `rem` b)
  where
    nonZero = if b == 0 then Left DivideByZero else Right ()

-- * Recursive-descent parser that evaluates as it goes

type Parser = [Token] -> Either CalcError (Integer, [Token])

-- | Parse a left-associative chain of binary operators drawn from @ops@.
chainLeft :: [Op] -> Parser -> Parser
chainLeft ops operand ts0 = operand ts0 >>= uncurry go
  where
    go acc (TOp op : ts)
      | op `elem` ops = do
          (rhs, ts') <- operand ts
          v <- applyOp op acc rhs
          go v ts'
    go acc ts = Right (acc, ts)

expr :: Parser
expr = chainLeft [Add, Sub] term

term :: Parser
term = chainLeft [Mul, Div, Mod] unary

unary :: Parser
unary (TOp Sub : ts) = do
  (v, ts') <- unary ts
  (,ts') <$> inRange (negate v)
unary ts = primary ts

primary :: Parser
primary (TNum n : ts) = (,ts) <$> inRange n
primary (TOpen : ts) =
  expr ts >>= \case
    (v, TClose : ts') -> Right (v, ts')
    _ -> Left SyntaxError
primary _ = Left SyntaxError

evaluate :: [Token] -> Either CalcError Integer
evaluate ts =
  expr ts >>= \case
    (v, []) -> Right v
    _ -> Left SyntaxError

-- * Driver

-- | Render the output for one input line, or 'Nothing' for a blank line.
processLine :: BS.ByteString -> Maybe B.Builder
processLine line
  | BS.all isBlank line = Nothing
  | otherwise = Just (render (tokenize line >>= evaluate) <> B.char7 '\n')
  where
    render = either (const (B.string7 "error")) B.integerDec

main :: IO ()
main = do
  input <- BS.getContents
  B.hPutBuilder stdout (foldMap processLine' (BS.lines input))
  where
    processLine' = fromMaybe mempty . processLine
