use anyhow::Result;
use chrono::Local;
use serde::Serialize;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

fn audit_dir(data_dir: &Path) -> PathBuf {
    data_dir.join("audit")
}

fn today_file(data_dir: &Path) -> PathBuf {
    let date = Local::now().format("%Y-%m-%d").to_string();
    audit_dir(data_dir).join(format!("{}.jsonl", date))
}

#[derive(Debug, Serialize)]
pub struct AuditEntry {
    pub timestamp: String,
    #[serde(rename = "type")]
    pub entry_type: String,
    #[serde(skip_serializing_if = "Option::is_none", rename = "senderPubkey")]
    pub sender_pubkey: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none", rename = "groupId")]
    pub group_id: Option<String>,
    pub allowed: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
}

pub fn log_entry(data_dir: &Path, entry: &AuditEntry) -> Result<()> {
    let dir = audit_dir(data_dir);
    fs::create_dir_all(&dir)?;
    let path = today_file(data_dir);
    let mut f = OpenOptions::new().create(true).append(true).open(&path)?;
    writeln!(f, "{}", serde_json::to_string(entry)?)?;
    Ok(())
}

pub fn log_message(data_dir: &Path, sender: &str, group_id: &str, allowed: bool, details: Option<&str>) {
    let entry = AuditEntry {
        timestamp: Local::now().to_rfc3339(),
        entry_type: "message".into(),
        sender_pubkey: Some(sender.into()),
        group_id: Some(group_id.into()),
        allowed,
        details: details.map(|s| s.into()),
    };
    let _ = log_entry(data_dir, &entry);
}

pub fn log_access_change(data_dir: &Path, details: &str) {
    let entry = AuditEntry {
        timestamp: Local::now().to_rfc3339(),
        entry_type: "access_change".into(),
        sender_pubkey: None,
        group_id: None,
        allowed: true,
        details: Some(details.into()),
    };
    let _ = log_entry(data_dir, &entry);
}

pub fn read_audit_log(data_dir: &Path, days: u32) -> Result<Vec<String>> {
    let dir = audit_dir(data_dir);
    let mut lines = Vec::new();
    if !dir.exists() { return Ok(lines); }
    let today = Local::now().date_naive();
    for i in 0..days {
        let date = today - chrono::Duration::days(i as i64);
        let path = dir.join(format!("{}.jsonl", date.format("%Y-%m-%d")));
        if path.exists() {
            let content = fs::read_to_string(&path)?;
            for line in content.lines() {
                if !line.trim().is_empty() {
                    lines.push(line.to_string());
                }
            }
        }
    }
    lines.sort();
    Ok(lines)
}
