/*
 * Transport layer module for hyper-svid-agent.
 * Provides connection handlers for vsock transport.
 */
pub mod vsock;

use tokio_vsock::VsockStream;

/*
 * Connect to the CA server over vsock using the configured client port.
 */
pub async fn connect_to_server(config: &crate::config::AgentConfig) -> anyhow::Result<VsockStream> {
    connect_to_server_port(config, config.client_port).await
}

/*
 * Connect to the CA server over vsock using a specific local client port.
 */
pub async fn connect_to_server_port(
    config: &crate::config::AgentConfig,
    client_port: u32,
) -> anyhow::Result<VsockStream> {
    vsock::connect_vsock_port(config, client_port).await
}
