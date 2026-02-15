use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_sqlite_storage::MdkSqliteStorage;
use mdk_storage_traits::welcomes::types::WelcomeState;
use nostr_sdk::prelude::*;
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::sync::Arc;

use crate::acl::access_control::AccessControl;
use crate::acl::audit;
use crate::config;
use crate::relay::pool;
use crate::storage::file_store::{FileStore, StoredGroup, StoredMessage};

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
        eprintln!("ℹ️ No groups yet — listening for invites only.");
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
    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = MdkSqliteStorage::new_unencrypted(&mls_db_path)
        .context("Failed to open MLS SQLite database")?;
    let mdk = MDK::new(mdk_storage);

    // Generate a KeyPackage so MDK has the private key material for processing Welcomes.
    // Without this, process_welcome fails with "No matching key package was found in the key store."
    {
        let relay_parsed: Vec<RelayUrl> = all_relays.iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect();
        match mdk.create_key_package_for_event(&keys.public_key(), relay_parsed) {
            Ok((kp_base64, kp_tags)) => {
                // Publish the fresh KeyPackage to relays
                let nostr_tags: Vec<Tag> = kp_tags.iter()
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
                match client.send_event_builder(builder).await {
                    Ok(output) => {
                        let entry = DaemonLogEntry {
                            entry_type: "keygen".into(),
                            timestamp: chrono::Utc::now().to_rfc3339(),
                            group_id: None,
                            sender_pubkey: None,
                            content: Some(format!("KeyPackage published: {}", output.id().to_hex())),
                            allowed: None,
                            error: None,
                        };
                        write_jsonl(&log_path, &entry);
                    }
                    Err(e) => {
                        eprintln!("⚠️ Failed to publish KeyPackage: {}", e);
                    }
                }
            }
            Err(e) => {
                eprintln!("⚠️ Failed to generate KeyPackage: {}", e);
            }
        }
    }

    // Subscribe to kind 445 for all groups
    let mut filter = Filter::new().kind(Kind::MlsGroupMessage);
    for g in &groups {
        filter = filter.custom_tag(SingleLetterTag::lowercase(Alphabet::H), g.nostr_group_id_hex.clone());
    }

    // Subscribe to kind 1059 (NIP-59 gift wraps) tagged with our pubkey for welcomes
    let gift_wrap_filter = Filter::new()
        .kind(Kind::GiftWrap)
        .custom_tag(SingleLetterTag::lowercase(Alphabet::P), keys.public_key().to_hex());

    let startup = DaemonLogEntry {
        entry_type: "startup".into(),
        timestamp: chrono::Utc::now().to_rfc3339(),
        group_id: None,
        sender_pubkey: None,
        content: Some(format!("Listening on {} groups, {} relays + NIP-59 gift wraps", groups.len(), all_relays.len())),
        allowed: None,
        error: None,
    };
    write_jsonl(&log_path, &startup);

    client.subscribe(filter, None).await?;
    client.subscribe(gift_wrap_filter, None).await?;

    let data_clone = data.clone();
    let log_path_clone = log_path.clone();
    let keys_clone = keys.clone();
    let store_clone = Arc::new(store);

    client
        .handle_notifications(|notification| async {
            if let RelayPoolNotification::Event { event, .. } = notification {
                // Handle NIP-59 gift wraps (kind 1059) — Welcome messages
                if event.kind == Kind::GiftWrap {
                    match nip59::extract_rumor(&keys_clone, &event).await {
                        Ok(unwrapped) => {
                            if unwrapped.rumor.kind == Kind::Custom(444) {
                                let entry = DaemonLogEntry {
                                    entry_type: "gift_wrap_received".into(),
                                    timestamp: chrono::Utc::now().to_rfc3339(),
                                    group_id: None,
                                    sender_pubkey: Some(unwrapped.sender.to_hex()),
                                    content: Some("Kind 444 Welcome rumor received".into()),
                                    allowed: None,
                                    error: None,
                                };
                                write_jsonl(&log_path_clone, &entry);

                                // Process welcome via MDK
                                match mdk.process_welcome(&event.id, &unwrapped.rumor) {
                                    Ok(welcome) => {
                                        // Skip already-accepted welcomes (re-delivered by relays after restart)
                                        if welcome.state == WelcomeState::Accepted {
                                            let skip_entry = DaemonLogEntry {
                                                entry_type: "welcome_skipped".into(),
                                                timestamp: chrono::Utc::now().to_rfc3339(),
                                                group_id: Some(hex::encode(&welcome.nostr_group_id)),
                                                sender_pubkey: Some(unwrapped.sender.to_hex()),
                                                content: Some(format!(
                                                    "Already accepted welcome to '{}', skipping",
                                                    welcome.group_name
                                                )),
                                                allowed: None,
                                                error: None,
                                            };
                                            write_jsonl(&log_path_clone, &skip_entry);
                                        } else {
                                        let welcome_entry = DaemonLogEntry {
                                            entry_type: "welcome_processed".into(),
                                            timestamp: chrono::Utc::now().to_rfc3339(),
                                            group_id: Some(hex::encode(&welcome.nostr_group_id)),
                                            sender_pubkey: Some(unwrapped.sender.to_hex()),
                                            content: Some(format!(
                                                "Welcome to group '{}' ({} members)",
                                                welcome.group_name, welcome.member_count
                                            )),
                                            allowed: None,
                                            error: None,
                                        };
                                        write_jsonl(&log_path_clone, &welcome_entry);

                                        // Auto-accept: use the welcome ID from process_welcome result
                                        let welcome_id = welcome.id;
                                        match mdk.get_welcome(&welcome_id) {
                                            Ok(Some(w)) => {
                                                match mdk.accept_welcome(&w) {
                                                    Ok(()) => {
                                                        // Save the new group
                                                        let group = StoredGroup {
                                                            mls_group_id_hex: hex::encode(welcome.mls_group_id.as_slice()),
                                                            nostr_group_id_hex: hex::encode(&welcome.nostr_group_id),
                                                            name: welcome.group_name.clone(),
                                                            description: welcome.group_description.clone(),
                                                            admin_pubkeys: vec![unwrapped.sender.to_hex()],
                                                            relay_urls: config::default_relays(),
                                                            created_at: chrono::Utc::now().timestamp() as u64,
                                                        };
                                                        let _ = store_clone.save_group(&group);

                                                        let accepted_entry = DaemonLogEntry {
                                                            entry_type: "welcome_accepted".into(),
                                                            timestamp: chrono::Utc::now().to_rfc3339(),
                                                            group_id: Some(hex::encode(&welcome.nostr_group_id)),
                                                            sender_pubkey: Some(unwrapped.sender.to_hex()),
                                                            content: Some(format!(
                                                                "Auto-accepted welcome to '{}'. Restart daemon to listen on new group.",
                                                                welcome.group_name
                                                            )),
                                                            allowed: None,
                                                            error: None,
                                                        };
                                                        write_jsonl(&log_path_clone, &accepted_entry);
                                                    }
                                                    Err(e) => {
                                                        let err_entry = DaemonLogEntry {
                                                            entry_type: "welcome_accept_error".into(),
                                                            timestamp: chrono::Utc::now().to_rfc3339(),
                                                            group_id: Some(hex::encode(&welcome.nostr_group_id)),
                                                            sender_pubkey: None,
                                                            content: None,
                                                            allowed: None,
                                                            error: Some(format!("accept_welcome failed: {}", e)),
                                                        };
                                                        write_jsonl(&log_path_clone, &err_entry);
                                                    }
                                                }
                                            }
                                            Ok(None) => {
                                                let err_entry = DaemonLogEntry {
                                                    entry_type: "welcome_accept_error".into(),
                                                    timestamp: chrono::Utc::now().to_rfc3339(),
                                                    group_id: None,
                                                    sender_pubkey: None,
                                                    content: None,
                                                    allowed: None,
                                                    error: Some("Welcome not found after processing".into()),
                                                };
                                                write_jsonl(&log_path_clone, &err_entry);
                                            }
                                            Err(e) => {
                                                let err_entry = DaemonLogEntry {
                                                    entry_type: "welcome_accept_error".into(),
                                                    timestamp: chrono::Utc::now().to_rfc3339(),
                                                    group_id: None,
                                                    sender_pubkey: None,
                                                    content: None,
                                                    allowed: None,
                                                    error: Some(format!("get_welcome failed: {}", e)),
                                                };
                                                write_jsonl(&log_path_clone, &err_entry);
                                            }
                                        }
                                        } // end else (not already accepted)
                                    }
                                    Err(e) => {
                                        let err_entry = DaemonLogEntry {
                                            entry_type: "welcome_process_error".into(),
                                            timestamp: chrono::Utc::now().to_rfc3339(),
                                            group_id: None,
                                            sender_pubkey: Some(unwrapped.sender.to_hex()),
                                            content: None,
                                            allowed: None,
                                            error: Some(format!("process_welcome failed: {}", e)),
                                        };
                                        write_jsonl(&log_path_clone, &err_entry);
                                    }
                                }
                            }
                        }
                        Err(e) => {
                            // Silently ignore unwrap failures (not all 1059s are for us / valid)
                            let entry = DaemonLogEntry {
                                entry_type: "gift_wrap_error".into(),
                                timestamp: chrono::Utc::now().to_rfc3339(),
                                group_id: None,
                                sender_pubkey: None,
                                content: None,
                                allowed: None,
                                error: Some(format!("NIP-59 unwrap failed: {}", e)),
                            };
                            write_jsonl(&log_path_clone, &entry);
                        }
                    }
                }
                else if event.kind == Kind::MlsGroupMessage {
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

                            let tags: Vec<Vec<String>> = msg.tags.iter()
                                .map(|t| t.as_slice().to_vec())
                                .collect();
                            let media_dir = data_clone.join("media");

                            // Auto-download encrypted media attachments
                            if allowed {
                                crate::media::auto_download_attachments(
                                    &mdk, &msg.mls_group_id, &tags, &media_dir,
                                ).await;
                            }

                            let display_content = if allowed {
                                Some(crate::media::format_message_with_media(
                                    &msg.content, &tags, Some(&media_dir),
                                ))
                            } else {
                                None
                            };

                            let entry = DaemonLogEntry {
                                entry_type: "message".into(),
                                timestamp: chrono::Utc::now().to_rfc3339(),
                                group_id: Some(nostr_gid.to_string()),
                                sender_pubkey: Some(sender_hex.clone()),
                                content: display_content,
                                allowed: Some(allowed),
                                error: None,
                            };
                            write_jsonl(&log_path_clone, &entry);

                            if allowed {
                                let tags: Vec<Vec<String>> = msg.tags.iter()
                                    .map(|t| t.as_slice().to_vec())
                                    .collect();
                                let stored = StoredMessage {
                                    event_id_hex: msg.id.to_hex(),
                                    author_pubkey_hex: sender_hex,
                                    content: msg.content.clone(),
                                    created_at: msg.created_at.as_secs(),
                                    mls_group_id_hex: group_hex,
                                    wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
                                    epoch: msg.epoch.unwrap_or(0),
                                    tags,
                                };
                                let _ = store_clone.save_message(&stored);
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
