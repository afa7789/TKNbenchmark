(* Bindings live in a circular doubly linked list threaded through a
   sentinel: [sentinel.next] is the most recently used node and
   [sentinel.prev] the least recently used one. A hash table maps each key
   to its node. *)

type 'a node = {
  key : string;
  mutable value : 'a option;  (* [None] only for the sentinel *)
  mutable prev : 'a node;
  mutable next : 'a node;
}

type 'a t = {
  capacity : int;
  table : (string, 'a node) Hashtbl.t;
  sentinel : 'a node;
}

let create capacity =
  if capacity < 1 then invalid_arg "Lru.create: capacity must be positive";
  let rec sentinel = { key = ""; value = None; prev = sentinel; next = sentinel } in
  { capacity; table = Hashtbl.create (min capacity 65536); sentinel }

let unlink node =
  node.prev.next <- node.next;
  node.next.prev <- node.prev

let push_front t node =
  let s = t.sentinel in
  node.prev <- s;
  node.next <- s.next;
  s.next.prev <- node;
  s.next <- node

let size t = Hashtbl.length t.table

let evict_lru t =
  let lru = t.sentinel.prev in
  if lru != t.sentinel then begin
    unlink lru;
    Hashtbl.remove t.table lru.key
  end

let set t key value =
  match Hashtbl.find_opt t.table key with
  | Some node ->
      node.value <- Some value;
      unlink node;
      push_front t node
  | None ->
      let s = t.sentinel in
      let node = { key; value = Some value; prev = s; next = s } in
      Hashtbl.replace t.table key node;
      push_front t node;
      if size t > t.capacity then evict_lru t

let get t key =
  match Hashtbl.find_opt t.table key with
  | Some node ->
      unlink node;
      push_front t node;
      node.value
  | None -> None

let remove t key =
  match Hashtbl.find_and_remove t.table key with
  | Some node ->
      unlink node;
      true
  | None -> false
