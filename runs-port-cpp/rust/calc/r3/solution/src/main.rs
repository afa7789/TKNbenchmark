//! calc: 64-bit signed integer expression evaluator (see SPEC.md).
//!
//! Each input line is evaluated with an iterative operator-precedence parser,
//! so arbitrarily deep nesting cannot overflow the call stack.

use std::io::{self, Read, Write};

type Value = i64;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Op {
    Neg,
    Add,
    Sub,
    Mul,
    Div,
    Mod,
    LParen,
}

impl Op {
    fn precedence(self) -> u8 {
        match self {
            Op::LParen => 0,
            Op::Add | Op::Sub => 1,
            Op::Mul | Op::Div | Op::Mod => 2,
            Op::Neg => 3,
        }
    }

    fn binary(byte: u8) -> Option<Op> {
        match byte {
            b'+' => Some(Op::Add),
            b'-' => Some(Op::Sub),
            b'*' => Some(Op::Mul),
            b'/' => Some(Op::Div),
            b'%' => Some(Op::Mod),
            _ => None,
        }
    }

    /// Applies a binary operator, returning `None` on overflow or division by zero.
    fn apply(self, a: Value, b: Value) -> Option<Value> {
        match self {
            Op::Add => a.checked_add(b),
            Op::Sub => a.checked_sub(b),
            Op::Mul => a.checked_mul(b),
            Op::Div => a.checked_div(b),
            // `MIN % -1` is mathematically 0; only a zero divisor is an error.
            Op::Mod if b == 0 => None,
            Op::Mod => Some(a.wrapping_rem(b)),
            Op::Neg | Op::LParen => unreachable!("{self:?} is not a binary operator"),
        }
    }
}

fn is_blank(byte: u8) -> bool {
    byte == b' ' || byte == b'\t'
}

/// Marker for any syntax or arithmetic error; the spec reports both as `error`.
#[derive(Debug)]
struct EvalError;

type EvalResult<T> = Result<T, EvalError>;

/// Reusable evaluator; keeps its stacks between lines to avoid reallocating.
#[derive(Default)]
struct Evaluator {
    values: Vec<Value>,
    ops: Vec<Op>,
}

impl Evaluator {
    /// Returns the value of `line`, or an error on any syntax or arithmetic failure.
    fn evaluate(&mut self, line: &[u8]) -> EvalResult<Value> {
        self.values.clear();
        self.ops.clear();

        let mut expect_operand = true;
        let mut i = 0;

        loop {
            while line.get(i).copied().is_some_and(is_blank) {
                i += 1;
            }
            let Some(&c) = line.get(i) else { break };

            if expect_operand {
                match c {
                    b'-' => {
                        self.ops.push(Op::Neg);
                        i += 1;
                    }
                    b'(' => {
                        self.ops.push(Op::LParen);
                        i += 1;
                    }
                    b'0'..=b'9' => {
                        let (value, len) = parse_number(&line[i..])?;
                        self.values.push(value);
                        i += len;
                        expect_operand = false;
                    }
                    _ => return Err(EvalError),
                }
            } else if c == b')' {
                self.reduce_while(|op| op != Op::LParen)?;
                // An empty stack here means an unmatched ')'.
                self.ops.pop().ok_or(EvalError)?;
                i += 1;
            } else if let Some(op) = Op::binary(c) {
                let p = op.precedence();
                self.reduce_while(|top| top.precedence() >= p)?;
                self.ops.push(op);
                expect_operand = true;
                i += 1;
            } else {
                return Err(EvalError);
            }
        }

        if expect_operand {
            return Err(EvalError); // missing operand
        }
        self.reduce_while(|op| op != Op::LParen)?;
        match (self.ops.is_empty(), self.values.as_slice()) {
            (true, &[value]) => Ok(value),
            _ => Err(EvalError), // unmatched '('
        }
    }

    /// Applies the top operator to the value stack.
    fn reduce_once(&mut self) -> EvalResult<()> {
        let op = self.ops.pop().ok_or(EvalError)?;
        let b = self.values.pop().ok_or(EvalError)?;
        let result = if op == Op::Neg {
            b.checked_neg()
        } else {
            let a = self.values.pop().ok_or(EvalError)?;
            op.apply(a, b)
        };
        self.values.push(result.ok_or(EvalError)?);
        Ok(())
    }

    fn reduce_while(&mut self, pred: impl Fn(Op) -> bool) -> EvalResult<()> {
        while self.ops.last().is_some_and(|&op| pred(op)) {
            self.reduce_once()?;
        }
        Ok(())
    }
}

/// Parses the leading run of ASCII digits in `bytes`, returning its value and
/// length. Fails if the literal exceeds `i64::MAX`.
fn parse_number(bytes: &[u8]) -> EvalResult<(Value, usize)> {
    let len = bytes.iter().take_while(|b| b.is_ascii_digit()).count();
    let value = bytes[..len].iter().try_fold(0 as Value, |acc, &d| {
        acc.checked_mul(10)?.checked_add(Value::from(d - b'0'))
    });
    value.map(|v| (v, len)).ok_or(EvalError)
}

fn main() -> io::Result<()> {
    let mut input = Vec::new();
    io::stdin().lock().read_to_end(&mut input)?;

    let mut evaluator = Evaluator::default();
    let mut out = io::BufWriter::new(io::stdout().lock());

    for line in input.split(|&b| b == b'\n') {
        if line.iter().all(|&b| is_blank(b)) {
            continue;
        }
        match evaluator.evaluate(line) {
            Ok(value) => writeln!(out, "{value}")?,
            Err(EvalError) => writeln!(out, "error")?,
        }
    }
    out.flush()
}
