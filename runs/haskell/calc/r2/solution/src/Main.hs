-- | calc: a 64-bit signed integer expression evaluator.
--
-- Reads one expression per line from standard input and prints its value,
-- or @error@ on a syntax error, division by zero, or 64-bit overflow.
module Main (main) where

import Data.Char (isDigit)
import Data.Int (Int64)
import Data.List (foldl')
import System.IO

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

-- | Split a line into tokens; 'Nothing' on any character outside the grammar.
tokenize :: String -> Maybe [Token]
tokenize [] = Just []
tokenize (c : cs)
  | c == ' ' || c == '\t' = tokenize cs
  | isDigit c =
      let (ds, rest) = span isDigit (c : cs)
       in (TNum (foldl' step 0 ds) :) <$> tokenize rest
  | otherwise = do
      t <- symbol c
      (t :) <$> tokenize cs
  where
    step acc d = acc * 10 + toInteger (fromEnum d - fromEnum '0')
    symbol '+' = Just TPlus
    symbol '-' = Just TMinus
    symbol '*' = Just TStar
    symbol '/' = Just TSlash
    symbol '%' = Just TPercent
    symbol '(' = Just TLParen
    symbol ')' = Just TRParen
    symbol _ = Nothing

-- * Syntax tree

data BinOp = Add | Sub | Mul | Div | Rem
  deriving (Eq, Show)

data Expr
  = Lit !Integer
  | Neg Expr
  | Bin !BinOp Expr Expr
  deriving (Show)

-- * Parser (recursive descent over the token list)

type Parser a = [Token] -> Maybe (a, [Token])

parseLine :: [Token] -> Maybe Expr
parseLine ts = case expr ts of
  Just (e, []) -> Just e
  _ -> Nothing

-- | Parse a left-associative chain of operands separated by operators.
chainl :: Parser Expr -> (Token -> Maybe BinOp) -> Parser Expr
chainl operand opOf ts0 = operand ts0 >>= uncurry go
  where
    go lhs (t : ts)
      | Just op <- opOf t = do
          (rhs, rest) <- operand ts
          go (Bin op lhs rhs) rest
    go lhs ts = Just (lhs, ts)

expr :: Parser Expr
expr = chainl term additive
  where
    additive TPlus = Just Add
    additive TMinus = Just Sub
    additive _ = Nothing

term :: Parser Expr
term = chainl unary multiplicative
  where
    multiplicative TStar = Just Mul
    multiplicative TSlash = Just Div
    multiplicative TPercent = Just Rem
    multiplicative _ = Nothing

unary :: Parser Expr
unary (TMinus : ts) = do
  (e, rest) <- unary ts
  Just (Neg e, rest)
unary ts = primary ts

primary :: Parser Expr
primary (TNum n : ts) = Just (Lit n, ts)
primary (TLParen : ts) = do
  (e, rest) <- expr ts
  case rest of
    TRParen : rest' -> Just (e, rest')
    _ -> Nothing
primary _ = Nothing

-- * Evaluation

-- | Evaluate with exact arithmetic, failing whenever a result leaves the
-- 64-bit signed range or a division by zero occurs.
eval :: Expr -> Maybe Int64
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
      | b == 0 = Nothing
      | otherwise = checked (a `quot` b)
    apply Rem a b
      | b == 0 = Nothing
      | otherwise = checked (a `rem` b)

    checked n
      | n < toInteger (minBound :: Int64) = Nothing
      | n > toInteger (maxBound :: Int64) = Nothing
      | otherwise = Just n

-- * Driver

-- | Result for one input line; 'Nothing' for a blank line.
evalLine :: String -> Maybe String
evalLine line
  | all (`elem` " \t") line = Nothing
  | otherwise =
      Just . maybe "error" show $
        tokenize line >>= parseLine >>= eval

main :: IO ()
main = do
  hSetBinaryMode stdin True
  hSetBinaryMode stdout True
  hSetBuffering stdout (BlockBuffering Nothing)
  input <- getContents
  mapM_ putStrLn [out | Just out <- map evalLine (lines input)]
  hFlush stdout
