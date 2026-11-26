// Package store provides a concurrency-safe in-memory key/value store.
package store

import (
	"slices"
	"sync"
)

// Store is a thread-safe in-memory key/value store. Stored values are treated
// as immutable: callers must not modify a slice after passing it to Put or
// after receiving it from Get.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// New returns an empty Store.
func New() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Put stores value under key. It reports whether the key was newly created.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, exists := s.data[key]
	s.data[key] = value
	return !exists
}

// Get returns the value stored under key and whether it was present.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.data[key]
	return v, ok
}

// Delete removes key and reports whether it was present.
func (s *Store) Delete(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.data[key]
	delete(s.data, key)
	return ok
}

// Keys returns every key in ascending byte order. The result is never nil.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := make([]string, 0, len(s.data))
	for k := range s.data {
		keys = append(keys, k)
	}
	s.mu.RUnlock()
	slices.Sort(keys)
	return keys
}
