(** Maps requests on the kvhttp API to responses. *)

val handle : Store.t -> Http.request -> Http.response
