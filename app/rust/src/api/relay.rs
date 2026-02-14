//! Relay management: connect to Nostr relays, publish and subscribe to events.

use flutter_rust_bridge::frb;
use nostr_sdk::prelude::*;

use crate::api::error::BurrowError;
use crate::api::state;

/// Status of a relay connection, flattened for FFI.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct RelayInfo {
    pub url: String,
    pub connected: bool,
}

/// Add a relay and connect to it.
#[frb]
pub async fn add_relay(url: String) -> Result<(), BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    client
        .add_relay(&url)
        .await
        .map(|_| ())
        .map_err(|e| BurrowError::from(e.to_string()))
}

/// Remove a relay.
#[frb]
pub async fn remove_relay(url: String) -> Result<(), BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    client
        .remove_relay(&url)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))
}

/// Connect to all added relays.
#[frb]
pub async fn connect_relays() -> Result<(), BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    client.connect().await;
    Ok(())
}

/// Disconnect from all relays.
#[frb]
pub async fn disconnect_relays() -> Result<(), BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    client.disconnect().await;
    Ok(())
}

/// List all configured relays and their connection status.
#[frb]
pub async fn list_relays() -> Result<Vec<RelayInfo>, BurrowError> {
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    let relays = client.relays().await;
    Ok(relays
        .iter()
        .map(|(url, relay)| RelayInfo {
            url: url.to_string(),
            connected: relay.is_connected(),
        })
        .collect())
}

/// Publish a signed event to connected relays.
/// Takes a JSON-serialized Nostr event string.
#[frb]
pub async fn publish_event_json(event_json: String) -> Result<String, BurrowError> {
    let event: Event =
        serde_json::from_str(&event_json).map_err(|e| BurrowError::from(e.to_string()))?;
    let client = state::with_state(|s| Ok(s.client.clone())).await?;
    let output = client
        .send_event(&event)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;
    Ok(output.id().to_hex())
}

/// Verify that an event has been published to at least one relay.
/// Queries all connected relays for the event by ID and returns true if found.
#[frb]
pub async fn verify_event_published(event_id_hex: String) -> Result<bool, BurrowError> {
    let event_id =
        EventId::from_hex(&event_id_hex).map_err(|e| BurrowError::from(e.to_string()))?;
    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    let filter = Filter::new().id(event_id).limit(1);

    let events = client
        .fetch_events(filter, std::time::Duration::from_secs(10))
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;

    Ok(events.into_iter().any(|e| e.id == event_id))
}

/// Publish an event to a specific relay URL.
/// Used for retry logic when broadcast publish fails verification.
#[frb]
pub async fn publish_event_json_to_relay(
    event_json: String,
    relay_url: String,
) -> Result<String, BurrowError> {
    let event: Event =
        serde_json::from_str(&event_json).map_err(|e| BurrowError::from(e.to_string()))?;
    let client = state::with_state(|s| Ok(s.client.clone())).await?;

    let relay_url_parsed: Url =
        Url::parse(&relay_url).map_err(|e| BurrowError::from(e.to_string()))?;
    let output = client
        .send_event_to(vec![relay_url_parsed], &event)
        .await
        .map_err(|e| BurrowError::from(e.to_string()))?;
    Ok(output.id().to_hex())
}

/// Default relays for the Marmot/Burrow network.
#[frb(sync)]
pub fn default_relay_urls() -> Vec<String> {
    vec![
        "wss://relay.ditto.pub".to_string(),
        "wss://nos.lol".to_string(),
        "wss://relay.damus.io".to_string(),
        "wss://relay.primal.net".to_string(),
    ]
}
