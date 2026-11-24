package kvhttp

import "base:runtime"
import "core:slice"
import "core:strings"
import "core:sync"

// Store is a thread-safe in-memory key-value map. Keys and values are owned
// by the store and allocated with its own allocator, independent of the
// per-request allocators used by connection handlers.
Store :: struct {
	mutex:     sync.Mutex,
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

// store_put stores a copy of value under key. Returns true if the key was new.
store_put :: proc(s: ^Store, key: string, value: []byte) -> (created: bool) {
	owned_value := slice.clone(value, s.allocator)

	sync.mutex_guard(&s.mutex)
	if existing, found := &s.entries[key]; found {
		delete(existing^, s.allocator)
		existing^ = owned_value
		return false
	}
	s.entries[strings.clone(key, s.allocator)] = owned_value
	return true
}

// store_get returns a copy of the value for key, allocated with `allocator`.
store_get :: proc(s: ^Store, key: string, allocator := context.allocator) -> (value: []byte, found: bool) {
	sync.mutex_guard(&s.mutex)
	stored := s.entries[key] or_return
	return slice.clone(stored, allocator), true
}

// store_delete removes key. Returns true if it was present.
store_delete :: proc(s: ^Store, key: string) -> (deleted: bool) {
	sync.mutex_guard(&s.mutex)
	owned_key, owned_value := delete_key(&s.entries, key)
	if owned_key == "" && owned_value == nil {
		return false
	}
	delete(owned_key, s.allocator)
	delete(owned_value, s.allocator)
	return true
}

// store_keys returns every key sorted ascending, cloned with `allocator`.
store_keys :: proc(s: ^Store, allocator := context.allocator) -> []string {
	keys: [dynamic]string
	{
		sync.mutex_guard(&s.mutex)
		keys = make([dynamic]string, 0, len(s.entries), allocator)
		for k in s.entries {
			append(&keys, strings.clone(k, allocator))
		}
	}
	slice.sort(keys[:])
	return keys[:]
}
