use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_sqlite_storage::MdkSqliteStorage;
use nostr_sdk::prelude::*;
use std::fs;

use crate::acl::access_control::AccessControl;
use crate::config;
use crate::relay::pool;
use crate::storage::file_store::FileStore;

pub async fn run(
    group_id: String,
    message: String,
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store.find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let kp = key_path.map(std::path::PathBuf::from).unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    // ACL check on outgoing
    let acl = AccessControl::load(&data)?;
    if !acl.is_allowed(&keys.public_key().to_hex(), &group.nostr_group_id_hex) {
        anyhow::bail!("ACL: not allowed to send to this group");
    }

    // Use SQLite storage (same as daemon) instead of in-memory
    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = MdkSqliteStorage::new_unencrypted(&mls_db_path)
        .context("Failed to open MLS SQLite database")?;
    let mdk = MDK::new(mdk_storage);
    let mls_group_id = mdk_core::prelude::GroupId::from_slice(
        &hex::decode(&group.mls_group_id_hex)?
    );

    // Build rumor and encrypt
    let rumor = EventBuilder::new(Kind::TextNote, &message)
        .build(keys.public_key());

    let event = mdk.create_message(&mls_group_id, rumor)
        .context("Failed to encrypt message")?;

    // Publish to relays
    let client = pool::connect(&keys, &group.relay_urls).await?;
    let output = client.send_event(&event).await
        .context("Failed to publish message")?;

    println!("✅ Sent to {} ({})", group.name, output.id().to_hex());
    client.disconnect().await;
    Ok(())
}
