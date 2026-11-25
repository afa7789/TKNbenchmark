(** Maps a parsed request onto the key-value store. *)

val max_value_size : int
(** Largest accepted value, in bytes (1 MiB). *)

val valid_key : string -> bool
(** [valid_key k] holds iff [k] matches [[A-Za-z0-9_-]{1,64}]. *)

val handle : Store.t -> meth:string -> path:string -> body:string -> Response.t
