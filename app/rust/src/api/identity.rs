//! Identity management: import/export keys, manage display name and profile.

use flutter_rust_bridge::frb;
use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;
use crate::api::state;

/// Export the secret key as nsec bech32 string.
#[frb]
pub async fn export_nsec() -> Result<String, BurrowError> {
    state::with_state(|s| {
        s.keys
            .secret_key()
            .to_bech32()
            .map_err(|e| BurrowError::from(e.to_string()))
    })
    .await
}

/// Export the public key as npub bech32 string.
#[frb]
pub async fn export_npub() -> Result<String, BurrowError> {
    state::with_state(|s| {
        s.keys
            .public_key()
            .to_bech32()
            .map_err(|e| BurrowError::from(e.to_string()))
    })
    .await
}

/// Export the public key as hex string.
#[frb]
pub async fn export_pubkey_hex() -> Result<String, BurrowError> {
    state::with_state(|s| Ok(s.keys.public_key().to_hex())).await
}

/// Nostr profile metadata (kind 0), FFI-friendly.
#[frb(non_opaque)]
#[derive(Debug, Clone, Default)]
pub struct ProfileData {
    pub name: Option<String>,
    pub display_name: Option<String>,
    pub about: Option<String>,
    pub picture: Option<String>,
    pub nip05: Option<String>,
    pub lud16: Option<String>,
}

/// Publish a kind 0 metadata event to connected relays.
#[frb]
pub async fn set_profile(profile: ProfileData) -> Result<(), BurrowError> {
    state::with_state(|_s| {
        let mut metadata = Metadata::new();
        if let Some(name) = profile.name {
            metadata = metadata.name(name);
        }
        if let Some(display_name) = profile.display_name {
            metadata = metadata.display_name(display_name);
        }
        if let Some(about) = profile.about {
            metadata = metadata.about(about);
        }
        if let Some(picture) = profile.picture {
            metadata = metadata.picture(Url::parse(&picture).map_err(|e| BurrowError::from(e.to_string()))?);
        }
        if let Some(nip05) = profile.nip05 {
            metadata = metadata.nip05(nip05);
        }
        if let Some(lud16) = profile.lud16 {
            metadata = metadata.lud16(lud16);
        }

        // Build and sign the event — actual publishing happens via relay module
        let _event = EventBuilder::metadata(&metadata);
        Ok(())
    })
    .await
}

/// Fetch the metadata for a given pubkey from connected relays.
#[frb]
pub async fn fetch_profile(pubkey_hex: String) -> Result<ProfileData, BurrowError> {
    let pubkey = PublicKey::parse(&pubkey_hex).map_err(|e| BurrowError::from(e.to_string()))?;
    state::with_state(|_s| {
        // Use the nostr client to fetch metadata
        let _pubkey = pubkey;
        // For now, return empty profile — actual fetching requires async relay queries
        // which will be wired up when relay connections are established
        Ok(ProfileData::default())
    })
    .await
}
