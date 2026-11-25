-- | A 64-bit signed integer expression evaluator.
--
-- Grammar:
--
-- > expr    := term    (('+' | '-') term)*
-- > term    := unary   (('*' | '/' | '%') unary)*
-- > unary   := '-' unary | primary
-- > primary := NUMBER | '(' expr ')'
--
-- Arithmetic is carried out on exact 'Integer's and every intermediate
-- result is range-checked, so overflow is detected precisely.
module Calc
  ( CalcError (..)
  , Expr (..)
  , BinOp (..)
  , parseExpr
  , eval
  , evaluate
  ) where

import Data.ByteString.Char8 qualified as BS
import Data.Char (isDigit)
import Data.Int (Int64)

-- | Why an expression could not be evaluated.
data CalcError
  = SyntaxError
  | DivisionByZero
  | Overflow
  deriving stock (Eq, Show)

data BinOp = Add | Sub | Mul | Div | Rem
  deriving stock (Eq, Show)

data Expr
  = Lit !Integer
  | Neg Expr
  | Bin !BinOp Expr Expr
  deriving stock (Eq, Show)

data Token
  = TNum !Integer
  | TOp !Char
  | TOpen
  | TClose
  deriving stock (Eq, Show)

------------------------------------------------------------------------------
-- Lexing

isBlank :: Char -> Bool
isBlank c = c == ' ' || c == '\t'

-- | Split a line into tokens. Literals are kept as 'Integer' so that
-- out-of-range values can be reported as overflow later; overly long
-- literals are rejected here without converting them.
tokenize :: BS.ByteString -> Either CalcError [Token]
tokenize s = case BS.uncons (BS.dropWhile isBlank s) of
  Nothing -> Right []
  Just (c, rest)
    | isDigit c ->
        let (digits, rest') = BS.span isDigit (BS.cons c rest)
         in (:) <$> literal digits <*> tokenize rest'
    | c == '(' -> (TOpen :) <$> tokenize rest
    | c == ')' -> (TClose :) <$> tokenize rest
    | c `elem` ("+-*/%" :: String) -> (TOp c :) <$> tokenize rest
    | otherwise -> Left SyntaxError

literal :: BS.ByteString -> Either CalcError Token
literal digits
  | BS.length significant > maxDigits = Left Overflow
  | otherwise = Right (TNum (BS.foldl' step 0 significant))
  where
    significant = BS.dropWhile (== '0') digits
    maxDigits = length (show (maxBound :: Int64))
    step acc d = acc * 10 + toInteger (fromEnum d - fromEnum '0')

------------------------------------------------------------------------------
-- Parsing (recursive descent over the token list)

type Parser a = [Token] -> Either CalcError (a, [Token])

-- | Parse a complete expression; trailing tokens are a syntax error.
parseExpr :: BS.ByteString -> Either CalcError Expr
parseExpr line = do
  tokens <- tokenize line
  (e, rest) <- expr tokens
  case rest of
    [] -> Right e
    _ -> Left SyntaxError

-- | Parse a left-associative chain of operands separated by operators
-- accepted by @opFor@.
chainl :: (Char -> Maybe BinOp) -> Parser Expr -> Parser Expr
chainl opFor operand ts0 = operand ts0 >>= uncurry go
  where
    go lhs (TOp c : ts)
      | Just op <- opFor c = do
          (rhs, ts') <- operand ts
          go (Bin op lhs rhs) ts'
    go lhs ts = Right (lhs, ts)

expr :: Parser Expr
expr = chainl additive term
  where
    additive '+' = Just Add
    additive '-' = Just Sub
    additive _ = Nothing

term :: Parser Expr
term = chainl multiplicative unary
  where
    multiplicative '*' = Just Mul
    multiplicative '/' = Just Div
    multiplicative '%' = Just Rem
    multiplicative _ = Nothing

unary :: Parser Expr
unary (TOp '-' : ts) = do
  (e, ts') <- unary ts
  Right (Neg e, ts')
unary ts = primary ts

primary :: Parser Expr
primary (TNum n : ts) = Right (Lit n, ts)
primary (TOpen : ts) = do
  (e, ts') <- expr ts
  case ts' of
    TClose : rest -> Right (e, rest)
    _ -> Left SyntaxError
primary _ = Left SyntaxError

------------------------------------------------------------------------------
-- Evaluation

-- | Ensure a value fits in a signed 64-bit integer.
checked :: Integer -> Either CalcError Integer
checked n
  | n < toInteger (minBound :: Int64) || n > toInteger (maxBound :: Int64) = Left Overflow
  | otherwise = Right n

-- | Evaluate an expression with 64-bit signed semantics: division truncates
-- toward zero and the remainder takes the sign of the dividend.
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
      | b == 0 = Left DivisionByZero
      | otherwise = checked (a `quot` b)
    apply Rem a b
      | b == 0 = Left DivisionByZero
      | otherwise = Right (a `rem` b)

-- | Parse and evaluate one line of input.
evaluate :: BS.ByteString -> Either CalcError Int64
evaluate line = parseExpr line >>= eval
