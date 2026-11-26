//! Error type for expression evaluation.

use std::fmt;

/// Any failure while evaluating an expression.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CalcError {
    /// The input does not match the grammar; `pos` is the byte offset of the problem.
    Syntax { pos: usize },
    /// Division or remainder by zero.
    DivisionByZero,
    /// A literal or intermediate result outside the signed 64-bit range.
    Overflow,
    /// Parentheses or unary minus nested deeper than the evaluator supports.
    TooDeep,
}

impl fmt::Display for CalcError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Syntax { pos } => write!(f, "syntax error at byte {pos}"),
            Self::DivisionByZero => f.write_str("division by zero"),
            Self::Overflow => f.write_str("integer overflow"),
            Self::TooDeep => f.write_str("expression nested too deeply"),
        }
    }
}

impl std::error::Error for CalcError {}
