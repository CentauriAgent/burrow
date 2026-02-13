//! Account management: create/load Nostr keypairs, initialize MDK.

use flutter_rust_bridge::frb;
use nostr_sdk::prelude::*;
use std::path::Path;

use crate::api::error::BurrowError;
use crate::api::state;

/// Information about the current account (FFI-friendly).
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct AccountInfo {
    /// Hex-encoded public key.
    pub pubkey_hex: String,
    /// Bech32-encoded public key (npub...).
    pub npub: String,
}

/// Create a new identity with a fresh random keypair.
/// Initializes the MDK instance and Nostr client.
#[frb]
pub async fn create_account() -> Result<AccountInfo, BurrowError> {
    let keys = Keys::generate();
    let info = AccountInfo {
        pubkey_hex: keys.public_key().to_hex(),
        npub: keys.public_key().to_bech32().map_err(|e| BurrowError::from(e.to_string()))?,
    };
    state::init_state(keys).await?;
    Ok(info)
}

/// Login with an existing secret key (nsec bech32 or hex format).
/// Initializes the MDK instance and Nostr client.
#[frb]
pub async fn login(secret_key: String) -> Result<AccountInfo, BurrowError> {
    let keys = Keys::parse(&secret_key).map_err(|e| BurrowError::from(e.to_string()))?;
    let info = AccountInfo {
        pubkey_hex: keys.public_key().to_hex(),
        npub: keys.public_key().to_bech32().map_err(|e| BurrowError::from(e.to_string()))?,
    };
    state::init_state(keys).await?;
    Ok(info)
}

/// Save the current secret key to a file (encrypted path recommended).
/// The caller should provide a secure filesystem path.
#[frb]
pub async fn save_secret_key(file_path: String) -> Result<(), BurrowError> {
    state::with_state(|s| {
        let nsec = s
            .keys
            .secret_key()
            .to_bech32()
            .map_err(|e| BurrowError::from(e.to_string()))?;
        std::fs::write(Path::new(&file_path), nsec.as_bytes())
            .map_err(BurrowError::from)
    })
    .await
}

/// Load a secret key from a file and initialize the account.
#[frb]
pub async fn load_account_from_file(file_path: String) -> Result<AccountInfo, BurrowError> {
    let content = std::fs::read_to_string(Path::new(&file_path))
        .map_err(BurrowError::from)?;
    login(content.trim().to_string()).await
}

/// Get the current account info, or error if not logged in.
#[frb]
pub async fn get_current_account() -> Result<AccountInfo, BurrowError> {
    state::with_state(|s| {
        Ok(AccountInfo {
            pubkey_hex: s.keys.public_key().to_hex(),
            npub: s.keys.public_key().to_bech32().map_err(|e| BurrowError::from(e.to_string()))?,
        })
    })
    .await
}

/// Logout and destroy all in-memory state.
#[frb]
pub async fn logout() -> Result<(), BurrowError> {
    state::destroy_state().await;
    Ok(())
}

/// Check if an account is currently active.
#[frb]
pub async fn is_logged_in() -> bool {
    state::is_initialized().await
}
