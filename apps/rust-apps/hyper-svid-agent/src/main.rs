/*
 * hyper-svid-agent — guest VM certificate agent.
 * the agent connects to the host CA over vsock, requests certificates for
 * every Identity listed in the config, and writes the credentials to disk
 * with the configured POSIX ownership and permissions.
 */

use std::{path::PathBuf, process};

use clap::Parser;
use tracing::{error, info};
use tracing_subscriber::{fmt, EnvFilter};

mod client;
mod config;
mod csr;
mod transport;

use config::AgentConfig;

// hyper-svid guest agent — requests X.509 certificates from the host CA.
#[derive(Debug, Parser)]
#[command(
    name = "hyper-svid-agent",
    about = "Guest agent: requests Identity certificates from the hyper-svid host CA",
    version
)]
struct Cli {
    // Path to the agent JSON configuration file.
    #[arg(
        short,
        long,
        default_value = "/etc/hyper-svid/agent.json",
        value_name = "FILE"
    )]
    config: PathBuf,
}

#[tokio::main]
async fn main() {
    fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    // Root permissions are required to set file permissions and ownership.
    #[cfg(unix)]
    if unsafe { libc_getuid() } != 0 && std::env::var("HYPER_SVID_ALLOW_NON_ROOT").is_err() {
        error!("hyper-svid-agent must run as root to set file permissions and ownership");
        process::exit(1);
    }

    let cli = Cli::parse();

    let cfg = match AgentConfig::from_file(&cli.config) {
        Ok(c) => c,
        Err(e) => {
            error!(config = %cli.config.display(), error = %e, "Failed to load config");
            process::exit(1);
        }
    };

    info!("Starting hyper-svid-agent");

    if let Err(e) = client::run_agent(&cfg).await {
        error!(error = %e, "Agent encountered a fatal error");
        process::exit(1);
    }

    info!("hyper-svid-agent completed successfully");
}

#[cfg(unix)]
extern "C" {
    fn getuid() -> u32;
}

#[cfg(unix)]
unsafe fn libc_getuid() -> u32 {
    getuid()
}
