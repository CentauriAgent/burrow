mod acl;
mod commands;
mod config;
pub mod media;
mod relay;
mod storage;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "burrow", version = "0.1.0")]
#[command(about = "🦫 Marmot Protocol encrypted messaging for AI agents and humans")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize identity and publish a KeyPackage
    Init {
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
        #[arg(short = 'r', long, num_args = 1..)]
        relay: Option<Vec<String>>,
        #[arg(short = 'g', long)]
        generate: bool,
    },
    /// Group management
    #[command(subcommand)]
    Group(GroupCommands),
    /// List all groups
    Groups {
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Invite a user to a group
    Invite {
        group_id: String,
        pubkey: String,
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Send an encrypted message
    Send {
        group_id: String,
        message: String,
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Read stored messages
    Read {
        group_id: String,
        #[arg(short = 'n', long, default_value = "50")]
        limit: usize,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Listen for real-time messages in a group
    Listen {
        group_id: String,
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Run persistent daemon on all groups (JSONL output)
    Daemon {
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
        #[arg(short = 'l', long)]
        log_file: Option<String>,
        #[arg(long, default_value = "5000")]
        reconnect_delay: u64,
        #[arg(long)]
        no_access_control: bool,
    },
    /// Manage NIP-59 welcome invitations
    #[command(subcommand)]
    Welcome(WelcomeCommands),
    /// Access control management
    #[command(subcommand)]
    Acl(AclCommands),
}

#[derive(Subcommand)]
enum GroupCommands {
    /// Create a new encrypted group
    Create {
        name: String,
        #[arg(long)]
        description: Option<String>,
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
        #[arg(short = 'r', long, num_args = 1..)]
        relay: Option<Vec<String>>,
    },
}

#[derive(Subcommand)]
enum WelcomeCommands {
    /// List pending NIP-59 welcome messages from relays
    List {
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Accept a welcome invitation and join the group
    Accept {
        /// Event ID of the gift wrap containing the welcome
        event_id: String,
        #[arg(short = 'k', long)]
        key_path: Option<String>,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
}

#[derive(Subcommand)]
enum AclCommands {
    /// Display access control config
    Show {
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Add contact to allowlist
    AddContact {
        pubkey: String,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Remove contact from allowlist
    RemoveContact {
        pubkey: String,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Add group to allowlist
    AddGroup {
        group_id: String,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Remove group from allowlist
    RemoveGroup {
        group_id: String,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
    /// Show audit log
    Audit {
        #[arg(long, default_value = "7")]
        days: u32,
        #[arg(short = 'd', long)]
        data_dir: Option<String>,
    },
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Init { key_path, data_dir, relay, generate } => {
            commands::init::run(key_path, data_dir, relay, generate).await?;
        }
        Commands::Group(sub) => match sub {
            GroupCommands::Create { name, description, key_path, data_dir, relay } => {
                commands::group::create(name, description, key_path, data_dir, relay).await?;
            }
        },
        Commands::Groups { data_dir } => {
            commands::group::list(data_dir)?;
        }
        Commands::Invite { group_id, pubkey, key_path, data_dir } => {
            commands::invite::run(group_id, pubkey, key_path, data_dir).await?;
        }
        Commands::Send { group_id, message, key_path, data_dir } => {
            commands::send::run(group_id, message, key_path, data_dir).await?;
        }
        Commands::Read { group_id, limit, data_dir } => {
            commands::read::run(group_id, limit, data_dir)?;
        }
        Commands::Listen { group_id, key_path, data_dir } => {
            commands::listen::run(group_id, key_path, data_dir).await?;
        }
        Commands::Daemon { key_path, data_dir, log_file, reconnect_delay, no_access_control } => {
            commands::daemon::run(key_path, data_dir, log_file, reconnect_delay, no_access_control).await?;
        }
        Commands::Welcome(sub) => match sub {
            WelcomeCommands::List { key_path, data_dir } => {
                commands::welcome::list(key_path, data_dir).await?;
            }
            WelcomeCommands::Accept { event_id, key_path, data_dir } => {
                commands::welcome::accept(event_id, key_path, data_dir).await?;
            }
        },
        Commands::Acl(sub) => match sub {
            AclCommands::Show { data_dir } => commands::acl::show(data_dir)?,
            AclCommands::AddContact { pubkey, data_dir } => commands::acl::add_contact(pubkey, data_dir)?,
            AclCommands::RemoveContact { pubkey, data_dir } => commands::acl::remove_contact(pubkey, data_dir)?,
            AclCommands::AddGroup { group_id, data_dir } => commands::acl::add_group(group_id, data_dir)?,
            AclCommands::RemoveGroup { group_id, data_dir } => commands::acl::remove_group(group_id, data_dir)?,
            AclCommands::Audit { days, data_dir } => commands::acl::show_audit(data_dir, days)?,
        },
    }

    Ok(())
}
