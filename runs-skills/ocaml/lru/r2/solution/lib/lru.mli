(** A fixed-capacity least-recently-used cache from string keys to string
    values. Every operation runs in O(1) expected time. *)

type t

val create : int -> t
(** [create capacity] is an empty cache holding at most [capacity] keys.
    @raise Invalid_argument if [capacity < 1]. *)

val set : t -> string -> string -> unit
(** [set t k v] binds [k] to [v] and marks [k] most recently used, evicting
    the least recently used key if the capacity would be exceeded. *)

val get : t -> string -> string option
(** [get t k] is the value bound to [k], if any; a hit marks [k] most
    recently used. *)

val remove : t -> string -> bool
(** [remove t k] unbinds [k] and reports whether it was present. *)

val size : t -> int
(** Number of keys currently held. *)
