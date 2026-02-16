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

const KEYRING_SERVICE: &str = "com.burrow.app";
const KEYRING_NSEC_KEY: &str = "burrow.nsec";

/// Save the current secret key to the platform keyring.
///
/// Uses the OS credential store (D-Bus Secret Service on Linux, Keychain on
/// macOS/iOS, Credential Manager on Android/Windows). The nsec never touches
/// the filesystem.
#[frb]
pub async fn save_secret_key_to_keyring() -> Result<(), BurrowError> {
    state::initialize_keyring_store();
    state::with_state(|s| {
        let nsec = s
            .keys
            .secret_key()
            .to_bech32()
            .map_err(|e| BurrowError::from(e.to_string()))?;

        let entry = keyring_core::Entry::new(KEYRING_SERVICE, KEYRING_NSEC_KEY)
            .map_err(|e| BurrowError::from(format!("Keyring entry: {e}")))?;
        entry
            .set_secret(nsec.as_bytes())
            .map_err(|e| BurrowError::from(format!("Keyring save: {e}")))?;
        Ok(())
    })
    .await
}

/// Load the secret key from the platform keyring and initialize the account.
///
/// Returns the account info if a key was found in the keyring, or an error
/// if no key is stored or the keyring is unavailable.
#[frb]
pub async fn load_account_from_keyring() -> Result<AccountInfo, BurrowError> {
    state::initialize_keyring_store();
    let entry = keyring_core::Entry::new(KEYRING_SERVICE, KEYRING_NSEC_KEY)
        .map_err(|e| BurrowError::from(format!("Keyring entry: {e}")))?;
    let secret_bytes = entry
        .get_secret()
        .map_err(|e| BurrowError::from(format!("Keyring load: {e}")))?;
    let nsec = String::from_utf8(secret_bytes)
        .map_err(|e| BurrowError::from(format!("Keyring decode: {e}")))?;
    login(nsec.trim().to_string()).await
}

/// Delete the secret key from the platform keyring (logout).
#[frb]
pub async fn delete_secret_key_from_keyring() -> Result<(), BurrowError> {
    state::initialize_keyring_store();
    if let Ok(entry) = keyring_core::Entry::new(KEYRING_SERVICE, KEYRING_NSEC_KEY) {
        let _ = entry.delete_credential(); // Ignore errors (key might not exist)
    }
    Ok(())
}

/// Check if a secret key exists in the platform keyring.
#[frb]
pub async fn has_keyring_account() -> bool {
    state::initialize_keyring_store();
    if let Ok(entry) = keyring_core::Entry::new(KEYRING_SERVICE, KEYRING_NSEC_KEY) {
        entry.get_secret().is_ok()
    } else {
        false
    }
}

// --- Legacy file-based functions (kept for migration) ---

/// Save the current secret key to a file (DEPRECATED — use save_secret_key_to_keyring).
#[frb]
pub async fn save_secret_key(file_path: String) -> Result<(), BurrowError> {
    if file_path.contains("..") {
        return Err(BurrowError::from("Invalid file path: path traversal detected".to_string()));
    }
    state::with_state(|s| {
        let nsec = s
            .keys
            .secret_key()
            .to_bech32()
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let path = Path::new(&file_path);
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(BurrowError::from)?;
        }
        std::fs::write(path, nsec.as_bytes()).map_err(BurrowError::from)?;
        Ok(())
    })
    .await
}

/// Load a secret key from a file (DEPRECATED — use load_account_from_keyring).
#[frb]
pub async fn load_account_from_file(file_path: String) -> Result<AccountInfo, BurrowError> {
    if file_path.contains("..") {
        return Err(BurrowError::from("Invalid file path: path traversal detected".to_string()));
    }
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
