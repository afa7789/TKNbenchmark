(** Thread-safe in-memory key-value store. *)

type t

val create : unit -> t

val put : t -> string -> string -> [ `Created | `Replaced ]
(** [put t k v] binds [k] to [v]. *)

val get : t -> string -> string option
val delete : t -> string -> bool
(** [delete t k] is [true] if [k] was bound. *)

val keys : t -> string list
(** All keys, sorted ascending (byte order). *)
