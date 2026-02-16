use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_sqlite_storage::MdkSqliteStorage;
use nostr_sdk::prelude::*;
use std::fs;

use crate::config;
use crate::relay::pool;
use crate::storage::file_store::{FileStore, StoredGroup};

/// List pending NIP-59 welcome messages from relays.
pub async fn list(
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let kp = key_path
        .map(std::path::PathBuf::from)
        .unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    let mls_db_path = data.join("mls.sqlite");

    let relays = config::default_relays();
    let client = pool::connect(&keys, &relays).await?;

    println!("🔍 Fetching NIP-59 gift wraps (kind 1059) for our pubkey...");

    let filter = Filter::new()
        .kind(Kind::GiftWrap)
        .custom_tag(SingleLetterTag::lowercase(Alphabet::P), keys.public_key().to_hex())
        .limit(50);

    let events = client
        .fetch_events(filter, std::time::Duration::from_secs(15))
        .await
        .context("Failed to fetch gift wrap events")?;

    if events.is_empty() {
        println!("📭 No gift wrap events found.");
        client.disconnect().await;
        return Ok(());
    }

    let mdk_storage = MdkSqliteStorage::new_unencrypted(&mls_db_path)
        .context("Failed to open MLS SQLite database")?;
    let mdk = MDK::new(mdk_storage);
    let mut found = 0;

    for event in events.into_iter() {
        match nip59::extract_rumor(&keys, &event).await {
            Ok(unwrapped) => {
                if unwrapped.rumor.kind == Kind::Custom(444) {
                    found += 1;
                    // Try to process as welcome
                    let _rumor_json = unwrapped.rumor.as_json();
                    match mdk.process_welcome(&event.id, &unwrapped.rumor) {
                        Ok(welcome) => {
                            println!(
                                "\n📨 Welcome #{found}:");
                            println!("   Event ID:  {}", event.id.to_hex());
                            println!("   From:      {}", unwrapped.sender.to_hex());
                            println!("   Group:     {}", welcome.group_name);
                            println!("   Desc:      {}", welcome.group_description);
                            println!("   Members:   {}", welcome.member_count);
                            println!("   MLS Group: {}", hex::encode(welcome.mls_group_id.as_slice()));
                            println!("   Nostr GID: {}", hex::encode(&welcome.nostr_group_id));
                            println!("   Status:    {:?}", welcome.state);
                        }
                        Err(e) => {
                            println!(
                                "\n⚠️  Gift wrap {} - kind 444 rumor but MDK process_welcome failed: {}",
                                &event.id.to_hex()[..12],
                                e
                            );
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("⚠️  Could not unwrap {}: {}", &event.id.to_hex()[..12], e);
            }
        }
    }

    if found == 0 {
        println!("📭 No Welcome (kind 444) rumors found in gift wraps.");
    } else {
        println!("\n✅ Found {} welcome(s). Use `burrow welcome accept <event-id>` to join.", found);
    }

    client.disconnect().await;
    Ok(())
}

/// Accept a pending welcome and save the group.
pub async fn accept(
    event_id_hex: String,
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;
    let kp = key_path
        .map(std::path::PathBuf::from)
        .unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    let relays = config::default_relays();
    let client = pool::connect(&keys, &relays).await?;
    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = MdkSqliteStorage::new_unencrypted(&mls_db_path)
        .context("Failed to open MLS SQLite database")?;
    let mdk = MDK::new(mdk_storage);

    // Fetch the specific gift wrap event
    let target_id = EventId::from_hex(&event_id_hex)
        .context("Invalid event ID")?;

    let filter = Filter::new()
        .id(target_id)
        .kind(Kind::GiftWrap);

    println!("🔍 Fetching gift wrap event {}...", &event_id_hex[..12]);
    let events = client
        .fetch_events(filter, std::time::Duration::from_secs(15))
        .await
        .context("Failed to fetch gift wrap event")?;

    let event = events
        .into_iter()
        .next()
        .context("Gift wrap event not found on relays")?;

    // Unwrap NIP-59
    let unwrapped = nip59::extract_rumor(&keys, &event)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to unwrap gift wrap: {}", e))?;

    if unwrapped.rumor.kind != Kind::Custom(444) {
        anyhow::bail!("Unwrapped rumor is kind {}, expected 444 (Welcome)", unwrapped.rumor.kind.as_u16());
    }

    // Process welcome
    let welcome = mdk
        .process_welcome(&event.id, &unwrapped.rumor)
        .map_err(|e| anyhow::anyhow!("MDK process_welcome failed: {}", e))?;

    println!("📨 Welcome from {} to group '{}'", unwrapped.sender.to_hex(), welcome.group_name);

    // Accept welcome
    let welcome_ref = mdk
        .get_welcome(&event.id)
        .map_err(|e| anyhow::anyhow!("MDK get_welcome failed: {}", e))?
        .context("Welcome not found after processing")?;

    mdk.accept_welcome(&welcome_ref)
        .map_err(|e| anyhow::anyhow!("MDK accept_welcome failed: {}", e))?;

    // Save the group
    let group = StoredGroup {
        mls_group_id_hex: hex::encode(welcome.mls_group_id.as_slice()),
        nostr_group_id_hex: hex::encode(&welcome.nostr_group_id),
        name: welcome.group_name.clone(),
        description: welcome.group_description.clone(),
        admin_pubkeys: vec![unwrapped.sender.to_hex()],
        relay_urls: config::default_relays(),
        created_at: chrono::Utc::now().timestamp() as u64,
    };
    store.save_group(&group)?;

    println!("✅ Joined group '{}' ({})", welcome.group_name, &hex::encode(&welcome.nostr_group_id)[..12]);
    println!("   Restart the daemon to start listening on this group.");

    client.disconnect().await;
    Ok(())
}
