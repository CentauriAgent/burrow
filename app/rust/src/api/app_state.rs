//! Persistent app state stored in a SQLite database alongside the MLS data.
//!
//! Stores per-group read markers, archive state, and other UI metadata.
//! Follows the "Rust owns data" principle — Flutter never persists state directly.

use std::path::PathBuf;
use std::sync::{LazyLock, Mutex};

use flutter_rust_bridge::frb;
use rusqlite::{params, Connection};

use crate::api::error::BurrowError;
use crate::api::state;

static APP_DB: LazyLock<Mutex<Option<Connection>>> = LazyLock::new(|| Mutex::new(None));

/// Initialize (or reinitialize) the app state database.
/// Called after MdkSqliteStorage::new creates the mls_dir.
/// `mls_dir` may be a file (MdkSqliteStorage DB) or a directory — we handle
/// both by placing app_state.db alongside or inside it.
#[frb(ignore)]
pub fn init_app_state_db(mls_dir: &PathBuf) -> Result<(), BurrowError> {
    // If mls_dir is a file (MdkSqliteStorage creates a flat DB file),
    // place app_state.db next to it with a suffix. If it's a directory,
    // place it inside.
    let db_path = if mls_dir.is_file() {
        let mut p = mls_dir.clone().into_os_string();
        p.push("_app_state.db");
        PathBuf::from(p)
    } else {
        mls_dir.join("app_state.db")
    };
    let conn =
        Connection::open(db_path).map_err(|e| BurrowError::from(format!("app_state db: {e}")))?;

    conn.execute_batch(
        "CREATE TABLE IF NOT EXISTS app_state (
            group_id_hex TEXT NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now')),
            PRIMARY KEY (group_id_hex, key)
        );",
    )
    .map_err(|e| BurrowError::from(format!("app_state schema: {e}")))?;

    // Store the connection first so with_db() works even if later migrations fail.
    let mut guard = APP_DB
        .lock()
        .map_err(|e| BurrowError::from(format!("app_state lock: {e}")))?;
    *guard = Some(conn);
    drop(guard);

    // Contacts tables — run as a migration after DB is available.
    // Uses with_db so the connection is reused properly.
    let _ = with_db(|conn| {
        conn.execute_batch(
            "CREATE TABLE IF NOT EXISTS follows (
                pubkey_hex TEXT PRIMARY KEY,
                display_name TEXT,
                picture TEXT,
                has_key_package INTEGER NOT NULL DEFAULT 0,
                key_package_checked_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now'))
            );

            CREATE TABLE IF NOT EXISTS contacts_meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );",
        )
        .map_err(|e| BurrowError::from(format!("contacts schema: {e}")))?;
        Ok(())
    });

    Ok(())
}

#[frb(ignore)]
pub(crate) fn with_db<F, T>(f: F) -> Result<T, BurrowError>
where
    F: FnOnce(&Connection) -> Result<T, BurrowError>,
{
    let guard = APP_DB
        .lock()
        .map_err(|e| BurrowError::from(format!("app_state lock: {e}")))?;
    let conn = guard
        .as_ref()
        .ok_or_else(|| BurrowError::from("App state DB not initialized".to_string()))?;
    f(conn)
}

/// Check if the app state DB is initialized.
#[frb(ignore)]
pub fn is_db_initialized() -> bool {
    APP_DB
        .lock()
        .map(|guard| guard.is_some())
        .unwrap_or(false)
}

/// Initialize the app state DB from a known data dir and pubkey hex.
/// Safe to call multiple times — no-ops if already initialized.
#[frb(ignore)]
pub fn ensure_db_with(data_dir: &std::path::Path, pubkey_hex: &str) -> Result<(), BurrowError> {
    if is_db_initialized() {
        return Ok(());
    }

    let mls_dir = data_dir.join("mls").join(pubkey_hex);
    // mls_dir may be a file (MdkSqliteStorage flat DB) or a directory.
    // Don't try to create it — just pass it to init_app_state_db which
    // handles both cases.
    init_app_state_db(&mls_dir)
}

// ---------------------------------------------------------------------------
// Generic key-value CRUD
// ---------------------------------------------------------------------------

/// Store a key-value pair for a group.
#[frb]
pub async fn set_group_state(
    group_id_hex: String,
    key: String,
    value: String,
) -> Result<(), BurrowError> {
    with_db(|conn| {
        conn.execute(
            "INSERT OR REPLACE INTO app_state (group_id_hex, key, value, updated_at)
             VALUES (?1, ?2, ?3, strftime('%s','now'))",
            params![group_id_hex, key, value],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        Ok(())
    })
}

/// Get a value for a group.
#[frb]
pub async fn get_group_state(
    group_id_hex: String,
    key: String,
) -> Result<Option<String>, BurrowError> {
    with_db(|conn| {
        let mut stmt = conn
            .prepare("SELECT value FROM app_state WHERE group_id_hex = ?1 AND key = ?2")
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let result = stmt
            .query_row(params![group_id_hex, key], |row| row.get(0))
            .ok();
        Ok(result)
    })
}

/// Delete a key for a group.
#[frb]
pub async fn delete_group_state(
    group_id_hex: String,
    key: String,
) -> Result<(), BurrowError> {
    with_db(|conn| {
        conn.execute(
            "DELETE FROM app_state WHERE group_id_hex = ?1 AND key = ?2",
            params![group_id_hex, key],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        Ok(())
    })
}

// ---------------------------------------------------------------------------
// Read markers
// ---------------------------------------------------------------------------

/// Mark a group as read up to a specific message.
#[frb]
pub async fn mark_group_read(
    group_id_hex: String,
    last_event_id_hex: String,
    timestamp: i64,
) -> Result<(), BurrowError> {
    with_db(|conn| {
        conn.execute(
            "INSERT OR REPLACE INTO app_state (group_id_hex, key, value, updated_at)
             VALUES (?1, 'last_read_event_id', ?2, ?3)",
            params![group_id_hex, last_event_id_hex, timestamp],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        conn.execute(
            "INSERT OR REPLACE INTO app_state (group_id_hex, key, value, updated_at)
             VALUES (?1, 'last_read_timestamp', ?2, ?3)",
            params![group_id_hex, timestamp.to_string(), timestamp],
        )
        .map_err(|e| BurrowError::from(e.to_string()))?;
        Ok(())
    })
}

/// Get the last-read timestamp for a group (seconds since epoch).
#[frb]
pub async fn get_last_read_timestamp(
    group_id_hex: String,
) -> Result<Option<i64>, BurrowError> {
    with_db(|conn| {
        let mut stmt = conn
            .prepare(
                "SELECT value FROM app_state WHERE group_id_hex = ?1 AND key = 'last_read_timestamp'",
            )
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let result: Option<String> = stmt
            .query_row(params![group_id_hex], |row| row.get(0))
            .ok();
        Ok(result.and_then(|v| v.parse::<i64>().ok()))
    })
}

// ---------------------------------------------------------------------------
// Archive state
// ---------------------------------------------------------------------------

/// Archive a group.
#[frb]
pub async fn archive_group(group_id_hex: String) -> Result<(), BurrowError> {
    set_group_state(group_id_hex, "archived".to_string(), "true".to_string()).await
}

/// Unarchive a group.
#[frb]
pub async fn unarchive_group(group_id_hex: String) -> Result<(), BurrowError> {
    delete_group_state(group_id_hex, "archived".to_string()).await
}

/// Check if a group is archived.
#[frb]
pub async fn is_group_archived(group_id_hex: String) -> Result<bool, BurrowError> {
    let val = get_group_state(group_id_hex, "archived".to_string()).await?;
    Ok(val.as_deref() == Some("true"))
}

/// Get all archived group IDs.
#[frb]
pub async fn get_archived_group_ids() -> Result<Vec<String>, BurrowError> {
    with_db(|conn| {
        let mut stmt = conn
            .prepare("SELECT group_id_hex FROM app_state WHERE key = 'archived' AND value = 'true'")
            .map_err(|e| BurrowError::from(e.to_string()))?;
        let ids: Vec<String> = stmt
            .query_map([], |row| row.get(0))
            .map_err(|e| BurrowError::from(e.to_string()))?
            .filter_map(|r| r.ok())
            .collect();
        Ok(ids)
    })
}

// ---------------------------------------------------------------------------
// Group summary (last message + unread count)
// ---------------------------------------------------------------------------

/// Summary of a group's last message and unread count.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct GroupSummary {
    pub last_message_content: Option<String>,
    pub last_message_timestamp: Option<i64>,
    pub last_message_author_hex: Option<String>,
    pub unread_count: u32,
}

/// Get the last message and unread count for a group.
///
/// Fetches the most recent message from MDK, and counts messages newer
/// than the last-read timestamp from app_state.
#[frb]
pub async fn get_group_summary(
    mls_group_id_hex: String,
) -> Result<GroupSummary, BurrowError> {
    let last_read_ts = get_last_read_timestamp(mls_group_id_hex.clone()).await?.unwrap_or(0);

    state::with_state(|s| {
        let group_id = mdk_core::prelude::GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        // Get the most recent message
        let pagination = mdk_storage_traits::groups::Pagination::new(Some(1), Some(0));
        let messages = s
            .mdk
            .get_messages(&group_id, Some(pagination))
            .unwrap_or_default();

        let (last_content, last_ts, last_author) = if let Some(msg) = messages.first() {
            (
                Some(msg.content.clone()),
                Some(msg.created_at.as_secs() as i64),
                Some(msg.pubkey.to_hex()),
            )
        } else {
            (None, None, None)
        };

        // Count unread: iterate messages newer than last_read_ts
        let unread = if last_read_ts > 0 {
            // Fetch in pages of 50 until we hit an old message
            let mut count = 0u32;
            let mut offset = 0usize;
            loop {
                let page = mdk_storage_traits::groups::Pagination::new(Some(50), Some(offset));
                let batch = s
                    .mdk
                    .get_messages(&group_id, Some(page))
                    .unwrap_or_default();
                if batch.is_empty() {
                    break;
                }
                for msg in &batch {
                    if (msg.created_at.as_secs() as i64) > last_read_ts {
                        count += 1;
                    } else {
                        // Messages are descending, so we can stop
                        return Ok(GroupSummary {
                            last_message_content: last_content,
                            last_message_timestamp: last_ts,
                            last_message_author_hex: last_author,
                            unread_count: count,
                        });
                    }
                }
                offset += batch.len();
            }
            count
        } else {
            // No read marker → all messages are "unread" (but cap at message count)
            // For first launch, treat everything as read (0 unread)
            0
        };

        Ok(GroupSummary {
            last_message_content: last_content,
            last_message_timestamp: last_ts,
            last_message_author_hex: last_author,
            unread_count: unread,
        })
    })
    .await
}

// ---------------------------------------------------------------------------
// Migration helper
// ---------------------------------------------------------------------------

/// Import archived group IDs from a list (for migrating from shared_preferences).
#[frb]
pub async fn import_archived_groups(group_ids: Vec<String>) -> Result<(), BurrowError> {
    for id in group_ids {
        archive_group(id).await?;
    }
    Ok(())
}
