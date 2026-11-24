(* A hash table maps keys to nodes of an intrusive doubly-linked list
   ordered from most recently used ([head]) to least recently used
   ([tail]). Inline records keep each node to a single allocation. *)

type ('k, 'v) link =
  | Nil
  | Node of {
      key : 'k;
      mutable value : 'v;
      mutable prev : ('k, 'v) link;
      mutable next : ('k, 'v) link;
    }

type ('k, 'v) t = {
  capacity : int;
  table : ('k, ('k, 'v) link) Hashtbl.t;
  mutable head : ('k, 'v) link;
  mutable tail : ('k, 'v) link;
}

let create capacity =
  if capacity < 1 then invalid_arg "Lru.create: capacity must be positive";
  { capacity; table = Hashtbl.create (min capacity 65536); head = Nil; tail = Nil }

let set_prev link p = match link with Nil -> () | Node n -> n.prev <- p
let set_next link nx = match link with Nil -> () | Node n -> n.next <- nx

let unlink t link =
  match link with
  | Nil -> ()
  | Node n ->
      (match n.prev with Nil -> t.head <- n.next | prev -> set_next prev n.next);
      (match n.next with Nil -> t.tail <- n.prev | next -> set_prev next n.prev);
      n.prev <- Nil;
      n.next <- Nil

let push_front t link =
  match link with
  | Nil -> ()
  | Node n ->
      n.prev <- Nil;
      n.next <- t.head;
      (match t.head with Nil -> t.tail <- link | head -> set_prev head link);
      t.head <- link

let touch t link =
  if t.head != link then begin
    unlink t link;
    push_front t link
  end

let evict_lru t =
  match t.tail with
  | Nil -> ()
  | Node n as last ->
      unlink t last;
      Hashtbl.remove t.table n.key

let set t key value =
  match Hashtbl.find_opt t.table key with
  | Some (Node n as link) ->
      n.value <- value;
      touch t link
  | Some Nil | None ->
      let link = Node { key; value; prev = Nil; next = Nil } in
      Hashtbl.replace t.table key link;
      push_front t link;
      if Hashtbl.length t.table > t.capacity then evict_lru t

let get t key =
  match Hashtbl.find_opt t.table key with
  | Some (Node n as link) ->
      touch t link;
      Some n.value
  | Some Nil | None -> None

let remove t key =
  match Hashtbl.find_opt t.table key with
  | Some link ->
      unlink t link;
      Hashtbl.remove t.table key;
      true
  | None -> false

let length t = Hashtbl.length t.table
