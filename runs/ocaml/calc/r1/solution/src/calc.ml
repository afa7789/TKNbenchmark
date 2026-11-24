(* calc: a 64-bit signed integer expression evaluator.

   Reads one expression per line from standard input and prints its value,
   or [error] on a syntax error, division by zero, or overflow. *)

exception Error

(* ---------- checked 64-bit arithmetic ---------- *)

module Checked = struct
  let add a b =
    let r = Int64.add a b in
    (* Overflow iff both operands have the same sign and the result differs. *)
    if Int64.logand (Int64.logxor a r) (Int64.logxor b r) < 0L then raise Error;
    r

  let sub a b =
    let r = Int64.sub a b in
    (* Overflow iff operands differ in sign and the result's sign differs from [a]. *)
    if Int64.logand (Int64.logxor a b) (Int64.logxor a r) < 0L then raise Error;
    r

  let neg a = if a = Int64.min_int then raise Error else Int64.neg a

  let mul a b =
    if a = 0L || b = 0L then 0L
    else if (a = -1L && b = Int64.min_int) || (b = -1L && a = Int64.min_int)
    then raise Error
    else
      let r = Int64.mul a b in
      if Int64.div r b <> a then raise Error;
      r

  let div a b =
    if b = 0L then raise Error
    else if b = -1L then neg a
    else Int64.div a b

  let rem a b =
    if b = 0L then raise Error
    else if b = -1L then 0L
    else Int64.rem a b
end

(* ---------- recursive-descent parser / evaluator ---------- *)

type state = { line : string; mutable pos : int }

let is_blank c = c = ' ' || c = '\t'
let is_digit c = c >= '0' && c <= '9'

let skip_blanks st =
  let n = String.length st.line in
  while st.pos < n && is_blank st.line.[st.pos] do
    st.pos <- st.pos + 1
  done

(* Next non-blank character, without consuming it. *)
let peek st =
  skip_blanks st;
  if st.pos < String.length st.line then Some st.line.[st.pos] else None

let advance st = st.pos <- st.pos + 1

let number st =
  let n = String.length st.line in
  let rec go acc =
    if st.pos < n && is_digit st.line.[st.pos] then begin
      let d = Int64.of_int (Char.code st.line.[st.pos] - Char.code '0') in
      (* acc * 10 + d <= max_int  <=>  acc <= (max_int - d) / 10 *)
      if acc > Int64.div (Int64.sub Int64.max_int d) 10L then raise Error;
      advance st;
      go (Int64.add (Int64.mul acc 10L) d)
    end
    else acc
  in
  go 0L

let rec expr st =
  let rec loop acc =
    match peek st with
    | Some '+' -> advance st; loop (Checked.add acc (term st))
    | Some '-' -> advance st; loop (Checked.sub acc (term st))
    | _ -> acc
  in
  loop (term st)

and term st =
  let rec loop acc =
    match peek st with
    | Some '*' -> advance st; loop (Checked.mul acc (unary st))
    | Some '/' -> advance st; loop (Checked.div acc (unary st))
    | Some '%' -> advance st; loop (Checked.rem acc (unary st))
    | _ -> acc
  in
  loop (unary st)

and unary st =
  match peek st with
  | Some '-' -> advance st; Checked.neg (unary st)
  | _ -> primary st

and primary st =
  match peek st with
  | Some c when is_digit c -> number st
  | Some '(' ->
      advance st;
      let v = expr st in
      (match peek st with Some ')' -> advance st | _ -> raise Error);
      v
  | _ -> raise Error

let evaluate line =
  let st = { line; pos = 0 } in
  match
    let v = expr st in
    if peek st <> None then raise Error;
    v
  with
  | v -> Some v
  | exception (Error | Stack_overflow) -> None

let is_blank_line line = String.for_all is_blank line

let () =
  let out = Buffer.create 65536 in
  let flush_if_large () =
    if Buffer.length out >= 65536 then begin
      print_string (Buffer.contents out);
      Buffer.clear out
    end
  in
  let rec loop () =
    match In_channel.input_line stdin with
    | None -> ()
    | Some line ->
        if not (is_blank_line line) then begin
          (match evaluate line with
           | Some v -> Buffer.add_string out (Int64.to_string v)
           | None -> Buffer.add_string out "error");
          Buffer.add_char out '\n';
          flush_if_large ()
        end;
        loop ()
  in
  loop ();
  print_string (Buffer.contents out);
  exit 0
