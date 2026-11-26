//! Evaluator for 64-bit signed integer expressions.
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! ```
//!
//! Spaces and tabs may separate tokens. Parsing uses an operator-precedence
//! (shunting-yard) algorithm with explicit stacks, so arbitrarily deep nesting
//! cannot exhaust the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// The input does not match the grammar.
    Syntax,
    /// A divisor or remainder operand was zero.
    DivisionByZero,
    /// A literal or intermediate result is outside the `i64` range.
    Overflow,
}

impl fmt::Display for EvalError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for EvalError {}

/// Returns true for the blank characters allowed between tokens.
pub fn is_blank(byte: u8) -> bool {
    matches!(byte, b' ' | b'\t')
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinaryOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinaryOp {
    fn from_byte(byte: u8) -> Option<Self> {
        Some(match byte {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    fn precedence(self) -> u8 {
        match self {
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, left: i64, right: i64) -> Result<i64, EvalError> {
        if matches!(self, Self::Div | Self::Rem) && right == 0 {
            return Err(EvalError::DivisionByZero);
        }
        match self {
            Self::Add => left.checked_add(right),
            Self::Sub => left.checked_sub(right),
            Self::Mul => left.checked_mul(right),
            Self::Div => left.checked_div(right),
            // `i64::MIN % -1` is mathematically 0, which `wrapping_rem` yields.
            Self::Rem => Some(left.wrapping_rem(right)),
        }
        .ok_or(EvalError::Overflow)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Negate,
    OpenParen,
    Binary(BinaryOp),
}

/// Evaluates `src` as one complete expression.
pub fn evaluate(src: &[u8]) -> Result<i64, EvalError> {
    Evaluator::new(src).run()
}

struct Evaluator<'a> {
    src: &'a [u8],
    pos: usize,
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl<'a> Evaluator<'a> {
    fn new(src: &'a [u8]) -> Self {
        Self {
            src,
            pos: 0,
            values: Vec::new(),
            ops: Vec::new(),
        }
    }

    fn run(mut self) -> Result<i64, EvalError> {
        loop {
            self.operand()?;
            if !self.operator()? {
                break;
            }
        }
        while let Some(op) = self.ops.pop() {
            match op {
                StackOp::OpenParen => return Err(EvalError::Syntax),
                op => self.reduce(op)?,
            }
        }
        debug_assert_eq!(self.values.len(), 1);
        self.values.pop().ok_or(EvalError::Syntax)
    }

    /// Parses prefix negations and opening parentheses up to and including one literal.
    fn operand(&mut self) -> Result<(), EvalError> {
        loop {
            match self.peek() {
                Some(b'-') => self.push_prefix(StackOp::Negate),
                Some(b'(') => self.push_prefix(StackOp::OpenParen),
                Some(b'0'..=b'9') => {
                    let value = self.number()?;
                    self.values.push(value);
                    return Ok(());
                }
                _ => return Err(EvalError::Syntax),
            }
        }
    }

    fn push_prefix(&mut self, op: StackOp) {
        self.pos += 1;
        self.ops.push(op);
    }

    /// Parses closing parentheses followed by one binary operator.
    ///
    /// Returns `Ok(false)` at end of input, `Ok(true)` when an operand must follow.
    fn operator(&mut self) -> Result<bool, EvalError> {
        loop {
            let Some(byte) = self.peek() else {
                return Ok(false);
            };
            self.pos += 1;
            if byte == b')' {
                self.close_paren()?;
                continue;
            }
            let op = BinaryOp::from_byte(byte).ok_or(EvalError::Syntax)?;
            while let Some(&top) = self.ops.last() {
                let binds_tighter = match top {
                    StackOp::Negate => true,
                    StackOp::Binary(prev) => prev.precedence() >= op.precedence(),
                    StackOp::OpenParen => false,
                };
                if !binds_tighter {
                    break;
                }
                self.ops.pop();
                self.reduce(top)?;
            }
            self.ops.push(StackOp::Binary(op));
            return Ok(true);
        }
    }

    fn close_paren(&mut self) -> Result<(), EvalError> {
        loop {
            match self.ops.pop() {
                Some(StackOp::OpenParen) => return Ok(()),
                Some(op) => self.reduce(op)?,
                None => return Err(EvalError::Syntax),
            }
        }
    }

    /// Applies `op` to the operands on top of the value stack.
    fn reduce(&mut self, op: StackOp) -> Result<(), EvalError> {
        let right = self.values.pop().ok_or(EvalError::Syntax)?;
        let result = match op {
            StackOp::Negate => right.checked_neg().ok_or(EvalError::Overflow)?,
            StackOp::Binary(op) => {
                let left = self.values.pop().ok_or(EvalError::Syntax)?;
                op.apply(left, right)?
            }
            StackOp::OpenParen => unreachable!("parentheses are never reduced"),
        };
        self.values.push(result);
        Ok(())
    }

    fn number(&mut self) -> Result<i64, EvalError> {
        let digits = self.src[self.pos..]
            .iter()
            .take_while(|byte| byte.is_ascii_digit())
            .count();
        let literal = &self.src[self.pos..self.pos + digits];
        self.pos += digits;
        literal.iter().try_fold(0i64, |acc, &digit| {
            acc.checked_mul(10)
                .and_then(|acc| acc.checked_add(i64::from(digit - b'0')))
                .ok_or(EvalError::Overflow)
        })
    }

    /// Skips blanks and returns the next byte without consuming it.
    fn peek(&mut self) -> Option<u8> {
        while self.src.get(self.pos).copied().is_some_and(is_blank) {
            self.pos += 1;
        }
        self.src.get(self.pos).copied()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, EvalError> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("1 % 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
        assert_eq!(eval("-4611686018427387904 * 2"), Ok(i64::MIN));
    }

    #[test]
    fn syntax_errors() {
        for input in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "-", "1 -", "1\r"] {
            assert_eq!(eval(input), Err(EvalError::Syntax), "{input:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let input = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&input), Ok(1));
        let input = format!("{}7", "-".repeat(depth + 1));
        assert_eq!(eval(&input), Ok(-7));
    }
}
