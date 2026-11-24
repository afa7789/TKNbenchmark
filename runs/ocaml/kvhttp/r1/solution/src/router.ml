type route = Health | Key_list | Key of string | Invalid_key | Unknown

let kv_prefix = "/kv/"

let route_of_target = function
  | "/health" -> Health
  | "/kv" -> Key_list
  | target when String.starts_with ~prefix:kv_prefix target ->
      let p = String.length kv_prefix in
      let key = String.sub target p (String.length target - p) in
      if Store.is_valid_key key then Key key else Invalid_key
  | _ -> Unknown

let method_not_allowed allowed =
  Http.response 405 ~headers:[ ("Allow", String.concat ", " allowed) ]

let text body =
  Http.response 200 ~body ~headers:[ ("Content-Type", "text/plain; charset=utf-8") ]

(* Keys are restricted to [A-Za-z0-9_-], so they never need JSON escaping. *)
let json_string_array items =
  let b = Buffer.create 256 in
  Buffer.add_char b '[';
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_char b ',';
      Buffer.add_char b '"';
      Buffer.add_string b s;
      Buffer.add_char b '"')
    items;
  Buffer.add_char b ']';
  Buffer.contents b

let handle store (req : Http.request) =
  match (route_of_target req.target, req.meth) with
  | Health, "GET" -> text "ok"
  | Health, _ -> method_not_allowed [ "GET" ]
  | Key_list, "GET" ->
      Http.response 200
        ~body:(json_string_array (Store.keys store))
        ~headers:[ ("Content-Type", "application/json") ]
  | Key_list, _ -> method_not_allowed [ "GET" ]
  | Key key, "GET" -> (
      match Store.get store key with
      | Some value ->
          Http.response 200 ~body:value
            ~headers:[ ("Content-Type", "application/octet-stream") ]
      | None -> Http.response 404)
  | Key key, "PUT" -> (
      match Store.put store key req.body with
      | `Created -> Http.response 201
      | `Replaced -> Http.response 200)
  | Key key, "DELETE" ->
      if Store.delete store key then Http.response 204 else Http.response 404
  | Key _, _ -> method_not_allowed [ "GET"; "PUT"; "DELETE" ]
  | Invalid_key, _ -> Http.response 400
  | Unknown, _ -> Http.response 404
