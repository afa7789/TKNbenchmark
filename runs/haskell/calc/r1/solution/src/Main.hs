-- | calc: a 64-bit signed integer expression evaluator.
--
-- Reads one expression per line from standard input and prints its value,
-- or @error@ on a syntax error, division by zero, or 64-bit overflow.
module Main (main) where

import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BC
import Data.Char (isDigit)
import Data.Int (Int64)
import System.IO (stdout)

-- | Why evaluation failed. Every failure prints the same @error@ line, but
-- keeping the reasons distinct makes the evaluator easier to reason about.
data CalcError
  = SyntaxError
  | DivisionByZero
  | Overflow
  deriving (Eq, Show)

data Token
  = TNum !Integer
  | TPlus
  | TMinus
  | TStar
  | TSlash
  | TPercent
  | TLParen
  | TRParen
  deriving (Eq, Show)

-- * Lexing

isBlank :: Char -> Bool
isBlank c = c == ' ' || c == '\t'

tokenize :: BC.ByteString -> Either CalcError [Token]
tokenize s = case BC.uncons s of
  Nothing -> Right []
  Just (c, rest)
    | isBlank c -> tokenize rest
    | isDigit c ->
        let (digits, rest') = BC.span isDigit s
         in (TNum (digitsValue digits) :) <$> tokenize rest'
    | otherwise -> case symbol c of
        Just t -> (t :) <$> tokenize rest
        Nothing -> Left SyntaxError
  where
    symbol c = lookup c
      [ ('+', TPlus), ('-', TMinus), ('*', TStar)
      , ('/', TSlash), ('%', TPercent), ('(', TLParen), (')', TRParen) ]

digitsValue :: BC.ByteString -> Integer
digitsValue = BC.foldl' (\acc d -> acc * 10 + toInteger (fromEnum d - fromEnum '0')) 0

-- * Checked 64-bit arithmetic

-- | Narrow an exact result to the 64-bit range, failing on overflow.
toInt64 :: Integer -> Either CalcError Int64
toInt64 n
  | n < toInteger (minBound :: Int64) || n > toInteger (maxBound :: Int64) = Left Overflow
  | otherwise = Right (fromInteger n)

-- | Apply an operation on exact integers and check the result fits.
exact :: (Integer -> Integer -> Integer) -> Int64 -> Int64 -> Either CalcError Int64
exact f a b = toInt64 (f (toInteger a) (toInteger b))

applyOp :: Token -> Int64 -> Int64 -> Either CalcError Int64
applyOp TPlus a b = exact (+) a b
applyOp TMinus a b = exact (-) a b
applyOp TStar a b = exact (*) a b
applyOp TSlash a b
  | b == 0 = Left DivisionByZero
  | otherwise = exact quot a b
applyOp TPercent a b
  | b == 0 = Left DivisionByZero
  -- 'rem' on Int64 throws for minBound `rem` (-1); the exact result is 0.
  | otherwise = exact rem a b
applyOp _ _ _ = Left SyntaxError

-- * Parsing and evaluation (recursive descent)

type Parser = [Token] -> Either CalcError (Int64, [Token])

-- | Parse a left-associative chain of operands separated by any of @ops@.
chainLeft :: [Token] -> Parser -> Parser
chainLeft ops operand ts0 = operand ts0 >>= uncurry go
  where
    go acc (t : ts)
      | t `elem` ops = do
          (rhs, ts') <- operand ts
          acc' <- applyOp t acc rhs
          go acc' ts'
    go acc ts = Right (acc, ts)

expr :: Parser
expr = chainLeft [TPlus, TMinus] term

term :: Parser
term = chainLeft [TStar, TSlash, TPercent] unary

unary :: Parser
unary (TMinus : ts) = do
  (v, ts') <- unary ts
  v' <- toInt64 (negate (toInteger v))
  pure (v', ts')
unary ts = primary ts

primary :: Parser
primary (TNum n : ts) = (\v -> (v, ts)) <$> toInt64 n
primary (TLParen : ts) = do
  (v, ts') <- expr ts
  case ts' of
    TRParen : rest -> Right (v, rest)
    _ -> Left SyntaxError
primary _ = Left SyntaxError

evaluate :: BC.ByteString -> Either CalcError Int64
evaluate line = do
  tokens <- tokenize line
  (v, rest) <- expr tokens
  if null rest then Right v else Left SyntaxError

-- * Driver

-- | Render the output for one input line; blank lines produce nothing.
renderLine :: BC.ByteString -> B.Builder
renderLine line
  | BC.all isBlank line = mempty
  | otherwise = either (const (B.string7 "error")) B.int64Dec (evaluate line) <> B.char7 '\n'

main :: IO ()
main = do
  input <- BC.getContents
  B.hPutBuilder stdout (foldMap renderLine (BC.lines input))
