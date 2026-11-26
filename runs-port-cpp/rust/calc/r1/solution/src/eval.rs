//! Iterative (shunting-yard) evaluator for checked 64-bit integer expressions.

use std::fmt;

/// Why an expression could not be evaluated.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum EvalError {
    /// The input does not match the grammar.
    Syntax,
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result does not fit in an `i64`.
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    Neg,
    LParen,
}

impl Op {
    fn binary(byte: u8) -> Option<Self> {
        match byte {
            b'+' => Some(Self::Add),
            b'-' => Some(Self::Sub),
            b'*' => Some(Self::Mul),
            b'/' => Some(Self::Div),
            b'%' => Some(Self::Mod),
            _ => None,
        }
    }

    fn precedence(self) -> u8 {
        match self {
            Self::LParen => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Mod => 2,
            Self::Neg => 3,
        }
    }

    fn apply_binary(self, lhs: i64, rhs: i64) -> Result<i64, EvalError> {
        let result = match self {
            Self::Add => lhs.checked_add(rhs),
            Self::Sub => lhs.checked_sub(rhs),
            Self::Mul => lhs.checked_mul(rhs),
            Self::Div => {
                if rhs == 0 {
                    return Err(EvalError::DivisionByZero);
                }
                lhs.checked_div(rhs)
            }
            Self::Mod => {
                if rhs == 0 {
                    return Err(EvalError::DivisionByZero);
                }
                // `i64::MIN % -1` is mathematically 0, which wrapping_rem yields.
                Some(lhs.wrapping_rem(rhs))
            }
            Self::Neg | Self::LParen => unreachable!("{self:?} is not a binary operator"),
        };
        result.ok_or(EvalError::Overflow)
    }
}

/// Evaluates expressions, reusing its stacks between calls.
#[derive(Debug, Default)]
pub struct Evaluator {
    values: Vec<i64>,
    ops: Vec<Op>,
}

impl Evaluator {
    /// Returns the value of `line`, which must contain a single expression.
    pub fn evaluate(&mut self, line: &[u8]) -> Result<i64, EvalError> {
        self.values.clear();
        self.ops.clear();

        let mut expect_operand = true;
        let mut i = 0;

        loop {
            while matches!(line.get(i), Some(b' ' | b'\t')) {
                i += 1;
            }
            let Some(&c) = line.get(i) else { break };

            if expect_operand {
                match c {
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&line[i..])?;
                        self.values.push(value);
                        i += len;
                        expect_operand = false;
                        continue;
                    }
                    b'-' => self.ops.push(Op::Neg),
                    b'(' => self.ops.push(Op::LParen),
                    _ => return Err(EvalError::Syntax),
                }
            } else if c == b')' {
                while self.ops.last().is_some_and(|&op| op != Op::LParen) {
                    self.reduce()?;
                }
                self.ops.pop().ok_or(EvalError::Syntax)?;
            } else if let Some(op) = Op::binary(c) {
                // Left associativity: reduce operators of equal or higher precedence.
                while self
                    .ops
                    .last()
                    .is_some_and(|top| top.precedence() >= op.precedence())
                {
                    self.reduce()?;
                }
                self.ops.push(op);
                expect_operand = true;
            } else {
                return Err(EvalError::Syntax);
            }
            i += 1;
        }

        if expect_operand {
            return Err(EvalError::Syntax);
        }
        while let Some(&top) = self.ops.last() {
            if top == Op::LParen {
                return Err(EvalError::Syntax);
            }
            self.reduce()?;
        }
        self.values.last().copied().ok_or(EvalError::Syntax)
    }

    /// Applies the operator on top of the stack to its operand(s).
    ///
    /// The parser guarantees the operand stack holds enough values.
    fn reduce(&mut self) -> Result<(), EvalError> {
        let op = self.ops.pop().expect("reduce called with an empty operator stack");
        let rhs = self.values.pop().expect("operator without operand");
        let result = if op == Op::Neg {
            rhs.checked_neg().ok_or(EvalError::Overflow)?
        } else {
            let lhs = self.values.pop().expect("binary operator without left operand");
            op.apply_binary(lhs, rhs)?
        };
        self.values.push(result);
        Ok(())
    }
}

/// Parses the leading run of ASCII digits, returning its value and length.
fn parse_number(bytes: &[u8]) -> Result<(i64, usize), EvalError> {
    let len = bytes.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = bytes[..len].iter().try_fold(0i64, |acc, &b| {
        acc.checked_mul(10)
            .and_then(|acc| acc.checked_add(i64::from(b - b'0')))
            .ok_or(EvalError::Overflow)
    })?;
    Ok((value, len))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Result<i64, EvalError> {
        Evaluator::default().evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic() {
        assert_eq!(eval("1 + 2 * 3"), Ok(7));
        assert_eq!(eval("10 - 4 - 3"), Ok(3));
        assert_eq!(eval("-7 / 2"), Ok(-3));
        assert_eq!(eval("-7 % 3"), Ok(-1));
        assert_eq!(eval("7 % -3"), Ok(1));
        assert_eq!(eval("--5"), Ok(5));
        assert_eq!(eval("-(2 + 3)"), Ok(-5));
    }

    #[test]
    fn limits() {
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Ok(0));
        assert_eq!(eval("-9223372036854775807 - 1"), Ok(i64::MIN));
        assert_eq!(eval("9223372036854775807 + 1"), Err(EvalError::Overflow));
        assert_eq!(eval("9223372036854775808"), Err(EvalError::Overflow));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), Err(EvalError::Overflow));
        assert_eq!(eval("-(-9223372036854775807 - 1)"), Err(EvalError::Overflow));
    }

    #[test]
    fn errors() {
        assert_eq!(eval("1 / 0"), Err(EvalError::DivisionByZero));
        assert_eq!(eval("5 % 0"), Err(EvalError::DivisionByZero));
        for bad in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1)", "1\r"] {
            assert_eq!(eval(bad), Err(EvalError::Syntax), "{bad}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let expr = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&expr), Ok(1));
    }
}
