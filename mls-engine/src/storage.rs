//! State persistence for the daemon mode.
//!
//! Since MdkMemoryStorage's snapshot is not serializable, we use a different approach:
//! The daemon process keeps MDK in memory. State is NOT persisted between daemon restarts.
//! The Node CLI is responsible for restarting the daemon and re-bootstrapping state
//! (re-processing welcomes, etc.) if the daemon dies.
//!
//! Future improvement: implement a file-backed MdkStorageProvider.

use std::fs;

use anyhow::{Context, Result};
use mdk_core::MDK;
use mdk_memory_storage::MdkMemoryStorage;
use nostr_sdk::prelude::*;
use openmls::prelude::OpenMlsProvider;
use serde_json::Value;

/// Daemon state holding the MDK instance and keys.
/// Uses interior mutability since MDK methods take &self but mutate internal state.
pub struct DaemonState {
    mdk: MDK<MdkMemoryStorage>,
    pub keys: Keys,
}

impl DaemonState {
    pub fn load_or_new(
        state_dir: &str,
        mdk: MDK<MdkMemoryStorage>,
        keys: Keys,
    ) -> Result<Self> {
        // Ensure state directory exists
        fs::create_dir_all(state_dir)
            .with_context(|| format!("Failed to create state dir: {state_dir}"))?;

        Ok(Self { mdk, keys })
    }

    pub fn mdk(&self) -> &MDK<MdkMemoryStorage> {
        &self.mdk
    }

    pub fn storage(&self) -> &MdkMemoryStorage {
        self.mdk.provider.storage()
    }

    /// Save state to disk (placeholder for future file-backed storage)
    pub fn save(&self, _state_dir: &str) -> Result<()> {
        // Currently a no-op — MdkMemoryStorage snapshots are not serializable.
        // State lives in memory for the daemon's lifetime.
        Ok(())
    }

    /// Handle a JSON command and return a JSON response.
    pub fn handle_command(&self, cmd: &Value) -> String {
        let cmd_type = cmd["command"].as_str().unwrap_or("");

        let result = match cmd_type {
            "create_group" => self.cmd_create_group(cmd),
            "merge_pending_commit" => self.cmd_merge_pending_commit(cmd),
            "add_members" => self.cmd_add_members(cmd),
            "list_groups" => self.cmd_list_groups(),
            "process_welcome" => self.cmd_process_welcome(cmd),
            "accept_welcome" => self.cmd_accept_welcome(cmd),
            "send_message" => self.cmd_send_message(cmd),
            "process_message" => self.cmd_process_message(cmd),
            "export_secret" => self.cmd_export_secret(cmd),
            "keygen" => {
                let relay_urls: Vec<String> = cmd["relays"]
                    .as_array()
                    .unwrap_or(&vec![])
                    .iter()
                    .filter_map(|v| v.as_str().map(|s| s.to_string()))
                    .collect();
                match crate::keygen::generate_key_package(
                    &self.keys.secret_key().to_bech32().unwrap_or_default(),
                    &relay_urls,
                ) {
                    Ok(result) => Ok(serde_json::to_value(result).unwrap_or_default()),
                    Err(e) => Err(e),
                }
            }
            "ping" => Ok(serde_json::json!({"type": "pong"})),
            _ => Err(anyhow::anyhow!("Unknown command: {cmd_type}")),
        };

        match result {
            Ok(v) => serde_json::to_string(&v).unwrap_or_else(|e| {
                format!(r#"{{"type":"error","error":"Serialization failed: {e}"}}"#)
            }),
            Err(e) => {
                let err = serde_json::json!({
                    "type": "error",
                    "error": e.to_string(),
                });
                serde_json::to_string(&err).unwrap_or_else(|_| {
                    format!(r#"{{"type":"error","error":"{}"}}"#, e)
                })
            }
        }
    }
}
