//! Group management — create groups, add members, manage state.
//! Mirrors the Flutter app's group.rs and invite.rs logic.

use anyhow::Result;
use mdk_core::groups::NostrGroupConfigData;
use mdk_storage_traits::GroupId;
use nostr_sdk::prelude::*;
use serde_json::Value;

use crate::storage::DaemonState;

impl DaemonState {
    /// Create a new MLS group (MIP-01)
    pub fn cmd_create_group(&self, cmd: &Value) -> Result<Value> {
        let name = cmd["name"].as_str().unwrap_or("Unnamed Group").to_string();
        let description = cmd["description"].as_str().unwrap_or("").to_string();

        let admin_pubkeys: Vec<PublicKey> = match cmd["admin_pubkeys"].as_array() {
            Some(arr) => arr
                .iter()
                .filter_map(|v| v.as_str())
                .filter_map(|h| PublicKey::from_hex(h).ok())
                .collect(),
            None => vec![self.keys.public_key()],
        };

        let relay_urls: Vec<RelayUrl> = match cmd["relays"].as_array() {
            Some(arr) => arr
                .iter()
                .filter_map(|v| v.as_str())
                .filter_map(|u| RelayUrl::parse(u).ok())
                .collect(),
            None => vec![],
        };

        let kp_events: Vec<Event> = match cmd["member_key_package_events"].as_array() {
            Some(arr) => arr
                .iter()
                .filter_map(|v| v.as_str())
                .filter_map(|j| Event::from_json(j).ok())
                .collect(),
            None => vec![],
        };

        let config = NostrGroupConfigData::new(
            name.clone(),
            description,
            None,
            None,
            None,
            relay_urls,
            admin_pubkeys,
        );

        let result = self.mdk()
            .create_group(&self.keys.public_key(), kp_events, config)
            .map_err(|e| anyhow::anyhow!("MDK create_group error: {e}"))?;

        let mls_group_id_hex = hex::encode(result.group.mls_group_id.as_slice());
        let nostr_group_id_hex = hex::encode(result.group.nostr_group_id);

        let welcome_jsons: Vec<String> = result
            .welcome_rumors
            .iter()
            .map(|r| serde_json::to_string(r).unwrap_or_default())
            .collect();

        Ok(serde_json::json!({
            "type": "create_group_result",
            "mls_group_id_hex": mls_group_id_hex,
            "nostr_group_id_hex": nostr_group_id_hex,
            "name": name,
            "epoch": result.group.epoch,
            "welcome_rumors_json": welcome_jsons,
        }))
    }

    /// Merge pending commit after publishing evolution event
    pub fn cmd_merge_pending_commit(&self, cmd: &Value) -> Result<Value> {
        let group_id_hex = cmd["mls_group_id_hex"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing mls_group_id_hex"))?;
        let group_id = GroupId::from_slice(
            &hex::decode(group_id_hex)?
        );

        self.mdk()
            .merge_pending_commit(&group_id)
            .map_err(|e| anyhow::anyhow!("MDK merge_pending_commit error: {e}"))?;

        Ok(serde_json::json!({
            "type": "ok",
            "mls_group_id_hex": group_id_hex,
        }))
    }

    /// Add members to a group (MIP-02)
    pub fn cmd_add_members(&self, cmd: &Value) -> Result<Value> {
        let group_id_hex = cmd["mls_group_id_hex"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing mls_group_id_hex"))?;
        let group_id = GroupId::from_slice(
            &hex::decode(group_id_hex)?
        );

        let kp_events: Vec<Event> = cmd["key_package_events"]
            .as_array()
            .unwrap_or(&vec![])
            .iter()
            .filter_map(|v| v.as_str())
            .filter_map(|j| Event::from_json(j).ok())
            .collect();

        let result = self.mdk()
            .add_members(&group_id, &kp_events)
            .map_err(|e| anyhow::anyhow!("MDK add_members error: {e}"))?;

        let evolution_json = serde_json::to_string(&result.evolution_event).unwrap_or_default();
        let welcome_jsons: Vec<String> = result
            .welcome_rumors
            .iter()
            .flatten()
            .map(|r| serde_json::to_string(r).unwrap_or_default())
            .collect();

        Ok(serde_json::json!({
            "type": "add_members_result",
            "mls_group_id_hex": hex::encode(result.mls_group_id.as_slice()),
            "evolution_event_json": evolution_json,
            "welcome_rumors_json": welcome_jsons,
        }))
    }

    /// List all groups
    pub fn cmd_list_groups(&self) -> Result<Value> {
        let groups = self.mdk()
            .get_groups()
            .map_err(|e| anyhow::anyhow!("MDK get_groups error: {e}"))?;

        let group_list: Vec<Value> = groups.iter().map(|g| {
            let members = self.mdk()
                .get_members(&g.mls_group_id)
                .unwrap_or_default();

            serde_json::json!({
                "mls_group_id_hex": hex::encode(g.mls_group_id.as_slice()),
                "nostr_group_id_hex": hex::encode(g.nostr_group_id),
                "name": g.name,
                "description": g.description,
                "epoch": g.epoch,
                "member_count": members.len(),
                "admin_pubkeys": g.admin_pubkeys.iter().map(|pk| pk.to_hex()).collect::<Vec<_>>(),
            })
        }).collect();

        Ok(serde_json::json!({
            "type": "groups",
            "groups": group_list,
        }))
    }

    /// Process a welcome message (kind 444 rumor)
    pub fn cmd_process_welcome(&self, cmd: &Value) -> Result<Value> {
        let wrapper_event_id_hex = cmd["wrapper_event_id_hex"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing wrapper_event_id_hex"))?;
        let welcome_rumor_json = cmd["welcome_rumor_json"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing welcome_rumor_json"))?;

        let wrapper_event_id = EventId::from_hex(wrapper_event_id_hex)
            .map_err(|e| anyhow::anyhow!("Invalid wrapper_event_id: {e}"))?;
        let rumor: UnsignedEvent = serde_json::from_str(welcome_rumor_json)
            .map_err(|e| anyhow::anyhow!("Invalid welcome rumor JSON: {e}"))?;

        let welcome = self.mdk()
            .process_welcome(&wrapper_event_id, &rumor)
            .map_err(|e| anyhow::anyhow!("MDK process_welcome error: {e}"))?;

        Ok(serde_json::json!({
            "type": "welcome_info",
            "welcome_event_id": welcome.id.to_hex(),
            "mls_group_id_hex": hex::encode(welcome.mls_group_id.as_slice()),
            "nostr_group_id_hex": hex::encode(welcome.nostr_group_id),
            "group_name": welcome.group_name,
            "group_description": welcome.group_description,
            "welcomer_pubkey_hex": welcome.welcomer.to_hex(),
            "member_count": welcome.member_count,
        }))
    }

    /// Accept a welcome
    pub fn cmd_accept_welcome(&self, cmd: &Value) -> Result<Value> {
        let welcome_event_id_hex = cmd["welcome_event_id_hex"].as_str()
            .ok_or_else(|| anyhow::anyhow!("Missing welcome_event_id_hex"))?;

        let event_id = EventId::from_hex(welcome_event_id_hex)
            .map_err(|e| anyhow::anyhow!("Invalid event_id: {e}"))?;

        let welcome = self.mdk()
            .get_welcome(&event_id)
            .map_err(|e| anyhow::anyhow!("MDK get_welcome error: {e}"))?
            .ok_or_else(|| anyhow::anyhow!("Welcome not found"))?;

        self.mdk()
            .accept_welcome(&welcome)
            .map_err(|e| anyhow::anyhow!("MDK accept_welcome error: {e}"))?;

        Ok(serde_json::json!({
            "type": "ok",
            "mls_group_id_hex": hex::encode(welcome.mls_group_id.as_slice()),
        }))
    }
}
