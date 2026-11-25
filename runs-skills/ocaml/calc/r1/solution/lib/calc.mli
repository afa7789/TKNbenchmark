(** Evaluator for signed 64-bit integer arithmetic expressions.

    Grammar:
    {v
    expr    := term    (('+' | '-') term)*
    term    := unary   (('*' | '/' | '%') unary)*
    unary   := '-' unary | primary
    primary := NUMBER | '(' expr ')'
    NUMBER  := [0-9]+
    v}
    Spaces and tabs may separate tokens. *)

type error =
  | Syntax_error
  | Division_by_zero
  | Overflow

val eval : string -> (int64, error) result
(** [eval s] evaluates the expression [s] with exact 64-bit semantics:
    division truncates toward zero, remainder takes the sign of the dividend,
    and any result outside the signed 64-bit range is an [Overflow]. *)

val is_blank : string -> bool
(** [is_blank s] holds when [s] contains only spaces and tabs. *)
