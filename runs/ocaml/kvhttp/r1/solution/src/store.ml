type t = { lock : Mutex.t; table : (string, string) Hashtbl.t }

let create () = { lock = Mutex.create (); table = Hashtbl.create 1024 }
let max_key_length = 64
let max_value_size = 1 lsl 20

let is_key_char = function
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '-' -> true
  | _ -> false

let is_valid_key k =
  let n = String.length k in
  n >= 1 && n <= max_key_length && String.for_all is_key_char k

let locked t f = Mutex.protect t.lock f

let put t key value =
  locked t (fun () ->
      let existed = Hashtbl.mem t.table key in
      Hashtbl.replace t.table key value;
      if existed then `Replaced else `Created)

let get t key = locked t (fun () -> Hashtbl.find_opt t.table key)

let delete t key =
  locked t (fun () ->
      if Hashtbl.mem t.table key then (
        Hashtbl.remove t.table key;
        true)
      else false)

let keys t =
  let ks = locked t (fun () -> Hashtbl.fold (fun k _ acc -> k :: acc) t.table []) in
  List.sort String.compare ks
