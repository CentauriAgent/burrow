use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_sqlite_storage::MdkSqliteStorage;

use crate::config;
use crate::media;
use crate::storage::file_store::FileStore;

pub async fn run(group_id: String, limit: usize, data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store
        .find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let messages = store.load_messages(&group.mls_group_id_hex, limit)?;

    if messages.is_empty() {
        println!("No messages in group '{}'.", group.name);
        return Ok(());
    }

    let media_dir = data.join("media");

    // Create MDK for auto-downloading media
    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = MdkSqliteStorage::new_unencrypted(&mls_db_path)
        .context("Failed to open MLS SQLite database")?;
    let mdk = MDK::new(mdk_storage);

    // Reconstruct GroupId from stored hex
    let mls_group_id_bytes = hex::decode(&group.mls_group_id_hex)?;
    let mls_group_id = mdk_core::prelude::GroupId::from_slice(&mls_group_id_bytes);

    // Auto-download any media not yet on disk
    for msg in &messages {
        media::auto_download_attachments(&mdk, &mls_group_id, &msg.tags, &media_dir).await;
    }

    println!("📨 Messages in '{}' (last {}):", group.name, messages.len());
    for msg in &messages {
        let time = chrono::DateTime::from_timestamp(msg.created_at as i64, 0)
            .map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string())
            .unwrap_or_else(|| "?".into());
        let sender = &msg.author_pubkey_hex[..12.min(msg.author_pubkey_hex.len())];
        let display = media::format_message_with_media(&msg.content, &msg.tags, Some(&media_dir));
        println!("[{}] {}.. : {}", time, sender, display);
    }
    Ok(())
}
