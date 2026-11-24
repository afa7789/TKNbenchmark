(** Thread-safe in-memory key-value store. *)

type t

val create : unit -> t

val is_valid_key : string -> bool
(** [is_valid_key k] holds iff [k] matches [[A-Za-z0-9_-]{1,64}]. *)

val max_value_size : int
(** Largest accepted value, in bytes (1 MiB). *)

val put : t -> string -> string -> [ `Created | `Replaced ]
val get : t -> string -> string option
val delete : t -> string -> bool

val keys : t -> string list
(** All keys, sorted ascending by byte order. *)
