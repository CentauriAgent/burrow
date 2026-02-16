//! Invite management: fetch KeyPackages, create Welcome events, handle incoming Welcomes.
//!
//! Implements MIP-02 welcome flow with state fork prevention:
//! 1. Add members → get commit + welcome events
//! 2. Publish commit (kind 445) to relays and wait for ack
//! 3. Only then send Welcome (kind 444) via NIP-59 gift wrap
//!
//! Also handles receiving and processing incoming Welcome messages.

use flutter_rust_bridge::frb;
use mdk_core::prelude::*;
use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;
use crate::api::group::UpdateGroupResult;
use crate::api::state;

/// Welcome information received from another user.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct WelcomeInfo {
    /// Hex-encoded welcome event ID.
    pub welcome_event_id: String,
    /// Hex-encoded MLS group ID.
    pub mls_group_id_hex: String,
    /// Hex-encoded Nostr group ID.
    pub nostr_group_id_hex: String,
    /// Group name from the welcome.
    pub group_name: String,
    /// Group description.
    pub group_description: String,
    /// Hex-encoded public key of the person who invited us.
    pub welcomer_pubkey_hex: String,
    /// Number of members in the group.
    pub member_count: u32,
    /// Welcome state: "pending", "accepted", or "declined".
    pub state: String,
}

/// Add members to an existing group. Admin-only.
///
/// `key_package_events_json`: JSON-serialized kind 443 KeyPackage events for each new member.
///
/// Returns an evolution event (commit) to publish and welcome rumors to gift-wrap.
/// IMPORTANT: Publish the evolution event FIRST, wait for relay ack, then merge_pending_commit,
/// then send welcome rumors via NIP-59 gift wrap. This prevents state forks per MIP-02.
#[frb]
pub async fn add_members(
    mls_group_id_hex: String,
    key_package_events_json: Vec<String>,
) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let kp_events: Vec<Event> = key_package_events_json
            .iter()
            .map(|j| Event::from_json(j).map_err(|e| BurrowError::from(e.to_string())))
            .collect::<Result<Vec<_>, _>>()?;

        let result = s
            .mdk
            .add_members(&group_id, &kp_events)
            .map_err(BurrowError::from)?;

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

/// Remove members from a group. Admin-only.
///
/// `pubkeys_hex`: Hex-encoded public keys of members to remove.
#[frb]
pub async fn remove_members(
    mls_group_id_hex: String,
    pubkeys_hex: Vec<String>,
) -> Result<UpdateGroupResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let pubkeys: Vec<PublicKey> = pubkeys_hex
            .iter()
            .map(|h| PublicKey::from_hex(h).map_err(|e| BurrowError::from(e.to_string())))
            .collect::<Result<Vec<_>, _>>()?;

        let result = s
            .mdk
            .remove_members(&group_id, &pubkeys)
            .map_err(BurrowError::from)?;

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

/// Process an incoming Welcome message (kind 444 rumor from NIP-59 gift wrap).
///
/// `wrapper_event_id_hex`: The hex-encoded event ID of the NIP-59 gift wrap event.
/// `welcome_rumor_json`: JSON-serialized UnsignedEvent (the unwrapped rumor).
///
/// Returns info about the group invitation for the user to accept or decline.
#[frb]
pub async fn process_welcome(
    wrapper_event_id_hex: String,
    welcome_rumor_json: String,
) -> Result<WelcomeInfo, BurrowError> {
    state::with_state(|s| {
        let wrapper_event_id = EventId::from_hex(&wrapper_event_id_hex)
            .map_err(|e| BurrowError::from(e.to_string()))?;

        let rumor: UnsignedEvent = serde_json::from_str(&welcome_rumor_json)
            .map_err(|e| BurrowError::from(e.to_string()))?;

        let welcome = s
            .mdk
            .process_welcome(&wrapper_event_id, &rumor)
            .map_err(BurrowError::from)?;

        let state_str = match welcome.state {
            welcome_types::WelcomeState::Pending => "pending",
            welcome_types::WelcomeState::Accepted => "accepted",
            welcome_types::WelcomeState::Declined => "declined",
            welcome_types::WelcomeState::Ignored => "ignored",
        };

        Ok(WelcomeInfo {
            welcome_event_id: welcome.id.to_hex(),
            mls_group_id_hex: hex::encode(welcome.mls_group_id.as_slice()),
            nostr_group_id_hex: hex::encode(welcome.nostr_group_id),
            group_name: welcome.group_name,
            group_description: welcome.group_description,
            welcomer_pubkey_hex: welcome.welcomer.to_hex(),
            member_count: welcome.member_count,
            state: state_str.to_string(),
        })
    })
    .await
}

/// Accept a pending welcome invitation and join the group.
#[frb]
pub async fn accept_welcome(welcome_event_id_hex: String) -> Result<(), BurrowError> {
    state::with_state(|s| {
        let event_id = EventId::from_hex(&welcome_event_id_hex)
            .map_err(|e| BurrowError::from(e.to_string()))?;

        let welcome = s
            .mdk
            .get_welcome(&event_id)
            .map_err(BurrowError::from)?
            .ok_or_else(|| BurrowError::from("Welcome not found".to_string()))?;

        s.mdk.accept_welcome(&welcome).map_err(BurrowError::from)
    })
    .await
}

/// Decline a pending welcome invitation.
#[frb]
pub async fn decline_welcome(welcome_event_id_hex: String) -> Result<(), BurrowError> {
    state::with_state(|s| {
        let event_id = EventId::from_hex(&welcome_event_id_hex)
            .map_err(|e| BurrowError::from(e.to_string()))?;

        let welcome = s
            .mdk
            .get_welcome(&event_id)
            .map_err(BurrowError::from)?
            .ok_or_else(|| BurrowError::from("Welcome not found".to_string()))?;

        s.mdk.decline_welcome(&welcome).map_err(BurrowError::from)
    })
    .await
}

/// List pending welcome invitations.
#[frb]
pub async fn list_pending_welcomes() -> Result<Vec<WelcomeInfo>, BurrowError> {
    state::with_state(|s| {
        let welcomes = s
            .mdk
            .get_pending_welcomes(None)
            .map_err(BurrowError::from)?;

        Ok(welcomes
            .iter()
            .map(|w| {
                let state_str = match w.state {
                    welcome_types::WelcomeState::Pending => "pending",
                    welcome_types::WelcomeState::Accepted => "accepted",
                    welcome_types::WelcomeState::Declined => "declined",
            welcome_types::WelcomeState::Ignored => "ignored",
                };
                WelcomeInfo {
                    welcome_event_id: w.id.to_hex(),
                    mls_group_id_hex: hex::encode(w.mls_group_id.as_slice()),
                    nostr_group_id_hex: hex::encode(w.nostr_group_id),
                    group_name: w.group_name.clone(),
                    group_description: w.group_description.clone(),
                    welcomer_pubkey_hex: w.welcomer.to_hex(),
                    member_count: w.member_count,
                    state: state_str.to_string(),
                }
            })
            .collect())
    })
    .await
}

/// Fetch and process incoming welcome messages from relays (catch-up sync).
///
/// Queries relays for kind 1059 (GiftWrap) events addressed to us, unwraps
/// each via NIP-59, and processes any kind 444 (MLS Welcome) rumors through
/// MDK's `process_welcome`. Returns the count of new welcomes found.
///
/// Call this on app startup and when refreshing the invites screen to catch
/// welcomes sent while the app was offline.
#[frb]
pub async fn sync_welcomes() -> Result<u32, BurrowError> {
    let (client, keys) = state::with_state(|s| {
        Ok((s.client.clone(), s.keys.clone()))
    })
    .await?;

    // Query for gift wraps addressed to us (NIP-59: recipient is in the p-tag)
    let filter = Filter::new()
        .kind(Kind::GiftWrap)
        .custom_tag(
            SingleLetterTag::lowercase(Alphabet::P),
            keys.public_key().to_hex(),
        )
        .limit(100);

    let events = client
        .fetch_events(filter, std::time::Duration::from_secs(10))
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    let mut welcome_count: u32 = 0;

    for event in events.iter() {
        // Unwrap NIP-59 gift wrap
        let rumor = match client.unwrap_gift_wrap(event).await {
            Ok(unwrapped) => unwrapped.rumor,
            Err(_) => continue,
        };

        // Only process kind 444 (MLS Welcome) rumors
        if rumor.kind != Kind::Custom(444) {
            continue;
        }

        let wrapper_event_id = event.id;
        let rumor_json = match serde_json::to_string(&rumor) {
            Ok(j) => j,
            Err(_) => continue,
        };

        // Process through MDK — silently skip already-processed welcomes
        let result = state::with_state(|s| {
            let unsigned: UnsignedEvent = serde_json::from_str(&rumor_json)
                .map_err(|e| BurrowError::from(e.to_string()))?;
            s.mdk
                .process_welcome(&wrapper_event_id, &unsigned)
                .map_err(BurrowError::from)
        })
        .await;

        if result.is_ok() {
            welcome_count += 1;
        }
    }

    Ok(welcome_count)
}

/// Gift-wrap a welcome rumor for a specific recipient and return the
/// serialized kind 1059 event for relay publication.
///
/// `welcome_rumor_json`: JSON-serialized unsigned welcome rumor event.
/// `recipient_pubkey_hex`: Hex-encoded pubkey of the welcome recipient.
#[frb]
pub async fn gift_wrap_welcome(
    welcome_rumor_json: String,
    recipient_pubkey_hex: String,
) -> Result<String, BurrowError> {
    let rumor: UnsignedEvent = serde_json::from_str(&welcome_rumor_json)
        .map_err(|e| BurrowError::from(format!("Failed to parse welcome rumor: {e}")))?;
    let recipient = PublicKey::from_hex(&recipient_pubkey_hex)
        .map_err(|e| BurrowError::from(e.to_string()))?;

    let keys = state::with_state(|s| Ok(s.keys.clone())).await?;

    let gift_wrap = EventBuilder::gift_wrap(&keys, &recipient, rumor, Vec::<Tag>::new())
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    serde_json::to_string(&gift_wrap).map_err(|e| BurrowError::from(e.to_string()))
}

/// Fetch a user's most recent KeyPackage from relays (kind 443).
///
/// Queries connected relays for all KeyPackage events published by the given pubkey,
/// then selects the newest one (highest `created_at`). This ensures we always use
/// the latest key package even when relays return results in arbitrary order or
/// the local cache has stale entries.
///
/// Returns the JSON-serialized kind 443 event, or error if not found.
#[frb]
pub async fn fetch_key_package(pubkey_hex: String) -> Result<String, BurrowError> {
    let pubkey =
        PublicKey::from_hex(&pubkey_hex).map_err(|e| BurrowError::from(e.to_string()))?;

    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    // Fetch ALL key packages for this pubkey — don't use .limit(1) because
    // that doesn't guarantee the newest event is returned, and the local
    // cache may have stale entries.
    let filter = Filter::new()
        .author(pubkey)
        .kind(Kind::MlsKeyPackage);

    let events = client
        .fetch_events(filter, std::time::Duration::from_secs(10))
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    // Select the newest key package by created_at timestamp.
    let event = events
        .into_iter()
        .max_by_key(|e| e.created_at)
        .ok_or_else(|| {
            BurrowError::from(format!(
                "No KeyPackage found for pubkey {}",
                pubkey_hex
            ))
        })?;

    serde_json::to_string(&event).map_err(|e| BurrowError::from(e.to_string()))
}
