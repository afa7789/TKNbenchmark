(** A fixed-capacity least-recently-used cache with string keys and values.
    All operations run in O(1) expected time. *)

type t

val create : int -> t
(** [create capacity] makes an empty cache. Raises [Invalid_argument] if
    [capacity < 1]. *)

val set : t -> string -> string -> unit
(** Insert or overwrite a binding, making it the most recently used. Evicts
    the least recently used binding if the capacity is exceeded. *)

val get : t -> string -> string option
(** Look up a key; a hit makes it the most recently used. *)

val remove : t -> string -> bool
(** Remove a key, returning whether it was present. *)

val size : t -> int
