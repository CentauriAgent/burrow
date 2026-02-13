//! Message encryption/decryption — mirrors the Flutter app's message.rs logic.
//! Implements MIP-03 message flow.

use anyhow::Result;
use mdk_core::messages::MessageProcessingResult;
use mdk_storage_traits::GroupId;
use nostr_sdk::prelude::*;
use serde_json::Value;

use crate::storage::DaemonState;

impl DaemonState {
    /// Send an encrypted message to a group (MIP-03)
    ///
    /// Creates a plaintext rumor, MLS-encrypts it, NIP-44-encrypts with exporter_secret,
    /// signs with ephemeral key, returns kind 445 event JSON.
    pub fn cmd_send_message(&self, cmd: &Value) -> Result<Value> {
        let group_id_hex = cmd["mls_group_id_hex"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing mls_group_id_hex"))?;
        let content = cmd["content"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing content"))?;

        let group_id = GroupId::from_slice(&hex::decode(group_id_hex)?);

        // Build unsigned rumor (kind 1 text note)
        let rumor = EventBuilder::new(Kind::TextNote, content)
            .build(self.keys.public_key());

        let event = self.mdk()
            .create_message(&group_id, rumor)
            .map_err(|e| anyhow::anyhow!("MDK create_message error: {e}"))?;

        let event_json = serde_json::to_string(&event)
            .map_err(|e| anyhow::anyhow!("Failed to serialize event: {e}"))?;

        Ok(serde_json::json!({
            "type": "send_result",
            "event_json": event_json,
            "event_id": event.id.to_hex(),
            "mls_group_id_hex": group_id_hex,
        }))
    }

    /// Process an incoming kind 445 group message event
    pub fn cmd_process_message(&self, cmd: &Value) -> Result<Value> {
        let event_json = cmd["event_json"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing event_json"))?;

        let event: Event = Event::from_json(event_json)
            .map_err(|e| anyhow::anyhow!("Invalid event JSON: {e}"))?;

        let result = self.mdk()
            .process_message(&event)
            .map_err(|e| anyhow::anyhow!("MDK process_message error: {e}"))?;

        match result {
            MessageProcessingResult::ApplicationMessage(msg) => {
                Ok(serde_json::json!({
                    "type": "application_message",
                    "event_id_hex": msg.id.to_hex(),
                    "author_pubkey_hex": msg.pubkey.to_hex(),
                    "content": msg.content,
                    "created_at": msg.created_at.as_secs(),
                    "mls_group_id_hex": hex::encode(msg.mls_group_id.as_slice()),
                    "kind": msg.kind.as_u16(),
                    "wrapper_event_id_hex": msg.wrapper_event_id.to_hex(),
                    "epoch": msg.epoch.unwrap_or(0),
                    "tags": msg.tags.iter().map(|t| t.as_slice().to_vec()).collect::<Vec<Vec<String>>>(),
                }))
            }
            MessageProcessingResult::Commit { mls_group_id } => {
                Ok(serde_json::json!({
                    "type": "commit",
                    "mls_group_id_hex": hex::encode(mls_group_id.as_slice()),
                }))
            }
            MessageProcessingResult::Proposal(update_result) => {
                let evolution_json = serde_json::to_string(&update_result.evolution_event).unwrap_or_default();
                Ok(serde_json::json!({
                    "type": "proposal",
                    "mls_group_id_hex": hex::encode(update_result.mls_group_id.as_slice()),
                    "evolution_event_json": evolution_json,
                }))
            }
            MessageProcessingResult::PendingProposal { mls_group_id } => {
                Ok(serde_json::json!({
                    "type": "pending_proposal",
                    "mls_group_id_hex": hex::encode(mls_group_id.as_slice()),
                }))
            }
            MessageProcessingResult::Unprocessable { mls_group_id } => {
                Ok(serde_json::json!({
                    "type": "unprocessable",
                    "mls_group_id_hex": hex::encode(mls_group_id.as_slice()),
                }))
            }
            MessageProcessingResult::PreviouslyFailed => {
                Ok(serde_json::json!({
                    "type": "previously_failed",
                }))
            }
            MessageProcessingResult::IgnoredProposal { mls_group_id, .. } => {
                Ok(serde_json::json!({
                    "type": "ignored_proposal",
                    "mls_group_id_hex": hex::encode(mls_group_id.as_slice()),
                }))
            }
            MessageProcessingResult::ExternalJoinProposal { mls_group_id } => {
                Ok(serde_json::json!({
                    "type": "external_join_proposal",
                    "mls_group_id_hex": hex::encode(mls_group_id.as_slice()),
                }))
            }
        }
    }

    /// Get the exporter secret for a group (for NIP-44 encryption layer)
    pub fn cmd_export_secret(&self, cmd: &Value) -> Result<Value> {
        let group_id_hex = cmd["mls_group_id_hex"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing mls_group_id_hex"))?;

        let group_id = GroupId::from_slice(&hex::decode(group_id_hex)?);

        // Get the group to find the current epoch
        let group = self.mdk()
            .get_group(&group_id)
            .map_err(|e| anyhow::anyhow!("MDK get_group error: {e}"))?
            .ok_or_else(|| anyhow::anyhow!("Group not found"))?;

        // The exporter secret is stored by MDK internally and used in create_message/process_message.
        // For the NIP-44 layer, we need the group's exporter secret at the current epoch.
        // MDK stores this via the storage provider.
        use mdk_storage_traits::groups::GroupStorage;
        let secret = self.storage()
            .get_group_exporter_secret(&group_id, group.epoch)
            .map_err(|e| anyhow::anyhow!("Storage error: {e}"))?;

        match secret {
            Some(s) => {
                Ok(serde_json::json!({
                    "type": "exporter_secret",
                    "mls_group_id_hex": group_id_hex,
                    "epoch": group.epoch,
                    "secret_hex": hex::encode(s.secret.as_ref()),
                }))
            }
            None => {
                Err(anyhow::anyhow!("No exporter secret found for group at epoch {}", group.epoch))
            }
        }
    }
}
