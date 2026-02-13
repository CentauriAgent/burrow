use anyhow::{Context, Result};

use crate::config;
use crate::storage::file_store::FileStore;

pub fn run(group_id: String, limit: usize, data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store.find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let messages = store.load_messages(&group.mls_group_id_hex, limit)?;

    if messages.is_empty() {
        println!("No messages in group '{}'.", group.name);
        return Ok(());
    }

    println!("📨 Messages in '{}' (last {}):", group.name, messages.len());
    for msg in &messages {
        let time = chrono::DateTime::from_timestamp(msg.created_at as i64, 0)
            .map(|t| t.format("%Y-%m-%d %H:%M:%S").to_string())
            .unwrap_or_else(|| "?".into());
        let sender = &msg.author_pubkey_hex[..12.min(msg.author_pubkey_hex.len())];
        println!("[{}] {}.. : {}", time, sender, msg.content);
    }
    Ok(())
}
