use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_memory_storage::MdkMemoryStorage;
use nostr_sdk::prelude::*;
use std::fs;

use crate::config;
use crate::relay::pool;
use crate::storage::file_store::FileStore;

pub async fn run(key_path: Option<String>, data_dir: Option<String>, relays: Option<Vec<String>>, generate: bool) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    fs::create_dir_all(&data)?;
    let store = FileStore::new(&data)?;

    // Load or generate keys
    let kp = key_path.map(std::path::PathBuf::from).unwrap_or_else(config::default_key_path);
    let keys = if kp.exists() {
        let secret = fs::read_to_string(&kp)
            .context("Failed to read secret key")?
            .trim()
            .to_string();
        // Try hex first, then nsec
        if let Ok(sk) = SecretKey::from_hex(&secret) {
            Keys::new(sk)
        } else {
            let sk = SecretKey::from_bech32(&secret)
                .context("Invalid secret key (not hex or nsec)")?;
            Keys::new(sk)
        }
    } else if generate {
        let keys = Keys::generate();
        fs::create_dir_all(kp.parent().unwrap())?;
        fs::write(&kp, keys.secret_key().to_secret_hex())?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&kp, fs::Permissions::from_mode(0o600))?;
        }
        println!("🔑 Generated new identity: {}", keys.public_key().to_bech32()?);
        keys
    } else {
        anyhow::bail!("No secret key found at {}. Use --generate to create one.", kp.display());
    };

    let pubkey = keys.public_key();
    println!("🦫 Identity: {}", pubkey.to_bech32()?);
    println!("   Hex:      {}", pubkey.to_hex());

    // Initialize MDK
    let mdk = MDK::new(MdkMemoryStorage::default());

    // Generate KeyPackage
    let relay_urls = relays.unwrap_or_else(config::default_relays);
    let relay_parsed: Vec<RelayUrl> = relay_urls.iter()
        .filter_map(|u| RelayUrl::parse(u).ok())
        .collect();

    let (kp_base64, tags, _hash_ref) = mdk.create_key_package_for_event(&pubkey, relay_parsed)
        .context("Failed to create KeyPackage")?;

    println!("📦 KeyPackage generated");

    // Connect to relays and publish kind 443
    let client = pool::connect(&keys, &relay_urls).await?;

    let nostr_tags: Vec<Tag> = tags.iter()
        .filter_map(|t| {
            let s = t.as_slice();
            if s.len() >= 2 {
                Some(Tag::custom(TagKind::from(s[0].as_str()), s[1..].to_vec()))
            } else {
                None
            }
        })
        .collect();

    let builder = EventBuilder::new(Kind::MlsKeyPackage, &kp_base64).tags(nostr_tags);
    let output = client.send_event_builder(builder).await
        .context("Failed to publish KeyPackage")?;

    println!("✅ KeyPackage published: {}", output.id().to_hex());
    println!("   Relays: {}", relay_urls.join(", "));

    client.disconnect().await;
    Ok(())
}
