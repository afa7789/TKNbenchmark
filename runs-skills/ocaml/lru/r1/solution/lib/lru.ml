(* A hash table maps each key to its cell in a doubly linked recency list.
   [head] is the most recently used cell and [tail] the least recently used
   one. Cells are inline records, so links cost no extra indirection. *)

type ('k, 'v) cell =
  | Nil
  | Cell of {
      key : 'k;
      mutable value : 'v;
      mutable prev : ('k, 'v) cell;
      mutable next : ('k, 'v) cell;
    }

type ('k, 'v) t = {
  capacity : int;
  table : ('k, ('k, 'v) cell) Hashtbl.t;
  mutable head : ('k, 'v) cell;
  mutable tail : ('k, 'v) cell;
}

let create capacity =
  if capacity < 1 then invalid_arg "Lru.create: capacity must be positive";
  { capacity; table = Hashtbl.create (min capacity 1_000_000); head = Nil; tail = Nil }

let size t = Hashtbl.length t.table

let set_next cell next =
  match cell with Nil -> () | Cell c -> c.next <- next

let set_prev cell prev =
  match cell with Nil -> () | Cell c -> c.prev <- prev

let unlink t cell =
  match cell with
  | Nil -> ()
  | Cell c ->
      (match c.prev with Nil -> t.head <- c.next | prev -> set_next prev c.next);
      (match c.next with Nil -> t.tail <- c.prev | next -> set_prev next c.prev);
      c.prev <- Nil;
      c.next <- Nil

let push_front t cell =
  match cell with
  | Nil -> ()
  | Cell c ->
      c.prev <- Nil;
      c.next <- t.head;
      (match t.head with Nil -> t.tail <- cell | head -> set_prev head cell);
      t.head <- cell

let touch t cell =
  if t.head != cell then begin
    unlink t cell;
    push_front t cell
  end

let evict_lru t =
  match t.tail with
  | Nil -> ()
  | Cell { key; _ } as lru ->
      unlink t lru;
      Hashtbl.remove t.table key

let set t key value =
  match Hashtbl.find_opt t.table key with
  | Some (Cell c as cell) ->
      c.value <- value;
      touch t cell
  | Some Nil | None ->
      (* Evicting first is equivalent to evicting after the insertion: the
         new key is the most recently used, so it is never the victim. *)
      if Hashtbl.length t.table >= t.capacity then evict_lru t;
      let cell = Cell { key; value; prev = Nil; next = Nil } in
      push_front t cell;
      Hashtbl.replace t.table key cell

let get t key =
  match Hashtbl.find_opt t.table key with
  | Some (Cell { value; _ } as cell) ->
      touch t cell;
      Some value
  | Some Nil | None -> None

let remove t key =
  match Hashtbl.find_and_remove t.table key with
  | Some cell ->
      unlink t cell;
      true
  | None -> false
