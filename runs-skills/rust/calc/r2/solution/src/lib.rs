//! A checked 64-bit signed integer expression evaluator.
//!
//! Grammar (spaces and tabs may separate any two tokens):
//!
//! ```text
//! expr    := term    (('+' | '-') term)*
//! term    := unary   (('*' | '/' | '%') unary)*
//! unary   := '-' unary | primary
//! primary := NUMBER | '(' expr ')'
//! NUMBER  := [0-9]+
//! ```
//!
//! Evaluation uses an operator-precedence (shunting-yard) algorithm with
//! explicit stacks, so arbitrarily deep nesting cannot overflow the call stack.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result lies outside the `i64` range.
    Overflow,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Self::Syntax => "syntax error",
            Self::DivisionByZero => "division by zero",
            Self::Overflow => "overflow",
        })
    }
}

impl std::error::Error for Error {}

/// Returns `true` if the line is empty or holds only spaces and tabs.
#[must_use]
pub fn is_blank(line: &[u8]) -> bool {
    line.iter().all(|&b| is_space(b))
}

const fn is_space(b: u8) -> bool {
    matches!(b, b' ' | b'\t')
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
}

impl BinOp {
    const fn from_byte(b: u8) -> Option<Self> {
        Some(match b {
            b'+' => Self::Add,
            b'-' => Self::Sub,
            b'*' => Self::Mul,
            b'/' => Self::Div,
            b'%' => Self::Rem,
            _ => return None,
        })
    }

    const fn precedence(self) -> u8 {
        match self {
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
        }
    }

    fn apply(self, lhs: i64, rhs: i64) -> Result<i64, Error> {
        match self {
            Self::Add => lhs.checked_add(rhs).ok_or(Error::Overflow),
            Self::Sub => lhs.checked_sub(rhs).ok_or(Error::Overflow),
            Self::Mul => lhs.checked_mul(rhs).ok_or(Error::Overflow),
            Self::Div | Self::Rem if rhs == 0 => Err(Error::DivisionByZero),
            Self::Div => lhs.checked_div(rhs).ok_or(Error::Overflow),
            // `i64::MIN % -1` is mathematically 0; only the quotient overflows.
            Self::Rem => Ok(lhs.wrapping_rem(rhs)),
        }
    }
}

/// An entry on the pending-operator stack.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Pending {
    Neg,
    Bin(BinOp),
    Open,
}

/// Explicit evaluation state for the shunting-yard algorithm.
#[derive(Default)]
struct Machine {
    values: Vec<i64>,
    ops: Vec<Pending>,
}

impl Machine {
    fn pop_value(&mut self) -> Result<i64, Error> {
        // The parser state machine guarantees operands are present.
        self.values.pop().ok_or(Error::Syntax)
    }

    /// Applies the operator on top of the stack to the value stack.
    fn reduce(&mut self, op: Pending) -> Result<(), Error> {
        let result = match op {
            Pending::Neg => self.pop_value()?.checked_neg().ok_or(Error::Overflow)?,
            Pending::Bin(bin) => {
                let rhs = self.pop_value()?;
                let lhs = self.pop_value()?;
                bin.apply(lhs, rhs)?
            }
            Pending::Open => return Err(Error::Syntax),
        };
        self.values.push(result);
        Ok(())
    }

    /// Reduces every pending operator that binds at least as tightly as
    /// `min_precedence` (unary minus binds tighter than any binary operator).
    fn reduce_while(&mut self, min_precedence: u8) -> Result<(), Error> {
        while let Some(&top) = self.ops.last() {
            let binds = match top {
                Pending::Neg => true,
                Pending::Bin(bin) => bin.precedence() >= min_precedence,
                Pending::Open => false,
            };
            if !binds {
                break;
            }
            self.ops.pop();
            self.reduce(top)?;
        }
        Ok(())
    }
}

/// Parses a run of ASCII digits as a non-negative `i64`.
fn parse_number(digits: &[u8]) -> Result<i64, Error> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)
            .and_then(|v| v.checked_add(i64::from(d - b'0')))
            .ok_or(Error::Overflow)
    })
}

/// Evaluates one expression.
///
/// # Errors
///
/// Returns [`Error::Syntax`] for input outside the grammar,
/// [`Error::DivisionByZero`] for `/` or `%` by zero, and [`Error::Overflow`]
/// when a literal or any intermediate result does not fit in an `i64`.
pub fn evaluate(input: &[u8]) -> Result<i64, Error> {
    let mut machine = Machine::default();
    // `true` while the next token must start an operand (number, `-`, `(`).
    let mut expect_operand = true;
    let mut i = 0;

    while i < input.len() {
        let b = input[i];
        if is_space(b) {
            i += 1;
            continue;
        }

        if b.is_ascii_digit() {
            if !expect_operand {
                return Err(Error::Syntax);
            }
            let len = input[i..].iter().take_while(|c| c.is_ascii_digit()).count();
            machine.values.push(parse_number(&input[i..i + len])?);
            expect_operand = false;
            i += len;
            continue;
        }

        match (expect_operand, b) {
            (true, b'-') => machine.ops.push(Pending::Neg),
            (true, b'(') => machine.ops.push(Pending::Open),
            (false, b')') => {
                machine.reduce_while(0)?;
                if machine.ops.pop() != Some(Pending::Open) {
                    return Err(Error::Syntax);
                }
            }
            (false, _) => {
                let op = BinOp::from_byte(b).ok_or(Error::Syntax)?;
                machine.reduce_while(op.precedence())?;
                machine.ops.push(Pending::Bin(op));
                expect_operand = true;
            }
            (true, _) => return Err(Error::Syntax),
        }
        i += 1;
    }

    if expect_operand {
        return Err(Error::Syntax);
    }
    machine.reduce_while(0)?;
    if !machine.ops.is_empty() {
        // Only unmatched `(` can remain.
        return Err(Error::Syntax);
    }
    match machine.values.as_slice() {
        &[value] => Ok(value),
        _ => Err(Error::Syntax),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, Error> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn precedence_and_associativity() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("(1 + 2) * 3"), Ok(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Ok(5));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("100 / 10 / 5"), Ok(2));
        assert_eq!(eval("2*(3+4)*5"), Ok(70));
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("2 * -3"), Ok(-6));
        assert_eq!(eval("1 - -2"), Ok(3));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
        assert_eq!(eval("-2 * 3"), Ok(-6));
        assert_eq!(eval("- 7"), Ok(-7));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("1 / 0"), Err(Error::DivisionByZero));
        assert_eq!(eval("5 % (1 - 1)"), Err(Error::DivisionByZero));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807"), Ok(i64::MAX));
        assert_eq!(eval("9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775808"), Err(Error::Overflow));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(Error::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(Error::Overflow));
        assert_eq!(
            eval("(-9223372036854775807 - 1) / -1"),
            Err(Error::Overflow)
        );
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("3037000500 * 3037000500"), Err(Error::Overflow));
        assert_eq!(eval("00000000000000000000001"), Ok(1));
    }

    #[test]
    fn syntax_errors() {
        for s in [
            "1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 -", "*1", "1 ** 2", "(",
            ")", "-", "2 (3)", "(2) 3", "1\r", "1_000", "",
        ] {
            assert_eq!(eval(s), Err(Error::Syntax), "{s:?}");
        }
    }

    #[test]
    fn deep_nesting_does_not_overflow_stack() {
        let depth = 1_000_000;
        let s = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
        let s = format!("{}1", "-".repeat(depth));
        assert_eq!(eval(&s), Ok(1));
    }

    #[test]
    fn blank_detection() {
        assert!(is_blank(b""));
        assert!(is_blank(b" \t "));
        assert!(!is_blank(b" 1 "));
    }
}
