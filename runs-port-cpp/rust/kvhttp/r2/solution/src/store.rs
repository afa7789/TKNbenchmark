//! Thread-safe in-memory key-value store.

use std::collections::BTreeMap;
use std::sync::{PoisonError, RwLock, RwLockReadGuard, RwLockWriteGuard};

/// Outcome of [`KvStore::put`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PutResult {
    Created,
    Replaced,
}

/// Keys are kept ordered so that listing them sorted is a linear walk.
#[derive(Debug, Default)]
pub struct KvStore {
    data: RwLock<BTreeMap<String, Vec<u8>>>,
}

impl KvStore {
    pub fn new() -> Self {
        Self::default()
    }

    // The map is never left in an inconsistent state, so a poisoned lock is
    // safe to keep using.
    fn read(&self) -> RwLockReadGuard<'_, BTreeMap<String, Vec<u8>>> {
        self.data.read().unwrap_or_else(PoisonError::into_inner)
    }

    fn write(&self) -> RwLockWriteGuard<'_, BTreeMap<String, Vec<u8>>> {
        self.data.write().unwrap_or_else(PoisonError::into_inner)
    }

    pub fn put(&self, key: String, value: Vec<u8>) -> PutResult {
        match self.write().insert(key, value) {
            Some(_) => PutResult::Replaced,
            None => PutResult::Created,
        }
    }

    pub fn get(&self, key: &str) -> Option<Vec<u8>> {
        self.read().get(key).cloned()
    }

    pub fn remove(&self, key: &str) -> bool {
        self.write().remove(key).is_some()
    }

    /// All keys in ascending order.
    pub fn keys(&self) -> Vec<String> {
        self.read().keys().cloned().collect()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn crud() {
        let store = KvStore::new();
        assert_eq!(store.put("b".into(), b"1".to_vec()), PutResult::Created);
        assert_eq!(store.put("b".into(), b"2".to_vec()), PutResult::Replaced);
        store.put("a".into(), Vec::new());
        assert_eq!(store.get("b").as_deref(), Some(&b"2"[..]));
        assert_eq!(store.keys(), ["a", "b"]);
        assert!(store.remove("b"));
        assert!(!store.remove("b"));
        assert_eq!(store.get("b"), None);
    }
}
