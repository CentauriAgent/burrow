//! Media attachment parsing and download for the CLI.
//!
//! Parses `imeta` tags from messages, downloads encrypted blobs from Blossom,
//! and decrypts them using MDK's encrypted media manager.

use anyhow::{Context, Result};
use mdk_core::encrypted_media::types::MediaReference;
use mdk_core::prelude::*;
use std::fs;
use std::path::{Path, PathBuf};

/// Parsed media attachment from an imeta tag.
#[derive(Debug, Clone)]
pub struct MediaAttachment {
    pub url: String,
    pub mime_type: String,
    pub filename: String,
    pub original_hash_hex: String,
    pub nonce_hex: String,
    pub scheme_version: String,
    pub dimensions: Option<String>,
}

/// Parse imeta tags from a message's tags list.
pub fn parse_imeta_tags(tags: &[Vec<String>]) -> Vec<MediaAttachment> {
    let mut attachments = Vec::new();
    for tag in tags {
        if tag.is_empty() || tag[0] != "imeta" {
            continue;
        }
        let values = &tag[1..];
        let mut url = None;
        let mut mime = None;
        let mut fname = None;
        let mut hash = None;
        let mut nonce = None;
        let mut version = None;
        let mut dims = None;

        for v in values {
            let mut parts = v.splitn(2, ' ');
            let key = match parts.next() {
                Some(k) => k,
                None => continue,
            };
            let val = match parts.next() {
                Some(v) => v.to_string(),
                None => continue,
            };
            match key {
                "url" => url = Some(val),
                "m" => mime = Some(val),
                "filename" => fname = Some(val),
                "x" => hash = Some(val),
                "n" => nonce = Some(val),
                "v" => version = Some(val),
                "dim" => dims = Some(val),
                _ => {}
            }
        }

        if let (Some(url), Some(mime), Some(fname), Some(hash), Some(nonce), Some(version)) =
            (url, mime, fname, hash, nonce, version)
        {
            attachments.push(MediaAttachment {
                url,
                mime_type: mime,
                filename: fname,
                original_hash_hex: hash,
                nonce_hex: nonce,
                scheme_version: version,
                dimensions: dims,
            });
        }
    }
    attachments
}

/// Convert a MediaAttachment to MDK's MediaReference for decryption.
fn to_media_reference(att: &MediaAttachment) -> Result<MediaReference> {
    let hash_bytes = hex::decode(&att.original_hash_hex)
        .context("Invalid original_hash hex")?;
    let nonce_bytes = hex::decode(&att.nonce_hex)
        .context("Invalid nonce hex")?;

    let mut hash = [0u8; 32];
    let mut nonce = [0u8; 12];
    if hash_bytes.len() != 32 {
        anyhow::bail!("original_hash must be 32 bytes, got {}", hash_bytes.len());
    }
    if nonce_bytes.len() != 12 {
        anyhow::bail!("nonce must be 12 bytes, got {}", nonce_bytes.len());
    }
    hash.copy_from_slice(&hash_bytes);
    nonce.copy_from_slice(&nonce_bytes);

    let dimensions = att.dimensions.as_ref().and_then(|d| {
        let parts: Vec<&str> = d.split('x').collect();
        if parts.len() == 2 {
            Some((parts[0].parse::<u32>().ok()?, parts[1].parse::<u32>().ok()?))
        } else {
            None
        }
    });

    Ok(MediaReference {
        url: att.url.clone(),
        original_hash: hash,
        mime_type: att.mime_type.clone(),
        filename: att.filename.clone(),
        dimensions,
        scheme_version: att.scheme_version.clone(),
        nonce,
    })
}

/// Download an encrypted blob from Blossom and decrypt it using MDK.
/// Returns the path to the decrypted file saved in `media_dir`.
pub async fn download_and_decrypt<S: mdk_storage_traits::MdkStorageProvider>(
    mdk: &MDK<S>,
    group_id: &GroupId,
    attachment: &MediaAttachment,
    media_dir: &Path,
) -> Result<PathBuf> {
    // Check cache first
    let out_path = media_dir.join(&attachment.filename);
    if out_path.exists() {
        return Ok(out_path);
    }

    // Download encrypted blob
    let client = reqwest::Client::new();
    let resp = client
        .get(&attachment.url)
        .send()
        .await
        .context("Failed to download from Blossom")?;

    if !resp.status().is_success() {
        anyhow::bail!("Blossom returned HTTP {}", resp.status());
    }

    let encrypted_data = resp.bytes().await?.to_vec();

    // Build MediaReference for decryption
    let media_ref = to_media_reference(attachment)?;

    // Decrypt using MDK media manager
    let manager = mdk.media_manager(group_id.clone());
    let decrypted = manager
        .decrypt_from_download(&encrypted_data, &media_ref)
        .map_err(|e| anyhow::anyhow!("Decryption failed: {}", e))?;

    // Save to disk
    fs::create_dir_all(media_dir)?;
    fs::write(&out_path, &decrypted)?;

    Ok(out_path)
}

/// Auto-download and decrypt all media attachments in a message's tags.
/// Silently skips any attachments that fail to download.
pub async fn auto_download_attachments<S: mdk_storage_traits::MdkStorageProvider>(
    mdk: &MDK<S>,
    group_id: &GroupId,
    tags: &[Vec<String>],
    media_dir: &Path,
) {
    let attachments = parse_imeta_tags(tags);
    for att in &attachments {
        let path = media_dir.join(&att.filename);
        if path.exists() {
            continue;
        }
        if let Err(e) = download_and_decrypt(mdk, group_id, att, media_dir).await {
            eprintln!("⚠️ media download failed for {}: {}", att.filename, e);
        }
    }
}

/// Format a message for CLI display, including media attachment info.
pub fn format_message_with_media(
    content: &str,
    tags: &[Vec<String>],
    media_dir: Option<&Path>,
) -> String {
    let attachments = parse_imeta_tags(tags);
    if attachments.is_empty() {
        return content.to_string();
    }

    let mut parts = Vec::new();
    let mut content_is_filename = false;

    for att in &attachments {
        if att.filename == content {
            content_is_filename = true;
        }
        if let Some(dir) = media_dir {
            let path = dir.join(&att.filename);
            if path.exists() {
                parts.push(format!("[📎 {} -> {}]", att.filename, path.display()));
            } else {
                parts.push(format!("[📎 {} (encrypted, use `burrow media download` to decrypt)]", att.filename));
            }
        } else {
            parts.push(format!("[📎 {} attached]", att.filename));
        }
    }

    if content_is_filename {
        parts.join(" ")
    } else {
        format!("{} {}", content, parts.join(" "))
    }
}
