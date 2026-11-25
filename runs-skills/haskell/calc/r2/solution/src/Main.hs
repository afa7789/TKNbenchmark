-- | calc: a 64-bit signed integer expression evaluator.
--
-- Reads one expression per line from standard input and prints its value,
-- or @error@ on a syntax error, division by zero, or 64-bit overflow.
module Main (main) where

import Data.ByteString.Builder qualified as B
import Data.ByteString.Char8 qualified as BS
import Data.Char (isDigit)
import Data.Int (Int64)
import System.IO (BufferMode (BlockBuffering), hSetBinaryMode, hSetBuffering, stdin, stdout)

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
  deriving stock (Eq, Show)

data CalcError
  = SyntaxError
  | DivideByZero
  | Overflow
  deriving stock (Eq, Show)

tokenize :: BS.ByteString -> Either CalcError [Token]
tokenize s = case BS.uncons s of
  Nothing -> Right []
  Just (c, rest)
    | c == ' ' || c == '\t' -> tokenize rest
    | isDigit c ->
        let (digits, rest') = BS.span isDigit s
         in (TNum (digitsValue digits) :) <$> tokenize rest'
    | otherwise -> case c of
        '+' -> (TPlus :) <$> tokenize rest
        '-' -> (TMinus :) <$> tokenize rest
        '*' -> (TStar :) <$> tokenize rest
        '/' -> (TSlash :) <$> tokenize rest
        '%' -> (TPercent :) <$> tokenize rest
        '(' -> (TLParen :) <$> tokenize rest
        ')' -> (TRParen :) <$> tokenize rest
        _ -> Left SyntaxError
  where
    digitsValue = BS.foldl' (\acc d -> acc * 10 + toInteger (fromEnum d - fromEnum '0')) 0

-- * Syntax tree

data BinOp = Add | Sub | Mul | Div | Rem
  deriving stock (Eq, Show)

data Expr
  = Lit !Integer
  | Neg Expr
  | Bin !BinOp Expr Expr
  deriving stock (Eq, Show)

-- * Parser (recursive descent)

type Parser a = [Token] -> Either CalcError (a, [Token])

parseExpr :: [Token] -> Either CalcError Expr
parseExpr toks = case expr toks of
  Right (e, []) -> Right e
  Right _ -> Left SyntaxError
  Left err -> Left err

-- | Parses a left-associative chain of operands separated by operators.
chainl :: (Token -> Maybe BinOp) -> Parser Expr -> Parser Expr
chainl opOf operand toks = operand toks >>= uncurry go
  where
    go lhs (t : rest)
      | Just op <- opOf t = do
          (rhs, rest') <- operand rest
          go (Bin op lhs rhs) rest'
    go lhs rest = Right (lhs, rest)

expr :: Parser Expr
expr = chainl additive term
  where
    additive TPlus = Just Add
    additive TMinus = Just Sub
    additive _ = Nothing

term :: Parser Expr
term = chainl multiplicative unary
  where
    multiplicative TStar = Just Mul
    multiplicative TSlash = Just Div
    multiplicative TPercent = Just Rem
    multiplicative _ = Nothing

unary :: Parser Expr
unary (TMinus : rest) = do
  (e, rest') <- unary rest
  Right (Neg e, rest')
unary toks = primary toks

primary :: Parser Expr
primary (TNum n : rest) = Right (Lit n, rest)
primary (TLParen : rest) = do
  (e, rest') <- expr rest
  case rest' of
    TRParen : rest'' -> Right (e, rest'')
    _ -> Left SyntaxError
primary _ = Left SyntaxError

-- * Evaluation

-- | Evaluates with exact arithmetic, rejecting any intermediate result
-- outside the signed 64-bit range.
eval :: Expr -> Either CalcError Int64
eval = fmap fromInteger . go
  where
    go (Lit n) = checked n
    go (Neg e) = go e >>= checked . negate
    go (Bin op l r) = do
      a <- go l
      b <- go r
      apply op a b

    apply Add a b = checked (a + b)
    apply Sub a b = checked (a - b)
    apply Mul a b = checked (a * b)
    apply Div a b
      | b == 0 = Left DivideByZero
      | otherwise = checked (a `quot` b)
    apply Rem a b
      | b == 0 = Left DivideByZero
      | otherwise = checked (a `rem` b)

    checked n
      | n < toInteger (minBound :: Int64) || n > toInteger (maxBound :: Int64) = Left Overflow
      | otherwise = Right n

evaluateLine :: BS.ByteString -> Either CalcError Int64
evaluateLine line = tokenize line >>= parseExpr >>= eval

isBlank :: BS.ByteString -> Bool
isBlank = BS.all (\c -> c == ' ' || c == '\t')

render :: Either CalcError Int64 -> B.Builder
render (Right v) = B.int64Dec v <> B.char7 '\n'
render (Left _) = B.string7 "error\n"

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering Nothing)
  input <- BS.getContents
  B.hPutBuilder stdout $
    foldMap (render . evaluateLine) (filter (not . isBlank) (BS.lines input))
