use anyhow::Result;

use crate::acl::access_control::{self, AccessControl};
use crate::acl::audit;
use crate::config;

pub fn show(data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let acl = AccessControl::load(&data)?;
    let c = &acl.config;
    println!("🔐 Burrow Access Control");
    println!("========================");
    if !c.owner.npub.is_empty() {
        println!("Owner: {}", c.owner.npub);
    }
    if !c.owner.hex.is_empty() {
        println!("       {}", c.owner.hex);
    }
    println!("Policy: {}", c.default_policy);
    println!("\nAllowed Contacts ({}):", c.allowed_contacts.len());
    if c.allowed_contacts.is_empty() {
        println!("  (none — only owner can send messages)");
    } else {
        for contact in &c.allowed_contacts {
            println!("  • {}", contact);
        }
    }
    println!("\nAllowed Groups ({}):", c.allowed_groups.len());
    if c.allowed_groups.is_empty() {
        println!("  (none)");
    } else {
        for g in &c.allowed_groups {
            println!("  • {}", g);
        }
    }
    println!("\nSettings:");
    println!("  Log rejected content: {}", c.settings.log_rejected_content);
    println!("  Audit enabled: {}", c.settings.audit_enabled);
    Ok(())
}

pub fn add_contact(pubkey: String, data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let hex = access_control::resolve_to_hex(&pubkey)?;
    let mut acl = AccessControl::load(&data)?;
    acl.add_contact(&hex)?;
    audit::log_access_change(&data, &format!("Added contact: {}", hex));
    println!("✅ Added contact: {}", hex);
    Ok(())
}

pub fn remove_contact(pubkey: String, data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let hex = access_control::resolve_to_hex(&pubkey)?;
    let mut acl = AccessControl::load(&data)?;
    if acl.remove_contact(&hex)? {
        audit::log_access_change(&data, &format!("Removed contact: {}", hex));
        println!("✅ Removed contact: {}", hex);
    } else {
        println!("⚠️ Contact not found: {}", hex);
    }
    Ok(())
}

pub fn add_group(group_id: String, data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let mut acl = AccessControl::load(&data)?;
    acl.add_group(&group_id)?;
    audit::log_access_change(&data, &format!("Added group: {}", group_id));
    println!("✅ Added group: {}", group_id);
    Ok(())
}

pub fn remove_group(group_id: String, data_dir: Option<String>) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let mut acl = AccessControl::load(&data)?;
    if acl.remove_group(&group_id)? {
        audit::log_access_change(&data, &format!("Removed group: {}", group_id));
        println!("✅ Removed group: {}", group_id);
    } else {
        println!("⚠️ Group not found: {}", group_id);
    }
    Ok(())
}

pub fn show_audit(data_dir: Option<String>, days: u32) -> Result<()> {
    let data = config::data_dir(data_dir.as_deref());
    let lines = audit::read_audit_log(&data, days)?;
    if lines.is_empty() {
        println!("No audit entries in the last {} day(s).", days);
        return Ok(());
    }
    println!("📋 Audit log (last {} day(s), {} entries):", days, lines.len());
    println!("{}", "─".repeat(80));
    for line in &lines {
        if let Ok(entry) = serde_json::from_str::<serde_json::Value>(line) {
            let time = entry["timestamp"].as_str().unwrap_or("?");
            let icon = if entry["allowed"].as_bool().unwrap_or(false) { "✅" } else { "🚫" };
            let etype = entry["type"].as_str().unwrap_or("?");
            let sender = entry["senderPubkey"].as_str().map(|s| format!(" from:{}...", &s[..12.min(s.len())])).unwrap_or_default();
            let group = entry["groupId"].as_str().map(|s| format!(" group:{}...", &s[..12.min(s.len())])).unwrap_or_default();
            let details = entry["details"].as_str().unwrap_or("");
            println!("{} {} [{}]{}{} {}", icon, &time[..19.min(time.len())], etype, sender, group, details);
        } else {
            println!("{}", line);
        }
    }
    Ok(())
}
