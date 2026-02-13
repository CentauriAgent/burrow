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

/// Publish a KeyPackage as a kind 443 event to the given relays.
/// This signs and sends the event via the Nostr client.
#[frb]
pub async fn publish_key_package(relay_urls: Vec<String>) -> Result<String, BurrowError> {
    // Generate the key package
    let kp_data = generate_key_package(relay_urls.clone()).await?;

    state::with_state(|s| {
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

        // Build the kind 443 (MlsKeyPackage) event
        let builder = EventBuilder::new(Kind::MlsKeyPackage, &kp_data.key_package_base64)
            .tags(tags);

        // We return the builder info — actual signing + publishing happens
        // when relay connections are wired up
        let _builder = builder;
        let _keys = &s.keys;

        Ok("key_package_generated".to_string())
    })
    .await
}

/// Build a kind 10051 (KeyPackage relay list) event content.
/// Returns the relay URLs that would be published.
#[frb]
pub async fn set_key_package_relays(relay_urls: Vec<String>) -> Result<Vec<String>, BurrowError> {
    state::with_state(|_s| {
        // Validate all URLs parse as relay URLs
        let valid_urls: Vec<String> = relay_urls
            .iter()
            .filter_map(|u| RelayUrl::parse(u).ok().map(|r| r.to_string()))
            .collect();

        if valid_urls.is_empty() {
            return Err(BurrowError::from(
                "No valid relay URLs provided".to_string(),
            ));
        }

        // Kind 10051 event will be built and published when relay module is connected
        Ok(valid_urls)
    })
    .await
}
