//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{Mutex, MutexGuard};

use bytes::Bytes;

/// Maps keys to their stored bytes. Keys are kept sorted so listing is cheap.
#[derive(Debug, Default)]
pub struct Store {
    entries: Mutex<BTreeMap<String, Bytes>>,
}

impl Store {
    fn lock(&self) -> MutexGuard<'_, BTreeMap<String, Bytes>> {
        // No operation can leave the map in an inconsistent state, so a poisoned
        // lock is still safe to use.
        self.entries.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    pub fn get(&self, key: &str) -> Option<Bytes> {
        self.lock().get(key).cloned()
    }

    /// Stores `value` under `key`; returns `true` if the key was new.
    pub fn put(&self, key: &str, value: Bytes) -> bool {
        self.lock().insert(key.to_owned(), value).is_none()
    }

    /// Removes `key`; returns `true` if it was present.
    pub fn delete(&self, key: &str) -> bool {
        self.lock().remove(key).is_some()
    }

    /// All keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        self.lock().keys().cloned().collect()
    }
}
