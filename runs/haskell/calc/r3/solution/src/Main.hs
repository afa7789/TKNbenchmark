-- | calc: a 64-bit signed integer expression evaluator.
--
-- Reads one expression per line from standard input and prints its value,
-- or @error@ on a syntax error, division by zero, or 64-bit overflow.
module Main (main) where

import qualified Data.ByteString.Builder as B
import qualified Data.ByteString.Char8 as BC
import Data.Char (isDigit)
import Data.Int (Int64)
import Data.Maybe (fromMaybe)
import System.IO (stdout)

-- * Tokens

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

-- | Why an expression failed to evaluate. All are reported as @error@.
data CalcError
  = SyntaxError
  | DivisionByZero
  | Overflow
  deriving (Eq, Show)

isBlank :: Char -> Bool
isBlank c = c == ' ' || c == '\t'

tokenize :: BC.ByteString -> Either CalcError [Token]
tokenize s = case BC.uncons (BC.dropWhile isBlank s) of
  Nothing -> Right []
  Just (c, rest)
    | isDigit c ->
        let (digits, rest') = BC.span isDigit (BC.cons c rest)
         in (TNum (readDigits digits) :) <$> tokenize rest'
    | otherwise -> case symbol c of
        Just t -> (t :) <$> tokenize rest
        Nothing -> Left SyntaxError
  where
    symbol '+' = Just TPlus
    symbol '-' = Just TMinus
    symbol '*' = Just TStar
    symbol '/' = Just TSlash
    symbol '%' = Just TPercent
    symbol '(' = Just TLParen
    symbol ')' = Just TRParen
    symbol _ = Nothing

readDigits :: BC.ByteString -> Integer
readDigits = BC.foldl' (\acc d -> acc * 10 + toInteger (fromEnum d - fromEnum '0')) 0

-- * Checked 64-bit arithmetic

-- | Narrow an exact result to the 64-bit range, failing on overflow.
checked :: Integer -> Either CalcError Integer
checked n
  | n < toInteger (minBound :: Int64) || n > toInteger (maxBound :: Int64) = Left Overflow
  | otherwise = Right n

data BinOp = Add | Sub | Mul | Div | Rem

applyOp :: BinOp -> Integer -> Integer -> Either CalcError Integer
applyOp Add a b = checked (a + b)
applyOp Sub a b = checked (a - b)
applyOp Mul a b = checked (a * b)
applyOp Div _ 0 = Left DivisionByZero
applyOp Div a b = checked (a `quot` b)
applyOp Rem _ 0 = Left DivisionByZero
applyOp Rem a b = Right (a `rem` b)

-- * Parsing and evaluation

-- | A parser that consumes tokens and evaluates as it goes.
type Parser = [Token] -> Either CalcError (Integer, [Token])

-- | Evaluate a full token stream; trailing tokens are a syntax error.
evaluate :: [Token] -> Either CalcError Integer
evaluate ts = do
  (v, rest) <- expr ts
  if null rest then Right v else Left SyntaxError

-- | Parse a left-associative chain of operands separated by operators.
chainl :: (Token -> Maybe BinOp) -> Parser -> Parser
chainl opOf operand ts0 = operand ts0 >>= uncurry go
  where
    go acc (t : ts)
      | Just op <- opOf t = do
          (rhs, ts') <- operand ts
          acc' <- applyOp op acc rhs
          go acc' ts'
    go acc ts = Right (acc, ts)

expr :: Parser
expr = chainl additive term
  where
    additive TPlus = Just Add
    additive TMinus = Just Sub
    additive _ = Nothing

term :: Parser
term = chainl multiplicative unary
  where
    multiplicative TStar = Just Mul
    multiplicative TSlash = Just Div
    multiplicative TPercent = Just Rem
    multiplicative _ = Nothing

unary :: Parser
unary (TMinus : ts) = do
  (v, rest) <- unary ts
  v' <- checked (negate v)
  Right (v', rest)
unary ts = primary ts

primary :: Parser
primary (TNum n : ts) = do
  v <- checked n
  Right (v, ts)
primary (TLParen : ts) = do
  (v, rest) <- expr ts
  case rest of
    TRParen : rest' -> Right (v, rest')
    _ -> Left SyntaxError
primary _ = Left SyntaxError

-- * Driver

-- | Render the result for one input line, or 'Nothing' for a blank line.
processLine :: BC.ByteString -> Maybe B.Builder
processLine line
  | BC.all isBlank line = Nothing
  | otherwise = Just $ case tokenize line >>= evaluate of
      Right v -> B.integerDec v <> B.char7 '\n'
      Left _ -> B.string7 "error\n"

main :: IO ()
main = do
  input <- BC.getContents
  B.hPutBuilder stdout (foldMap (fromMaybe mempty . processLine) (BC.lines input))
