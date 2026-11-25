let max_value_size = 1 lsl 20

let is_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let is_valid_key k =
  let n = String.length k in
  n >= 1 && n <= 64 && String.for_all is_key_char k

let method_not_allowed allowed =
  Http.response ~headers:[ ("Allow", String.concat ", " allowed) ] 405

let keys_json keys =
  (* Valid keys never need JSON escaping. *)
  let buf = Buffer.create 256 in
  Buffer.add_char buf '[';
  List.iteri
    (fun i k ->
      if i > 0 then Buffer.add_char buf ',';
      Buffer.add_char buf '"';
      Buffer.add_string buf k;
      Buffer.add_char buf '"')
    keys;
  Buffer.add_char buf ']';
  Buffer.contents buf

let handle_key store (req : Http.request) key =
  match req.meth with
  | "GET" -> (
      match Store.get store key with
      | Some body ->
          Http.response ~headers:[ ("Content-Type", "application/octet-stream") ] ~body 200
      | None -> Http.response 404)
  | "PUT" ->
      if String.length req.body > max_value_size then Http.response 413
      else (
        match Store.put store key req.body with
        | `Created -> Http.response 201
        | `Replaced -> Http.response 200)
  | "DELETE" -> if Store.delete store key then Http.response 204 else Http.response 404
  | _ -> method_not_allowed [ "GET"; "PUT"; "DELETE" ]

let handle store (req : Http.request) =
  match req.path with
  | "/health" -> (
      match req.meth with
      | "GET" -> Http.response ~headers:[ ("Content-Type", "text/plain") ] ~body:"ok" 200
      | _ -> method_not_allowed [ "GET" ])
  | "/kv" -> (
      match req.meth with
      | "GET" ->
          Http.response
            ~headers:[ ("Content-Type", "application/json") ]
            ~body:(keys_json (Store.keys store))
            200
      | _ -> method_not_allowed [ "GET" ])
  | path -> (
      match String.cut_first 4 path with
      | "/kv/", key ->
          if is_valid_key key then handle_key store req key else Http.response 400
      | _ -> Http.response 404)
