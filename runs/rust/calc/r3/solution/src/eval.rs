//! Expression parsing and evaluation.
//!
//! Grammar:
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! The parser is an operator-precedence (shunting-yard) machine with explicit
//! stacks rather than recursive descent, so arbitrarily deep nesting such as
//! `((((…))))` or `------1` cannot overflow the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Syntax,
    DivisionByZero,
    Overflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Error::Syntax => "syntax error",
            Error::DivisionByZero => "division by zero",
            Error::Overflow => "integer overflow",
        })
    }
}

impl std::error::Error for Error {}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinOp {
    fn from_byte(b: u8) -> Option<Self> {
        Some(match b {
            b'+' => BinOp::Add,
            b'-' => BinOp::Sub,
            b'*' => BinOp::Mul,
            b'/' => BinOp::Div,
            b'%' => BinOp::Rem,
            _ => return None,
        })
    }

    fn precedence(self) -> u8 {
        match self {
            BinOp::Add | BinOp::Sub => 1,
            BinOp::Mul | BinOp::Div | BinOp::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> Result<i64, Error> {
        match self {
            BinOp::Add => lhs.checked_add(rhs).ok_or(Error::Overflow),
            BinOp::Sub => lhs.checked_sub(rhs).ok_or(Error::Overflow),
            BinOp::Mul => lhs.checked_mul(rhs).ok_or(Error::Overflow),
            BinOp::Div | BinOp::Rem if rhs == 0 => Err(Error::DivisionByZero),
            BinOp::Div => lhs.checked_div(rhs).ok_or(Error::Overflow),
            // `i64::MIN % -1` is mathematically 0; only the hardware op traps.
            BinOp::Rem => Ok(lhs.wrapping_rem(rhs)),
        }
    }
}

/// An entry on the operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StackOp {
    Neg,
    Bin(BinOp),
    LParen,
}

/// Unary minus binds tighter than every binary operator.
const NEG_PRECEDENCE: u8 = 3;

struct Machine {
    values: Vec<i64>,
    ops: Vec<StackOp>,
}

impl Machine {
    fn new() -> Self {
        Self {
            values: Vec::new(),
            ops: Vec::new(),
        }
    }

    fn pop_value(&mut self) -> Result<i64, Error> {
        self.values.pop().ok_or(Error::Syntax)
    }

    /// Applies a single operator to the value stack.
    fn reduce(&mut self, op: StackOp) -> Result<(), Error> {
        let result = match op {
            StackOp::Neg => self.pop_value()?.checked_neg().ok_or(Error::Overflow)?,
            StackOp::Bin(bin) => {
                let rhs = self.pop_value()?;
                let lhs = self.pop_value()?;
                bin.apply(lhs, rhs)?
            }
            StackOp::LParen => return Err(Error::Syntax),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces every pending operator that binds at least as tightly as
    /// `min_precedence` (left associativity), stopping at a parenthesis.
    fn reduce_while(&mut self, min_precedence: u8) -> Result<(), Error> {
        while let Some(&top) = self.ops.last() {
            let precedence = match top {
                StackOp::Neg => NEG_PRECEDENCE,
                StackOp::Bin(bin) => bin.precedence(),
                StackOp::LParen => break,
            };
            if precedence < min_precedence {
                break;
            }
            self.ops.pop();
            self.reduce(top)?;
        }
        Ok(())
    }

    fn close_paren(&mut self) -> Result<(), Error> {
        self.reduce_while(0)?;
        match self.ops.pop() {
            Some(StackOp::LParen) => Ok(()),
            _ => Err(Error::Syntax),
        }
    }

    fn finish(mut self) -> Result<i64, Error> {
        self.reduce_while(0)?;
        if !self.ops.is_empty() {
            // Only an unmatched '(' can remain.
            return Err(Error::Syntax);
        }
        match self.values.as_slice() {
            &[value] => Ok(value),
            _ => Err(Error::Syntax),
        }
    }
}

/// Parses the decimal literal starting at `start`, returning its value and
/// the index just past its last digit.
fn parse_number(line: &[u8], start: usize) -> Result<(i64, usize), Error> {
    let mut end = start;
    let mut value: i64 = 0;
    let mut overflow = false;
    while let Some(&b) = line.get(end).filter(|b| b.is_ascii_digit()) {
        let digit = i64::from(b - b'0');
        match value.checked_mul(10).and_then(|v| v.checked_add(digit)) {
            Some(v) => value = v,
            None => overflow = true,
        }
        end += 1;
    }
    // Consume the whole literal before reporting overflow so the error is
    // attributed to the literal, not to whatever follows it.
    if overflow {
        Err(Error::Overflow)
    } else {
        Ok((value, end))
    }
}

/// Evaluates one expression line.
pub fn evaluate(line: &[u8]) -> Result<i64, Error> {
    let mut machine = Machine::new();
    // True when the next token must start an operand; false when it must be
    // a binary operator or ')'.
    let mut expect_operand = true;
    let mut i = 0;

    while i < line.len() {
        let b = line[i];
        if b == b' ' || b == b'\t' {
            i += 1;
            continue;
        }

        if expect_operand {
            match b {
                b'0'..=b'9' => {
                    let (value, end) = parse_number(line, i)?;
                    machine.values.push(value);
                    expect_operand = false;
                    i = end;
                    continue;
                }
                b'-' => machine.ops.push(StackOp::Neg),
                b'(' => machine.ops.push(StackOp::LParen),
                _ => return Err(Error::Syntax),
            }
        } else if b == b')' {
            machine.close_paren()?;
        } else {
            let op = BinOp::from_byte(b).ok_or(Error::Syntax)?;
            machine.reduce_while(op.precedence())?;
            machine.ops.push(StackOp::Bin(op));
            expect_operand = true;
        }
        i += 1;
    }

    if expect_operand {
        return Err(Error::Syntax);
    }
    machine.finish()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, Error> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("- ( 2 + 3 )"), Ok(-5));
        assert_eq!(eval("1 - -2"), Ok(3));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("1 % 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(Error::Overflow));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(eval("3037000500 * 3037000500"), Err(Error::Overflow));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")", "1 * * 2", "1-", "(", "1 (2)"] {
            assert_eq!(eval(s), Err(Error::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        let s = format!("{}1", "-".repeat(depth + 1));
        assert_eq!(eval(&s), Ok(-1));
    }
}
