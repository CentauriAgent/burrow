use anyhow::{Context, Result};
use mdk_core::MDK;
use nostr_sdk::prelude::*;
use std::collections::HashSet;
use std::fs;
use std::sync::{Arc, Mutex};

use crate::config;
use crate::keyring;
use crate::relay::pool;
use crate::storage::file_store::{FileStore, StoredMessage};

pub async fn run(
    group_id: String,
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

    let client = pool::connect(&keys, &group.relay_urls).await?;
    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = keyring::open_mls_storage(&mls_db_path, &keys)?;
    let mdk = MDK::new(mdk_storage);

    // Subscribe to kind 445 for this group (only new events from now)
    let nostr_gid = &group.nostr_group_id_hex;
    let filter = Filter::new()
        .kind(Kind::MlsGroupMessage)
        .since(Timestamp::now())
        .custom_tag(SingleLetterTag::lowercase(Alphabet::H), nostr_gid.to_string());

    println!("👂 Listening for messages in '{}' ({}..)", group.name, &nostr_gid[..12]);
    println!("   Press Ctrl+C to stop.");

    client.subscribe(filter, None).await?;
    let seen_events: Arc<Mutex<HashSet<EventId>>> = Arc::new(Mutex::new(HashSet::new()));

    // Process events
    client
        .handle_notifications(|notification| async {
            if let RelayPoolNotification::Event { event, .. } = notification {
                // Deduplicate: skip events already seen from other relays
                {
                    let mut seen = seen_events.lock().unwrap();
                    if !seen.insert(event.id) {
                        return Ok(false);
                    }
                    if seen.len() > 10_000 {
                        seen.clear();
                    }
                }
                if event.kind == Kind::MlsGroupMessage {
                    match mdk.process_message(&event) {
                        Ok(mdk_core::messages::MessageProcessingResult::ApplicationMessage(msg)) => {
                            let time = chrono::DateTime::from_timestamp(msg.created_at.as_secs() as i64, 0)
                                .map(|t| t.format("%H:%M:%S").to_string())
                                .unwrap_or_else(|| "?".into());
                            let sender = &msg.pubkey.to_hex()[..12];
                            let tags: Vec<Vec<String>> = msg.tags.iter()
                                .map(|t| t.as_slice().to_vec())
                                .collect();
                            let media_dir = data.join("media");

                            // Auto-download encrypted media attachments
                            crate::media::auto_download_attachments(
                                &mdk, &msg.mls_group_id, &tags, &media_dir,
                            ).await;

                            let display = crate::media::format_message_with_media(
                                &msg.content, &tags, Some(&media_dir),
                            );
                            println!("[{}] {}.. : {}", time, sender, display);

                            // Persist
                            let stored = StoredMessage {
                                event_id_hex: msg.id.to_hex(),
                                author_pubkey_hex: msg.pubkey.to_hex(),
                                content: msg.content.clone(),
                                created_at: msg.created_at.as_secs(),
                                mls_group_id_hex: hex::encode(msg.mls_group_id.as_slice()),
                                wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
                                epoch: msg.epoch.unwrap_or(0),
                                tags,
                            };
                            let _ = store.save_message(&stored);
                        }
                        Ok(_) => {} // commit/proposal — silent
                        Err(e) => eprintln!("⚠️ decrypt error: {}", e),
                    }
                }
            }
            Ok(false) // keep listening
        })
        .await?;

    Ok(())
}
