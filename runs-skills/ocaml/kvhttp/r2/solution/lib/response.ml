type t = { status : int; headers : (string * string) list; body : string }

let make ?(headers = []) ?(body = "") status = { status; headers; body }

let reason = function
  | 200 -> "OK"
  | 201 -> "Created"
  | 204 -> "No Content"
  | 400 -> "Bad Request"
  | 404 -> "Not Found"
  | 405 -> "Method Not Allowed"
  | 408 -> "Request Timeout"
  | 413 -> "Content Too Large"
  | 431 -> "Request Header Fields Too Large"
  | 500 -> "Internal Server Error"
  | 501 -> "Not Implemented"
  | _ -> "Unknown"

let serialize { status; headers; body } =
  let b = Buffer.create (128 + String.length body) in
  Printf.bprintf b "HTTP/1.1 %d %s\r\n" status (reason status);
  List.iter (fun (k, v) -> Printf.bprintf b "%s: %s\r\n" k v) headers;
  (* 204 must not carry a body; Content-Length: 0 is still accepted. *)
  Printf.bprintf b "Content-Length: %d\r\nConnection: close\r\n\r\n"
    (String.length body);
  Buffer.add_string b body;
  Buffer.contents b
