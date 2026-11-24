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

exception Error of int

let max_line = 8192
let max_headers = 100

(* Buffered reader over a socket. *)
module Reader = struct
  type t = { fd : Unix.file_descr; buf : Bytes.t; mutable pos : int; mutable len : int }

  let create fd = { fd; buf = Bytes.create 65536; pos = 0; len = 0 }

  let rec fill r =
    match Unix.read r.fd r.buf 0 (Bytes.length r.buf) with
    | n ->
        r.pos <- 0;
        r.len <- n;
        n
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> fill r

  let index_in r c =
    let rec go i = if i >= r.len then None else if Bytes.get r.buf i = c then Some i else go (i + 1) in
    go r.pos

  (* Reads a line terminated by LF (optional preceding CR is stripped).
     Returns [None] on EOF before any byte was read. *)
  let read_line r =
    let line = Buffer.create 128 in
    let rec loop () =
      if r.pos >= r.len && fill r = 0 then
        if Buffer.length line = 0 then None else raise (Error 400)
      else
        match index_in r '\n' with
        | Some i ->
            Buffer.add_subbytes line r.buf r.pos (i - r.pos);
            r.pos <- i + 1;
            let n = Buffer.length line in
            if n > max_line then raise (Error 431);
            if n > 0 && Buffer.nth line (n - 1) = '\r' then
              Some (Buffer.sub line 0 (n - 1))
            else Some (Buffer.contents line)
        | _ ->
            Buffer.add_subbytes line r.buf r.pos (r.len - r.pos);
            r.pos <- r.len;
            if Buffer.length line > max_line then raise (Error 431);
            loop ()
    in
    loop ()

  let read_exact r n =
    let out = Bytes.create n in
    let rec loop off =
      if off < n then begin
        if r.pos >= r.len && fill r = 0 then raise (Error 400);
        let k = min (n - off) (r.len - r.pos) in
        Bytes.blit r.buf r.pos out off k;
        r.pos <- r.pos + k;
        loop (off + k)
      end
    in
    loop 0;
    Bytes.unsafe_to_string out
end

let parse_request_line line =
  match String.split_on_char ' ' line with
  | [ meth; target; version ]
    when meth <> "" && target <> ""
         && String.length version >= 5
         && String.sub version 0 5 = "HTTP/" ->
      (meth, target)
  | _ -> raise (Error 400)

let parse_header line =
  match String.index_opt line ':' with
  | None | Some 0 -> raise (Error 400)
  | Some i ->
      let name = String.lowercase_ascii (String.sub line 0 i) in
      let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
      (name, value)

let parse_content_length s =
  if s = "" || String.length s > 18 || not (String.for_all (fun c -> c >= '0' && c <= '9') s)
  then raise (Error 400)
  else int_of_string s

let content_length headers =
  match List.filter_map (fun (k, v) -> if k = "content-length" then Some v else None) headers with
  | [] -> 0
  | v :: rest ->
      let n = parse_content_length v in
      if List.exists (fun v' -> parse_content_length v' <> n) rest then raise (Error 400);
      n

let read_request ~max_body fd =
  let r = Reader.create fd in
  (* Tolerate stray empty lines before the request line (RFC 9112 §2.2). *)
  let rec request_line () =
    match Reader.read_line r with
    | None -> None
    | Some "" -> request_line ()
    | Some l -> Some l
  in
  match request_line () with
  | None -> None
  | Some line ->
      let meth, target = parse_request_line line in
      let rec headers acc count =
        match Reader.read_line r with
        | None -> raise (Error 400)
        | Some "" -> List.rev acc
        | Some _ when count >= max_headers -> raise (Error 431)
        | Some l -> headers (parse_header l :: acc) (count + 1)
      in
      let headers = headers [] 0 in
      (match List.assoc_opt "transfer-encoding" headers with
       | Some te when String.lowercase_ascii te <> "identity" -> raise (Error 501)
       | _ -> ());
      let len = content_length headers in
      if len > max_body then raise (Error 413);
      let body = Reader.read_exact r len in
      Some { meth; path = target; headers; body }

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

let respond ?(headers = []) ?(body = "") status = { status; headers; body }

let rec write_all fd s off len =
  if len > 0 then
    match Unix.write_substring fd s off len with
    | n -> write_all fd s (off + n) (len - n)
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> write_all fd s off len

let write_response fd { status; headers; body } =
  let b = Buffer.create 256 in
  Printf.bprintf b "HTTP/1.1 %d %s\r\n" status (reason status);
  List.iter (fun (k, v) -> Printf.bprintf b "%s: %s\r\n" k v) headers;
  (* 204 must not carry a body or Content-Length framing for one. *)
  if status <> 204 then Printf.bprintf b "Content-Length: %d\r\n" (String.length body);
  Buffer.add_string b "Connection: close\r\n\r\n";
  let head = Buffer.contents b in
  write_all fd head 0 (String.length head);
  write_all fd body 0 (String.length body)
