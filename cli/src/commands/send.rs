use anyhow::{Context, Result};
use mdk_core::MDK;
use nostr_sdk::prelude::*;
// sha2 available for future hash verification if needed
use std::fs;
use std::path::Path;

use crate::acl::access_control::AccessControl;
use crate::config;
use crate::keyring;
use crate::relay::pool;
use crate::storage::file_store::FileStore;

pub async fn run(
    group_id: String,
    message: String,
    key_path: Option<String>,
    data_dir: Option<String>,
    media_path: Option<String>,
    blossom_url: String,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store.find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let kp = key_path.map(std::path::PathBuf::from).unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    // ACL check on outgoing
    let acl = AccessControl::load(&data)?;
    if !acl.is_allowed(&keys.public_key().to_hex(), &group.nostr_group_id_hex) {
        anyhow::bail!("ACL: not allowed to send to this group");
    }

    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = keyring::open_mls_storage(&mls_db_path, &keys)?;
    let mdk = MDK::new(mdk_storage);
    let mls_group_id = mdk_core::prelude::GroupId::from_slice(
        &hex::decode(&group.mls_group_id_hex)?
    );

    let client = pool::connect(&keys, &group.relay_urls).await?;

    let event = if let Some(ref file_path) = media_path {
        // Media message: encrypt file, upload to Blossom, attach imeta tags
        let path = Path::new(file_path);
        if !path.exists() {
            anyhow::bail!("File not found: {}", file_path);
        }

        let file_data = fs::read(path)?;
        let filename = path.file_name()
            .map(|n| n.to_string_lossy().to_string())
            .unwrap_or_else(|| "attachment".to_string());
        let mime_type = guess_mime_type(&filename);

        eprintln!("📎 Encrypting {} ({} bytes, {})...", filename, file_data.len(), mime_type);

        // Encrypt via MIP-04
        let manager = mdk.media_manager(mls_group_id.clone());
        let upload_data = manager.encrypt_for_upload(&file_data, &mime_type, &filename)
            .map_err(|e| anyhow::anyhow!("MIP-04 encrypt failed: {}", e))?;

        let encrypted_hash_hex = hex::encode(upload_data.encrypted_hash);
        let nonce_hex = hex::encode(upload_data.nonce);

        // Upload to Blossom (BUD-02 auth)
        eprintln!("📤 Uploading to {}...", blossom_url);
        let auth_event = EventBuilder::new(
            Kind::Custom(24242),
            "Upload encrypted media",
        )
        .tag(Tag::parse(["t".to_string(), "upload".to_string()]).unwrap())
        .tag(Tag::parse(["x".to_string(), encrypted_hash_hex.clone()]).unwrap())
        .tag(Tag::parse(["expiration".to_string(), (Timestamp::now().as_secs() + 300).to_string()]).unwrap())
        .build(keys.public_key())
        .sign(&keys)
        .await
        .map_err(|e| anyhow::anyhow!("Failed to sign auth event: {}", e))?;

        let auth_b64 = {
            use base64::Engine;
            base64::engine::general_purpose::STANDARD.encode(auth_event.as_json().as_bytes())
        };

        let http = reqwest::Client::new();
        let resp = http
            .put(format!("{}/upload", blossom_url.trim_end_matches('/')))
            .header("Content-Type", "application/octet-stream")
            .header("X-SHA-256", &encrypted_hash_hex)
            .header("Authorization", format!("Nostr {}", auth_b64))
            .body(upload_data.encrypted_data)
            .send()
            .await
            .context("Blossom upload failed")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let body = resp.text().await.unwrap_or_default();
            anyhow::bail!("Blossom upload returned HTTP {}: {}", status, body);
        }

        let resp_text = resp.text().await?;
        let stored_url = if let Ok(json) = serde_json::from_str::<serde_json::Value>(&resp_text) {
            json.get("url")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string())
                .unwrap_or_else(|| format!("{}/{}", blossom_url.trim_end_matches('/'), encrypted_hash_hex))
        } else {
            format!("{}/{}", blossom_url.trim_end_matches('/'), encrypted_hash_hex)
        };

        eprintln!("✅ Uploaded: {}", stored_url);

        // Build imeta tag
        let original_hash_hex = hex::encode(upload_data.original_hash);
        let mut imeta_parts = vec![
            "imeta".to_string(),
            format!("url {}", stored_url),
            format!("m {}", upload_data.mime_type),
            format!("filename {}", upload_data.filename),
            format!("x {}", original_hash_hex),
            format!("n {}", nonce_hex),
            format!("v mip04-v2"),
        ];
        if let Some((w, h)) = upload_data.dimensions {
            imeta_parts.push(format!("dim {}x{}", w, h));
        }

        let imeta_tag = Tag::parse(imeta_parts)
            .map_err(|e| anyhow::anyhow!("Failed to build imeta tag: {}", e))?;

        // Use filename as content (convention for media-only messages)
        let content = if message.is_empty() || message == filename {
            &filename
        } else {
            &message
        };

        let rumor = EventBuilder::new(Kind::TextNote, content)
            .tag(imeta_tag)
            .build(keys.public_key());

        mdk.create_message(&mls_group_id, rumor)
            .context("Failed to encrypt media message")?
    } else {
        // Plain text message
        let rumor = EventBuilder::new(Kind::TextNote, &message)
            .build(keys.public_key());

        mdk.create_message(&mls_group_id, rumor)
            .context("Failed to encrypt message")?
    };

    let output = client.send_event(&event).await
        .context("Failed to publish message")?;

    if media_path.is_some() {
        println!("✅ Sent media to {} ({})", group.name, output.id().to_hex());
    } else {
        println!("✅ Sent to {} ({})", group.name, output.id().to_hex());
    }
    client.disconnect().await;
    Ok(())
}

/// Send a typing indicator (kind 10000 ephemeral MLS message).
pub async fn typing(
    group_id: String,
    key_path: Option<String>,
    data_dir: Option<String>,
) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let store = FileStore::new(&data)?;

    let group = store.find_group_by_prefix(&group_id)?
        .context("Group not found")?;

    let kp = key_path.map(std::path::PathBuf::from).unwrap_or_else(config::default_key_path);
    let secret = fs::read_to_string(&kp).context("Failed to read secret key")?;
    let sk = SecretKey::from_hex(secret.trim())
        .or_else(|_| SecretKey::from_bech32(secret.trim()))
        .context("Invalid secret key")?;
    let keys = Keys::new(sk);

    let mls_db_path = data.join("mls.sqlite");
    let mdk_storage = keyring::open_mls_storage(&mls_db_path, &keys)?;
    let mdk = MDK::new(mdk_storage);
    let mls_group_id = mdk_core::prelude::GroupId::from_slice(
        &hex::decode(&group.mls_group_id_hex)?
    );

    let rumor = EventBuilder::new(Kind::Custom(10000), "typing")
        .build(keys.public_key());

    let event = mdk.create_message(&mls_group_id, rumor)
        .context("Failed to encrypt typing indicator")?;

    let client = pool::connect(&keys, &group.relay_urls).await?;
    client.send_event(&event).await
        .context("Failed to publish typing indicator")?;

    client.disconnect().await;
    Ok(())
}

/// Guess MIME type from filename extension.
fn guess_mime_type(filename: &str) -> String {
    let ext = filename.rsplit('.').next().unwrap_or("").to_lowercase();
    match ext.as_str() {
        "mp3" => "audio/mpeg".to_string(),
        "m4a" | "aac" => "audio/aac".to_string(),
        "ogg" | "oga" => "audio/ogg".to_string(),
        "wav" => "audio/wav".to_string(),
        "opus" => "audio/opus".to_string(),
        "flac" => "audio/flac".to_string(),
        "webm" => "audio/webm".to_string(),
        "jpg" | "jpeg" => "image/jpeg".to_string(),
        "png" => "image/png".to_string(),
        "gif" => "image/gif".to_string(),
        "webp" => "image/webp".to_string(),
        "mp4" => "video/mp4".to_string(),
        "pdf" => "application/pdf".to_string(),
        _ => "application/octet-stream".to_string(),
    }
}
