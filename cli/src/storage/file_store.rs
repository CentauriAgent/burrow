use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

/// Stored group metadata (persisted to disk, separate from MLS state).
/// Uses camelCase to match existing TypeScript CLI format.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredGroup {
    #[serde(alias = "mls_group_id_hex", rename = "mlsGroupId")]
    pub mls_group_id_hex: String,
    #[serde(alias = "nostr_group_id_hex", rename = "nostrGroupId")]
    pub nostr_group_id_hex: String,
    pub name: String,
    #[serde(default)]
    pub description: String,
    #[serde(alias = "admin_pubkeys", rename = "adminPubkeys")]
    pub admin_pubkeys: Vec<String>,
    #[serde(alias = "relay_urls", rename = "relays")]
    pub relay_urls: Vec<String>,
    #[serde(alias = "created_at", rename = "createdAt")]
    pub created_at: u64,
}

/// Stored message (persisted to disk).
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StoredMessage {
    pub event_id_hex: String,
    pub author_pubkey_hex: String,
    pub content: String,
    pub created_at: u64,
    pub mls_group_id_hex: String,
    pub wrapper_event_id_hex: String,
    pub epoch: u64,
    /// Tags from the inner rumor, stored as arrays of strings.
    /// Used for imeta (media attachment) tags.
    #[serde(default)]
    pub tags: Vec<Vec<String>>,
}

/// File-based persistence for groups, messages, and MLS state.
pub struct FileStore {
    base: PathBuf,
}

impl FileStore {
    pub fn new(data_dir: &Path) -> Result<Self> {
        let base = data_dir.to_path_buf();
        fs::create_dir_all(base.join("groups"))?;
        fs::create_dir_all(base.join("messages"))?;
        fs::create_dir_all(base.join("mls-state"))?;
        fs::create_dir_all(base.join("keypackages"))?;
        Ok(Self { base })
    }

    // --- Groups ---

    pub fn save_group(&self, group: &StoredGroup) -> Result<()> {
        let path = self
            .base
            .join("groups")
            .join(format!("{}.json", group.nostr_group_id_hex));
        fs::write(&path, serde_json::to_string_pretty(group)?)?;
        Ok(())
    }

    pub fn load_groups(&self) -> Result<Vec<StoredGroup>> {
        let dir = self.base.join("groups");
        let mut groups = Vec::new();
        if dir.exists() {
            for entry in fs::read_dir(&dir)? {
                let entry = entry?;
                if entry.path().extension().map_or(false, |e| e == "json") {
                    let data = fs::read_to_string(entry.path())?;
                    if let Ok(g) = serde_json::from_str::<StoredGroup>(&data) {
                        groups.push(g);
                    }
                }
            }
        }
        Ok(groups)
    }

    pub fn find_group_by_prefix(&self, prefix: &str) -> Result<Option<StoredGroup>> {
        let groups = self.load_groups()?;
        let lower = prefix.to_lowercase();
        Ok(groups.into_iter().find(|g| {
            g.nostr_group_id_hex.starts_with(&lower)
                || g.mls_group_id_hex.starts_with(&lower)
                || g.name.to_lowercase().contains(&lower)
        }))
    }

    // --- Messages ---

    pub fn save_message(&self, msg: &StoredMessage) -> Result<()> {
        let dir = self.base.join("messages").join(&msg.mls_group_id_hex);
        fs::create_dir_all(&dir)?;
        let path = dir.join(format!("{}.json", msg.event_id_hex));
        fs::write(&path, serde_json::to_string(msg)?)?;
        Ok(())
    }

    pub fn load_messages(
        &self,
        mls_group_id_hex: &str,
        limit: usize,
    ) -> Result<Vec<StoredMessage>> {
        let dir = self.base.join("messages").join(mls_group_id_hex);
        let mut msgs = Vec::new();
        if dir.exists() {
            for entry in fs::read_dir(&dir)? {
                let entry = entry?;
                if entry.path().extension().map_or(false, |e| e == "json") {
                    let data = fs::read_to_string(entry.path())?;
                    if let Ok(m) = serde_json::from_str::<StoredMessage>(&data) {
                        msgs.push(m);
                    }
                }
            }
        }
        msgs.sort_by_key(|m| m.created_at);
        if msgs.len() > limit {
            msgs = msgs.split_off(msgs.len() - limit);
        }
        Ok(msgs)
    }

    // --- MLS state (raw bytes) ---

    pub fn save_mls_state(&self, identity: &str, data: &[u8]) -> Result<()> {
        let path = self
            .base
            .join("mls-state")
            .join(format!("{}.bin", identity));
        fs::write(&path, data)?;
        // Restrict permissions
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&path, fs::Permissions::from_mode(0o600))?;
        }
        Ok(())
    }

    pub fn load_mls_state(&self, identity: &str) -> Result<Option<Vec<u8>>> {
        let path = self
            .base
            .join("mls-state")
            .join(format!("{}.bin", identity));
        if path.exists() {
            Ok(Some(fs::read(&path)?))
        } else {
            Ok(None)
        }
    }
}
