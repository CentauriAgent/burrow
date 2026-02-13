use std::path::PathBuf;

/// Default relays for Marmot/Burrow.
pub fn default_relays() -> Vec<String> {
    vec![
        "wss://relay.damus.io".into(),
        "wss://nos.lol".into(),
        "wss://relay.primal.net".into(),
        "wss://relay.ditto.pub".into(),
    ]
}

/// Resolve the data directory (~/.burrow by default).
pub fn data_dir(custom: Option<&str>) -> PathBuf {
    if let Some(d) = custom {
        PathBuf::from(d)
    } else {
        dirs::home_dir()
            .unwrap_or_else(|| PathBuf::from("."))
            .join(".burrow")
    }
}

/// Default secret key path (~/.clawstr/secret.key).
pub fn default_key_path() -> PathBuf {
    dirs::home_dir()
        .unwrap_or_else(|| PathBuf::from("."))
        .join(".clawstr")
        .join("secret.key")
}
