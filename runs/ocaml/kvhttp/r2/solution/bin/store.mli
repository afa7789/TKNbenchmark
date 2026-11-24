(** Thread-safe in-memory key/value store. *)

type t

val create : unit -> t
val find : t -> string -> string option
val put : t -> string -> string -> [ `Created | `Replaced ]
val delete : t -> string -> bool
val sorted_keys : t -> string list
(** All keys, in ascending byte order. *)
