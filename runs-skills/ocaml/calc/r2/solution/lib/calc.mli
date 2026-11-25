(** Evaluator for signed 64-bit integer arithmetic expressions.

    Grammar (spaces and tabs allowed between tokens):
    {v
    expr    := term    (('+' | '-') term)*
    term    := unary   (('*' | '/' | '%') unary)*
    unary   := '-' unary | primary
    primary := NUMBER | '(' expr ')'
    v} *)

type error =
  | Syntax  (** Malformed input. *)
  | Division_by_zero  (** Right operand of [/] or [%] is zero. *)
  | Overflow  (** A literal or intermediate result exceeds 64 bits. *)

val eval : string -> (int64, error) result
(** [eval s] evaluates the expression [s]. *)

val is_blank : string -> bool
(** [is_blank s] holds when [s] contains only spaces and tabs. *)
