use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_memory_storage::MdkMemoryStorage;
use nostr_sdk::prelude::*;
use std::fs;

use crate::config;
use crate::storage::file_store::{FileStore, StoredGroup};

pub async fn create(
    name: String,
    description: Option<String>,
    key_path: Option<String>,
    data_dir: Option<String>,
    relays: Option<Vec<String>>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let kp = key_path.map(std::path::PathBuf::from).unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let secret = secret.trim();
    let sk = SecretKey::from_hex(secret)
        .or_else(|_| SecretKey::from_bech32(secret))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);
    let pubkey = keys.public_key();

    let relay_urls = relays.unwrap_or_else(config::default_relays);
    let relay_parsed: Vec<RelayUrl> = relay_urls.iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .collect();

    let mdk = MDK::new(MdkMemoryStorage::default());
    let desc = description.unwrap_or_default();

    let config = mdk_core::groups::NostrGroupConfigData::new(
        name.clone(),
        desc.clone(),
        None, None, None,
        relay_parsed,
        vec![pubkey],
    );

    let result = mdk.create_group(&pubkey, vec![], config)
        .context("Failed to create group")?;

    let mls_id_hex = hex::encode(result.group.mls_group_id.as_slice());
    let nostr_id_hex = hex::encode(result.group.nostr_group_id);

    // Persist group metadata
    let stored = StoredGroup {
        mls_group_id_hex: mls_id_hex.clone(),
        nostr_group_id_hex: nostr_id_hex.clone(),
        name: name.clone(),
        description: desc,
        admin_pubkeys: vec![pubkey.to_hex()],
        relay_urls: relay_urls.clone(),
        created_at: chrono::Utc::now().timestamp() as u64,
    };
    store.save_group(&stored)?;

    println!("✅ Group created: {}", name);
    println!("   MLS ID:   {}", mls_id_hex);
    println!("   Nostr ID: {}", nostr_id_hex);

    Ok(())
}

pub fn list(data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;
    let groups = store.load_groups()?;

    if groups.is_empty() {
        println!("No groups found. Create one with: burrow group create <name>");
        return Ok(());
    }

    println!("📋 Groups ({}):", groups.len());
    for g in &groups {
        println!("  {} (nostr: {}..)", g.name, &g.nostr_group_id_hex[..12.min(g.nostr_group_id_hex.len())]);
        println!("    MLS: {}", g.mls_group_id_hex);
    }
    Ok(())
}
