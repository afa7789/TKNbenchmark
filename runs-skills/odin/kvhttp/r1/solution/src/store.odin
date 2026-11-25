package main

import "base:runtime"
import "core:slice"
import "core:strings"
import "core:sync"

// Thread-safe in-memory key-value store. Keys and values are owned by the
// store and live on the (thread-safe) heap allocator, independent of whatever
// allocator the calling request handler has in its context.
Store :: struct {
	lock:  sync.RW_Mutex,
	items: map[string][]byte,
}

store_init :: proc(s: ^Store) {
	s.items = make(map[string][]byte, runtime.heap_allocator())
}

store_destroy :: proc(s: ^Store) {
	for k, v in s.items {
		delete(k, runtime.heap_allocator())
		delete(v, runtime.heap_allocator())
	}
	delete(s.items)
}

Put_Result :: enum {
	Created,
	Replaced,
}

store_put :: proc(s: ^Store, key: string, value: []byte) -> Put_Result {
	// Copy outside the lock so large values do not stall other requests.
	owned := slice.clone(value, runtime.heap_allocator())

	sync.rw_mutex_lock(&s.lock)
	defer sync.rw_mutex_unlock(&s.lock)

	if old, ok := &s.items[key]; ok {
		delete(old^, runtime.heap_allocator())
		old^ = owned
		return .Replaced
	}
	s.items[strings.clone(key, runtime.heap_allocator())] = owned
	return .Created
}

// Returns a copy of the stored value made with `allocator`.
store_get :: proc(s: ^Store, key: string, allocator := context.allocator) -> (value: []byte, found: bool) {
	sync.rw_mutex_shared_lock(&s.lock)
	defer sync.rw_mutex_shared_unlock(&s.lock)

	v := s.items[key] or_return
	return slice.clone(v, allocator), true
}

store_delete :: proc(s: ^Store, key: string) -> bool {
	sync.rw_mutex_lock(&s.lock)
	defer sync.rw_mutex_unlock(&s.lock)

	if key not_in s.items {
		return false
	}
	k, v := delete_key(&s.items, key)
	delete(k, runtime.heap_allocator())
	delete(v, runtime.heap_allocator())
	return true
}

// Returns all keys sorted ascending, cloned with `allocator`.
store_keys :: proc(s: ^Store, allocator := context.allocator) -> []string {
	keys: []string
	{
		sync.rw_mutex_shared_lock(&s.lock)
		defer sync.rw_mutex_shared_unlock(&s.lock)

		keys = make([]string, len(s.items), allocator)
		i := 0
		for k in s.items {
			keys[i] = strings.clone(k, allocator)
			i += 1
		}
	}
	slice.sort(keys)
	return keys
}
