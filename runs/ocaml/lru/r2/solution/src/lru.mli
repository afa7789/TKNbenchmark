(** A fixed-capacity least-recently-used cache from string keys to string
    values. All operations run in O(1) expected time. *)

type t

val create : int -> t
(** [create capacity] returns an empty cache holding at most [capacity] keys.
    @raise Invalid_argument if [capacity < 1]. *)

val set : t -> string -> string -> unit
(** Insert or overwrite a binding and mark it most recently used, evicting the
    least recently used binding if the capacity is exceeded. *)

val get : t -> string -> string option
(** Look up a key; a hit marks it most recently used. *)

val remove : t -> string -> bool
(** Remove a key, returning whether it was present. *)

val size : t -> int
