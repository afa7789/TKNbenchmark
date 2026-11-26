//! Thread-safe in-memory key/value store.

use std::collections::BTreeMap;
use std::sync::{Arc, PoisonError, RwLock};

/// A stored value. Shared so readers can drop the lock before the
/// (possibly large) value is sent.
pub type Value = Arc<[u8]>;

#[derive(Debug, Default)]
pub struct KvStore {
    map: RwLock<BTreeMap<String, Value>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`. Returns `true` if the key was new,
    /// `false` if it replaced an existing value.
    pub fn put(&self, key: &str, value: Vec<u8>) -> bool {
        let value: Value = value.into();
        let mut map = self.map.write().unwrap_or_else(PoisonError::into_inner);
        if let Some(slot) = map.get_mut(key) {
            *slot = value;
            false
        } else {
            map.insert(key.to_owned(), value);
            true
        }
    }

    pub fn get(&self, key: &str) -> Option<Value> {
        let map = self.map.read().unwrap_or_else(PoisonError::into_inner);
        map.get(key).cloned()
    }

    /// Removes `key`. Returns `true` if it was present.
    pub fn remove(&self, key: &str) -> bool {
        let mut map = self.map.write().unwrap_or_else(PoisonError::into_inner);
        map.remove(key).is_some()
    }

    /// All keys in ascending byte-wise order.
    pub fn keys(&self) -> Vec<String> {
        let map = self.map.read().unwrap_or_else(PoisonError::into_inner);
        map.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_remove() {
        let store = KvStore::new();
        assert!(store.put("a", b"1".to_vec()));
        assert!(!store.put("a", b"2".to_vec()));
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.remove("a"));
        assert!(!store.remove("a"));
        assert!(store.get("a").is_none());
    }

    #[test]
    fn keys_sorted() {
        let store = KvStore::new();
        for k in ["b", "a", "C", "_"] {
            store.put(k, Vec::new());
        }
        assert_eq!(store.keys(), ["C", "_", "a", "b"]);
    }
}
