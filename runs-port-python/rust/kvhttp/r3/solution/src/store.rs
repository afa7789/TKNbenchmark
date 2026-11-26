//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{Mutex, MutexGuard};

use bytes::Bytes;

/// In-memory key-value store shared by all connections.
///
/// Keys are kept in a `BTreeMap` so listing them in ascending order is cheap.
/// Values are reference-counted `Bytes`, so reads never copy under the lock.
#[derive(Debug, Default)]
pub struct Store {
    data: Mutex<BTreeMap<String, Bytes>>,
}

impl Store {
    pub fn new() -> Self {
        Self::default()
    }

    /// Stores a value; returns `true` if the key was newly created.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.lock().insert(key.to_owned(), value).is_none()
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.lock().get(key).cloned()
    }

    /// Removes a key; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.lock().remove(key).is_some()
    }

    /// Every key, sorted ascending.
    pub fn keys(&self) -> Vec<String> {
        self.lock().keys().cloned().collect()
    }

    fn lock(&self) -> MutexGuard<'_, BTreeMap<String, Bytes>> {
        // A panic while holding the lock cannot leave the map half-updated,
        // so recovering from poisoning is safe.
        self.data.lock().unwrap_or_else(|e| e.into_inner())
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
        for k in ["b", "a", "C", "_", "-"] {
            store.put(k, Bytes::new());
        }
        assert_eq!(store.keys(), ["-", "C", "_", "a", "b"]);
    }
}
