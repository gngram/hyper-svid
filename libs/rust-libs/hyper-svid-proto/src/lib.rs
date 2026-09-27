/*
 * Shared wire types and codec for the hyper-svid protocol.
 */

pub mod codec;
pub mod wire;

pub mod spiffe {
    pub mod workload {
        tonic::include_proto!("_");
    }
}
