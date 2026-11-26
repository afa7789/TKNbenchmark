//! Thread-safe in-memory key/value store.

use std::collections::BTreeMap;
use std::sync::{Arc, PoisonError, RwLock};

/// A stored value. Shared so readers can release the lock before copying
/// large values onto the wire.
pub type Value = Arc<Vec<u8>>;

#[derive(Debug, Default)]
pub struct Store {
    data: RwLock<BTreeMap<String, Value>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`. Returns `true` if the key was newly created,
    /// `false` if it replaced an existing value.
    pub fn put(&self, key: &str, value: Vec<u8>) -> bool {
        let value = Arc::new(value);
        let mut data = self.data.write().unwrap_or_else(PoisonError::into_inner);
        match data.get_mut(key) {
            Some(slot) => {
                *slot = value;
                false
            }
            None => {
                data.insert(key.to_owned(), value);
                true
            }
        }
    }

    pub fn get(&self, key: &str) -> Option<Value> {
        let data = self.data.read().unwrap_or_else(PoisonError::into_inner);
        data.get(key).cloned()
    }

    /// Removes `key`. Returns `true` if it was present.
    pub fn remove(&self, key: &str) -> bool {
        let mut data = self.data.write().unwrap_or_else(PoisonError::into_inner);
        data.remove(key).is_some()
    }

    /// All keys in ascending byte order.
    pub fn keys(&self) -> Vec<String> {
        let data = self.data.read().unwrap_or_else(PoisonError::into_inner);
        data.keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_remove() {
        let store = Store::new();
        assert!(store.put("a", b"1".to_vec()));
        assert!(!store.put("a", b"2".to_vec()));
        assert_eq!(
            store.get("a").as_deref().map(Vec::as_slice),
            Some(&b"2"[..])
        );
        assert!(store.remove("a"));
        assert!(!store.remove("a"));
        assert!(store.get("a").is_none());
    }

    #[test]
    fn keys_are_sorted() {
        let store = Store::new();
        for k in ["b", "a", "C", "_", "-"] {
            store.put(k, Vec::new());
        }
        assert_eq!(store.keys(), ["-", "C", "_", "a", "b"]);
    }
}
