//! Identity management: import/export keys, manage display name and profile.
//!
//! Profile fetching follows the White Noise pattern:
//! - `blocking_sync = false`: return from cache immediately (may be empty)
//! - `blocking_sync = true`: query relays and wait for result

use std::time::Duration;

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

impl ProfileData {
    /// Returns true if all meaningful display fields are empty.
    #[frb(ignore)]
    pub fn is_empty(&self) -> bool {
        self.name.is_none()
            && self.display_name.is_none()
            && self.picture.is_none()
    }

    /// Build from nostr_sdk Metadata.
    #[frb(ignore)]
    pub fn from_metadata(m: &Metadata) -> Self {
        ProfileData {
            name: m.name.clone(),
            display_name: m.display_name.clone(),
            about: m.about.clone(),
            picture: m.picture.as_ref().map(|u| u.to_string()),
            nip05: m.nip05.clone(),
            lud16: m.lud16.clone(),
        }
    }

    /// Convert to nostr_sdk Metadata.
    #[frb(ignore)]
    pub fn to_metadata(&self) -> Result<Metadata, BurrowError> {
        let mut metadata = Metadata::new();
        if let Some(ref name) = self.name {
            metadata = metadata.name(name);
        }
        if let Some(ref display_name) = self.display_name {
            metadata = metadata.display_name(display_name);
        }
        if let Some(ref about) = self.about {
            metadata = metadata.about(about);
        }
        if let Some(ref picture) = self.picture {
            metadata = metadata.picture(
                Url::parse(picture).map_err(|e| BurrowError::from(e.to_string()))?,
            );
        }
        if let Some(ref nip05) = self.nip05 {
            metadata = metadata.nip05(nip05);
        }
        if let Some(ref lud16) = self.lud16 {
            metadata = metadata.lud16(lud16);
        }
        Ok(metadata)
    }

    /// Best display name: prefers display_name, falls back to name.
    #[frb(ignore)]
    pub fn best_name(&self) -> Option<String> {
        self.display_name
            .clone()
            .or_else(|| self.name.clone())
    }
}

/// Publish a kind 0 metadata event to connected relays.
#[frb]
pub async fn set_profile(profile: ProfileData) -> Result<(), BurrowError> {
    let metadata = profile.to_metadata()?;
    // Clone the client out so we can drop the state lock before awaiting
    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    let builder = EventBuilder::metadata(&metadata);
    client
        .send_event_builder(builder)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    // Update cache with our own profile
    let pubkey_hex = state::with_state(|s| Ok(s.keys.public_key().to_hex())).await?;
    state::with_state_mut(|s| {
        s.profile_cache.insert(pubkey_hex, profile);
        Ok(())
    })
    .await
}

/// Fetch the metadata for a given pubkey.
///
/// - `blocking_sync = false`: return cached data immediately (may be empty).
/// - `blocking_sync = true`: query connected relays and wait up to 10 seconds.
///
/// Follows the White Noise two-step pattern: Flutter calls with false first,
/// then with true only if the result is empty.
#[frb]
pub async fn fetch_profile(
    pubkey_hex: String,
    blocking_sync: bool,
) -> Result<ProfileData, BurrowError> {
    // Check cache first
    let cached = state::with_state(|s| {
        Ok(s.profile_cache.get(&pubkey_hex).cloned())
    })
    .await?;

    if !blocking_sync {
        return Ok(cached.unwrap_or_default());
    }

    // If cache has data and we're not forcing refresh, return it
    if let Some(ref profile) = cached {
        if !profile.is_empty() {
            return Ok(profile.clone());
        }
    }

    // Query relays for kind 0 metadata
    let pubkey =
        PublicKey::parse(&pubkey_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    // Clone client out, drop the lock, then do async relay query
    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    let filter = Filter::new()
        .kind(Kind::Metadata)
        .author(pubkey)
        .limit(1);
    let events = client
        .fetch_events(filter, Duration::from_secs(10))
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    let profile = if let Some(event) = events.into_iter().next() {
        let metadata = Metadata::from_json(&event.content)
            .map_err(|e| BurrowError::from(e.to_string()))?;
        ProfileData::from_metadata(&metadata)
    } else {
        ProfileData::default()
    };

    // Store in cache
    if !profile.is_empty() {
        let pk_hex = pubkey_hex.clone();
        let cached_profile = profile.clone();
        state::with_state_mut(|s| {
            s.profile_cache.insert(pk_hex, cached_profile);
            Ok(())
        })
        .await?;
    }

    Ok(profile)
}

/// Fetch relay list (NIP-65 kind 10002) for a given pubkey.
/// Returns a list of relay URLs.
#[frb]
pub async fn fetch_user_relays(pubkey_hex: String) -> Result<Vec<String>, BurrowError> {
    let pubkey =
        PublicKey::parse(&pubkey_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    let filter = Filter::new()
        .kind(Kind::RelayList)
        .author(pubkey)
        .limit(1);
    let events = client
        .fetch_events(filter, Duration::from_secs(10))
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    if let Some(event) = events.into_iter().next() {
        let urls: Vec<String> = event
            .tags
            .iter()
            .filter(|t| t.kind() == TagKind::single_letter(Alphabet::R, false))
            .filter_map(|t| t.content().map(|s| s.to_string()))
            .collect();
        Ok(urls)
    } else {
        Ok(vec![])
    }
}

/// Bootstrap a newly imported identity: connect default relays, fetch own
/// profile (kind 0) and relay list (NIP-65 kind 10002), then add user's
/// relays if found.
#[frb]
pub async fn bootstrap_identity() -> Result<ProfileData, BurrowError> {
    let (pubkey_hex, client) = state::with_state(|s| {
        Ok((s.keys.public_key().to_hex(), s.client.clone()))
    }).await?;

    // Add default relays and connect (non-blocking, nostr-sdk auto-reconnects)
    let defaults = crate::api::relay::default_relay_urls();
    for url in &defaults {
        let _ = crate::api::relay::add_relay(url.clone()).await;
    }
    client.connect().await;

    // Brief pause for initial handshakes
    tokio::time::sleep(std::time::Duration::from_millis(500)).await;

    // Non-blocking profile fetch (cache only — fast)
    let profile = fetch_profile(pubkey_hex.clone(), false).await.unwrap_or_default();

    // Background: fetch NIP-65 relays + blocking profile (don't hold up startup)
    let client_bg = client.clone();
    let pubkey_bg = pubkey_hex.clone();
    tokio::spawn(async move {
        // Fetch user's relay list and add those relays
        if let Ok(user_relays) = fetch_user_relays(pubkey_bg.clone()).await {
            for url in &user_relays {
                let _ = crate::api::relay::add_relay(url.clone()).await;
            }
            client_bg.connect().await;
        }
        // Try blocking profile fetch to warm the cache for next time
        let _ = fetch_profile(pubkey_bg, true).await;
    });

    Ok(profile)
}

/// Look up a cached profile without any relay queries. Returns empty if not cached.
#[frb]
pub async fn get_cached_profile(pubkey_hex: String) -> Result<ProfileData, BurrowError> {
    state::with_state(|s| {
        Ok(s.profile_cache.get(&pubkey_hex).cloned().unwrap_or_default())
    })
    .await
}
