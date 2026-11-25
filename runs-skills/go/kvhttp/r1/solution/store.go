package main

import (
	"maps"
	"slices"
	"sync"
)

// Store is a concurrency-safe in-memory key-value store.
// Stored values are treated as immutable once written.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// NewStore returns an empty Store.
func NewStore() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Get returns the value for key and whether it was present.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.data[key]
	return v, ok
}

// Put stores value under key and reports whether the key was newly created.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, existed := s.data[key]
	s.data[key] = value
	return !existed
}

// Delete removes key and reports whether it was present.
func (s *Store) Delete(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.data[key]
	delete(s.data, key)
	return ok
}

// Keys returns all keys in ascending order.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := slices.Collect(maps.Keys(s.data))
	s.mu.RUnlock()
	slices.Sort(keys)
	if keys == nil {
		keys = []string{}
	}
	return keys
}
