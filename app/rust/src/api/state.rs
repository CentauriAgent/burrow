//! Global application state for Burrow's MDK instance and Nostr client.
//!
//! Uses MdkSqliteStorage for persistent, encrypted MLS group state.
//! Encryption keys are stored in the platform keyring (following White Noise).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;

use flutter_rust_bridge::frb;

pub use mdk_core::MDK;
pub use mdk_sqlite_storage::MdkSqliteStorage;
pub use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;
use crate::api::identity::ProfileData;

const KEYRING_SERVICE_ID: &str = "com.burrow.app";

/// Global app state holding the MDK instance and Nostr keys.
#[frb(ignore)]
pub struct BurrowState {
    pub mdk: MDK<MdkSqliteStorage>,
    pub keys: Keys,
    pub client: Client,
    /// In-memory cache of Nostr profile metadata (kind 0), keyed by pubkey hex.
    pub profile_cache: HashMap<String, ProfileData>,
}

static INSTANCE: OnceLock<Arc<RwLock<Option<BurrowState>>>> = OnceLock::new();

fn global() -> &'static Arc<RwLock<Option<BurrowState>>> {
    INSTANCE.get_or_init(|| Arc::new(RwLock::new(None)))
}

/// Initialize the platform-specific keyring store (once).
fn initialize_keyring_store() {
    static KEYRING_INIT: OnceLock<()> = OnceLock::new();
    KEYRING_INIT.get_or_init(|| {
        #[cfg(target_os = "linux")]
        {
            let store = linux_keyutils_keyring_store::Store::new()
                .expect("Failed to create Linux keyutils credential store");
            keyring_core::set_default_store(store);
        }
        #[cfg(target_os = "macos")]
        {
            let store = apple_native_keyring_store::keychain::Store::new()
                .expect("Failed to create macOS Keychain credential store");
            keyring_core::set_default_store(store);
        }
        #[cfg(target_os = "ios")]
        {
            let store = apple_native_keyring_store::protected::Store::new()
                .expect("Failed to create iOS protected-data credential store");
            keyring_core::set_default_store(store);
        }
        #[cfg(target_os = "android")]
        {
            let store = android_native_keyring_store::Store::new()
                .expect("Failed to create Android credential store");
            keyring_core::set_default_store(store);
        }
        #[cfg(target_os = "windows")]
        {
            let store = windows_native_keyring_store::Store::new()
                .expect("Failed to create Windows credential store");
            keyring_core::set_default_store(store);
        }
    });
}

/// Set the data directory from Flutter. Must be called before init_state.
static DATA_DIR: OnceLock<PathBuf> = OnceLock::new();

/// Set the application data directory (called from Flutter on startup).
#[frb]
pub fn set_data_dir(path: String) {
    let _ = DATA_DIR.set(PathBuf::from(path));
}

fn get_data_dir() -> Result<PathBuf, BurrowError> {
    DATA_DIR
        .get()
        .cloned()
        .ok_or_else(|| BurrowError::from("Data directory not set. Call set_data_dir first.".to_string()))
}

/// Initialize the global state with a keypair and persistent MLS storage.
pub async fn init_state(keys: Keys) -> Result<(), BurrowError> {
    initialize_keyring_store();

    let data_dir = get_data_dir()?;
    let mls_dir = data_dir.join("mls").join(keys.public_key().to_hex());
    let db_key_id = format!("mdk.db.key.{}", keys.public_key().to_hex());

    let storage = MdkSqliteStorage::new(mls_dir, KEYRING_SERVICE_ID, &db_key_id)
        .map_err(|e| BurrowError::from(format!("Failed to initialize MLS storage: {e}")))?;

    let mdk = MDK::new(storage);
    let client = Client::builder().signer(keys.clone()).build();

    let state = BurrowState {
        mdk,
        keys,
        client,
        profile_cache: HashMap::new(),
    };
    let mut guard = global().write().await;
    *guard = Some(state);
    Ok(())
}

/// Get a read lock on the global state. Returns error if not initialized.
pub async fn with_state<F, T>(f: F) -> Result<T, BurrowError>
where
    F: FnOnce(&BurrowState) -> Result<T, BurrowError>,
{
    let guard = global().read().await;
    let state = guard
        .as_ref()
        .ok_or_else(|| BurrowError::from("Burrow not initialized. Call create_account or login first.".to_string()))?;
    f(state)
}

/// Get a write lock on the global state.
pub async fn with_state_mut<F, T>(f: F) -> Result<T, BurrowError>
where
    F: FnOnce(&mut BurrowState) -> Result<T, BurrowError>,
{
    let mut guard = global().write().await;
    let state = guard
        .as_mut()
        .ok_or_else(|| BurrowError::from("Burrow not initialized. Call create_account or login first.".to_string()))?;
    f(state)
}

/// Check if state is initialized.
pub async fn is_initialized() -> bool {
    let guard = global().read().await;
    guard.is_some()
}

/// Destroy the global state (logout).
pub async fn destroy_state() {
    let mut guard = global().write().await;
    *guard = None;
}
