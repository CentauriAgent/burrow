//! KeyPackage management: generate, publish (kind 443), and manage KeyPackage relay lists (kind 10051).

use flutter_rust_bridge::frb;
use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;
use crate::api::state;

/// A KeyPackage event ready to be published, flattened for FFI.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct KeyPackageData {
    /// Base64-encoded MLS KeyPackage bytes (content of kind 443 event).
    pub key_package_base64: String,
    /// Tags for the event as flat string pairs.
    pub tags: Vec<Vec<String>>,
}

/// Generate a new MLS KeyPackage for the current account.
/// Returns the data needed to create a kind 443 Nostr event.
#[frb]
pub async fn generate_key_package(relay_urls: Vec<String>) -> Result<KeyPackageData, BurrowError> {
    state::with_state(|s| {
        let relays: Vec<RelayUrl> = relay_urls
            .iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect();

        let (kp_base64, tags) = s
            .mdk
            .create_key_package_for_event(&s.keys.public_key(), relays)
            .map_err(BurrowError::from)?;

        let tags_flat: Vec<Vec<String>> = tags
            .iter()
            .map(|tag| tag.as_slice().to_vec())
            .collect();

        Ok(KeyPackageData {
            key_package_base64: kp_base64,
            tags: tags_flat,
        })
    })
    .await
}

/// Publish a KeyPackage as a kind 443 event to connected relays.
/// Signs and sends the event, returns the event ID hex.
#[frb]
pub async fn publish_key_package(relay_urls: Vec<String>) -> Result<String, BurrowError> {
    let kp_data = generate_key_package(relay_urls).await?;

    // Reconstruct tags
    let tags: Vec<Tag> = kp_data
        .tags
        .iter()
        .filter_map(|t| {
            if t.len() >= 2 {
                Some(Tag::custom(
                    TagKind::from(t[0].as_str()),
                    t[1..].to_vec(),
                ))
            } else {
                None
            }
        })
        .collect();

    // Build and publish the kind 443 event
    let builder = EventBuilder::new(Kind::MlsKeyPackage, &kp_data.key_package_base64)
        .tags(tags);

    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    let output = client
        .send_event_builder(builder)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    Ok(output.id().to_hex())
}

/// Publish a kind 10051 (KeyPackage relay list) event to connected relays.
/// This tells other users which relays to find our key packages on.
#[frb]
pub async fn publish_key_package_relays(relay_urls: Vec<String>) -> Result<String, BurrowError> {
    let tags: Vec<Tag> = relay_urls
        .iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .map(|r| Tag::relay(r))
        .collect();

    if tags.is_empty() {
        return Err(BurrowError::from("No valid relay URLs provided".to_string()));
    }

    let builder = EventBuilder::new(Kind::Custom(10051), "")
        .tags(tags);

    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    let output = client
        .send_event_builder(builder)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    Ok(output.id().to_hex())
}
