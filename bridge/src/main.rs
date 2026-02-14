use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::io::{BufRead, BufReader, Seek, SeekFrom};
use std::path::PathBuf;
use std::process::Command;
use std::time::Duration;

// --- Config ---

struct Config {
    api_url: String,
    api_key: Option<String>,
    data_dir: PathBuf,
    burrow_binary: String,
    burrow_dir: PathBuf,
    self_pubkey: Option<String>,
}

impl Config {
    fn from_env() -> Self {
        let home = dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home/moltbot"));
        Self {
            api_url: std::env::var("OPENCLAW_API_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:18789/v1/chat/completions".into()),
            api_key: std::env::var("OPENCLAW_API_KEY").ok(),
            data_dir: std::env::var("BURROW_DATA_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|_| home.join(".burrow")),
            burrow_binary: std::env::var("BURROW_BINARY")
                .unwrap_or_else(|_| "/home/moltbot/clawd/burrow/target/release/burrow".into()),
            burrow_dir: std::env::var("BURROW_DIR")
                .map(PathBuf::from)
                .unwrap_or_else(|_| PathBuf::from("/home/moltbot/clawd/burrow")),
            self_pubkey: std::env::var("BURROW_SELF_PUBKEY").ok(),
        }
    }

    fn log_path(&self) -> PathBuf {
        self.data_dir.join("daemon.jsonl")
    }

    fn offset_path(&self) -> PathBuf {
        self.data_dir.join(".bridge-offset")
    }

    fn acl_path(&self) -> PathBuf {
        self.data_dir.join("access-control.json")
    }
}

// --- Data types ---

#[derive(Deserialize, Debug)]
struct LogEntry {
    #[serde(rename = "type")]
    entry_type: Option<String>,
    #[serde(rename = "groupId")]
    group_id: Option<String>,
    #[serde(rename = "senderPubkey")]
    sender_pubkey: Option<String>,
    content: Option<String>,
    allowed: Option<bool>,
}

#[derive(Deserialize)]
struct AccessControl {
    owner: Option<Owner>,
    #[serde(rename = "allowedContacts")]
    allowed_contacts: Option<Vec<String>>,
    #[serde(rename = "allowedGroups")]
    allowed_groups: Option<Vec<String>>,
}

#[derive(Deserialize)]
struct Owner {
    hex: Option<String>,
}

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
}

#[derive(Serialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Option<Vec<Choice>>,
}

#[derive(Deserialize)]
struct Choice {
    message: Option<ChoiceMessage>,
}

#[derive(Deserialize)]
struct ChoiceMessage {
    content: Option<String>,
}

// --- ACL ---

fn load_acl(config: &Config) -> Result<(HashSet<String>, HashSet<String>)> {
    let data = std::fs::read_to_string(config.acl_path())
        .unwrap_or_else(|_| r#"{"allowedContacts":[],"allowedGroups":[]}"#.into());
    let acl: AccessControl = serde_json::from_str(&data)?;

    let mut allowed_pubkeys = HashSet::new();
    if let Some(owner) = &acl.owner {
        if let Some(hex) = &owner.hex {
            allowed_pubkeys.insert(hex.clone());
        }
    }
    if let Some(contacts) = &acl.allowed_contacts {
        for c in contacts {
            allowed_pubkeys.insert(c.clone());
        }
    }

    let allowed_groups: HashSet<String> = acl
        .allowed_groups
        .unwrap_or_default()
        .into_iter()
        .collect();

    Ok((allowed_pubkeys, allowed_groups))
}

// --- Offset tracking ---

fn load_offset(config: &Config) -> u64 {
    std::fs::read_to_string(config.offset_path())
        .ok()
        .and_then(|s| s.trim().parse().ok())
        .unwrap_or(0)
}

fn save_offset(config: &Config, offset: u64) -> Result<()> {
    std::fs::write(config.offset_path(), offset.to_string())?;
    Ok(())
}

// --- OpenClaw API ---

async fn chat_completion(config: &Config, sender: &str, content: &str) -> Result<String> {
    let client = reqwest::Client::new();
    let req = ChatRequest {
        model: "default".into(),
        messages: vec![ChatMessage {
            role: "user".into(),
            content: format!("{}: {}", sender, content),
        }],
    };

    let mut builder = client.post(&config.api_url).json(&req);
    if let Some(key) = &config.api_key {
        builder = builder.header("Authorization", format!("Bearer {}", key));
    }

    let resp = builder.send().await?.error_for_status()?;
    let chat_resp: ChatResponse = resp.json().await?;

    chat_resp
        .choices
        .and_then(|c| c.into_iter().next())
        .and_then(|c| c.message)
        .and_then(|m| m.content)
        .context("No response content from API")
}

// --- Burrow send ---

fn burrow_send(config: &Config, group_id: &str, message: &str) -> Result<()> {
    eprintln!("[bridge] Sending response to group {}", &group_id[..12]);
    let output = Command::new(&config.burrow_binary)
        .arg("send")
        .arg(group_id)
        .arg(message)
        .current_dir(&config.burrow_dir)
        .env("HOME", dirs::home_dir().unwrap_or_else(|| PathBuf::from("/home/moltbot")))
        .output()
        .context("Failed to run burrow send")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        eprintln!("[bridge] burrow send failed: {}", stderr);
        // Don't return error — daemon restart is expected behavior
    } else {
        eprintln!("[bridge] Message sent successfully");
    }
    Ok(())
}

// --- Main loop ---

#[tokio::main]
async fn main() -> Result<()> {
    let config = Config::from_env();
    eprintln!("[bridge] Starting burrow-bridge");
    eprintln!("[bridge] API URL: {}", config.api_url);
    eprintln!("[bridge] Data dir: {}", config.data_dir.display());
    eprintln!("[bridge] Log file: {}", config.log_path().display());

    // Wait for log file to exist
    while !config.log_path().exists() {
        eprintln!("[bridge] Waiting for daemon log...");
        tokio::time::sleep(Duration::from_secs(5)).await;
    }

    let mut offset = load_offset(&config);
    eprintln!("[bridge] Starting at offset {}", offset);

    loop {
        // Reload ACL each iteration (hot reload)
        let (allowed_pubkeys, allowed_groups) = load_acl(&config).unwrap_or_default();

        let log_path = config.log_path();
        let metadata = match std::fs::metadata(&log_path) {
            Ok(m) => m,
            Err(_) => {
                tokio::time::sleep(Duration::from_secs(2)).await;
                continue;
            }
        };

        let file_len = metadata.len();

        // If file was truncated/rotated, reset offset
        if file_len < offset {
            eprintln!("[bridge] Log file truncated, resetting offset");
            offset = 0;
        }

        if file_len <= offset {
            // No new data
            tokio::time::sleep(Duration::from_secs(1)).await;
            continue;
        }

        // Read new lines
        let mut file = std::fs::File::open(&log_path)?;
        file.seek(SeekFrom::Start(offset))?;
        let mut reader = BufReader::new(file);
        let mut new_offset = offset;

        let mut lines = Vec::new();
        loop {
            let mut line = String::new();
            match reader.read_line(&mut line) {
                Ok(0) => break,
                Ok(n) => {
                    new_offset += n as u64;
                    let trimmed = line.trim();
                    if !trimmed.is_empty() {
                        lines.push(trimmed.to_string());
                    }
                }
                Err(e) => {
                    eprintln!("[bridge] Read error: {}", e);
                    break;
                }
            }
        }

        // Process lines
        for line in &lines {
            let entry: LogEntry = match serde_json::from_str(line) {
                Ok(e) => e,
                Err(_) => continue,
            };

            // Only process message type with allowed == true
            if entry.entry_type.as_deref() != Some("message") {
                continue;
            }
            if entry.allowed != Some(true) {
                continue;
            }

            let group_id = match &entry.group_id {
                Some(g) => g.clone(),
                None => continue,
            };
            let sender = match &entry.sender_pubkey {
                Some(s) => s.clone(),
                None => continue,
            };
            let content = match &entry.content {
                Some(c) => c.clone(),
                None => continue,
            };

            // Skip our own messages
            if let Some(self_pk) = &config.self_pubkey {
                if sender == *self_pk {
                    continue;
                }
            }

            // Skip single-emoji messages (reactions like 👍 🔥 ❤️)
            let trimmed = content.trim();
            if !trimmed.is_empty() && trimmed.chars().count() <= 3 && trimmed.chars().all(|c| !c.is_ascii_alphanumeric() && !c.is_ascii_punctuation() && !c.is_ascii_whitespace()) {
                eprintln!("[bridge] Skipping reaction/emoji: {}", trimmed);
                continue;
            }

            // Check ACL: sender must be in allowed set, group must be in allowed set
            if !allowed_pubkeys.contains(&sender) {
                eprintln!("[bridge] Sender {} not in ACL, skipping", &sender[..12]);
                continue;
            }
            if !allowed_groups.is_empty() && !allowed_groups.contains(&group_id) {
                eprintln!("[bridge] Group {} not in ACL, skipping", &group_id[..12]);
                continue;
            }

            eprintln!(
                "[bridge] Message from {} in group {}: {}",
                &sender[..12],
                &group_id[..12],
                if content.len() > 50 { &content[..50] } else { &content }
            );

            // Call OpenClaw
            let short_sender = &sender[..8];
            match chat_completion(&config, short_sender, &content).await {
                Ok(response) => {
                    eprintln!("[bridge] Got response ({} chars)", response.len());
                    if let Err(e) = burrow_send(&config, &group_id, &response) {
                        eprintln!("[bridge] Send error: {}", e);
                    }
                    // Small delay after send since daemon may restart
                    tokio::time::sleep(Duration::from_secs(3)).await;
                }
                Err(e) => {
                    eprintln!("[bridge] API error (not sending to chat): {}", e);
                }
            }
        }

        // Save offset
        offset = new_offset;
        save_offset(&config, offset)?;

        tokio::time::sleep(Duration::from_secs(1)).await;
    }
}
