// Package store implements a concurrency-safe in-memory key-value store.
package store

import (
	"slices"
	"sync"
)

// Store maps string keys to byte values. The zero value is not usable; call New.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// New returns an empty store.
func New() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Put stores val under key, taking ownership of val. It reports whether the
// key was newly created (as opposed to replacing an existing value).
func (s *Store) Put(key string, val []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, exists := s.data[key]
	s.data[key] = val
	return !exists
}

// Get returns the value stored under key. The returned slice must not be
// modified by the caller.
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
