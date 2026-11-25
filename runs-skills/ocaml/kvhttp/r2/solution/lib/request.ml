type t = {
  meth : string;
  path : string;
  headers : (string * string) list;
  body : string;
}

type error = [ `Eof | `Bad_request | `Header_too_large | `Body_too_large ]

let max_line = 8192
let max_header_lines = 100

(* Upper bound on an oversized body we are willing to drain before replying. *)
let max_drain = 16 * 1024 * 1024

exception Line_too_long

(* Reads a line terminated by LF (an optional preceding CR is stripped).
   Returns [None] on EOF before any byte. *)
let input_line_bounded ic =
  let b = Buffer.create 128 in
  let rec loop () =
    match In_channel.input_char ic with
    | None -> if Buffer.length b = 0 then None else Some (Buffer.contents b)
    | Some '\n' ->
        let n = Buffer.length b in
        if n > 0 && Char.equal (Buffer.nth b (n - 1)) '\r' then
          Buffer.truncate b (n - 1);
        Some (Buffer.contents b)
    | Some c ->
        if Buffer.length b >= max_line then raise Line_too_long;
        Buffer.add_char b c;
        loop ()
  in
  loop ()

let parse_request_line line =
  match String.split_on_char ' ' line with
  | [ meth; target; version ]
    when meth <> "" && target <> "" && String.starts_with ~prefix:"HTTP/" version
    ->
      let path =
        match String.index_opt target '?' with
        | Some i -> String.sub target 0 i
        | None -> target
      in
      Ok (meth, path)
  | _ -> Error `Bad_request

let parse_header line =
  match String.index_opt line ':' with
  | Some i when i > 0 ->
      let name = String.lowercase_ascii (String.sub line 0 i) in
      let value =
        String.trim (String.sub line (i + 1) (String.length line - i - 1))
      in
      Ok (name, value)
  | Some _ | None -> Error `Bad_request

let rec read_headers ic acc count =
  if count > max_header_lines then Error `Header_too_large
  else
    match input_line_bounded ic with
    | None -> Error `Bad_request
    | Some "" -> Ok (List.rev acc)
    | Some line -> (
        match parse_header line with
        | Ok h -> read_headers ic (h :: acc) (count + 1)
        | Error _ as e -> e)

let content_length headers =
  match List.filter (fun (k, _) -> String.equal k "content-length") headers with
  | [] -> Ok 0
  | (_, v) :: rest -> (
      let all_same = List.for_all (fun (_, v') -> String.equal v v') rest in
      let digits = v <> "" && String.for_all Char.Ascii.is_digit v in
      match int_of_string_opt v with
      | Some n when all_same && digits && n >= 0 -> Ok n
      | Some _ | None -> Error `Bad_request)

let rec drain ic n =
  if n > 0 then begin
    let chunk = min n 65536 in
    let s = really_input_string ic chunk in
    ignore s;
    drain ic (n - chunk)
  end

let read_body ic ~max_body headers =
  if List.exists (fun (k, _) -> String.equal k "transfer-encoding") headers
  then Error `Bad_request
  else
    match content_length headers with
    | Error _ as e -> e
    | Ok n when n > max_body ->
        if n <= max_drain then drain ic n;
        Error `Body_too_large
    | Ok n -> Ok (really_input_string ic n)

let read ~max_body ic : (t, error) result =
  let ( let* ) = Result.bind in
  try
    match input_line_bounded ic with
    | None -> Error `Eof
    | Some line ->
        let* meth, path = parse_request_line line in
        let* headers = read_headers ic [] 0 in
        let* body = read_body ic ~max_body headers in
        Ok { meth; path; headers; body }
  with
  | Line_too_long -> Error `Header_too_large
  | End_of_file -> Error `Bad_request
