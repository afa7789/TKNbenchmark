(** Minimal HTTP/1.1 request parser (one request per connection). *)

type t = {
  meth : string;
  path : string;  (** Request target without any query string. *)
  headers : (string * string) list;  (** Names lower-cased. *)
  body : string;
}

type error =
  [ `Eof  (** Connection closed before a request line arrived. *)
  | `Bad_request
  | `Header_too_large
  | `Body_too_large ]

val read : max_body:int -> in_channel -> (t, error) result
(** Reads one request. Bodies longer than [max_body] are discarded (when
    reasonably small, so the client still receives the error response) and
    reported as [`Body_too_large]. *)
