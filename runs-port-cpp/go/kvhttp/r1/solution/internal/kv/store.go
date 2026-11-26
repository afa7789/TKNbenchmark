// Package kv provides a thread-safe in-memory key/value store.
package kv

import (
	"maps"
	"slices"
	"sync"
)

// Store is a concurrency-safe map from keys to byte values. Stored values
// are treated as immutable: callers must not modify a slice after passing it
// to Put or after receiving it from Get.
type Store struct {
	mu sync.RWMutex
	m  map[string][]byte
}

// NewStore returns an empty store.
func NewStore() *Store {
	return &Store{m: make(map[string][]byte)}
}

// Put stores value under key. It reports whether the key was newly created
// (true) or an existing value was replaced (false).
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, exists := s.m[key]
	s.m[key] = value
	return !exists
}

// Get returns the value stored under key and whether it was present.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.m[key]
	return v, ok
}

// Delete removes key and reports whether it was present.
func (s *Store) Delete(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.m[key]; !ok {
		return false
	}
	delete(s.m, key)
	return true
}

// Keys returns every key in ascending byte-wise order.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := slices.Collect(maps.Keys(s.m))
	s.mu.RUnlock()
	slices.Sort(keys)
	return keys
}
