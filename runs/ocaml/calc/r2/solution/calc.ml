(* calc: a 64-bit signed integer expression evaluator.

   Reads one expression per line from stdin and prints its value or
   [error]. Parsing and evaluation are fused in a recursive-descent
   parser; any syntax or arithmetic failure raises [Error]. *)

exception Error

(* ---------- checked 64-bit arithmetic ---------- *)

module Checked = struct
  let add a b =
    let s = Int64.add a b in
    (* Overflow iff both operands share a sign that the result lacks. *)
    if Int64.logand (Int64.logxor a s) (Int64.logxor b s) < 0L then raise Error;
    s

  let sub a b =
    let d = Int64.sub a b in
    (* Overflow iff the operands differ in sign and the result's sign
       differs from the minuend's. *)
    if Int64.logand (Int64.logxor a b) (Int64.logxor a d) < 0L then raise Error;
    d

  let neg a = if a = Int64.min_int then raise Error else Int64.neg a

  let mul a b =
    if a = 0L || b = 0L then 0L
    else if (a = -1L && b = Int64.min_int) || (b = -1L && a = Int64.min_int)
    then raise Error
    else
      let p = Int64.mul a b in
      if Int64.div p b <> a then raise Error;
      p

  let div a b =
    if b = 0L then raise Error
    else if b = -1L then neg a
    else Int64.div a b

  let rem a b =
    if b = 0L then raise Error
    else if b = -1L then 0L
    else Int64.rem a b
end

(* ---------- parser / evaluator ---------- *)

type state = { line : string; mutable pos : int }

let is_blank c = c = ' ' || c = '\t'

let skip_blanks st =
  let len = String.length st.line in
  while st.pos < len && is_blank st.line.[st.pos] do
    st.pos <- st.pos + 1
  done

(* Next non-blank character, without consuming it. *)
let peek st =
  skip_blanks st;
  if st.pos < String.length st.line then Some st.line.[st.pos] else None

let advance st = st.pos <- st.pos + 1

let number st =
  let len = String.length st.line in
  let rec loop acc =
    if st.pos < len then
      match st.line.[st.pos] with
      | '0' .. '9' as c ->
          let d = Int64.of_int (Char.code c - Char.code '0') in
          (* acc * 10 + d <= max_int  <=>  acc <= (max_int - d) / 10 *)
          if acc > Int64.div (Int64.sub Int64.max_int d) 10L then raise Error;
          advance st;
          loop (Int64.add (Int64.mul acc 10L) d)
      | _ -> acc
    else acc
  in
  loop 0L

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
  | Some '0' .. '9' -> number st
  | Some '(' ->
      advance st;
      let v = expr st in
      (match peek st with Some ')' -> advance st | _ -> raise Error);
      v
  | _ -> raise Error

let evaluate line =
  let st = { line; pos = 0 } in
  let v = expr st in
  match peek st with None -> v | Some _ -> raise Error

let is_blank_line line = String.for_all is_blank line

(* ---------- driver ---------- *)

let () =
  let out = Buffer.create 65536 in
  let flush_out () =
    print_string (Buffer.contents out);
    Buffer.clear out
  in
  (try
     while true do
       let line = input_line stdin in
       if not (is_blank_line line) then begin
         (match evaluate line with
          | v -> Buffer.add_string out (Int64.to_string v)
          | exception Error -> Buffer.add_string out "error");
         Buffer.add_char out '\n';
         if Buffer.length out >= 65536 then flush_out ()
       end
     done
   with End_of_file -> ());
  flush_out ();
  exit 0
