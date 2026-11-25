(** Thread-safe in-memory key-value store. *)

type t

val create : unit -> t

val get : t -> string -> string option

val put : t -> string -> string -> [ `Created | `Replaced ]
(** [put t k v] binds [k] to [v], reporting whether [k] was new. *)

val delete : t -> string -> bool
(** [delete t k] removes [k]; [false] if it was absent. *)

val keys : t -> string list
(** Every key, sorted ascending (bytewise). *)
