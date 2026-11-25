type t = { lock : Mutex.t; table : (string, string) Hashtbl.t }

let create () = { lock = Mutex.create (); table = Hashtbl.create 1024 }
let with_lock t f = Mutex.protect t.lock f

let put t key value =
  with_lock t (fun () ->
      match Hashtbl.find_and_replace t.table key value with
      | None -> `Created
      | Some _ -> `Replaced)

let get t key = with_lock t (fun () -> Hashtbl.find_opt t.table key)

let delete t key =
  with_lock t (fun () -> Option.is_some (Hashtbl.find_and_remove t.table key))

let keys t =
  let ks = with_lock t (fun () -> Hashtbl.fold (fun k _ acc -> k :: acc) t.table []) in
  List.sort String.compare ks
