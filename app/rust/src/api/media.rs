//! Encrypted media: MIP-04 v2 implementation (FFI layer).
//!
//! Wraps MDK's `EncryptedMediaManager` for Flutter/Dart consumption.
//! Handles encrypt, decrypt, upload (Blossom), download, and imeta tag
//! construction/parsing per the Marmot protocol MIP-04 v2 spec.

use flutter_rust_bridge::frb;
use mdk_core::prelude::*;
use nostr_sdk::prelude::*;
use sha2::{Sha256, Digest};

use crate::api::error::BurrowError;
use crate::api::state;

// ---------------------------------------------------------------------------
// FFI-friendly types
// ---------------------------------------------------------------------------

/// Metadata about an encrypted file, ready for upload or imeta tag creation.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct EncryptedFileResult {
    /// Encrypted bytes (ciphertext + Poly1305 tag).
    pub encrypted_data: Vec<u8>,
    /// SHA-256 of the *original* plaintext file (hex).
    pub original_hash_hex: String,
    /// SHA-256 of the encrypted data (hex).
    pub encrypted_hash_hex: String,
    /// Canonical MIME type.
    pub mime_type: String,
    /// Original filename.
    pub filename: String,
    /// Original file size in bytes.
    pub original_size: u64,
    /// Encrypted file size in bytes.
    pub encrypted_size: u64,
    /// Image/video dimensions ("widthxheight") if applicable.
    pub dimensions: Option<String>,
    /// Blurhash string for progressive image loading.
    pub blurhash: Option<String>,
    /// Encryption nonce (hex, 24 chars / 12 bytes).
    pub nonce_hex: String,
}

/// Parsed imeta tag fields for a received encrypted media reference.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct MediaReferenceInfo {
    /// Blossom storage URL.
    pub url: String,
    /// SHA-256 of the original file (hex).
    pub original_hash_hex: String,
    /// MIME type.
    pub mime_type: String,
    /// Original filename.
    pub filename: String,
    /// Dimensions ("widthxheight") if present.
    pub dimensions: Option<String>,
    /// Encryption scheme version (e.g. "mip04-v2").
    pub scheme_version: String,
    /// Nonce (hex, 24 chars).
    pub nonce_hex: String,
}

/// Result of uploading encrypted media to a Blossom server.
#[frb(non_opaque)]
#[derive(Debug, Clone)]
pub struct UploadMediaResult {
    /// The Blossom URL where the encrypted file was stored.
    pub url: String,
    /// Serialised imeta tag values (flat string array) for inclusion in a message.
    pub imeta_tag_values: Vec<String>,
    /// The parsed media reference info.
    pub reference: MediaReferenceInfo,
}

// ---------------------------------------------------------------------------
// Public FFI functions
// ---------------------------------------------------------------------------

/// Encrypt a file for a group using MIP-04 v2.
///
/// Derives a file-specific key from the group's current MLS exporter secret,
/// generates a random nonce, and encrypts with ChaCha20-Poly1305 + AAD.
#[frb]
pub async fn encrypt_file(
    mls_group_id_hex: String,
    file_data: Vec<u8>,
    mime_type: String,
    filename: String,
) -> Result<EncryptedFileResult, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let manager = s.mdk.media_manager(group_id);
        let upload = manager
            .encrypt_for_upload(&file_data, &mime_type, &filename)
            .map_err(|e| BurrowError::from(e.to_string()))?;

        Ok(EncryptedFileResult {
            encrypted_data: upload.encrypted_data,
            original_hash_hex: hex::encode(upload.original_hash),
            encrypted_hash_hex: hex::encode(upload.encrypted_hash),
            mime_type: upload.mime_type,
            filename: upload.filename,
            original_size: upload.original_size,
            encrypted_size: upload.encrypted_size,
            dimensions: upload
                .dimensions
                .map(|(w, h)| format!("{}x{}", w, h)),
            blurhash: upload.blurhash,
            nonce_hex: hex::encode(upload.nonce),
        })
    })
    .await
}

/// Decrypt an encrypted file received from a group.
///
/// Uses the imeta tag fields to reconstruct AAD and derive the correct key
/// from the group's exporter secret (with epoch fallback).
#[frb]
pub async fn decrypt_file(
    mls_group_id_hex: String,
    encrypted_data: Vec<u8>,
    url: String,
    mime_type: String,
    filename: String,
    original_hash_hex: String,
    nonce_hex: String,
    scheme_version: String,
    dimensions: Option<String>,
) -> Result<Vec<u8>, BurrowError> {
    state::with_state(|s| {
        let group_id = GroupId::from_slice(
            &hex::decode(&mls_group_id_hex).map_err(|e| BurrowError::from(e.to_string()))?,
        );

        let reference = build_media_reference(
            url,
            mime_type,
            filename,
            original_hash_hex,
            nonce_hex,
            scheme_version,
            dimensions,
        )?;

        let manager = s.mdk.media_manager(group_id);
        let plaintext = manager
            .decrypt_from_download(&encrypted_data, &reference)
            .map_err(|e| BurrowError::from(e.to_string()))?;

        Ok(plaintext)
    })
    .await
}

/// Upload encrypted media to a Blossom server and return imeta tag data.
///
/// 1. Encrypts the file via MIP-04 v2.
/// 2. Uploads the ciphertext to `blossom_server_url` using HTTP PUT.
/// 3. Constructs the imeta tag from the upload result + returned URL.
#[frb]
pub async fn upload_media(
    mls_group_id_hex: String,
    file_data: Vec<u8>,
    mime_type: String,
    filename: String,
    blossom_server_url: String,
) -> Result<UploadMediaResult, BurrowError> {
    // Step 1: Encrypt
    let enc = encrypt_file(
        mls_group_id_hex.clone(),
        file_data,
        mime_type,
        filename,
    )
    .await?;

    // Step 2: Upload to Blossom (HTTP PUT with SHA-256 hash path)
    let upload_url = format!(
        "{}/upload/{}",
        blossom_server_url.trim_end_matches('/'),
        &enc.encrypted_hash_hex
    );

    let client = reqwest::Client::new();
    let resp = client
        .put(&upload_url)
        .header("Content-Type", "application/octet-stream")
        .body(enc.encrypted_data.clone())
        .send()
        .await
        .map_err(|e| BurrowError::from(format!("Blossom upload failed: {}", e)))?;

    if !resp.status().is_success() {
        return Err(BurrowError::from(format!(
            "Blossom upload returned HTTP {}",
            resp.status()
        )));
    }

    // Parse response to get the stored URL
    // Blossom servers typically return JSON with a "url" field
    let resp_text = resp
        .text()
        .await
        .map_err(|e| BurrowError::from(format!("Failed to read Blossom response: {}", e)))?;

    let stored_url = parse_blossom_url(&resp_text, &blossom_server_url, &enc.encrypted_hash_hex);

    // Step 3: Build imeta tag
    let imeta = build_imeta_tag(
        stored_url.clone(),
        enc.mime_type.clone(),
        enc.filename.clone(),
        enc.original_hash_hex.clone(),
        enc.nonce_hex.clone(),
        enc.dimensions.clone(),
        enc.blurhash.clone(),
    )?;

    let reference = MediaReferenceInfo {
        url: stored_url,
        original_hash_hex: enc.original_hash_hex,
        mime_type: enc.mime_type,
        filename: enc.filename,
        dimensions: enc.dimensions,
        scheme_version: "mip04-v2".to_string(),
        nonce_hex: enc.nonce_hex,
    };

    Ok(UploadMediaResult {
        url: reference.url.clone(),
        imeta_tag_values: imeta,
        reference,
    })
}

/// Download encrypted media from a Blossom URL and decrypt it.
///
/// 1. Fetches the ciphertext from `url`.
/// 2. Decrypts using the group's exporter secret + imeta metadata.
/// 3. Returns the plaintext bytes.
#[frb]
pub async fn download_media(
    mls_group_id_hex: String,
    url: String,
    mime_type: String,
    filename: String,
    original_hash_hex: String,
    nonce_hex: String,
    scheme_version: String,
    dimensions: Option<String>,
) -> Result<Vec<u8>, BurrowError> {
    // Step 1: Fetch
    let client = reqwest::Client::new();
    let resp = client
        .get(&url)
        .send()
        .await
        .map_err(|e| BurrowError::from(format!("Download failed: {}", e)))?;

    if !resp.status().is_success() {
        return Err(BurrowError::from(format!(
            "Download returned HTTP {}",
            resp.status()
        )));
    }

    let encrypted_data = resp
        .bytes()
        .await
        .map_err(|e| BurrowError::from(format!("Failed to read download body: {}", e)))?
        .to_vec();

    // Step 1.5: Verify encrypted data hash matches URL hash (Blossom content-addressing)
    let actual_hash = hex::encode(Sha256::digest(&encrypted_data));
    // Extract expected hash from URL (last path segment is typically the SHA-256 hash)
    if let Some(url_hash) = url.split('/').last() {
        if url_hash.len() == 64 && hex::decode(url_hash).is_ok() && actual_hash != url_hash {
            return Err(BurrowError::from(format!(
                "Download integrity check failed: expected hash {}, got {}",
                url_hash, actual_hash
            )));
        }
    }

    // Step 2: Decrypt
    decrypt_file(
        mls_group_id_hex,
        encrypted_data,
        url,
        mime_type,
        filename,
        original_hash_hex,
        nonce_hex,
        scheme_version,
        dimensions,
    )
    .await
}

/// Build an imeta tag value array from media metadata.
///
/// Returns a flat `Vec<String>` of "key value" pairs suitable for inclusion
/// in a Nostr event tag: `["imeta", "url ...", "m ...", ...]`.
#[frb]
pub fn build_imeta_tag(
    url: String,
    mime_type: String,
    filename: String,
    original_hash_hex: String,
    nonce_hex: String,
    dimensions: Option<String>,
    blurhash: Option<String>,
) -> Result<Vec<String>, BurrowError> {
    let mut values = vec![
        format!("url {}", url),
        format!("m {}", mime_type),
        format!("filename {}", filename),
    ];

    if let Some(dim) = dimensions {
        values.push(format!("dim {}", dim));
    }

    if let Some(bh) = blurhash {
        values.push(format!("blurhash {}", bh));
    }

    values.push(format!("x {}", original_hash_hex));
    values.push(format!("n {}", nonce_hex));
    values.push("v mip04-v2".to_string());

    Ok(values)
}

/// Parse an imeta tag (as a flat string array) into a `MediaReferenceInfo`.
///
/// Input: the tag values *after* the "imeta" prefix, e.g.
/// `["url https://...", "m image/jpeg", "filename photo.jpg", "x abc...", "n def...", "v mip04-v2"]`
#[frb]
pub fn parse_imeta_tag(tag_values: Vec<String>) -> Result<MediaReferenceInfo, BurrowError> {
    let mut url: Option<String> = None;
    let mut mime_type: Option<String> = None;
    let mut filename: Option<String> = None;
    let mut original_hash_hex: Option<String> = None;
    let mut nonce_hex: Option<String> = None;
    let mut dimensions: Option<String> = None;
    let mut version: Option<String> = None;

    for item in &tag_values {
        let parts: Vec<&str> = item.splitn(2, ' ').collect();
        if parts.len() != 2 {
            continue;
        }
        match parts[0] {
            "url" => url = Some(parts[1].to_string()),
            "m" => mime_type = Some(parts[1].trim().to_lowercase()),
            "filename" => filename = Some(parts[1].to_string()),
            "x" => {
                let h = parts[1].to_string();
                if hex::decode(&h).map_or(true, |b| b.len() != 32) {
                    return Err(BurrowError::from("Invalid 'x' (hash) field in imeta tag".to_string()));
                }
                original_hash_hex = Some(h);
            }
            "n" => {
                let n = parts[1].to_string();
                if hex::decode(&n).map_or(true, |b| b.len() != 12) {
                    return Err(BurrowError::from(
                        "Invalid 'n' (nonce) field in imeta tag — must be 24 hex chars (12 bytes)".to_string(),
                    ));
                }
                nonce_hex = Some(n);
            }
            "dim" => dimensions = Some(parts[1].to_string()),
            "v" => version = Some(parts[1].to_string()),
            _ => {} // ignore unknown fields for forward compat
        }
    }

    let scheme_version =
        version.ok_or_else(|| BurrowError::from("Missing 'v' (version) in imeta tag".to_string()))?;
    if scheme_version != "mip04-v2" {
        return Err(BurrowError::from(format!(
            "Unsupported MIP-04 version: {}",
            scheme_version
        )));
    }

    Ok(MediaReferenceInfo {
        url: url.ok_or_else(|| BurrowError::from("Missing 'url' in imeta tag".to_string()))?,
        original_hash_hex: original_hash_hex
            .ok_or_else(|| BurrowError::from("Missing 'x' (hash) in imeta tag".to_string()))?,
        mime_type: mime_type
            .ok_or_else(|| BurrowError::from("Missing 'm' (mime_type) in imeta tag".to_string()))?,
        filename: filename
            .ok_or_else(|| BurrowError::from("Missing 'filename' in imeta tag".to_string()))?,
        dimensions,
        scheme_version,
        nonce_hex: nonce_hex
            .ok_or_else(|| BurrowError::from("Missing 'n' (nonce) in imeta tag".to_string()))?,
    })
}

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/// Build an `mdk_core::encrypted_media::MediaReference` from flat FFI fields.
fn build_media_reference(
    url: String,
    mime_type: String,
    filename: String,
    original_hash_hex: String,
    nonce_hex: String,
    scheme_version: String,
    dimensions: Option<String>,
) -> Result<mdk_core::encrypted_media::MediaReference, BurrowError> {
    let hash_bytes = hex::decode(&original_hash_hex)
        .map_err(|e| BurrowError::from(format!("Invalid hash hex: {}", e)))?;
    if hash_bytes.len() != 32 {
        return Err(BurrowError::from("Hash must be 32 bytes".to_string()));
    }
    let mut original_hash = [0u8; 32];
    original_hash.copy_from_slice(&hash_bytes);

    let nonce_bytes =
        hex::decode(&nonce_hex).map_err(|e| BurrowError::from(format!("Invalid nonce hex: {}", e)))?;
    if nonce_bytes.len() != 12 {
        return Err(BurrowError::from("Nonce must be 12 bytes".to_string()));
    }
    let mut nonce = [0u8; 12];
    nonce.copy_from_slice(&nonce_bytes);

    let dims = dimensions.and_then(|d| {
        let parts: Vec<&str> = d.split('x').collect();
        if parts.len() == 2 {
            Some((parts[0].parse::<u32>().ok()?, parts[1].parse::<u32>().ok()?))
        } else {
            None
        }
    });

    Ok(mdk_core::encrypted_media::MediaReference {
        url,
        original_hash,
        mime_type,
        filename,
        dimensions: dims,
        scheme_version,
        nonce,
    })
}

/// Try to extract a URL from a Blossom server response.
/// Falls back to constructing a URL from the server base + hash.
fn parse_blossom_url(response_body: &str, server_base: &str, hash_hex: &str) -> String {
    // Try JSON { "url": "..." }
    if let Ok(v) = serde_json::from_str::<serde_json::Value>(response_body) {
        if let Some(url) = v.get("url").and_then(|u| u.as_str()) {
            return url.to_string();
        }
    }
    // Fallback: server_base/<hash>
    format!("{}/{}", server_base.trim_end_matches('/'), hash_hex)
}
