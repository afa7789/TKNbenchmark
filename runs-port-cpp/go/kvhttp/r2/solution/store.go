package main

import (
	"maps"
	"slices"
	"sync"
)

// Store is a concurrency-safe in-memory key-value store.
type Store struct {
	mu   sync.RWMutex
	data map[string][]byte
}

// NewStore returns an empty Store.
func NewStore() *Store {
	return &Store{data: make(map[string][]byte)}
}

// Put stores value under key and reports whether the key was newly created.
// The store takes ownership of value.
func (s *Store) Put(key string, value []byte) (created bool) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, exists := s.data[key]
	s.data[key] = value
	return !exists
}

// Get returns the value stored under key. The returned slice must not be
// modified.
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
	if _, ok := s.data[key]; !ok {
		return false
	}
	delete(s.data, key)
	return true
}

// Keys returns every key in ascending order. The result is never nil.
func (s *Store) Keys() []string {
	s.mu.RLock()
	keys := slices.AppendSeq(make([]string, 0, len(s.data)), maps.Keys(s.data))
	s.mu.RUnlock()
	slices.Sort(keys)
	return keys
}
