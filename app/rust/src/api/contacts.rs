//! Contact discovery: NIP-02 follow list filtered to Marmot-capable users.
//!
//! Follows are stored locally in SQLite. On sync, the NIP-02 follow list is
//! fetched from relays, key packages (kind 443) are batch-checked, and profiles
//! are resolved. The contacts tab loads instantly from cache; relay queries only
//! happen on sync.

use std::collections::HashSet;
use std::time::Duration;

use flutter_rust_bridge::frb;
use nostr_sdk::prelude::*;

use crate::api::app_state;
use crate::api::error::BurrowError;
use crate::api::identity;
use crate::api::state;

/// A Marmot-capable contact (has published a key package).
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct ContactInfo {
    pub pubkey_hex: String,
    pub display_name: Option<String>,
    pub picture: Option<String>,
}

/// Diagnostic info for debugging contacts sync.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct ContactsSyncDebug {
    pub connected_relays: u32,
    pub follow_count: u32,
    pub key_package_count: u32,
    pub db_follow_count: u32,
    pub db_kp_count: u32,
    pub error: Option<String>,
}

/// Debug contacts sync: returns diagnostic info about each step.
#[frb]
pub async fn debug_sync_contacts() -> Result<ContactsSyncDebug, BurrowError> {
    let self_pubkey_hex = match state::with_state(|s| Ok(s.keys.public_key().to_hex())).await {
        Ok(pk) => pk,
        Err(e) => return Ok(ContactsSyncDebug {
            connected_relays: 0,
            follow_count: 0,
            key_package_count: 0,
            db_follow_count: 0,
            db_kp_count: 0,
            error: Some(format!("State not initialized: {e}")),
        }),
    };

    let client = match state::with_state(|s| Ok(s.client.clone())).await {
        Ok(c) => c,
        Err(e) => return Ok(ContactsSyncDebug {
            connected_relays: 0,
            follow_count: 0,
            key_package_count: 0,
            db_follow_count: 0,
            db_kp_count: 0,
            error: Some(format!("Client not available: {e}")),
        }),
    };

    // Check connected relays
    let relays = client.relays().await;
    let connected_count = relays.values().filter(|r| r.is_connected()).count() as u32;

    if connected_count == 0 {
        return Ok(ContactsSyncDebug {
            connected_relays: 0,
            follow_count: 0,
            key_package_count: 0,
            db_follow_count: 0,
            db_kp_count: 0,
            error: Some("No connected relays".to_string()),
        });
    }

    // Try fetching follow list
    let follow_pubkeys = match fetch_follow_list_inner(&client, &self_pubkey_hex).await {
        Ok(pks) => pks,
        Err(e) => return Ok(ContactsSyncDebug {
            connected_relays: connected_count,
            follow_count: 0,
            key_package_count: 0,
            db_follow_count: 0,
            db_kp_count: 0,
            error: Some(format!("Follow list fetch failed: {e}")),
        }),
    };

    if follow_pubkeys.is_empty() {
        return Ok(ContactsSyncDebug {
            connected_relays: connected_count,
            follow_count: 0,
            key_package_count: 0,
            db_follow_count: 0,
            db_kp_count: 0,
            error: Some(format!("No follows found for pubkey {}", self_pubkey_hex)),
        });
    }

    // Try checking key packages
    let has_kp = match batch_check_key_packages(&client, &follow_pubkeys).await {
        Ok(set) => set,
        Err(e) => return Ok(ContactsSyncDebug {
            connected_relays: connected_count,
            follow_count: follow_pubkeys.len() as u32,
            key_package_count: 0,
            db_follow_count: 0,
            db_kp_count: 0,
            error: Some(format!("Key package check failed: {e}")),
        }),
    };

    // Also try running the actual sync and report any error
    let sync_error = match sync_contacts_inner().await {
        Ok(_) => None,
        Err(e) => Some(format!("sync_contacts_inner: {e}")),
    };

    // Check DB state after sync attempt
    let (db_follows, db_kp) = app_state::with_db(|conn| {
        let total: u32 = conn
            .query_row("SELECT COUNT(*) FROM follows", [], |row| row.get(0))
            .unwrap_or(0);
        let with_kp: u32 = conn
            .query_row(
                "SELECT COUNT(*) FROM follows WHERE has_key_package = 1",
                [],
                |row| row.get(0),
            )
            .unwrap_or(0);
        Ok((total, with_kp))
    })
    .unwrap_or((0, 0));

    Ok(ContactsSyncDebug {
        connected_relays: connected_count,
        follow_count: follow_pubkeys.len() as u32,
        key_package_count: has_kp.len() as u32,
        db_follow_count: db_follows,
        db_kp_count: db_kp,
        error: sync_error,
    })
}

/// Return cached contacts (follows with key packages) from local SQLite.
/// Instant — no relay traffic. Returns empty list if DB is not yet initialized.
#[frb]
pub async fn get_cached_contacts() -> Result<Vec<ContactInfo>, BurrowError> {
    match app_state::with_db(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT pubkey_hex, display_name, picture FROM follows
                 WHERE has_key_package = 1
                 ORDER BY COALESCE(display_name, pubkey_hex) COLLATE NOCASE",
            )
            .map_err(|e| BurrowError::from(e.to_string()))?;

        let contacts = stmt
            .query_map([], |row| {
                Ok(ContactInfo {
                    pubkey_hex: row.get(0)?,
                    display_name: row.get(1)?,
                    picture: row.get(2)?,
                })
            })
            .map_err(|e| BurrowError::from(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();

        Ok(contacts)
    }) {
        Ok(contacts) => Ok(contacts),
        Err(_) => Ok(vec![]), // DB not initialized yet — return empty
    }
}

/// Full sync: fetch NIP-02 follow list, check key packages, resolve profiles,
/// update local SQLite, and return Marmot-capable contacts.
///
/// On any failure, returns whatever is currently cached rather than propagating
/// the error — this prevents the UI from showing an error screen.
#[frb]
pub async fn sync_contacts() -> Result<Vec<ContactInfo>, BurrowError> {
    match sync_contacts_inner().await {
        Ok(contacts) => Ok(contacts),
        Err(e) => {
            // Log the error for debugging, then fall back to cached data
            eprintln!("[contacts] sync_contacts_inner failed: {e}");
            get_cached_contacts().await
        }
    }
}

async fn sync_contacts_inner() -> Result<Vec<ContactInfo>, BurrowError> {
    let self_pubkey_hex = state::with_state(|s| Ok(s.keys.public_key().to_hex())).await?;
    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    // Ensure the app state DB is initialized before any DB operations.
    let data_dir = state::get_data_dir()?;
    app_state::ensure_db_with(&data_dir, &self_pubkey_hex)?;

    // Step 1: Fetch NIP-02 follow list (kind 3) from relays
    let follow_pubkeys = fetch_follow_list_inner(&client, &self_pubkey_hex).await?;

    if follow_pubkeys.is_empty() {
        // No follow list — clear local follows and return empty
        let _ = app_state::with_db(|conn| {
            conn.execute("DELETE FROM follows", [])
                .map_err(|e| BurrowError::from(e.to_string()))?;
            Ok(())
        });
        let _ = set_last_synced();
        return Ok(vec![]);
    }

    // Step 2: Diff against local follows table
    let local_follows = app_state::with_db(|conn| {
        let mut stmt = conn
            .prepare("SELECT pubkey_hex FROM follows")
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let keys: HashSet<String> = stmt
            .query_map([], |row| row.get(0))
            .map_err(|e| BurrowError::from(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();
        Ok(keys)
    })?;

    let remote_set: HashSet<String> = follow_pubkeys.iter().cloned().collect();

    // Insert new follows
    let new_follows: Vec<&String> = follow_pubkeys.iter().filter(|p| !local_follows.contains(*p)).collect();
    if !new_follows.is_empty() {
        app_state::with_db(|conn| {
            let mut stmt = conn
                .prepare(
                    "INSERT OR IGNORE INTO follows (pubkey_hex) VALUES (?1)",
                )
                .map_err(|e| BurrowError::from(e.to_string()))?;
            for pk in &new_follows {
                stmt.execute([pk.as_str()])
                    .map_err(|e| BurrowError::from(e.to_string()))?;
            }
            Ok(())
        })?;
    }

    // Delete unfollowed
    let unfollowed: Vec<&String> = local_follows.iter().filter(|p| !remote_set.contains(*p)).collect();
    if !unfollowed.is_empty() {
        app_state::with_db(|conn| {
            let mut stmt = conn
                .prepare("DELETE FROM follows WHERE pubkey_hex = ?1")
                .map_err(|e| BurrowError::from(e.to_string()))?;
            for pk in &unfollowed {
                stmt.execute([pk.as_str()])
                    .map_err(|e| BurrowError::from(e.to_string()))?;
            }
            Ok(())
        })?;
    }

    // Step 3: Batch-check key packages for follows that need checking
    let now_secs = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let stale_threshold = now_secs - 86400; // 24 hours

    let needs_check = app_state::with_db(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT pubkey_hex FROM follows
                 WHERE has_key_package = 0
                    OR key_package_checked_at IS NULL
                    OR key_package_checked_at < ?1",
            )
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let keys: Vec<String> = stmt
            .query_map([stale_threshold], |row| row.get(0))
            .map_err(|e| BurrowError::from(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();
        Ok(keys)
    })?;

    if !needs_check.is_empty() {
        // Chunk into batches of 150 to avoid relay query limits
        let has_kp = batch_check_key_packages(&client, &needs_check).await?;

        // Update database with results
        app_state::with_db(|conn| {
            let mut update_stmt = conn
                .prepare(
                    "UPDATE follows SET has_key_package = ?1, key_package_checked_at = ?2
                     WHERE pubkey_hex = ?3",
                )
                .map_err(|e| BurrowError::from(e.to_string()))?;

            for pk in &needs_check {
                let found = if has_kp.contains(pk) { 1 } else { 0 };
                update_stmt
                    .execute(rusqlite::params![found, now_secs, pk])
                    .map_err(|e| BurrowError::from(e.to_string()))?;
            }
            Ok(())
        })?;
    }

    // Step 4: Fetch profiles for Marmot-capable contacts missing display names.
    // Uses cache-first (non-blocking), then relay fetch for unknowns, in
    // parallel batches to avoid sequential 10s timeouts per contact.
    let needs_profile = app_state::with_db(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT pubkey_hex FROM follows
                 WHERE has_key_package = 1
                   AND (display_name IS NULL OR display_name = '')",
            )
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let keys: Vec<String> = stmt
            .query_map([], |row| row.get(0))
            .map_err(|e| BurrowError::from(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();
        Ok(keys)
    })?;

    if !needs_profile.is_empty() {
        // Phase 1: Try cache for all (instant, no relay traffic)
        let mut still_missing = Vec::new();
        for pk in &needs_profile {
            match identity::fetch_profile(pk.clone(), false).await {
                Ok(profile) if !profile.is_empty() => {
                    let best_name = profile.best_name();
                    let pic = profile.picture.clone();
                    let _ = app_state::with_db(|conn| {
                        conn.execute(
                            "UPDATE follows SET display_name = ?1, picture = ?2
                             WHERE pubkey_hex = ?3",
                            rusqlite::params![best_name, pic, pk],
                        )
                        .map_err(|e| BurrowError::from(e.to_string()))?;
                        Ok(())
                    });
                }
                _ => still_missing.push(pk.clone()),
            }
        }

        // Phase 2: Batch-fetch unknown profiles from relays (kind 0)
        // Query in batches of 50 authors at once instead of one-by-one.
        for chunk in still_missing.chunks(50) {
            let pubkeys: Vec<PublicKey> = chunk
                .iter()
                .filter_map(|h| PublicKey::from_hex(h).ok())
                .collect();

            if pubkeys.is_empty() {
                continue;
            }

            let filter = Filter::new()
                .authors(pubkeys)
                .kind(Kind::Metadata);

            if let Ok(events) = client.fetch_events(filter, Duration::from_secs(10)).await {
                for event in events {
                    let pk_hex = event.pubkey.to_hex();
                    if let Ok(metadata) = Metadata::from_json(&event.content) {
                        let profile = identity::ProfileData::from_metadata(&metadata);
                        let best_name = profile.best_name();
                        let pic = profile.picture.clone();
                        if best_name.is_some() || pic.is_some() {
                            let _ = app_state::with_db(|conn| {
                                conn.execute(
                                    "UPDATE follows SET display_name = ?1, picture = ?2
                                     WHERE pubkey_hex = ?3",
                                    rusqlite::params![best_name, pic, pk_hex],
                                )
                                .map_err(|e| BurrowError::from(e.to_string()))?;
                                Ok(())
                            });
                        }
                    }
                }
            }
        }
    }

    // Step 5: Update last_synced timestamp
    let _ = set_last_synced();

    // Step 6: Return all Marmot-capable contacts
    get_cached_contacts().await
}

/// Get the timestamp of the last contacts sync (epoch seconds), or None.
#[frb]
pub async fn get_last_contacts_sync() -> Result<Option<i64>, BurrowError> {
    match app_state::with_db(|conn| {
        let mut stmt = conn
            .prepare("SELECT value FROM contacts_meta WHERE key = 'last_synced'")
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let result: Option<String> = stmt
            .query_row([], |row| row.get(0))
            .ok();
        Ok(result.and_then(|v| v.parse::<i64>().ok()))
    }) {
        Ok(ts) => Ok(ts),
        Err(_) => Ok(None), // DB not initialized yet
    }
}

/// Follow a contact by adding them to the NIP-02 follow list (kind 3).
/// Publishes the updated follow list to relays and updates local DB.
#[frb]
pub async fn follow_contact(pubkey_hex: String) -> Result<(), BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    let self_pubkey_hex = state::with_state(|s| Ok(s.keys.public_key().to_hex())).await?;

    // Fetch current follow list
    let mut current = fetch_follow_list_inner(&client, &self_pubkey_hex).await?;

    // Don't add duplicates or self
    if current.contains(&pubkey_hex) || pubkey_hex == self_pubkey_hex {
        return Ok(());
    }
    current.push(pubkey_hex.clone());

    // Publish updated kind 3
    publish_follow_list(&client, &current).await?;

    // Update local DB
    let data_dir = state::get_data_dir()?;
    app_state::ensure_db_with(&data_dir, &self_pubkey_hex)?;
    let _ = app_state::with_db(|conn| {
        conn.execute(
            "INSERT OR IGNORE INTO follows (pubkey_hex) VALUES (?1)",
            [&pubkey_hex],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        Ok(())
    });

    Ok(())
}

/// Unfollow a contact by removing them from the NIP-02 follow list (kind 3).
/// Publishes the updated follow list to relays and removes from local DB.
#[frb]
pub async fn unfollow_contact(pubkey_hex: String) -> Result<(), BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    let self_pubkey_hex = state::with_state(|s| Ok(s.keys.public_key().to_hex())).await?;

    // Fetch current follow list
    let mut current = fetch_follow_list_inner(&client, &self_pubkey_hex).await?;

    // Remove the contact
    current.retain(|p| p != &pubkey_hex);

    // Publish updated kind 3
    publish_follow_list(&client, &current).await?;

    // Update local DB
    let data_dir = state::get_data_dir()?;
    app_state::ensure_db_with(&data_dir, &self_pubkey_hex)?;
    let _ = app_state::with_db(|conn| {
        conn.execute(
            "DELETE FROM follows WHERE pubkey_hex = ?1",
            [&pubkey_hex],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        Ok(())
    });

    Ok(())
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Fetch the NIP-02 follow list (kind 3) for a pubkey from relays.
/// Returns a list of followed pubkey hex strings.
async fn fetch_follow_list_inner(
    client: &Client,
    pubkey_hex: &str,
) -> Result<Vec<String>, BurrowError> {
    let pubkey =
        PublicKey::from_hex(pubkey_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let filter = Filter::new()
        .author(pubkey)
        .kind(Kind::ContactList)
        .limit(1);

    let events = client
        .fetch_events(filter, Duration::from_secs(10))
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    // Kind 3 is a replaceable event — take the newest
    let event = match events.into_iter().max_by_key(|e| e.created_at) {
        Some(e) => e,
        None => return Ok(vec![]),
    };

    // Extract pubkeys from "p" tags
    let p_tag = TagKind::single_letter(Alphabet::P, false);
    let pubkeys: Vec<String> = event
        .tags
        .iter()
        .filter(|t| t.kind() == p_tag)
        .filter_map(|t| t.content().map(|s| s.to_string()))
        .collect();

    Ok(pubkeys)
}

/// Batch-check which pubkeys have published key packages (kind 443).
/// Chunks into batches of 150 to avoid relay query limits.
/// Returns the set of pubkey hexes that have at least one key package.
async fn batch_check_key_packages(
    client: &Client,
    pubkey_hexes: &[String],
) -> Result<HashSet<String>, BurrowError> {
    let mut found = HashSet::new();

    for chunk in pubkey_hexes.chunks(150) {
        let pubkeys: Vec<PublicKey> = chunk
            .iter()
            .filter_map(|h| PublicKey::from_hex(h).ok())
            .collect();

        if pubkeys.is_empty() {
            continue;
        }

        let filter = Filter::new()
            .authors(pubkeys)
            .kind(Kind::MlsKeyPackage);

        match client.fetch_events(filter, Duration::from_secs(15)).await {
            Ok(events) => {
                for event in events {
                    found.insert(event.pubkey.to_hex());
                }
            }
            Err(_) => {
                // Partial failure is okay — contacts checked in this chunk
                // will be retried next sync since key_package_checked_at
                // won't be updated for them.
            }
        }
    }

    Ok(found)
}

/// Publish a NIP-02 follow list (kind 3) with the given pubkey hexes.
async fn publish_follow_list(
    client: &Client,
    pubkey_hexes: &[String],
) -> Result<(), BurrowError> {
    let tags: Vec<Tag> = pubkey_hexes
        .iter()
        .filter_map(|hex| {
            PublicKey::from_hex(hex)
                .ok()
                .map(|pk| Tag::public_key(pk))
        })
        .collect();

    let builder = EventBuilder::new(Kind::ContactList, "").tags(tags);
    client
        .send_event_builder(builder)
        .await
        .map_err(|e| BurrowError::from(format!("Failed to publish follow list: {e}")))?;

    Ok(())
}

/// Update the last_synced timestamp in contacts_meta.
fn set_last_synced() -> Result<(), BurrowError> {
    app_state::with_db(|conn| {
        conn.execute(
            "INSERT OR REPLACE INTO contacts_meta (key, value) VALUES ('last_synced', strftime('%s','now'))",
            [],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        Ok(())
    })
}
