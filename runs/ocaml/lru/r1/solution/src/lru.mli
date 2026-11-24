(** Mutable LRU cache with O(1) expected-time operations. *)

type ('k, 'v) t

val create : int -> ('k, 'v) t
(** [create capacity] makes an empty cache holding at most [capacity] keys.
    @raise Invalid_argument if [capacity < 1]. *)

val set : ('k, 'v) t -> 'k -> 'v -> unit
(** Insert or overwrite a binding and mark it most recently used, evicting
    the least recently used binding if capacity is exceeded. *)

val get : ('k, 'v) t -> 'k -> 'v option
(** Look up a binding; a hit marks it most recently used. *)

val remove : ('k, 'v) t -> 'k -> bool
(** Remove a binding, returning whether it was present. *)

val length : ('k, 'v) t -> int
(** Number of bindings currently held. *)
