//! burrow-mls: MLS engine for Burrow CLI
//!
//! This binary provides MLS operations using the official MDK (Marmot Developer Kit),
//! guaranteeing wire-format compatibility with the Flutter app.
//!
//! ## Architecture
//!
//! The binary runs in two modes:
//!
//! 1. **One-shot commands** (keygen) — stateless, run and exit
//! 2. **Daemon mode** — keeps MDK state in memory, reads JSON commands from stdin,
//!    writes JSON responses to stdout (one per line). This is how the Node CLI
//!    communicates with it for stateful operations.

use std::io::{self, BufRead, Write};

use anyhow::{Context, Result};
use clap::{Parser, Subcommand};

mod keygen;
mod group;
mod message;
mod storage;

#[derive(Parser)]
#[command(name = "burrow-mls", version, about = "MLS engine for Burrow CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Generate an MLS KeyPackage (stateless, outputs JSON to stdout)
    Keygen {
        /// Secret key (hex or nsec). Also reads NOSTR_SECRET_KEY env var.
        #[arg(long, env = "NOSTR_SECRET_KEY")]
        secret_key: String,

        /// Relay URLs for the key package event tags
        #[arg(long, default_values_t = vec![
            "wss://relay.damus.io".to_string(),
            "wss://relay.primal.net".to_string(),
            "wss://nos.lol".to_string(),
            "wss://relay.ditto.pub".to_string(),
        ])]
        relay: Vec<String>,
    },

    /// Run in daemon mode — reads JSON commands from stdin, writes responses to stdout.
    /// Keeps MDK state in memory for the lifetime of the process.
    Daemon {
        /// Secret key (hex or nsec). Also reads NOSTR_SECRET_KEY env var.
        #[arg(long, env = "NOSTR_SECRET_KEY")]
        secret_key: String,

        /// State directory for persisting MLS state between restarts
        #[arg(long, default_value_t = default_state_dir())]
        state_dir: String,
    },
}

fn default_state_dir() -> String {
    let home = std::env::var("HOME").unwrap_or_else(|_| "~".to_string());
    format!("{home}/.burrow/mls-state")
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Keygen { secret_key, relay } => {
            let result = keygen::generate_key_package(&secret_key, &relay)?;
            println!("{}", serde_json::to_string(&result)?);
        }
        Commands::Daemon { secret_key, state_dir } => {
            daemon_loop(&secret_key, &state_dir)?;
        }
    }

    Ok(())
}

/// Daemon mode: keeps MDK in memory, processes JSON commands from stdin.
fn daemon_loop(secret_key: &str, state_dir: &str) -> Result<()> {
    use nostr_sdk::prelude::*;
    use mdk_core::MDK;
    use mdk_memory_storage::MdkMemoryStorage;

    let keys = Keys::parse(secret_key).context("Failed to parse secret key")?;
    let storage = MdkMemoryStorage::default();
    let mdk = MDK::new(storage);

    // Load persisted state if it exists
    let state = storage::DaemonState::load_or_new(state_dir, mdk, keys.clone())?;

    // Signal ready
    let ready = serde_json::json!({
        "type": "ready",
        "pubkey": keys.public_key().to_hex(),
    });
    println!("{}", ready);
    io::stdout().flush()?;

    let stdin = io::stdin();
    for line in stdin.lock().lines() {
        let line = line.context("Failed to read stdin")?;
        if line.trim().is_empty() {
            continue;
        }

        let cmd: serde_json::Value = match serde_json::from_str(&line) {
            Ok(v) => v,
            Err(e) => {
                let err = serde_json::json!({
                    "type": "error",
                    "error": format!("Invalid JSON: {e}"),
                });
                println!("{}", err);
                io::stdout().flush()?;
                continue;
            }
        };

        let response = state.handle_command(&cmd);
        println!("{}", response);
        io::stdout().flush()?;

        // Persist state after each command
        if let Err(e) = state.save(state_dir) {
            eprintln!("Warning: failed to persist state: {e}");
        }
    }

    // Final save
    state.save(state_dir)?;
    Ok(())
}
