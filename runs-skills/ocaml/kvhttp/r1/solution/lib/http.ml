type request = {
  meth : string;
  path : string;
  headers : (string * string) list;
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

type read_error =
  | Closed
  | Bad_request of string
  | Header_too_large
  | Payload_too_large
  | Not_implemented of string

let response ?(headers = []) ?(body = "") status = { status; headers; body }

let error_response = function
  | Closed -> None
  | Bad_request _ -> Some (response 400)
  | Header_too_large -> Some (response 431)
  | Payload_too_large -> Some (response 413)
  | Not_implemented _ -> Some (response 501)

let reason = function
  | 200 -> "OK"
  | 201 -> "Created"
  | 204 -> "No Content"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 413 -> "Content Too Large"
  | 431 -> "Request Header Fields Too Large"
  | 500 -> "Internal Server Error"
  | 501 -> "Not Implemented"
  | _ -> "Unknown"

(* ---------- parsing ---------- *)

let is_tchar = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' -> true
  | '!' | '#' | '$' | '%' | '&' | '\'' | '*' | '+' | '-' | '.' | '^' | '_' | '`'
  | '|' | '~' ->
      true
  | _ -> false

let is_token s = (not (String.is_empty s)) && String.for_all is_tchar s

let strip_cr line =
  if String.ends_with ~suffix:"\r" line then String.take_first (String.length line - 1) line
  else line

let parse_request_line line =
  match String.split_on_char ' ' line with
  | [ meth; target; version ]
    when is_token meth && (not (String.is_empty target))
         && String.starts_with ~prefix:"HTTP/1." version ->
      Ok (meth, target)
  | _ -> Error (Bad_request "malformed request line")

let parse_header line =
  match String.split_first ~sep:":" line with
  | Some (name, value) when is_token name ->
      Ok (String.lowercase_ascii name, String.trim value)
  | Some _ | None -> Error (Bad_request "malformed header")

let parse_head head =
  let open Result.Syntax in
  match List.map strip_cr (String.split_on_char '\n' head) with
  | [] -> Error (Bad_request "empty request")
  | request_line :: header_lines ->
      let* meth, target = parse_request_line request_line in
      let rec headers acc = function
        | [] -> Ok (List.rev acc)
        | line :: rest ->
            let* h = parse_header line in
            headers (h :: acc) rest
      in
      let+ hs = headers [] header_lines in
      (meth, target, hs)

let content_length ~max_body headers =
  match
    List.filter_map
      (fun (n, v) -> if String.equal n "content-length" then Some v else None)
      headers
  with
  | [] -> Ok 0
  | v :: rest ->
      if not (List.for_all (String.equal v) rest) then
        Error (Bad_request "conflicting Content-Length")
      else if String.is_empty v || not (String.for_all Char.Ascii.is_digit v) then
        Error (Bad_request "invalid Content-Length")
      else if String.length v > 18 then Error Payload_too_large
      else
        let n = int_of_string v in
        if n > max_body then Error Payload_too_large else Ok n

(* ---------- socket IO ---------- *)

let rec recv fd buf off len =
  match Unix.recv fd buf off len [] with
  | n -> n
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> recv fd buf off len

(* Index just past the blank line ending the head, searching from [from], and
   the index where the head text itself ends. Accepts CRLF and bare LF. *)
let find_head_end buf ~from =
  let len = Buffer.length buf in
  let rec go i =
    if i >= len then None
    else if Char.equal (Buffer.nth buf i) '\n' then
      if i + 1 < len && Char.equal (Buffer.nth buf (i + 1)) '\n' then Some (i, i + 2)
      else if
        i + 2 < len
        && Char.equal (Buffer.nth buf (i + 1)) '\r'
        && Char.equal (Buffer.nth buf (i + 2)) '\n'
      then Some (i, i + 3)
      else go (i + 1)
    else go (i + 1)
  in
  go from

let read_head fd ~max_head =
  let buf = Buffer.create 1024 in
  let chunk = Bytes.create 16384 in
  let rec loop scanned =
    match find_head_end buf ~from:scanned with
    | Some (head_end, body_start) ->
        let all = Buffer.contents buf in
        let head = strip_cr (String.sub all 0 head_end) in
        let rest = String.sub all body_start (String.length all - body_start) in
        Ok (head, rest)
    | None ->
        let scanned = max 0 (Buffer.length buf - 2) in
        if Buffer.length buf > max_head then Error Header_too_large
        else
          let n = recv fd chunk 0 (Bytes.length chunk) in
          if n = 0 then Error Closed
          else (
            Buffer.add_subbytes buf chunk 0 n;
            loop scanned)
  in
  loop 0

let read_body fd ~length ~prefix =
  let have = min length (String.length prefix) in
  let body = Bytes.create length in
  Bytes.blit_string prefix 0 body 0 have;
  let rec fill off =
    if off >= length then Ok (Bytes.unsafe_to_string body)
    else
      let n = recv fd body off (length - off) in
      if n = 0 then Error (Bad_request "truncated body") else fill (off + n)
  in
  fill have

let read_request fd ~max_head ~max_body =
  let open Result.Syntax in
  let* head, rest = read_head fd ~max_head in
  let* meth, path, headers = parse_head head in
  if List.mem_assoc "transfer-encoding" headers then
    Error (Not_implemented "Transfer-Encoding")
  else
    let* length = content_length ~max_body headers in
    let+ body = read_body fd ~length ~prefix:rest in
    { meth; path; headers; body }

let write_response fd { status; headers; body } =
  let head = Buffer.create 256 in
  Printf.bprintf head "HTTP/1.1 %d %s\r\n" status (reason status);
  List.iter (fun (n, v) -> Printf.bprintf head "%s: %s\r\n" n v) headers;
  Printf.bprintf head "Content-Length: %d\r\nConnection: close\r\n\r\n"
    (String.length body);
  if String.length body <= 65536 then (
    Buffer.add_string head body;
    ignore (Unix.write_substring fd (Buffer.contents head) 0 (Buffer.length head) : int))
  else (
    ignore (Unix.write_substring fd (Buffer.contents head) 0 (Buffer.length head) : int);
    ignore (Unix.write_substring fd body 0 (String.length body) : int))
