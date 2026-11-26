//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{Mutex, MutexGuard};

use bytes::Bytes;

/// In-memory key-value store shared by all connections.
///
/// Keys are kept ordered so listing them is a simple in-order walk.
#[derive(Debug, Default)]
pub struct Store {
    data: Mutex<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores `value` under `key`, returning `true` if the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.lock().insert(key.to_owned(), value).is_none()
    }

    /// Returns the value stored under `key`, if any.
    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.lock().get(key).cloned()
    }

    /// Removes `key`, returning `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.lock().remove(key).is_some()
    }

    /// Returns every key in ascending order.
    pub fn keys(&self) -> Vec<String> {
        self.lock().keys().cloned().collect()
    }

    fn lock(&self) -> MutexGuard<'_, BTreeMap<String, Bytes>> {
        // No operation can leave the map in an inconsistent state, so a
        // poisoned lock is safe to keep using.
        self.data
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn put_get_delete() {
        let store = Store::new();
        assert!(store.put("a", Bytes::from_static(b"1")));
        assert!(!store.put("a", Bytes::from_static(b"2")));
        assert_eq!(store.get("a").as_deref(), Some(&b"2"[..]));
        assert!(store.delete("a"));
        assert!(!store.delete("a"));
        assert_eq!(store.get("a"), None);
    }

    #[test]
    fn keys_are_sorted() {
        let store = Store::new();
        for key in ["b", "a", "c", "A", "_"] {
            store.put(key, Bytes::new());
        }
        assert_eq!(store.keys(), ["A", "_", "a", "b", "c"]);
    }
}
