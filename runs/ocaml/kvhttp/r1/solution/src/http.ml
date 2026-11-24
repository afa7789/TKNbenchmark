type request = {
  meth : string;
  target : string;
  version : string;
  headers : (string * string) list;
  body : string;
}

type response = { status : int; headers : (string * string) list; body : string }
type read_error = [ `Eof | `Status of int ]

let response ?(headers = []) ?(body = "") status = { status; headers; body }

let header (req : request) name =
  List.assoc_opt (String.lowercase_ascii name) req.headers

let connection_tokens req =
  match header req "connection" with
  | None -> []
  | Some v ->
      String.split_on_char ',' v
      |> List.map (fun s -> String.trim s |> String.lowercase_ascii)

let wants_keep_alive req =
  let tokens = connection_tokens req in
  if List.mem "close" tokens then false
  else if req.version = "HTTP/1.0" then List.mem "keep-alive" tokens
  else true

(* ---------- reading ---------- *)

module Reader = struct
  type t = { fd : Unix.file_descr; buf : Bytes.t; mutable pos : int; mutable len : int }

  let create fd = { fd; buf = Bytes.create 65536; pos = 0; len = 0 }

  (* Returns [false] on end of stream. Read timeouts count as end of stream. *)
  let rec refill t =
    match Unix.read t.fd t.buf 0 (Bytes.length t.buf) with
    | n ->
        t.pos <- 0;
        t.len <- n;
        n > 0
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> refill t
    | exception
        Unix.Unix_error
          ((Unix.EAGAIN | Unix.EWOULDBLOCK | Unix.ECONNRESET | Unix.ETIMEDOUT), _, _) ->
        false

  let available t = t.len - t.pos
end

exception Fail of read_error

let fail e = raise (Fail e)

(* Read a line terminated by LF (an optional preceding CR is stripped).
   [budget] bounds the bytes consumed; exceeding it fails with [too_long]. *)
let read_line (r : Reader.t) ~budget ~too_long =
  let line = Buffer.create 128 in
  let rec loop budget =
    if Reader.available r = 0 && not (Reader.refill r) then fail `Eof;
    let stop = r.pos + min (Reader.available r) budget in
    match Bytes.index_from_opt r.buf r.pos '\n' with
    | Some i when i < stop ->
        Buffer.add_subbytes line r.buf r.pos (i - r.pos);
        let used = i + 1 - r.pos in
        r.pos <- i + 1;
        (budget - used)
    | _ ->
        let n = stop - r.pos in
        Buffer.add_subbytes line r.buf r.pos n;
        r.pos <- stop;
        if budget - n <= 0 then fail (`Status too_long);
        loop (budget - n)
  in
  let budget = loop budget in
  let s = Buffer.contents line in
  let n = String.length s in
  let s = if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s in
  (s, budget)

let read_exact (r : Reader.t) n =
  let out = Bytes.create n in
  let rec loop off =
    if off < n then begin
      if Reader.available r = 0 && not (Reader.refill r) then fail `Eof;
      let k = min (Reader.available r) (n - off) in
      Bytes.blit r.buf r.pos out off k;
      r.pos <- r.pos + k;
      loop (off + k)
    end
  in
  loop 0;
  Bytes.unsafe_to_string out

let skip (r : Reader.t) n =
  let rec loop left =
    if left > 0 then begin
      if Reader.available r = 0 && not (Reader.refill r) then fail `Eof;
      let k = min (Reader.available r) left in
      r.pos <- r.pos + k;
      loop (left - k)
    end
  in
  loop n

let max_head_bytes = 64 * 1024
let max_headers = 128

(* Oversized bodies up to this size are read and discarded so that the client,
   which is usually still sending, does not get a reset instead of our reply. *)
let max_drain_bytes = 64 * 1024 * 1024

let is_token_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9'
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`' | '|' | '~' ->
      true
  | _ -> false

let is_token s = s <> "" && String.for_all is_token_char s

let parse_request_line line =
  match String.split_on_char ' ' line with
  | [ meth; target; version ]
    when is_token meth && target <> ""
         && (version = "HTTP/1.1" || version = "HTTP/1.0") ->
      (meth, target, version)
  | [ _; _; version ] when String.starts_with ~prefix:"HTTP/" version -> fail (`Status 505)
  | _ -> fail (`Status 400)

let parse_header_line line =
  match String.index_opt line ':' with
  | None -> fail (`Status 400)
  | Some i ->
      let name = String.sub line 0 i in
      if not (is_token name) then fail (`Status 400);
      let value = String.sub line (i + 1) (String.length line - i - 1) |> String.trim in
      (String.lowercase_ascii name, value)

let parse_content_length headers =
  let values =
    List.filter_map (fun (n, v) -> if n = "content-length" then Some v else None) headers
  in
  match List.sort_uniq String.compare values with
  | [] -> 0
  | [ v ] when v <> "" && String.length v <= 18 && String.for_all (function '0' .. '9' -> true | _ -> false) v ->
      int_of_string v
  | _ -> fail (`Status 400)

let read_head r =
  (* Tolerate stray empty lines before the request line (RFC 9112 §2.2). *)
  let rec request_line budget =
    let line, budget = read_line r ~budget ~too_long:414 in
    if line = "" then request_line budget else (line, budget)
  in
  let line, budget = request_line max_head_bytes in
  let meth, target, version = parse_request_line line in
  let rec headers acc count budget =
    let line, budget = read_line r ~budget ~too_long:431 in
    if line = "" then List.rev acc
    else if count >= max_headers then fail (`Status 431)
    else headers (parse_header_line line :: acc) (count + 1) budget
  in
  (meth, target, version, headers [] 0 budget)

let read_request ?(on_continue = ignore) ~max_body r =
  match
    let meth, target, version, headers = read_head r in
    let req = { meth; target; version; headers; body = "" } in
    if header req "transfer-encoding" <> None then fail (`Status 501);
    let length = parse_content_length headers in
    if length > max_body then begin
      if length <= max_drain_bytes then skip r length;
      fail (`Status 413)
    end;
    let expects_continue =
      match header req "expect" with
      | Some v -> String.lowercase_ascii v = "100-continue"
      | None -> false
    in
    if expects_continue && length > 0 then on_continue ();
    { req with body = (if length = 0 then "" else read_exact r length) }
  with
  | req -> Ok req
  | exception Fail e -> Error e

(* ---------- writing ---------- *)

let reason = function
  | 100 -> "Continue"
  | 200 -> "OK"
  | 201 -> "Created"
  | 204 -> "No Content"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 408 -> "Request Timeout"
  | 413 -> "Content Too Large"
  | 414 -> "URI Too Long"
  | 431 -> "Request Header Fields Too Large"
  | 500 -> "Internal Server Error"
  | 501 -> "Not Implemented"
  | 505 -> "HTTP Version Not Supported"
  | _ -> "Unknown"

let rec write_all fd s off len =
  if len > 0 then
    match Unix.write_substring fd s off len with
    | n -> write_all fd s (off + n) (len - n)
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> write_all fd s off len

let write_string fd s = write_all fd s 0 (String.length s)

let write_response fd ~close resp =
  let b = Buffer.create (256 + String.length resp.body) in
  Printf.bprintf b "HTTP/1.1 %d %s\r\n" resp.status (reason resp.status);
  List.iter (fun (n, v) -> Printf.bprintf b "%s: %s\r\n" n v) resp.headers;
  let bodyless = resp.status = 204 || resp.status = 304 in
  if not bodyless then Printf.bprintf b "Content-Length: %d\r\n" (String.length resp.body);
  if close then Buffer.add_string b "Connection: close\r\n";
  Buffer.add_string b "\r\n";
  if not bodyless then Buffer.add_string b resp.body;
  write_string fd (Buffer.contents b)

let write_continue fd = write_string fd "HTTP/1.1 100 Continue\r\n\r\n"
