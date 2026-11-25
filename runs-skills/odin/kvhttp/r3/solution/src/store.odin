package main

import "base:runtime"
import "core:slice"
import "core:strings"
import "core:sync"

// Store is a thread-safe in-memory key-value map. Keys and values are owned by the store.
Store :: struct {
	lock:      sync.RW_Mutex,
	entries:   map[string][]byte,
	allocator: runtime.Allocator,
}

store_init :: proc(s: ^Store, allocator := context.allocator) {
	s.allocator = allocator
	s.entries = make(map[string][]byte, allocator)
}

store_destroy :: proc(s: ^Store) {
	for k, v in s.entries {
		delete(k, s.allocator)
		delete(v, s.allocator)
	}
	delete(s.entries)
}

// store_put copies value into the store. Returns true if the key did not exist before.
store_put :: proc(s: ^Store, key: string, value: []byte) -> (created: bool) {
	owned := slice.clone(value, s.allocator)

	sync.rw_mutex_lock(&s.lock)
	defer sync.rw_mutex_unlock(&s.lock)

	if old, found := &s.entries[key]; found {
		delete(old^, s.allocator)
		old^ = owned
		return false
	}
	s.entries[strings.clone(key, s.allocator)] = owned
	return true
}

// store_get returns a copy of the stored value, allocated with `allocator`.
store_get :: proc(s: ^Store, key: string, allocator := context.allocator) -> (value: []byte, found: bool) {
	sync.rw_mutex_shared_lock(&s.lock)
	defer sync.rw_mutex_shared_unlock(&s.lock)

	stored := s.entries[key] or_return
	return slice.clone(stored, allocator), true
}

store_delete :: proc(s: ^Store, key: string) -> (deleted: bool) {
	sync.rw_mutex_lock(&s.lock)
	defer sync.rw_mutex_unlock(&s.lock)

	k, v := delete_key(&s.entries, key)
	if k == "" {
		return false
	}
	delete(k, s.allocator)
	delete(v, s.allocator)
	return true
}

// store_keys returns every key, sorted ascending by byte order. The strings are
// cloned with `allocator`, as is the slice.
store_keys :: proc(s: ^Store, allocator := context.allocator) -> []string {
	keys: [dynamic]string
	{
		sync.rw_mutex_shared_lock(&s.lock)
		defer sync.rw_mutex_shared_unlock(&s.lock)

		keys = make([dynamic]string, 0, len(s.entries), allocator)
		for k in s.entries {
			append(&keys, strings.clone(k, allocator))
		}
	}
	slice.sort(keys[:])
	return keys[:]
}
