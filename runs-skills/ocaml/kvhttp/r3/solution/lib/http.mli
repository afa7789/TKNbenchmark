(** Minimal HTTP/1.1 message handling: one request per connection. *)

type request = {
  meth : string;
  path : string;
  headers : (string * string) list;  (** Names are lower-cased. *)
  body : string;
}

type response = {
  status : int;
  headers : (string * string) list;
  body : string;
}

val response : ?headers:(string * string) list -> ?body:string -> int -> response

type error =
  | Bad_request  (** Malformed request line, headers or framing. *)
  | Payload_too_large
  | Not_implemented  (** e.g. an unsupported [Transfer-Encoding]. *)
  | Closed  (** The peer closed before sending a full request head. *)

val read_request : max_body:int -> In_channel.t -> (request, error) result
(** Reads one request. On [Payload_too_large] the body has been drained so
    the error response can be delivered cleanly. *)

val error_response : error -> response option
(** The response to send for a read error, if any. *)

val write_response : Out_channel.t -> response -> unit
(** Writes and flushes [response], always with [Connection: close]. *)
