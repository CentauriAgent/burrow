use rust_lib_burrow_app::api::media::{build_imeta_tag, parse_imeta_tag};

#[test]
fn build_imeta_tag_basic() {
    let tag: Vec<String> = build_imeta_tag(
        "https://blossom.example.com/abc123".to_string(),
        "image/jpeg".to_string(),
        "photo.jpg".to_string(),
        "a".repeat(64),
        "b".repeat(24),
        Some("1920x1080".to_string()),
        Some("LEHV6nWB2yk8pyo0adR*.7kCMdnj".to_string()),
    )
    .unwrap();

    assert!(tag.iter().any(|v| v == "url https://blossom.example.com/abc123"));
    assert!(tag.iter().any(|v| v == "m image/jpeg"));
    assert!(tag.iter().any(|v| v == "filename photo.jpg"));
    assert!(tag.iter().any(|v| v == "dim 1920x1080"));
    assert!(tag.iter().any(|v| v == "blurhash LEHV6nWB2yk8pyo0adR*.7kCMdnj"));
    assert!(tag.iter().any(|v| v == &format!("x {}", "a".repeat(64))));
    assert!(tag.iter().any(|v| v == &format!("n {}", "b".repeat(24))));
    assert!(tag.iter().any(|v| v == "v mip04-v2"));
}

#[test]
fn build_imeta_tag_no_optional_fields() {
    let tag: Vec<String> = build_imeta_tag(
        "https://example.com/file".to_string(),
        "application/pdf".to_string(),
        "doc.pdf".to_string(),
        "a".repeat(64),
        "b".repeat(24),
        None,
        None,
    )
    .unwrap();

    assert!(!tag.iter().any(|v: &String| v.starts_with("dim ")));
    assert!(!tag.iter().any(|v: &String| v.starts_with("blurhash ")));
    assert!(tag.iter().any(|v| v == "v mip04-v2"));
}

#[test]
fn parse_imeta_tag_roundtrip() {
    let original_hash = "a".repeat(64);
    let nonce = "b".repeat(24);

    let tag: Vec<String> = build_imeta_tag(
        "https://blossom.example.com/file".to_string(),
        "image/png".to_string(),
        "screenshot.png".to_string(),
        original_hash.clone(),
        nonce.clone(),
        Some("800x600".to_string()),
        None,
    )
    .unwrap();

    let parsed = parse_imeta_tag(tag).unwrap();
    assert_eq!(parsed.url, "https://blossom.example.com/file");
    assert_eq!(parsed.mime_type, "image/png");
    assert_eq!(parsed.filename, "screenshot.png");
    assert_eq!(parsed.original_hash_hex, original_hash);
    assert_eq!(parsed.nonce_hex, nonce);
    assert_eq!(parsed.dimensions.as_deref(), Some("800x600"));
    assert_eq!(parsed.scheme_version, "mip04-v2");
}

#[test]
fn parse_imeta_tag_missing_url() {
    let tag = vec![
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "v mip04-v2".to_string(),
        "filename test.jpg".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("url"));
}

#[test]
fn parse_imeta_tag_missing_version() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "filename test.jpg".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("version"));
}

#[test]
fn parse_imeta_tag_wrong_version() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "filename test.jpg".to_string(),
        "v mip04-v1".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("Unsupported"));
}

#[test]
fn parse_imeta_tag_invalid_hash_length() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        "x abcdef".to_string(),
        format!("n {}", "b".repeat(24)),
        "filename test.jpg".to_string(),
        "v mip04-v2".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("hash"));
}

#[test]
fn parse_imeta_tag_invalid_nonce_length() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        "n abcdef".to_string(),
        "filename test.jpg".to_string(),
        "v mip04-v2".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("nonce"));
}

#[test]
fn parse_imeta_tag_mime_normalized_lowercase() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m IMAGE/JPEG".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "filename test.jpg".to_string(),
        "v mip04-v2".to_string(),
    ];
    let parsed = parse_imeta_tag(tag).unwrap();
    assert_eq!(parsed.mime_type, "image/jpeg");
}

#[test]
fn parse_imeta_tag_ignores_unknown_fields() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "filename test.jpg".to_string(),
        "v mip04-v2".to_string(),
        "future_field some_value".to_string(),
    ];
    let parsed = parse_imeta_tag(tag).unwrap();
    assert_eq!(parsed.url, "https://example.com/f");
}

#[test]
fn parse_imeta_tag_missing_nonce() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        "filename test.jpg".to_string(),
        "v mip04-v2".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("nonce"));
}

#[test]
fn parse_imeta_tag_missing_filename() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        "m image/jpeg".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "v mip04-v2".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("filename"));
}

#[test]
fn parse_imeta_tag_missing_mime() {
    let tag = vec![
        "url https://example.com/f".to_string(),
        format!("x {}", "a".repeat(64)),
        format!("n {}", "b".repeat(24)),
        "filename test.jpg".to_string(),
        "v mip04-v2".to_string(),
    ];
    let result = parse_imeta_tag(tag);
    assert!(result.is_err());
    assert!(result.unwrap_err().message.contains("mime"));
}

#[test]
fn build_and_parse_no_dimensions() {
    let hash = "a".repeat(64);
    let nonce = "b".repeat(24);
    let tag: Vec<String> = build_imeta_tag(
        "https://example.com/f".to_string(),
        "audio/mp3".to_string(),
        "song.mp3".to_string(),
        hash.clone(),
        nonce.clone(),
        None,
        None,
    )
    .unwrap();

    let parsed = parse_imeta_tag(tag).unwrap();
    assert!(parsed.dimensions.is_none());
    assert_eq!(parsed.mime_type, "audio/mp3");
}
