(* Maps requests onto store operations. Pure apart from the store. *)

let is_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let valid_key k =
  let n = String.length k in
  n >= 1 && n <= 64 && String.for_all is_key_char k

let respond ?content_type ?(body = "") status : Http.response =
  { status; content_type; body }

let json_string_array items =
  (* Keys are restricted to [A-Za-z0-9_-], so no escaping is required. *)
  let b = Buffer.create 256 in
  Buffer.add_char b '[';
  List.iteri
    (fun i k ->
      if i > 0 then Buffer.add_char b ',';
      Buffer.add_char b '"';
      Buffer.add_string b k;
      Buffer.add_char b '"')
    items;
  Buffer.add_char b ']';
  Buffer.contents b

let kv_prefix = "/kv/"

let handle store ({ meth; path; body; _ } : Http.request) : Http.response =
  match path with
  | "/health" -> (
      match meth with "GET" -> respond 200 ~body:"ok" | _ -> respond 405)
  | "/kv" -> (
      match meth with
      | "GET" ->
          respond 200 ~content_type:"application/json"
            ~body:(json_string_array (Store.keys store))
      | _ -> respond 405)
  | _ when String.starts_with ~prefix:kv_prefix path -> (
      let plen = String.length kv_prefix in
      let key = String.sub path plen (String.length path - plen) in
      if not (valid_key key) then respond 400
      else
        match meth with
        | "GET" -> (
            match Store.get store key with
            | Some v -> respond 200 ~body:v
            | None -> respond 404)
        | "PUT" -> respond (if Store.put store key body then 201 else 200)
        | "DELETE" -> respond (if Store.delete store key then 204 else 404)
        | _ -> respond 405)
  | _ -> respond 404
