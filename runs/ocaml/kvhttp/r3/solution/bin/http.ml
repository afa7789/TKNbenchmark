(* Minimal HTTP/1.1 request reader and response writer over a Unix socket.
   One request per connection. *)

type request = {
  meth : string;
  path : string;
  headers : (string * string) list;  (** names lower-cased *)
  body : string;
}

type response = {
  status : int;
  content_type : string option;
  body : string;
}

exception Bad_request of int * string
(** Raised while parsing; carries the status to reply with. *)

let max_header_bytes = 64 * 1024
let max_body_bytes = 1024 * 1024

(* ---------- buffered reader ---------- *)

type reader = {
  fd : Unix.file_descr;
  buf : Bytes.t;
  mutable pos : int;
  mutable len : int;
}

let reader fd = { fd; buf = Bytes.create 65536; pos = 0; len = 0 }

let rec fill r =
  match Unix.read r.fd r.buf 0 (Bytes.length r.buf) with
  | 0 -> raise End_of_file
  | n ->
      r.pos <- 0;
      r.len <- n
  | exception Unix.Unix_error (Unix.EINTR, _, _) -> fill r

(* Reads a CRLF- (or LF-) terminated line, without the terminator. [budget]
   counts bytes consumed so far by the header section. *)
let read_line r budget =
  let line = Buffer.create 128 in
  let rec loop () =
    if r.pos >= r.len then fill r;
    match Bytes.index_from_opt r.buf r.pos '\n' with
    | Some i when i < r.len ->
        Buffer.add_subbytes line r.buf r.pos (i - r.pos);
        budget := !budget + (i - r.pos + 1);
        r.pos <- i + 1
    | _ ->
        Buffer.add_subbytes line r.buf r.pos (r.len - r.pos);
        budget := !budget + (r.len - r.pos);
        r.pos <- r.len;
        if !budget > max_header_bytes then
          raise (Bad_request (431, "header section too large"));
        loop ()
  in
  loop ();
  if !budget > max_header_bytes then
    raise (Bad_request (431, "header section too large"));
  let s = Buffer.contents line in
  let n = String.length s in
  if n > 0 && s.[n - 1] = '\r' then String.sub s 0 (n - 1) else s

(* Reads exactly [n] bytes into [dst] at [off]. *)
let read_exact r dst off n =
  let off = ref off and rem = ref n in
  while !rem > 0 do
    if r.pos >= r.len then fill r;
    let k = min !rem (r.len - r.pos) in
    Bytes.blit r.buf r.pos dst !off k;
    r.pos <- r.pos + k;
    off := !off + k;
    rem := !rem - k
  done

(* ---------- parsing ---------- *)

let parse_request_line line =
  match String.split_on_char ' ' line with
  | [ meth; target; version ]
    when meth <> "" && target <> ""
         && String.length version >= 5
         && String.sub version 0 5 = "HTTP/" ->
      (meth, target)
  | _ -> raise (Bad_request (400, "malformed request line"))

let parse_header line =
  match String.index_opt line ':' with
  | Some i when i > 0 ->
      let name = String.lowercase_ascii (String.sub line 0 i) in
      let value = String.sub line (i + 1) (String.length line - i - 1) in
      (name, String.trim value)
  | _ -> raise (Bad_request (400, "malformed header"))

let parse_length s =
  let ok = s <> "" && String.for_all (fun c -> c >= '0' && c <= '9') s in
  match if ok then int_of_string_opt s else None with
  | Some n -> n
  | None -> raise (Bad_request (400, "invalid Content-Length"))

let read_fixed_body r len =
  if len > max_body_bytes then raise (Bad_request (413, "body too large"));
  let b = Bytes.create len in
  read_exact r b 0 len;
  Bytes.unsafe_to_string b

let read_chunked_body r =
  let body = Buffer.create 4096 in
  let budget = ref 0 in
  let rec loop () =
    let line = read_line r budget in
    let size_str =
      match String.index_opt line ';' with
      | Some i -> String.sub line 0 i
      | None -> line
    in
    let size =
      match int_of_string_opt ("0x" ^ String.trim size_str) with
      | Some n when n >= 0 -> n
      | _ -> raise (Bad_request (400, "invalid chunk size"))
    in
    if size = 0 then
      (* Skip trailers up to the terminating empty line. *)
      while read_line r budget <> "" do () done
    else begin
      if Buffer.length body + size > max_body_bytes then
        raise (Bad_request (413, "body too large"));
      let chunk = Bytes.create size in
      read_exact r chunk 0 size;
      Buffer.add_bytes body chunk;
      if read_line r budget <> "" then
        raise (Bad_request (400, "malformed chunk"));
      loop ()
    end
  in
  loop ();
  Buffer.contents body

let read_request fd =
  let r = reader fd in
  let budget = ref 0 in
  (* Tolerate stray empty lines before the request line (RFC 9112 §2.2). *)
  let rec first_line () =
    match read_line r budget with "" -> first_line () | l -> l
  in
  let meth, path = parse_request_line (first_line ()) in
  let rec headers acc =
    match read_line r budget with
    | "" -> List.rev acc
    | line -> headers (parse_header line :: acc)
  in
  let headers = headers [] in
  let chunked =
    match List.assoc_opt "transfer-encoding" headers with
    | Some te ->
        String.lowercase_ascii te
        |> String.split_on_char ','
        |> List.exists (fun s -> String.trim s = "chunked")
    | None -> false
  in
  let body =
    if chunked then read_chunked_body r
    else
      match List.assoc_opt "content-length" headers with
      | Some v -> read_fixed_body r (parse_length v)
      | None -> ""
  in
  { meth; path; headers; body }

(* ---------- writing ---------- *)

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
  | _ -> "Unknown"

let rec write_all fd s off len =
  if len > 0 then
    match Unix.write_substring fd s off len with
    | n -> write_all fd s (off + n) (len - n)
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> write_all fd s off len

let write_response fd { status; content_type; body } =
  let head = Buffer.create 160 in
  Printf.bprintf head "HTTP/1.1 %d %s\r\n" status (reason status);
  Option.iter (Printf.bprintf head "Content-Type: %s\r\n") content_type;
  Printf.bprintf head "Content-Length: %d\r\nConnection: close\r\n\r\n"
    (String.length body);
  if String.length body <= 16384 then begin
    Buffer.add_string head body;
    let s = Buffer.contents head in
    write_all fd s 0 (String.length s)
  end
  else begin
    let s = Buffer.contents head in
    write_all fd s 0 (String.length s);
    write_all fd body 0 (String.length body)
  end
