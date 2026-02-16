//! Encrypted MLS storage for the Burrow CLI.
//!
//! Derives a database encryption key from the Nostr secret key using HKDF-SHA256,
//! avoiding the need for a platform keyring (D-Bus Secret Service, macOS Keychain, etc.).
//! This works on headless servers where no keyring daemon is available.

use anyhow::{Context, Result};
use mdk_sqlite_storage::{EncryptionConfig, MdkSqliteStorage};
use nostr_sdk::prelude::*;
use sha2::{Sha256, Digest};
use std::path::Path;

/// Domain separation string for deriving the DB encryption key.
const HKDF_DOMAIN: &[u8] = b"burrow-cli-mls-db-encryption-v1";

/// Derive a 32-byte encryption key from the Nostr secret key.
///
/// Uses SHA-256(domain || secret_key_bytes) — simple, deterministic,
/// and sufficient since the input already has 256 bits of entropy.
fn derive_db_key(keys: &Keys) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(HKDF_DOMAIN);
    hasher.update(keys.secret_key().as_secret_bytes());
    hasher.finalize().into()
}

/// Open (or create) an encrypted MLS SQLite database.
///
/// The encryption key is deterministically derived from the Nostr identity,
/// so the same key always opens the same database.
pub fn open_mls_storage(db_path: &Path, keys: &Keys) -> Result<MdkSqliteStorage> {
    let key = derive_db_key(keys);
    let config = EncryptionConfig::new(key);

    MdkSqliteStorage::new_with_key(db_path, config)
        .context("Failed to open encrypted MLS database")
}
