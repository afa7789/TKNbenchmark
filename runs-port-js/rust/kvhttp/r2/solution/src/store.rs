//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock};

use bytes::Bytes;

/// In-memory map from keys to opaque byte values, kept in key order.
#[derive(Debug, Default)]
pub struct Store {
    entries: RwLock<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.read().get(key).cloned()
    }

    /// Stores `value` under `key`; returns `true` if the key already existed.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.write().insert(key.to_owned(), value).is_some()
    }

    /// Removes `key`; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    /// All keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }

    fn read(&self) -> std::sync::RwLockReadGuard<'_, BTreeMap<String, Bytes>> {
        // Critical sections cannot panic midway, so a poisoned map is still consistent.
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
    fn crud_and_sorted_keys() {
        let store = Store::default();
        assert!(!store.put("b", Bytes::from_static(b"2")));
        assert!(!store.put("a", Bytes::from_static(b"1")));
        assert!(store.put("a", Bytes::from_static(b"3")));
        assert_eq!(store.get("a").as_deref(), Some(&b"3"[..]));
        assert_eq!(store.keys(), ["a", "b"]);
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }
}
