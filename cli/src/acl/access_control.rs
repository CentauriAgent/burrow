use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OwnerInfo {
    #[serde(default)]
    pub npub: String,
    #[serde(default)]
    pub hex: String,
    #[serde(default)]
    pub note: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AclSettings {
    #[serde(default, rename = "logRejectedContent")]
    pub log_rejected_content: bool,
    #[serde(default = "default_true", rename = "auditEnabled")]
    pub audit_enabled: bool,
}

fn default_true() -> bool { true }

impl Default for AclSettings {
    fn default() -> Self {
        Self { log_rejected_content: false, audit_enabled: true }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AclConfig {
    #[serde(default = "default_version")]
    pub version: u32,
    pub owner: OwnerInfo,
    #[serde(default = "default_policy", rename = "defaultPolicy")]
    pub default_policy: String,
    #[serde(default, rename = "allowedContacts")]
    pub allowed_contacts: Vec<String>,
    #[serde(default, rename = "allowedGroups")]
    pub allowed_groups: Vec<String>,
    #[serde(default)]
    pub settings: AclSettings,
}

fn default_version() -> u32 { 1 }
fn default_policy() -> String { "ignore".into() }

pub struct AccessControl {
    config_path: PathBuf,
    pub config: AclConfig,
}

impl AccessControl {
    pub fn load(data_dir: &Path) -> Result<Self> {
        let config_path = data_dir.join("access-control.json");
        let config = if config_path.exists() {
            let data = fs::read_to_string(&config_path)
                .context("Failed to read access-control.json")?;
            serde_json::from_str(&data).context("Failed to parse access-control.json")?
        } else {
            AclConfig {
                version: 1,
                owner: OwnerInfo { npub: String::new(), hex: String::new(), note: String::new() },
                default_policy: "ignore".into(),
                allowed_contacts: vec![],
                allowed_groups: vec![],
                settings: AclSettings::default(),
            }
        };
        Ok(Self { config_path, config })
    }

    fn save(&self) -> Result<()> {
        let data = serde_json::to_string_pretty(&self.config)?;
        fs::write(&self.config_path, data)?;
        Ok(())
    }

    /// Get effective owner hex, checking env vars first.
    pub fn owner_hex(&self) -> String {
        if let Ok(hex) = std::env::var("BURROW_OWNER_HEX") {
            return hex;
        }
        if let Ok(npub) = std::env::var("BURROW_OWNER_NPUB") {
            if let Some(hex) = npub_to_hex(&npub) {
                return hex;
            }
        }
        self.config.owner.hex.clone()
    }

    /// Check if a sender is allowed to send messages in a group.
    pub fn is_allowed(&self, sender_hex: &str, group_id: &str) -> bool {
        let owner = self.owner_hex();
        if owner.is_empty() {
            return true; // No ACL configured
        }
        if sender_hex == owner {
            return true; // Owner always allowed
        }
        let contact_ok = self.config.allowed_contacts.iter().any(|c| c == sender_hex);
        let group_ok = self.config.allowed_groups.iter().any(|g| g == group_id);
        contact_ok || group_ok
    }

    pub fn add_contact(&mut self, hex: &str) -> Result<()> {
        if !self.config.allowed_contacts.contains(&hex.to_string()) {
            self.config.allowed_contacts.push(hex.to_string());
            self.save()?;
        }
        Ok(())
    }

    pub fn remove_contact(&mut self, hex: &str) -> Result<bool> {
        let before = self.config.allowed_contacts.len();
        self.config.allowed_contacts.retain(|c| c != hex);
        if self.config.allowed_contacts.len() < before {
            self.save()?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    pub fn add_group(&mut self, group_id: &str) -> Result<()> {
        if !self.config.allowed_groups.contains(&group_id.to_string()) {
            self.config.allowed_groups.push(group_id.to_string());
            self.save()?;
        }
        Ok(())
    }

    pub fn remove_group(&mut self, group_id: &str) -> Result<bool> {
        let before = self.config.allowed_groups.len();
        self.config.allowed_groups.retain(|g| g != group_id);
        if self.config.allowed_groups.len() < before {
            self.save()?;
            Ok(true)
        } else {
            Ok(false)
        }
    }
}

/// Decode npub bech32 to hex pubkey.
pub fn npub_to_hex(npub: &str) -> Option<String> {
    let (hrp, data) = bech32::decode(npub).ok()?;
    if hrp.as_str() != "npub" { return None; }
    Some(hex::encode(data))
}

/// Convert hex to npub.
pub fn hex_to_npub(hex_str: &str) -> Option<String> {
    use bech32::Hrp;
    let bytes = hex::decode(hex_str).ok()?;
    if bytes.len() != 32 { return None; }
    let hrp = Hrp::parse("npub").ok()?;
    bech32::encode::<bech32::Bech32>(hrp, &bytes).ok()
}

/// Resolve an npub or hex string to hex.
pub fn resolve_to_hex(input: &str) -> Result<String> {
    if input.len() == 64 && input.chars().all(|c| c.is_ascii_hexdigit()) {
        return Ok(input.to_lowercase());
    }
    if input.starts_with("npub1") {
        if let Some(hex) = npub_to_hex(input) {
            return Ok(hex);
        }
    }
    anyhow::bail!("Invalid pubkey: {}. Provide 64-char hex or npub1...", input)
}
