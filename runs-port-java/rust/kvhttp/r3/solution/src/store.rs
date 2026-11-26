//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// An ordered, concurrently accessible map from keys to byte values.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the value stored under `key`, if any.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.read().get(key).cloned()
    }

    /// Stores `value` under `key`, returning `true` if the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.write().insert(key.to_owned(), value).is_none()
    }

    /// Removes `key`, returning `true` if it was present.
    pub fn remove(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    /// Returns every key in ascending order.
    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }

    // The map is never left in an inconsistent state by a panicking holder,
    // so a poisoned lock is safe to keep using.
    fn read(&self) -> std::sync::RwLockReadGuard<'_, BTreeMap<String, Bytes>> {
        self.entries.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> std::sync::RwLockWriteGuard<'_, BTreeMap<String, Bytes>> {
        self.entries.write().unwrap_or_else(PoisonError::into_inner)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_remove() {
        let store = Store::new();
        assert!(store.put("a", Bytes::from_static(b"1")));
        assert!(!store.put("a", Bytes::from_static(b"2")));
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.remove("a"));
        assert!(!store.remove("a"));
        assert_eq!(store.get("a"), None);
    }

    #[test]
    fn keys_are_sorted() {
        let store = Store::new();
        for key in ["b", "C", "a", "_", "-", "0"] {
            store.put(key, Bytes::new());
        }
        assert_eq!(store.keys(), ["-", "0", "C", "_", "a", "b"]);
    }
}
