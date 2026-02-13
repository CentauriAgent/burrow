//! Encrypted group messaging: send, receive, decrypt, and query message history.
//!
//! Implements MIP-03 message flow:
//! 1. Plaintext rumor → MLS encrypt → NIP-44 encrypt with exporter_secret →
//!    ephemeral key sign → kind 445 event → relay
//!
//! Receiving:
//! 1. Receive kind 445 event → decrypt NIP-44 with exporter_secret →
//!    MLS decrypt → extract rumor → verify author binding → store message

use flutter_rust_bridge::frb;
use mdk_core::prelude::*;
use nostr_sdk::prelude::*;

use crate::frb_generated::StreamSink;

use crate::api::error::BurrowError;
use crate::api::state;

/// A decrypted group message, flattened for FFI.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct GroupMessage {
    /// Hex-encoded event ID of the inner rumor (the actual message).
    pub event_id_hex: String,
    /// Hex-encoded public key of the message author.
    pub author_pubkey_hex: String,
    /// Message content (plaintext after decryption).
    pub content: String,
    /// Unix timestamp of message creation.
    pub created_at: u64,
    /// Hex-encoded MLS group ID this message belongs to.
    pub mls_group_id_hex: String,
    /// Message kind (usually 1 for text).
    pub kind: u64,
    /// Tags from the inner rumor as flat string arrays.
    pub tags: Vec<Vec<String>>,
    /// Hex-encoded wrapper event ID (the kind 445 event on relays).
    pub wrapper_event_id_hex: String,
    /// MLS epoch when this message was created.
    pub epoch: u64,
}

/// Result of processing an incoming kind 445 event.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct ProcessMessageResult {
    /// "application_message", "commit", "proposal", "pending_proposal", "unprocessable"
    pub result_type: String,
    /// The decrypted message (only set for "application_message").
    pub message: Option<GroupMessage>,
    /// Hex-encoded MLS group ID (set for all types).
    pub mls_group_id_hex: String,
    /// For proposal results, JSON-serialized evolution event to publish.
    pub evolution_event_json: Option<String>,
}

/// Send an encrypted message to a group (MIP-03).
///
/// Creates a plaintext rumor, MLS-encrypts it, NIP-44-encrypts with exporter_secret,
/// signs with an ephemeral key, and returns a kind 445 event ready for relay publication.
///
/// Returns JSON-serialized signed Event (kind 445).
#[frb]
pub async fn send_message(
    mls_group_id_hex: String,
    content: String,
) -> Result<String, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        // Build an unsigned rumor event with kind 1 (text note) content
        let rumor = EventBuilder::new(Kind::TextNote, &content)
            .build(s.keys.public_key());

        let event = s
            .mdk
            .create_message(&group_id, rumor)
            .map_err(BurrowError::from)?;

        serde_json::to_string(&event).map_err(|e| BurrowError::from(e.to_string()))
    })
    .await
}

/// Process an incoming kind 445 group message event.
///
/// Decrypts the NIP-44 layer using the group's exporter_secret, then MLS-decrypts
/// to recover the plaintext rumor. Handles application messages, commits, and proposals.
///
/// `event_json`: JSON-serialized kind 445 Event received from a relay.
#[frb]
pub async fn process_message(event_json: String) -> Result<ProcessMessageResult, BurrowError> {
    state::with_state(|s| {
        let event: Event =
            Event::from_json(&event_json).map_err(|e| BurrowError::from(e.to_string()))?;

        let result = s
            .mdk
            .process_message(&event)
            .map_err(BurrowError::from)?;

        match result {
            mdk_core::messages::MessageProcessingResult::ApplicationMessage(msg) => {
                let group_message = GroupMessage {
                    event_id_hex: msg.id.to_hex(),
                    author_pubkey_hex: msg.pubkey.to_hex(),
                    content: msg.content.clone(),
                    created_at: msg.created_at.as_secs(),
                    mls_group_id_hex: hex::encode(msg.mls_group_id.as_slice()),
                    kind: msg.kind.as_u16() as u64,
                    tags: msg
                        .tags
                        .iter()
                        .map(|t| t.as_slice().to_vec())
                        .collect(),
                    wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
                    epoch: msg.epoch.unwrap_or(0),
                };
                Ok(ProcessMessageResult {
                    result_type: "application_message".to_string(),
                    message: Some(group_message),
                    mls_group_id_hex: hex::encode(msg.mls_group_id.as_slice()),
                    evolution_event_json: None,
                })
            }
            mdk_core::messages::MessageProcessingResult::Commit { mls_group_id } => {
                Ok(ProcessMessageResult {
                    result_type: "commit".to_string(),
                    message: None,
                    mls_group_id_hex: hex::encode(mls_group_id.as_slice()),
                    evolution_event_json: None,
                })
            }
            mdk_core::messages::MessageProcessingResult::Proposal(update_result) => {
                let evolution_json =
                    serde_json::to_string(&update_result.evolution_event).unwrap_or_default();
                Ok(ProcessMessageResult {
                    result_type: "proposal".to_string(),
                    message: None,
                    mls_group_id_hex: hex::encode(update_result.mls_group_id.as_slice()),
                    evolution_event_json: Some(evolution_json),
                })
            }
            mdk_core::messages::MessageProcessingResult::PendingProposal { mls_group_id } => {
                Ok(ProcessMessageResult {
                    result_type: "pending_proposal".to_string(),
                    message: None,
                    mls_group_id_hex: hex::encode(mls_group_id.as_slice()),
                    evolution_event_json: None,
                })
            }
            mdk_core::messages::MessageProcessingResult::IgnoredProposal {
                mls_group_id,
                ..
            } => Ok(ProcessMessageResult {
                result_type: "ignored_proposal".to_string(),
                message: None,
                mls_group_id_hex: hex::encode(mls_group_id.as_slice()),
                evolution_event_json: None,
            }),
            mdk_core::messages::MessageProcessingResult::ExternalJoinProposal {
                mls_group_id,
            } => Ok(ProcessMessageResult {
                result_type: "external_join_proposal".to_string(),
                message: None,
                mls_group_id_hex: hex::encode(mls_group_id.as_slice()),
                evolution_event_json: None,
            }),
            mdk_core::messages::MessageProcessingResult::Unprocessable { mls_group_id } => {
                Ok(ProcessMessageResult {
                    result_type: "unprocessable".to_string(),
                    message: None,
                    mls_group_id_hex: hex::encode(mls_group_id.as_slice()),
                    evolution_event_json: None,
                })
            }
            mdk_core::messages::MessageProcessingResult::PreviouslyFailed => {
                Ok(ProcessMessageResult {
                    result_type: "previously_failed".to_string(),
                    message: None,
                    mls_group_id_hex: String::new(),
                    evolution_event_json: None,
                })
            }
        }
    })
    .await
}

/// Get message history for a group with optional pagination.
///
/// Returns messages ordered by creation time (descending).
#[frb]
pub async fn get_messages(
    mls_group_id_hex: String,
    limit: Option<u32>,
    offset: Option<u32>,
) -> Result<Vec<GroupMessage>, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let pagination = match (limit, offset) {
            (Some(l), Some(o)) => {
                Some(mdk_storage_traits::groups::Pagination::new(Some(l as usize), Some(o as usize)))
            }
            (Some(l), None) => {
                Some(mdk_storage_traits::groups::Pagination::new(Some(l as usize), Some(0)))
            }
            _ => None,
        };

        let messages = s
            .mdk
            .get_messages(&group_id, pagination)
            .map_err(BurrowError::from)?;

        Ok(messages
            .iter()
            .map(|msg| GroupMessage {
                event_id_hex: msg.id.to_hex(),
                author_pubkey_hex: msg.pubkey.to_hex(),
                content: msg.content.clone(),
                created_at: msg.created_at.as_secs(),
                mls_group_id_hex: hex::encode(msg.mls_group_id.as_slice()),
                kind: msg.kind.as_u16() as u64,
                tags: msg
                    .tags
                    .iter()
                    .map(|t| t.as_slice().to_vec())
                    .collect(),
                wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
                epoch: msg.epoch.unwrap_or(0),
            })
            .collect())
    })
    .await
}

/// Get a specific message by its event ID within a group.
#[frb]
pub async fn get_message(
    mls_group_id_hex: String,
    event_id_hex: String,
) -> Result<GroupMessage, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );
        let event_id =
            EventId::from_hex(&event_id_hex).map_err(|e| BurrowError::from(e.to_string()))?;

        let msg = s
            .mdk
            .get_message(&group_id, &event_id)
            .map_err(BurrowError::from)?
            .ok_or_else(|| BurrowError::from("Message not found".to_string()))?;

        Ok(GroupMessage {
            event_id_hex: msg.id.to_hex(),
            author_pubkey_hex: msg.pubkey.to_hex(),
            content: msg.content.clone(),
            created_at: msg.created_at.as_secs(),
            mls_group_id_hex: hex::encode(msg.mls_group_id.as_slice()),
            kind: msg.kind.as_u16() as u64,
            tags: msg
                .tags
                .iter()
                .map(|t| t.as_slice().to_vec())
                .collect(),
            wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
            epoch: msg.epoch.unwrap_or(0),
        })
    })
    .await
}

/// Build a Nostr filter for subscribing to group messages on relays.
///
/// Returns a JSON-serialized Filter for kind 445 events with the group's `h` tag.
/// Use this with the Nostr client to subscribe to real-time group messages.
#[frb]
pub async fn group_message_filter(mls_group_id_hex: String) -> Result<String, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let group = s
            .mdk
            .get_group(&group_id)
            .map_err(BurrowError::from)?
            .ok_or_else(|| BurrowError::from("Group not found".to_string()))?;

        let nostr_group_id_hex = hex::encode(group.nostr_group_id);

        let filter = Filter::new()
            .kind(Kind::MlsGroupMessage)
            .custom_tag(SingleLetterTag::lowercase(Alphabet::H), nostr_group_id_hex);

        serde_json::to_string(&filter).map_err(|e| BurrowError::from(e.to_string()))
    })
    .await
}

/// Fetch and process missed group messages from relays (catch-up sync).
///
/// For each group, queries relays for kind 445 events and processes them
/// through MDK's `process_message`. Returns the count of new messages found.
/// Call this on app startup before `listen_for_group_messages` to catch
/// messages sent while the app was offline.
#[frb]
pub async fn sync_group_messages() -> Result<u32, BurrowError> {
    let (client, groups) = state::with_state(|s| {
        let groups = s.mdk.get_groups().map_err(BurrowError::from)?;
        Ok((s.client.clone(), groups))
    })
    .await?;

    if groups.is_empty() {
        return Ok(0);
    }

    let mut new_message_count: u32 = 0;

    for group in &groups {
        let nostr_group_id_hex = hex::encode(group.nostr_group_id);
        let filter = Filter::new()
            .kind(Kind::MlsGroupMessage)
            .custom_tag(
                SingleLetterTag::lowercase(Alphabet::H),
                nostr_group_id_hex,
            )
            .limit(100);

        let events = client
            .fetch_events(filter, std::time::Duration::from_secs(10))
            .await
            .map_err(|e| BurrowError::from(e.to_string()))?;

        // Process each event through MDK (sorts by timestamp internally)
        for event in events.iter() {
            let result = state::with_state(|s| {
                s.mdk.process_message(event).map_err(BurrowError::from)
            })
            .await;

            if let Ok(mdk_core::messages::MessageProcessingResult::ApplicationMessage(_)) = result
            {
                new_message_count += 1;
            }
            // Commits, proposals, etc. are processed silently
        }
    }

    Ok(new_message_count)
}

/// Subscribe to kind 445 group message events for all groups and stream
/// decrypted messages to the Dart side.
///
/// Builds a filter for each active group's Nostr group ID, subscribes to
/// connected relays, and processes incoming events through MDK's
/// `process_message` pipeline. Only `ApplicationMessage` results (actual
/// chat messages) are forwarded; commits and proposals are handled silently.
///
/// Runs indefinitely until the stream is closed from the Dart side.
#[frb]
pub async fn listen_for_group_messages(
    sink: StreamSink<GroupMessage>,
) -> Result<(), BurrowError> {
    let (client, groups) = state::with_state(|s| {
        let groups = s.mdk.get_groups().map_err(BurrowError::from)?;
        Ok((s.client.clone(), groups))
    })
    .await?;

    if groups.is_empty() {
        // No groups — still listen so the stream stays open; will get no events.
        let filter = Filter::new()
            .kind(Kind::MlsGroupMessage)
            .since(Timestamp::now());
        client
            .subscribe(filter, None)
            .await
            .map_err(|e| BurrowError::from(e.to_string()))?;
    } else {
        // Build one combined filter using all group Nostr IDs in the `h` tag
        let nostr_group_ids: Vec<String> = groups
            .iter()
            .map(|g| hex::encode(g.nostr_group_id))
            .collect();
        let mut filter = Filter::new()
            .kind(Kind::MlsGroupMessage)
            .since(Timestamp::now());
        for gid in &nostr_group_ids {
            filter = filter.custom_tag(
                SingleLetterTag::lowercase(Alphabet::H),
                gid.clone(),
            );
        }
        client
            .subscribe(filter, None)
            .await
            .map_err(|e| BurrowError::from(e.to_string()))?;
    }

    client
        .handle_notifications(|notification| {
            let sink = &sink;
            async move {
                if let nostr_sdk::RelayPoolNotification::Event { event, .. } = notification {
                    if event.kind == Kind::MlsGroupMessage {
                        let event_json = event.as_json();
                        // Process through MDK (decrypt NIP-44 + MLS)
                        let result = state::with_state(|s| {
                            let evt: Event = Event::from_json(&event_json)
                                .map_err(|e| BurrowError::from(e.to_string()))?;
                            s.mdk
                                .process_message(&evt)
                                .map_err(BurrowError::from)
                        })
                        .await;

                        match result {
                            Ok(mdk_core::messages::MessageProcessingResult::ApplicationMessage(
                                msg,
                            )) => {
                                let group_message = GroupMessage {
                                    event_id_hex: msg.id.to_hex(),
                                    author_pubkey_hex: msg.pubkey.to_hex(),
                                    content: msg.content.clone(),
                                    created_at: msg.created_at.as_secs(),
                                    mls_group_id_hex: hex::encode(
                                        msg.mls_group_id.as_slice(),
                                    ),
                                    kind: msg.kind.as_u16() as u64,
                                    tags: msg
                                        .tags
                                        .iter()
                                        .map(|t| t.as_slice().to_vec())
                                        .collect(),
                                    wrapper_event_id_hex: msg.wrapper_event_id.to_hex(),
                                    epoch: msg.epoch.unwrap_or(0),
                                };
                                let _ = sink.add(group_message);
                            }
                            Ok(mdk_core::messages::MessageProcessingResult::Commit {
                                ..
                            }) => {
                                // MLS epoch advanced — group state updated silently
                            }
                            Ok(mdk_core::messages::MessageProcessingResult::Proposal(
                                _update_result,
                            )) => {
                                // Proposal received — group state updated by MDK.
                                // Evolution events are handled by the invite/group providers.
                            }
                            _ => {
                                // Other results (pending proposals, unprocessable, etc.)
                            }
                        }
                    }
                }
                Ok(false) // keep listening
            }
        })
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    Ok(())
}
