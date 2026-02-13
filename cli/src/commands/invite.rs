use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_memory_storage::MdkMemoryStorage;
use nostr_sdk::prelude::*;
use std::fs;

use crate::acl::access_control::resolve_to_hex;
use crate::config;
use crate::relay::pool;
use crate::storage::file_store::FileStore;

pub async fn run(
    group_id: String,
    invitee: String,
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store.find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let invitee_hex = resolve_to_hex(&invitee)?;

    let kp = key_path.map(std::path::PathBuf::from).unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    // Connect to relays
    let client = pool::connect(&keys, &group.relay_urls).await?;

    // Fetch invitee's KeyPackage (kind 443)
    let invitee_pk = PublicKey::from_hex(&invitee_hex)?;
    let filter = Filter::new()
        .author(invitee_pk)
        .kind(Kind::MlsKeyPackage)
        .limit(1);

    println!("🔍 Fetching KeyPackage for {}...", &invitee_hex[..12]);
    let events = client.fetch_events(filter, std::time::Duration::from_secs(10)).await
        .context("Failed to fetch KeyPackage")?;

    let kp_event = events.into_iter().next()
        .context(format!("No KeyPackage found for {}", invitee_hex))?;

    // Add member via MDK
    let mdk = MDK::new(MdkMemoryStorage::default());
    let mls_group_id = mdk_core::prelude::GroupId::from_slice(
        &hex::decode(&group.mls_group_id_hex)?
    );

    let result = mdk.add_members(&mls_group_id, &[kp_event.clone()])
        .context("Failed to add member")?;

    // Publish evolution event (kind 445)
    let evolution_json = serde_json::to_string(&result.evolution_event)?;
    let evolution_event: Event = serde_json::from_str(&evolution_json)?;
    let output = client.send_event(&evolution_event).await
        .context("Failed to publish evolution event")?;
    println!("📤 Evolution event published: {}", output.id().to_hex());

    // Merge pending commit
    mdk.merge_pending_commit(&mls_group_id)?;

    // Send Welcome via NIP-59 gift wrap
    for rumor in result.welcome_rumors.iter().flatten() {
        let _rumor_str = serde_json::to_string(rumor)?;
        println!("📨 Welcome rumor prepared for {}", &invitee_hex[..12]);
        // TODO: NIP-59 gift wrap and send
    }

    println!("✅ Invited {} to group {}", &invitee_hex[..12], group.name);
    client.disconnect().await;
    Ok(())
}
