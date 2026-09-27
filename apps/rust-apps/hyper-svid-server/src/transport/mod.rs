/*
 * Transport layer module for hyper-svid-server.
 * Provides connection listeners for vsock transport.
 */

pub mod vsock;

/* Peer information extracted from the underlying vsock connection. */
#[derive(Debug, Clone)]
pub struct PeerInfo {
    // vsock Context ID.
    pub peer_cid: u32,
}

impl PeerInfo {
    pub fn from_vsock(cid: u32) -> Self {
        Self { peer_cid: cid }
    }
}
