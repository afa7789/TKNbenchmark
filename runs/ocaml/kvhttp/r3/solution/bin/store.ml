(* Thread-safe in-memory key/value store. Keys are kept in an ordered map so
   listing them sorted is a plain traversal. *)

module Smap = Map.Make (String)

type t = { lock : Mutex.t; mutable data : string Smap.t }

let create () = { lock = Mutex.create (); data = Smap.empty }

let with_lock t f = Mutex.protect t.lock f

let get t key = with_lock t (fun () -> Smap.find_opt key t.data)

(** Stores [value] under [key]; returns [true] if the key was not present. *)
let put t key value =
  with_lock t (fun () ->
      let is_new = not (Smap.mem key t.data) in
      t.data <- Smap.add key value t.data;
      is_new)

(** Removes [key]; returns [true] if it was present. *)
let delete t key =
  with_lock t (fun () ->
      if Smap.mem key t.data then (
        t.data <- Smap.remove key t.data;
        true)
      else false)

(** All keys in ascending order. *)
let keys t =
  let data = with_lock t (fun () -> t.data) in
  Smap.fold (fun k _ acc -> k :: acc) data [] |> List.rev
