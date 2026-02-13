//! Global application state for Burrow's MDK instance and Nostr client.

use std::sync::{Arc, OnceLock};
use tokio::sync::RwLock;

pub use mdk_core::MDK;
pub use mdk_memory_storage::MdkMemoryStorage;
pub use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;

/// Global app state holding the MDK instance and Nostr keys.
pub struct BurrowState {
    pub mdk: MDK<MdkMemoryStorage>,
    pub keys: Keys,
    pub client: Client,
}

static INSTANCE: OnceLock<Arc<RwLock<Option<BurrowState>>>> = OnceLock::new();

fn global() -> &'static Arc<RwLock<Option<BurrowState>>> {
    INSTANCE.get_or_init(|| Arc::new(RwLock::new(None)))
}

/// Initialize the global state with a keypair.
pub async fn init_state(keys: Keys) -> Result<(), BurrowError> {
    let mdk = MDK::new(MdkMemoryStorage::default());
    let client = Client::builder().signer(keys.clone()).build();
    let state = BurrowState { mdk, keys, client };
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
