use anyhow::Result;
use nostr_sdk::prelude::*;

/// Create a connected Nostr client with the given keys and relay URLs.
pub async fn connect(keys: &Keys, relay_urls: &[String]) -> Result<Client> {
    let client = Client::builder().signer(keys.clone()).build();
    for url in relay_urls {
        let _ = client.add_relay(url).await;
    }
    client.connect().await;
    Ok(client)
}
