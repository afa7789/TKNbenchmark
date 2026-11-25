type request = {
  meth : string;
  path : string;
  headers : (string * string) list;
  body : string;
}

type response = { status : int; headers : (string * string) list; body : string }

let response ?(headers = []) ?(body = "") status = { status; headers; body }

type error = Bad_request | Payload_too_large | Not_implemented | Closed

exception Read_error of error

let max_line = 8192
let max_headers = 100

(* Reads a CRLF- or LF-terminated line without the terminator, bounded by
   [max_line]. [None] on EOF before any byte. *)
let read_line ic =
  let buf = Buffer.create 128 in
  let rec loop () =
    match In_channel.input_char ic with
    | None -> if Buffer.length buf = 0 then None else raise (Read_error Bad_request)
    | Some '\n' ->
        let len = Buffer.length buf in
        let len = if len > 0 && Buffer.nth buf (len - 1) = '\r' then len - 1 else len in
        Some (Buffer.sub buf 0 len)
    | Some c ->
        if Buffer.length buf >= max_line then raise (Read_error Bad_request);
        Buffer.add_char buf c;
        loop ()
  in
  loop ()

let parse_request_line line =
  match String.split_on_char ' ' line with
  | [ meth; target; version ]
    when meth <> "" && target <> "" && String.starts_with ~prefix:"HTTP/1." version ->
      (meth, target)
  | _ -> raise (Read_error Bad_request)

let parse_header line =
  match String.index_opt line ':' with
  | None | Some 0 -> raise (Read_error Bad_request)
  | Some i ->
      let name = String.lowercase_ascii (String.sub line 0 i) in
      let value = String.trim (String.sub line (i + 1) (String.length line - i - 1)) in
      (name, value)

let rec read_headers ic acc n =
  if n > max_headers then raise (Read_error Bad_request);
  match read_line ic with
  | None -> raise (Read_error Bad_request)
  | Some "" -> List.rev acc
  | Some line -> read_headers ic (parse_header line :: acc) (n + 1)

let content_length headers =
  match List.filter_map (fun (k, v) -> if k = "content-length" then Some v else None) headers with
  | [] -> 0
  | v :: rest ->
      if not (List.for_all (String.equal v) rest) then raise (Read_error Bad_request);
      let is_digits = v <> "" && String.for_all Char.Ascii.is_digit v in
      (match if is_digits then int_of_string_opt v else None with
       | Some n -> n
       | None -> raise (Read_error Bad_request))

let drain ic n =
  let chunk = Bytes.create 65536 in
  let rec loop n =
    if n > 0 then
      match In_channel.input ic chunk 0 (min n (Bytes.length chunk)) with
      | 0 -> ()
      | got -> loop (n - got)
  in
  loop n

let read_request ~max_body ic =
  try
    match read_line ic with
    | None -> Error Closed
    | Some line ->
        let meth, path = parse_request_line line in
        let headers = read_headers ic [] 0 in
        if List.mem_assoc "transfer-encoding" headers then raise (Read_error Not_implemented);
        let len = content_length headers in
        if len > max_body then begin
          drain ic len;
          raise (Read_error Payload_too_large)
        end;
        let body =
          match In_channel.really_input_string ic len with
          | Some b -> b
          | None -> raise (Read_error Bad_request)
        in
        Ok { meth; path; headers; body }
  with Read_error e -> Error e

let error_response = function
  | Bad_request -> Some (response 400)
  | Payload_too_large -> Some (response 413)
  | Not_implemented -> Some (response 501)
  | Closed -> None

let reason = function
  | 200 -> "OK"
  | 201 -> "Created"
  | 204 -> "No Content"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 413 -> "Content Too Large"
  | 500 -> "Internal Server Error"
  | 501 -> "Not Implemented"
  | _ -> "Unknown"

let write_response oc { status; headers; body } =
  let buf = Buffer.create (128 + String.length body) in
  Printf.bprintf buf "HTTP/1.1 %d %s\r\n" status (reason status);
  List.iter (fun (k, v) -> Printf.bprintf buf "%s: %s\r\n" k v) headers;
  (* RFC 9110 forbids Content-Length on 204. *)
  if status <> 204 then Printf.bprintf buf "Content-Length: %d\r\n" (String.length body);
  Buffer.add_string buf "Connection: close\r\n\r\n";
  Buffer.add_string buf body;
  Out_channel.output_string oc (Buffer.contents buf);
  Out_channel.flush oc
