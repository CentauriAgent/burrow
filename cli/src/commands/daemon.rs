use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_memory_storage::MdkMemoryStorage;
use nostr_sdk::prelude::*;
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;

use crate::acl::access_control::AccessControl;
use crate::acl::audit;
use crate::config;
use crate::relay::pool;
use crate::storage::file_store::{FileStore, StoredMessage};

#[derive(Serialize)]
struct DaemonLogEntry {
    #[serde(rename = "type")]
    entry_type: String,
    timestamp: String,
    #[serde(skip_serializing_if = "Option::is_none", rename = "groupId")]
    group_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "senderPubkey")]
    sender_pubkey: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    allowed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

fn write_jsonl(log_file: &Option<PathBuf>, entry: &DaemonLogEntry) {
    let json = serde_json::to_string(entry).unwrap_or_default();
    println!("{}", json);
    if let Some(path) = log_file {
        if let Ok(mut f) = OpenOptions::new().create(true).append(true).open(path) {
            let _ = writeln!(f, "{}", json);
        }
    }
}

pub async fn run(
    key_path: Option<String>,
    data_dir: Option<String>,
    log_file: Option<String>,
    _reconnect_delay: u64,
    no_access_control: bool,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;
    let log_path = log_file.map(PathBuf::from);

    let kp = key_path.map(PathBuf::from).unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    let acl = if no_access_control {
        None
    } else {
        Some(AccessControl::load(&data)?)
    };

    let groups = store.load_groups()?;
    if groups.is_empty() {
        eprintln!("⚠️ No groups found. Create one first.");
        return Ok(());
    }

    // Collect all relay URLs
    let mut all_relays: Vec<String> = config::default_relays();
    for g in &groups {
        for r in &g.relay_urls {
            if !all_relays.contains(r) {
                all_relays.push(r.clone());
            }
        }
    }

    let client = pool::connect(&keys, &all_relays).await?;
    let mdk = MDK::new(MdkMemoryStorage::default());

    // Subscribe to kind 445 for all groups
    // Build filter with all group IDs — chain custom_tag calls since it takes one value
    let mut filter = Filter::new().kind(Kind::MlsGroupMessage);
    for g in &groups {
        filter = filter.custom_tag(SingleLetterTag::lowercase(Alphabet::H), g.nostr_group_id_hex.clone());
    }

    let startup = DaemonLogEntry {
        entry_type: "startup".into(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        group_id: None,
        sender_pubkey: None,
        content: Some(format!("Listening on {} groups, {} relays", groups.len(), all_relays.len())),
        allowed: None,
        error: None,
    };
    write_jsonl(&log_path, &startup);

    client.subscribe(filter, None).await?;

    let data_clone = data.clone();
    let log_path_clone = log_path.clone();

    client
        .handle_notifications(|notification| async {
            if let RelayPoolNotification::Event { event, .. } = notification {
                if event.kind == Kind::MlsGroupMessage {
                    match mdk.process_message(&event) {
                        Ok(mdk_core::messages::MessageProcessingResult::ApplicationMessage(msg)) => {
                            let sender_hex = msg.pubkey.to_hex();
                            let group_hex = hex::encode(msg.mls_group_id.as_slice());

                            // Find nostr group id for ACL check
                            let nostr_gid = groups.iter()
                                .find(|g| g.mls_group_id_hex == group_hex)
                                .map(|g| g.nostr_group_id_hex.as_str())
                                .unwrap_or("");

                            let allowed = acl.as_ref()
                                .map(|a| a.is_allowed(&sender_hex, nostr_gid))
                                .unwrap_or(true);

                            // Audit
                            if acl.as_ref().map(|a| a.config.settings.audit_enabled).unwrap_or(false) {
                                audit::log_message(&data_clone, &sender_hex, nostr_gid, allowed, None);
                            }

                            let entry = DaemonLogEntry {
                                entry_type: "message".into(),
                                timestamp: chrono::Utc::now().to_rfc3339(),
                                group_id: Some(nostr_gid.to_string()),
                                sender_pubkey: Some(sender_hex.clone()),
                                content: if allowed { Some(msg.content.clone()) } else { None },
                                allowed: Some(allowed),
                                error: None,
                            };
                            write_jsonl(&log_path_clone, &entry);

                            if allowed {
                                let stored = StoredMessage {
                                    event_id_hex: msg.id.to_hex(),
                                    author_pubkey_hex: sender_hex,
                                    content: msg.content.clone(),
                                    created_at: msg.created_at.as_secs(),
                                    mls_group_id_hex: group_hex,
                                    wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
                                    epoch: msg.epoch.unwrap_or(0),
                                };
                                let _ = store.save_message(&stored);
                            }
                        }
                        Ok(_) => {} // commit/proposal — silent
                        Err(e) => {
                            let entry = DaemonLogEntry {
                                entry_type: "decrypt_error".into(),
                                timestamp: chrono::Utc::now().to_rfc3339(),
                                group_id: None,
                                sender_pubkey: None,
                                content: None,
                                allowed: None,
                                error: Some(e.to_string()),
                            };
                            write_jsonl(&log_path_clone, &entry);
                        }
                    }
                }
            }
            Ok(false) // keep listening
        })
        .await?;

    Ok(())
}
