// Package kv implements an in-memory key-value store and its HTTP API.
package kv

import (
	"slices"
	"sync"
)

// Store is a concurrency-safe in-memory map from keys to byte values.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// NewStore returns an empty Store.
func NewStore() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Get returns the value stored under key and whether it was present.
// The returned slice must not be modified.
func (s *Store) Get(key string) ([]byte, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	v, ok := s.data[key]
	return v, ok
}

// Put stores value under key and reports whether the key already existed.
// The store takes ownership of value.
func (s *Store) Put(key string, value []byte) (replaced bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, replaced = s.data[key]
	s.data[key] = value
	return replaced
}

// Delete removes key and reports whether it was present.
func (s *Store) Delete(key string) bool {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, ok := s.data[key]
	if ok {
		delete(s.data, key)
	}
	return ok
}

// Keys returns every key in ascending order.
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
