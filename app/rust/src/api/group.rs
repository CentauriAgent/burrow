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
    /// Hex-encoded SHA-256 hash of encrypted group avatar on Blossom. None if no avatar.
    pub image_hash_hex: Option<String>,
    /// Whether this group has an avatar image set.
    pub has_image: bool,
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

    let image_hash_hex = group.image_hash.map(|h| hex::encode(h));
    let has_image = group.image_hash.is_some()
        && group.image_key.is_some()
        && group.image_nonce.is_some();

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
        image_hash_hex,
        has_image,
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
            welcome_rumors_json: vec![],
            mls_group_id_hex: hex::encode(result.mls_group_id.as_slice()),
        })
    })
    .await
}

/// Result of uploading a group image to Blossom.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct UploadGroupImageResult {
    /// Evolution event JSON (kind 445) to publish to relays.
    pub evolution_event_json: String,
    /// Hex-encoded SHA-256 of the encrypted blob (Blossom content address).
    pub encrypted_hash_hex: String,
    /// Hex-encoded MLS group ID.
    pub mls_group_id_hex: String,
}

/// Upload and set a group avatar image via encrypted Blossom (MIP-01).
///
/// 1. Validates and encrypts the image using MDK's `prepare_group_image_for_upload`.
/// 2. Uploads the encrypted blob to the Blossom server with NIP-98 auth.
/// 3. Updates the MLS group extension with image_hash/key/nonce/upload_key.
/// 4. Returns the evolution event to publish to relays.
#[frb]
pub async fn upload_group_image(
    mls_group_id_hex: String,
    image_data: Vec<u8>,
    mime_type: String,
    blossom_server_url: String,
) -> Result<UploadGroupImageResult, BurrowError> {
    use mdk_core::extension::group_image::prepare_group_image_for_upload;

    // 1. Encrypt the image
    let prepared = prepare_group_image_for_upload(&image_data, &mime_type)
        .map_err(|e| BurrowError::from(e.to_string()))?;

    let encrypted_hash_hex = hex::encode(prepared.encrypted_hash);

    // 2. Build NIP-98 authorization event for Blossom upload
    let upload_url = format!(
        "{}/upload/{}",
        blossom_server_url.trim_end_matches('/'),
        &encrypted_hash_hex
    );

    let payload_hash = sha256_hex(&prepared.encrypted_data);
    let auth_event = nostr_sdk::EventBuilder::new(
        nostr_sdk::Kind::HttpAuth,
        "",
    )
    .tag(nostr_sdk::Tag::parse(["u".to_string(), upload_url.clone()]).unwrap())
    .tag(nostr_sdk::Tag::parse(["method".to_string(), "PUT".to_string()]).unwrap())
    .tag(nostr_sdk::Tag::parse(["payload".to_string(), payload_hash]).unwrap())
    .build(prepared.upload_keypair.public_key())
    .sign(&prepared.upload_keypair)
    .await
    .map_err(|e| BurrowError::from(format!("Failed to sign NIP-98 event: {}", e)))?;

    let auth_header = format!("Nostr {}", base64_encode(&auth_event.as_json()));

    // 3. Upload to Blossom
    let client = reqwest::Client::new();
    let resp = client
        .put(&upload_url)
        .header("Content-Type", "application/octet-stream")
        .header("Authorization", &auth_header)
        .body(prepared.encrypted_data.as_ref().to_vec())
        .send()
        .await
        .map_err(|e| BurrowError::from(format!("Blossom upload failed: {}", e)))?;

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.unwrap_or_default();
        return Err(BurrowError::from(format!(
            "Blossom upload returned HTTP {}: {}",
            status, body
        )));
    }

    // 4. Update MLS group extension with image metadata
    let evolution_json = state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let update = mdk_core::groups::NostrGroupDataUpdate::new()
            .image_hash(Some(prepared.encrypted_hash))
            .image_key(Some(*prepared.image_key.as_ref()))
            .image_nonce(Some(*prepared.image_nonce.as_ref()))
            .image_upload_key(Some(*prepared.image_upload_key.as_ref()));

        let result = s
            .mdk
            .update_group_data(&group_id, update)
            .map_err(BurrowError::from)?;

        serde_json::to_string(&result.evolution_event)
            .map_err(|e| BurrowError::from(e.to_string()))
    })
    .await?;

    Ok(UploadGroupImageResult {
        evolution_event_json: evolution_json,
        encrypted_hash_hex,
        mls_group_id_hex,
    })
}

/// Download and decrypt a group's avatar image from Blossom.
///
/// Fetches the encrypted blob using the group's image_hash, then decrypts
/// using the image_key and image_nonce from the MLS group extension.
///
/// Returns the decrypted image bytes, or an error if the group has no image.
#[frb]
pub async fn download_group_image(
    mls_group_id_hex: String,
    blossom_server_url: String,
) -> Result<Vec<u8>, BurrowError> {
    use mdk_core::extension::group_image::decrypt_group_image;

    // Get image metadata from group extension
    let (image_hash, image_key, image_nonce) = state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let group = s
            .mdk
            .get_group(&group_id)
            .map_err(BurrowError::from)?
            .ok_or_else(|| BurrowError::from("Group not found".to_string()))?;

        let hash = group.image_hash
            .ok_or_else(|| BurrowError::from("Group has no avatar image".to_string()))?;
        let key = group.image_key
            .ok_or_else(|| BurrowError::from("Group image key missing".to_string()))?;
        let nonce = group.image_nonce
            .ok_or_else(|| BurrowError::from("Group image nonce missing".to_string()))?;

        Ok((hash, key, nonce))
    })
    .await?;

    // Download encrypted blob from Blossom
    let download_url = format!(
        "{}/{}",
        blossom_server_url.trim_end_matches('/'),
        hex::encode(image_hash)
    );

    let client = reqwest::Client::new();
    let resp = client
        .get(&download_url)
        .send()
        .await
        .map_err(|e| BurrowError::from(format!("Blossom download failed: {}", e)))?;

    if !resp.status().is_success() {
        return Err(BurrowError::from(format!(
            "Blossom download returned HTTP {}",
            resp.status()
        )));
    }

    let encrypted_data = resp
        .bytes()
        .await
        .map_err(|e| BurrowError::from(format!("Failed to read Blossom response: {}", e)))?
        .to_vec();

    // Decrypt
    let decrypted = decrypt_group_image(&encrypted_data, Some(&image_hash), &image_key, &image_nonce)
        .map_err(|e| BurrowError::from(e.to_string()))?;

    Ok(decrypted)
}

/// Remove a group's avatar image. Clears the MLS extension and optionally
/// deletes the blob from Blossom.
///
/// Returns the evolution event to publish to relays.
#[frb]
pub async fn remove_group_image(
    mls_group_id_hex: String,
) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        // Setting image_hash to None auto-clears image_key, image_nonce, image_upload_key
        let update = mdk_core::groups::NostrGroupDataUpdate::new()
            .image_hash(None);

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

/// Default Blossom server URL.
#[frb]
pub fn default_blossom_server() -> String {
    "https://blossom.primal.net".to_string()
}

// --- Internal helpers ---

fn sha256_hex(data: &[u8]) -> String {
    use sha2::{Sha256, Digest};
    hex::encode(Sha256::digest(data))
}

fn base64_encode(data: &str) -> String {
    use base64::Engine;
    base64::engine::general_purpose::STANDARD.encode(data.as_bytes())
}

/// Get the relay URLs configured for a group.
#[frb]
pub async fn get_group_relays(mls_group_id_hex: String) -> Result<Vec<String>, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let relays = s.mdk.get_relays(&group_id).map_err(BurrowError::from)?;
        Ok(relays.iter().map(|r| r.to_string()).collect())
    })
    .await
}

/// Update the relay URLs for a group. Admin-only.
/// Returns an evolution event to publish to the old and new relays.
#[frb]
pub async fn update_group_relays(
    mls_group_id_hex: String,
    relay_urls: Vec<String>,
) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let relays: Vec<RelayUrl> = relay_urls
            .iter()
            .filter_map(|u| RelayUrl::parse(u).ok())
            .collect();

        let update = mdk_core::groups::NostrGroupDataUpdate::new().relays(relays);
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

/// Update group name. Admin-only.
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

/// Update group description. Admin-only.
#[frb]
pub async fn update_group_description(
    mls_group_id_hex: String,
    description: String,
) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let update = mdk_core::groups::NostrGroupDataUpdate::new().description(description);
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
