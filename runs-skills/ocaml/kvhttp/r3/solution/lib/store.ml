type t = { lock : Mutex.t; table : (string, string) Hashtbl.t }

let create () = { lock = Mutex.create (); table = Hashtbl.create 1024 }
let with_lock t f = Mutex.protect t.lock f
let get t k = with_lock t (fun () -> Hashtbl.find_opt t.table k)

let put t k v =
  with_lock t (fun () ->
      let existed = Hashtbl.mem t.table k in
      Hashtbl.replace t.table k v;
      if existed then `Replaced else `Created)

let delete t k =
  with_lock t (fun () -> Option.is_some (Hashtbl.find_and_remove t.table k))

let keys t =
  let ks = with_lock t (fun () -> Hashtbl.fold (fun k _ acc -> k :: acc) t.table []) in
  List.sort String.compare ks
