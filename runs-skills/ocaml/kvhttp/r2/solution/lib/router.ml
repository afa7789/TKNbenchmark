let max_value_size = 1 lsl 20
let max_key_length = 64

let is_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let valid_key k =
  let n = String.length k in
  n >= 1 && n <= max_key_length && String.for_all is_key_char k

let json_string_list keys =
  let b = Buffer.create 256 in
  Buffer.add_char b '[';
  List.iteri
    (fun i k ->
      if i > 0 then Buffer.add_char b ',';
      (* Keys are restricted to [A-Za-z0-9_-], so no escaping is needed. *)
      Buffer.add_char b '"';
      Buffer.add_string b k;
      Buffer.add_char b '"')
    keys;
  Buffer.add_char b ']';
  Buffer.contents b

let method_not_allowed allowed =
  Response.make ~headers:[ ("Allow", String.concat ", " allowed) ] 405

let text body =
  Response.make ~headers:[ ("Content-Type", "text/plain") ] ~body 200

type route = Health | List_keys | Item of string | Bad_key | Unknown

let route_of_path path =
  match path with
  | "/health" -> Health
  | "/kv" -> List_keys
  | _ -> (
      match String.split_first ~sep:"/kv/" path with
      | Some ("", key) -> if valid_key key then Item key else Bad_key
      | Some _ | None -> Unknown)

let handle store ~meth ~path ~body =
  match route_of_path path with
  | Unknown -> Response.make 404
  | Bad_key -> Response.make 400
  | Health -> (
      match meth with "GET" -> text "ok" | _ -> method_not_allowed [ "GET" ])
  | List_keys -> (
      match meth with
      | "GET" ->
          Response.make
            ~headers:[ ("Content-Type", "application/json") ]
            ~body:(json_string_list (Store.keys store))
            200
      | _ -> method_not_allowed [ "GET" ])
  | Item key -> (
      match meth with
      | "GET" -> (
          match Store.get store key with
          | Some v ->
              Response.make
                ~headers:[ ("Content-Type", "application/octet-stream") ]
                ~body:v 200
          | None -> Response.make 404)
      | "PUT" ->
          if String.length body > max_value_size then Response.make 413
          else (
            match Store.put store key body with
            | `Created -> Response.make 201
            | `Replaced -> Response.make 200)
      | "DELETE" ->
          if Store.delete store key then Response.make 204
          else Response.make 404
      | _ -> method_not_allowed [ "GET"; "PUT"; "DELETE" ])
