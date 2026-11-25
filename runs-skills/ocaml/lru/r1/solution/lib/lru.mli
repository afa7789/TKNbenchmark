(** Mutable LRU cache with O(1) expected-time operations. *)

type ('k, 'v) t

val create : int -> ('k, 'v) t
(** [create capacity] makes an empty cache holding at most [capacity] keys.
    @raise Invalid_argument if [capacity < 1]. *)

val set : ('k, 'v) t -> 'k -> 'v -> unit
(** Insert or overwrite a binding, making it the most recently used and
    evicting the least recently used binding if the capacity is exceeded. *)

val get : ('k, 'v) t -> 'k -> 'v option
(** Look up a key; a hit makes it the most recently used. *)

val remove : ('k, 'v) t -> 'k -> bool
(** Remove a key; returns whether it was present. *)

val size : ('k, 'v) t -> int
(** Number of keys currently held. *)
