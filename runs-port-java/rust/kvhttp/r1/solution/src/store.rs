//! Thread-safe in-memory key-value store with keys kept in ascending order.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

#[derive(Debug, Default)]
pub struct KvStore {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`.
    ///
    /// Returns `true` if the key was new, `false` if an existing value was replaced.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.insert(key.to_owned(), value).is_none()
    }

    /// Returns the value stored under `key`, if any. Cloning `Bytes` is cheap.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.get(key).cloned()
    }

    /// Returns `true` if the key was present and has been removed.
    pub fn delete(&self, key: &str) -> bool {
        let mut entries = self.entries.write().unwrap_or_else(PoisonError::into_inner);
        entries.remove(key).is_some()
    }

    /// Returns a snapshot of all keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        let entries = self.entries.read().unwrap_or_else(PoisonError::into_inner);
        entries.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_delete_roundtrip() {
        let store = KvStore::new();
        assert!(store.put("a", Bytes::from_static(b"1")));
        assert!(!store.put("a", Bytes::from_static(b"2")));
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }

    #[test]
    fn keys_are_sorted() {
        let store = KvStore::new();
        for key in ["b", "a", "C", "_", "-"] {
            store.put(key, Bytes::new());
        }
        assert_eq!(store.keys(), ["-", "C", "_", "a", "b"]);
    }
}
