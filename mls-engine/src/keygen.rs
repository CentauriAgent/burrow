//! KeyPackage generation — stateless, mirrors the Flutter app's keygen logic.

use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_memory_storage::MdkMemoryStorage;
use nostr_sdk::prelude::*;
use serde::Serialize;

#[derive(Serialize)]
pub struct KeyPackageResult {
    /// Base64-encoded MLS KeyPackage bytes (goes in kind 443 event content)
    pub key_package_base64: String,
    /// Tags for the kind 443 event, as arrays of strings
    pub tags: Vec<Vec<String>>,
    /// The public key (hex) of the signer
    pub pubkey_hex: String,
}

pub fn generate_key_package(secret_key: &str, relay_urls: &[String]) -> Result<KeyPackageResult> {
    let keys = Keys::parse(secret_key).context("Failed to parse secret key")?;

    let relays: Vec<RelayUrl> = relay_urls
        .iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .collect();

    let mdk = MDK::new(MdkMemoryStorage::default());

    let (kp_base64, tags) = mdk
        .create_key_package_for_event(&keys.public_key(), relays)
        .map_err(|e| anyhow::anyhow!("MDK error: {e}"))?;

    let tags_flat: Vec<Vec<String>> = tags
        .iter()
        .map(|tag| tag.as_slice().to_vec())
        .collect();

    Ok(KeyPackageResult {
        key_package_base64: kp_base64,
        tags: tags_flat,
        pubkey_hex: keys.public_key().to_hex(),
    })
}
