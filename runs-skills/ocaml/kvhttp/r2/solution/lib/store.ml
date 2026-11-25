type t = { lock : Mutex.t; table : (string, string) Hashtbl.t }

let create () = { lock = Mutex.create (); table = Hashtbl.create 1024 }
let with_lock t f = Mutex.protect t.lock f

let put t k v =
  with_lock t (fun () ->
      match Hashtbl.find_and_replace t.table k v with
      | None -> `Created
      | Some _ -> `Replaced)

let get t k = with_lock t (fun () -> Hashtbl.find_opt t.table k)

let delete t k =
  with_lock t (fun () -> Option.is_some (Hashtbl.find_and_remove t.table k))

let keys t =
  with_lock t (fun () -> Hashtbl.fold (fun k _ acc -> k :: acc) t.table [])
  |> List.sort String.compare
