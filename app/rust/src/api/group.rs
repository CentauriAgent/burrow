//! Group management: create MLS groups, list groups, get group info, leave group.
//!
//! Implements MIP-01 group construction with marmot_group_data extension (0xF2EE),
//! random 32-byte Nostr group IDs, and admin management.

use flutter_rust_bridge::frb;
use mdk_core::prelude::*;
use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;
use crate::api::state;

/// Group information flattened for FFI.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct GroupInfo {
    /// Hex-encoded MLS group ID (internal protocol identifier).
    pub mls_group_id_hex: String,
    /// Hex-encoded Nostr group ID (used for relay message routing via `h` tag).
    pub nostr_group_id_hex: String,
    /// Human-readable group name.
    pub name: String,
    /// Group description.
    pub description: String,
    /// Hex-encoded admin public keys.
    pub admin_pubkeys: Vec<String>,
    /// Current MLS epoch.
    pub epoch: u64,
    /// Group state: "active", "pending", or "inactive".
    pub state: String,
    /// Number of members in the group.
    pub member_count: u32,
    /// Whether this is a 1:1 direct message group (2 members, including self).
    pub is_direct_message: bool,
    /// For DMs: the peer's display name (from profile cache). None for groups.
    pub dm_peer_display_name: Option<String>,
    /// For DMs: the peer's profile picture URL. None for groups.
    pub dm_peer_picture: Option<String>,
    /// For DMs: the peer's pubkey hex. None for groups.
    pub dm_peer_pubkey_hex: Option<String>,
}

/// Member information for FFI, enriched with cached profile data.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct MemberInfo {
    /// Hex-encoded public key of the member.
    pub pubkey_hex: String,
    /// Display name from cached profile (if available).
    pub display_name: Option<String>,
    /// Profile picture URL from cached profile (if available).
    pub picture: Option<String>,
}

/// Result of creating a group, including welcome events for invited members.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct CreateGroupResult {
    /// The created group info.
    pub group: GroupInfo,
    /// JSON-serialized welcome rumor events (kind 444) to be gift-wrapped and sent to invitees.
    pub welcome_rumors_json: Vec<String>,
    /// Hex-encoded MLS group ID for subsequent operations.
    pub mls_group_id_hex: String,
}

/// Result of a group update operation (add/remove members, leave, etc.).
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct UpdateGroupResult {
    /// JSON-serialized kind 445 evolution event to publish to group relays.
    pub evolution_event_json: String,
    /// JSON-serialized welcome rumor events for newly added members (if any).
    pub welcome_rumors_json: Vec<String>,
    /// Hex-encoded MLS group ID this update applies to.
    pub mls_group_id_hex: String,
}

fn group_state_str(state: &group_types::GroupState) -> String {
    match state {
        group_types::GroupState::Active => "active".to_string(),
        group_types::GroupState::Pending => "pending".to_string(),
        group_types::GroupState::Inactive => "inactive".to_string(),
    }
}

fn group_to_info(group: &group_types::Group, s: &state::BurrowState) -> GroupInfo {
    let members_set = s
        .mdk
        .get_members(&group.mls_group_id)
        .unwrap_or_default();
    let members: Vec<PublicKey> = members_set.into_iter().collect();
    let member_count = members.len() as u32;
    let is_dm = member_count == 2;
    let self_pubkey = s.keys.public_key();

    let (dm_peer_display_name, dm_peer_picture, dm_peer_pubkey_hex) = if is_dm {
        if let Some(peer) = members.iter().find(|pk| **pk != self_pubkey) {
            let hex = peer.to_hex();
            let cached = s.profile_cache.get(&hex);
            (
                cached.and_then(|p| p.best_name()),
                cached.and_then(|p| p.picture.clone()),
                Some(hex),
            )
        } else {
            (None, None, None)
        }
    } else {
        (None, None, None)
    };

    GroupInfo {
        mls_group_id_hex: hex::encode(group.mls_group_id.as_slice()),
        nostr_group_id_hex: hex::encode(group.nostr_group_id),
        name: group.name.clone(),
        description: group.description.clone(),
        admin_pubkeys: group.admin_pubkeys.iter().map(|pk: &PublicKey| pk.to_hex()).collect(),
        epoch: group.epoch,
        state: group_state_str(&group.state),
        member_count,
        is_direct_message: is_dm,
        dm_peer_display_name,
        dm_peer_picture,
        dm_peer_pubkey_hex,
    }
}

/// Create a new MLS group (MIP-01).
///
/// Generates a random 32-byte Nostr group ID and configures the group with
/// the marmot_group_data extension (0xF2EE). The creator is automatically
/// added as an admin.
///
/// `member_key_package_events_json`: JSON-serialized kind 443 events for initial members.
/// Pass empty vec for a self-only group.
#[frb]
pub async fn create_group(
    name: String,
    description: String,
    admin_pubkeys_hex: Vec<String>,
    member_key_package_events_json: Vec<String>,
    relay_urls: Vec<String>,
) -> Result<CreateGroupResult, BurrowError> {
    state::with_state(|s| {
        // Parse admin pubkeys
        let admins: Vec<PublicKey> = admin_pubkeys_hex
            .iter()
            .map(|h| PublicKey::from_hex(h).map_err(|e| BurrowError::from(e.to_string())))
            .collect::<Result<Vec<_>, _>>()?;

        // Parse relay URLs
        let relays: Vec<RelayUrl> = relay_urls
            .iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect();

        // Parse key package events
        let kp_events: Vec<Event> = member_key_package_events_json
            .iter()
            .map(|j| {
                Event::from_json(j).map_err(|e| BurrowError::from(e.to_string()))
            })
            .collect::<Result<Vec<_>, _>>()?;

        // Build group config
        let config = mdk_core::groups::NostrGroupConfigData::new(
            name,
            description,
            None, // image_hash
            None, // image_key
            None, // image_nonce
            relays,
            admins,
        );

        let result = s
            .mdk
            .create_group(&s.keys.public_key(), kp_events, config)
            .map_err(BurrowError::from)?;

        // Serialize welcome rumors to JSON
        let welcome_jsons: Vec<String> = result
            .welcome_rumors
            .iter()
            .map(|r| serde_json::to_string(r).unwrap_or_default())
            .collect();

        let mls_group_id_hex = hex::encode(result.group.mls_group_id.as_slice());
        let group_info = group_to_info(&result.group, s);

        Ok(CreateGroupResult {
            group: group_info,
            welcome_rumors_json: welcome_jsons,
            mls_group_id_hex,
        })
    })
    .await
}

/// Merge pending commit after publishing the evolution event to relays.
///
/// MUST be called after successfully publishing a kind 445 commit event.
/// This prevents state forks per MIP-02.
#[frb]
pub async fn merge_pending_commit(mls_group_id_hex: String) -> Result<(), BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        s.mdk
            .merge_pending_commit(&group_id)
            .map_err(BurrowError::from)
    })
    .await
}

/// List all groups the current user belongs to.
#[frb]
pub async fn list_groups() -> Result<Vec<GroupInfo>, BurrowError> {
    state::with_state(|s| {
        let groups = s.mdk.get_groups().map_err(BurrowError::from)?;
        Ok(groups.iter().map(|g| group_to_info(g, s)).collect())
    })
    .await
}

/// Get info about a specific group by its MLS group ID.
#[frb]
pub async fn get_group(mls_group_id_hex: String) -> Result<GroupInfo, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let group = s
            .mdk
            .get_group(&group_id)
            .map_err(BurrowError::from)?
            .ok_or_else(|| BurrowError::from("Group not found".to_string()))?;
        Ok(group_to_info(&group, s))
    })
    .await
}

/// Get members of a group, enriched with cached profile data.
#[frb]
pub async fn get_group_members(mls_group_id_hex: String) -> Result<Vec<MemberInfo>, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let members = s.mdk.get_members(&group_id).map_err(BurrowError::from)?;
        Ok(members
            .iter()
            .map(|pk| {
                let hex = pk.to_hex();
                let cached = s.profile_cache.get(&hex);
                MemberInfo {
                    pubkey_hex: hex,
                    display_name: cached.and_then(|p| p.best_name()),
                    picture: cached.and_then(|p| p.picture.clone()),
                }
            })
            .collect())
    })
    .await
}

/// Leave a group. Creates a leave proposal that must be committed by an admin.
///
/// Returns an evolution event (kind 445) to publish to group relays.
#[frb]
pub async fn leave_group(mls_group_id_hex: String) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let result = s.mdk.leave_group(&group_id).map_err(BurrowError::from)?;
        let evolution_json =
            serde_json::to_string(&result.evolution_event).unwrap_or_default();

        let welcome_jsons: Vec<String> = result
            .welcome_rumors
            .iter()
            .flatten()
            .map(|r| serde_json::to_string(r).unwrap_or_default())
            .collect();

        Ok(UpdateGroupResult {
            evolution_event_json: evolution_json,
            welcome_rumors_json: welcome_jsons,
            mls_group_id_hex: hex::encode(result.mls_group_id.as_slice()),
        })
    })
    .await
}

/// Update group metadata (name, description). Admin-only.
#[frb]
pub async fn update_group_name(
    mls_group_id_hex: String,
    name: String,
) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let update = mdk_core::groups::NostrGroupDataUpdate::new().name(name);
        let result = s
            .mdk
            .update_group_data(&group_id, update)
            .map_err(BurrowError::from)?;

        let evolution_json =
            serde_json::to_string(&result.evolution_event).unwrap_or_default();

        Ok(UpdateGroupResult {
            evolution_event_json: evolution_json,
            welcome_rumors_json: vec![],
            mls_group_id_hex: hex::encode(result.mls_group_id.as_slice()),
        })
    })
    .await
}
