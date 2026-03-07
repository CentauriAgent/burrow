use anyhow::{Context, Result};
use mdk_core::MDK;
use nostr_sdk::prelude::*;
use std::fs;

use crate::config;
use crate::keyring;
use crate::relay::pool;
use crate::storage::file_store::FileStore;

/// Kind 15 — Read receipt (inside MLS-encrypted rumor).
const READ_RECEIPT_KIND: u16 = 15;

/// Send read receipts for one or more messages in a group.
///
/// Creates a kind 15 MLS application message with `e` tags referencing
/// the event IDs of messages that have been read. The receipt is encrypted
/// via MLS + NIP-44, so relays see only a standard kind 445 event.
pub async fn run(
    group_id: String,
    message_ids: Vec<String>,
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<()> {
    if message_ids.is_empty() {
        anyhow::bail!("At least one message ID is required");
    }

    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store
        .find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let kp = key_path
        .map(std::path::PathBuf::from)
        .unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = keyring::open_mls_storage(&mls_db_path, &keys)?;
    let mdk = MDK::new(mdk_storage);
    let mls_group_id =
        mdk_core::prelude::GroupId::from_slice(&hex::decode(&group.mls_group_id_hex)?);

    // Build kind 15 rumor with e-tags for each read message
    let mut builder = EventBuilder::new(Kind::Custom(READ_RECEIPT_KIND), "");
    for msg_id in &message_ids {
        let event_id =
            EventId::from_hex(msg_id).context(format!("Invalid event ID: {}", msg_id))?;
        builder = builder.tag(Tag::event(event_id));
    }
    let rumor = builder.build(keys.public_key());

    let event = mdk
        .create_message(&mls_group_id, rumor)
        .context("Failed to encrypt read receipt")?;

    let client = pool::connect(&keys, &group.relay_urls).await?;
    let output = client
        .send_event(&event)
        .await
        .context("Failed to publish read receipt")?;

    println!(
        "✅ Read receipt sent for {} message(s) in {} ({})",
        message_ids.len(),
        group.name,
        output.id().to_hex()
    );
    client.disconnect().await;
    Ok(())
}
