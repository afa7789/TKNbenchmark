(** Maps requests to responses against a {!Store.t}. *)

val max_value : int
(** Largest accepted value, in bytes (1 MiB). *)

val is_valid_key : string -> bool
(** [true] iff the key matches [[A-Za-z0-9_-]{1,64}]. *)

val handle : Store.t -> Http.request -> Http.response
