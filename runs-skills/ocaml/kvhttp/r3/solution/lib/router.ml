let max_value = 1 lsl 20

let is_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let is_valid_key k =
  let n = String.length k in
  n >= 1 && n <= 64 && String.for_all is_key_char k

let json_string_list xs =
  (* Valid keys never need JSON escaping. *)
  "[" ^ String.concat "," (List.map (fun s -> "\"" ^ s ^ "\"") xs) ^ "]"

let method_not_allowed allowed =
  Http.response ~headers:[ ("Allow", String.concat ", " allowed) ] 405

let text body = Http.response ~headers:[ ("Content-Type", "text/plain") ] ~body 200

type route = Health | List_keys | Key of string | Invalid_key | Unknown

let route path =
  match path with
  | "/health" -> Health
  | "/kv" -> List_keys
  | _ -> (
      match String.split_first ~sep:"/kv/" path with
      | Some ("", key) -> if is_valid_key key then Key key else Invalid_key
      | Some _ | None -> Unknown)

let handle store (req : Http.request) =
  match (route req.path, req.meth) with
  | Unknown, _ -> Http.response 404
  | Invalid_key, _ -> Http.response 400
  | Health, "GET" -> text "ok"
  | Health, _ -> method_not_allowed [ "GET" ]
  | List_keys, "GET" ->
      Http.response
        ~headers:[ ("Content-Type", "application/json") ]
        ~body:(json_string_list (Store.keys store))
        200
  | List_keys, _ -> method_not_allowed [ "GET" ]
  | Key k, "GET" -> (
      match Store.get store k with
      | Some v ->
          Http.response ~headers:[ ("Content-Type", "application/octet-stream") ] ~body:v 200
      | None -> Http.response 404)
  | Key k, "PUT" -> (
      match Store.put store k req.body with
      | `Created -> Http.response 201
      | `Replaced -> Http.response 200)
  | Key k, "DELETE" -> Http.response (if Store.delete store k then 204 else 404)
  | Key _, _ -> method_not_allowed [ "GET"; "PUT"; "DELETE" ]
