(* Maps requests onto store operations. *)

let max_value = 1 lsl 20

let is_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let valid_key k =
  let n = String.length k in
  n >= 1 && n <= 64 && String.for_all is_key_char k

let json_string_array items =
  (* Keys are restricted to [A-Za-z0-9_-], so no escaping is required. *)
  "[" ^ String.concat "," (List.map (fun s -> "\"" ^ s ^ "\"") items) ^ "]"

let method_not_allowed allow = Http.respond ~headers:[ ("Allow", allow) ] 405

let kv_prefix = "/kv/"

let handle store (req : Http.request) : Http.response =
  let path = req.path in
  match path with
  | "/health" -> (
      match req.meth with
      | "GET" -> Http.respond ~headers:[ ("Content-Type", "text/plain") ] ~body:"ok" 200
      | _ -> method_not_allowed "GET")
  | "/kv" -> (
      match req.meth with
      | "GET" ->
          Http.respond
            ~headers:[ ("Content-Type", "application/json") ]
            ~body:(json_string_array (Store.sorted_keys store))
            200
      | _ -> method_not_allowed "GET")
  | _ when String.starts_with ~prefix:kv_prefix path -> (
      let plen = String.length kv_prefix in
      let key = String.sub path plen (String.length path - plen) in
      if not (valid_key key) then Http.respond 400
      else
        match req.meth with
        | "GET" -> (
            match Store.find store key with
            | Some v ->
                Http.respond ~headers:[ ("Content-Type", "application/octet-stream") ] ~body:v 200
            | None -> Http.respond 404)
        | "PUT" -> (
            match Store.put store key req.body with
            | `Created -> Http.respond 201
            | `Replaced -> Http.respond 200)
        | "DELETE" -> if Store.delete store key then Http.respond 204 else Http.respond 404
        | _ -> method_not_allowed "GET, PUT, DELETE")
  | _ -> Http.respond 404
