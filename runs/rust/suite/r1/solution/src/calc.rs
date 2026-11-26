//! `calc`: a checked 64-bit signed integer expression evaluator, one expression per line.
//!
//! Evaluation uses an explicit operator stack (shunting-yard), so arbitrarily deep
//! nesting cannot overflow the call stack.

use std::io::{self, Write};

/// Evaluates each non-blank line of `input`, writing its value or `error`.
pub fn run(input: &[u8], out: &mut dyn Write) -> io::Result<()> {
    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|&b| b == b' ' || b == b'\t') {
            continue;
        }
        match evaluate(line) {
            Some(value) => writeln!(out, "{value}")?,
            None => out.write_all(b"error\n")?,
        }
    }
    Ok(())
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum Op {
    Add,
    Sub,
    Mul,
    Div,
    Rem,
    Neg,
    /// An open parenthesis marker on the operator stack.
    Paren,
}

impl Op {
    fn binary(byte: u8) -> Option<Self> {
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
            Self::Paren => 0,
            Self::Add | Self::Sub => 1,
            Self::Mul | Self::Div | Self::Rem => 2,
            Self::Neg => 3,
        }
    }
}

/// Evaluates one expression; `None` signals a syntax, division-by-zero or overflow error.
pub fn evaluate(expr: &[u8]) -> Option<i64> {
    let mut values: Vec<i64> = Vec::new();
    let mut ops: Vec<Op> = Vec::new();
    let mut expect_operand = true;
    let mut i = 0;

    while i < expr.len() {
        let byte = expr[i];
        match byte {
            b' ' | b'\t' => {}
            b'0'..=b'9' if expect_operand => {
                let start = i;
                while i + 1 < expr.len() && expr[i + 1].is_ascii_digit() {
                    i += 1;
                }
                values.push(parse_literal(&expr[start..=i])?);
                expect_operand = false;
            }
            b'-' if expect_operand => ops.push(Op::Neg),
            b'(' if expect_operand => ops.push(Op::Paren),
            b')' if !expect_operand => {
                loop {
                    match ops.pop()? {
                        Op::Paren => break,
                        op => apply(op, &mut values)?,
                    }
                }
            }
            _ if !expect_operand => {
                let op = Op::binary(byte)?;
                while let Some(&top) = ops.last() {
                    if top.precedence() < op.precedence() {
                        break;
                    }
                    ops.pop();
                    apply(top, &mut values)?;
                }
                ops.push(op);
                expect_operand = true;
            }
            _ => return None,
        }
        i += 1;
    }

    if expect_operand {
        return None;
    }
    while let Some(op) = ops.pop() {
        if op == Op::Paren {
            return None;
        }
        apply(op, &mut values)?;
    }
    match values[..] {
        [value] => Some(value),
        _ => None,
    }
}

fn parse_literal(digits: &[u8]) -> Option<i64> {
    digits.iter().try_fold(0i64, |acc, &d| {
        acc.checked_mul(10)?.checked_add(i64::from(d - b'0'))
    })
}

fn apply(op: Op, values: &mut Vec<i64>) -> Option<()> {
    let rhs = values.pop()?;
    let result = if op == Op::Neg {
        rhs.checked_neg()?
    } else {
        let lhs = values.pop()?;
        match op {
            Op::Add => lhs.checked_add(rhs)?,
            Op::Sub => lhs.checked_sub(rhs)?,
            Op::Mul => lhs.checked_mul(rhs)?,
            Op::Div => lhs.checked_div(rhs)?,
            // MIN % -1 is mathematically 0; only a zero divisor is an error.
            Op::Rem if rhs == 0 => return None,
            Op::Rem => lhs.wrapping_rem(rhs),
            Op::Neg | Op::Paren => unreachable!("not a binary operator"),
        }
    };
    values.push(result);
    Some(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn eval(s: &str) -> Option<i64> {
        evaluate(s.as_bytes())
    }

    #[test]
    fn arithmetic_and_precedence() {
        assert_eq!(eval("1 + 2 * 3"), Some(7));
        assert_eq!(eval("(1 + 2) * 3"), Some(9));
        assert_eq!(eval("1 + 2 * 3 - 4 / 2 % 3"), Some(5));
        assert_eq!(eval("10 - 4 - 3"), Some(3));
        assert_eq!(eval("2*(3+4)*5"), Some(70));
        assert_eq!(eval("100 / 10 / 5"), Some(2));
    }

    #[test]
    fn division_semantics() {
        assert_eq!(eval("-7 / 2"), Some(-3));
        assert_eq!(eval("-7 % 3"), Some(-1));
        assert_eq!(eval("7 % -3"), Some(1));
        assert_eq!(eval("1 / 0"), None);
        assert_eq!(eval("5 % 0"), None);
        assert_eq!(eval("(-9223372036854775807 - 1) % -1"), Some(0));
        assert_eq!(eval("(-9223372036854775807 - 1) / -1"), None);
    }

    #[test]
    fn unary_minus() {
        assert_eq!(eval("--5"), Some(5));
        assert_eq!(eval("2 * -3"), Some(-6));
        assert_eq!(eval("1 - -2"), Some(3));
        assert_eq!(eval("-(2 + 3)"), Some(-5));
        assert_eq!(eval("- 2 * 3"), Some(-6));
        assert_eq!(eval("-9223372036854775808"), None);
        assert_eq!(eval("-9223372036854775807 - 1"), Some(i64::MIN));
    }

    #[test]
    fn overflow() {
        assert_eq!(eval("9223372036854775807 + 1"), None);
        assert_eq!(eval("9223372036854775808"), None);
        assert_eq!(eval("3037000500 * 3037000500"), None);
        assert_eq!(eval("0009223372036854775807"), Some(i64::MAX));
    }

    #[test]
    fn syntax_errors() {
        for s in ["1 +", "abc", "()", "1 2", "+1", "(1 + 2", "1 + 2)", ")(", "1 - ", "1 ** 2", "1 2 + 3", "1\r"] {
            assert_eq!(eval(s), None, "{s:?}");
        }
    }

    #[test]
    fn deep_nesting() {
        let depth = 1_000_000;
        let expr = format!("{}1{}", "(".repeat(depth), ")".repeat(depth));
        assert_eq!(eval(&expr), Some(1));
        assert_eq!(eval(&format!("{}1", "-".repeat(depth + 1))), Some(-1));
    }

    #[test]
    fn blank_lines_skipped() {
        let mut out = Vec::new();
        run(b"\n  42  \n\t\n1+1\n", &mut out).unwrap();
        assert_eq!(out, b"42\n2\n");
    }
}
