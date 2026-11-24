(* Thread-safe in-memory key/value store. *)

type t = { lock : Mutex.t; table : (string, string) Hashtbl.t }

let create () = { lock = Mutex.create (); table = Hashtbl.create 1024 }

let find t key = Mutex.protect t.lock (fun () -> Hashtbl.find_opt t.table key)

(* Returns [`Created] when the key was absent, [`Replaced] otherwise. *)
let put t key value =
  Mutex.protect t.lock (fun () ->
      let existed = Hashtbl.mem t.table key in
      Hashtbl.replace t.table key value;
      if existed then `Replaced else `Created)

(* Returns [true] when a binding was removed. *)
let delete t key =
  Mutex.protect t.lock (fun () ->
      if Hashtbl.mem t.table key then (
        Hashtbl.remove t.table key;
        true)
      else false)

let sorted_keys t =
  let keys =
    Mutex.protect t.lock (fun () ->
        Hashtbl.fold (fun k _ acc -> k :: acc) t.table [])
  in
  List.sort String.compare keys
