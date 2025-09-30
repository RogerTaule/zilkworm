use eyre::{Context, Result};
use reqwest::{header, Client};
use serde::Serialize;
use std::time::Duration;
use tracing::{debug, info};

#[derive(Clone, Debug)]
pub struct EthProofsConfig {
    pub endpoint: String,
    pub token: String,
    pub cluster_id: Option<String>,
    pub hook_id: Option<String>,
}

#[derive(Clone, Debug)]
pub struct EthproofsClient {
    client: Client,
    config: EthProofsConfig,
}

#[derive(Debug, Serialize)]
struct ProofPayload<'a> {
    block_number: u64,
    // #[serde(with = "base64_bytes")]
    proof: &'a [u8],
    cycle_count: u64,
    proving_millis: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    cluster_id: Option<&'a str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    hook_id: Option<&'a str>,
}

impl EthproofsClient {
    pub fn new(config: EthProofsConfig) -> Result<Self> {
        let mut headers = header::HeaderMap::new();
        headers.insert(header::CONTENT_TYPE, header::HeaderValue::from_static("application/json"));
        headers.insert(
            header::AUTHORIZATION,
            header::HeaderValue::from_str(&format!("Bearer {}", config.token))?,
        );

        let client = Client::builder()
            .default_headers(headers)
            .timeout(Duration::from_secs(30))
            .build()
            .wrap_err("failed to build reqwest client for ethproofs")?;

        Ok(Self { client, config })
    }

    pub async fn post_proof(
        &self,
        block_number: u64,
        proof_bytes: &[u8],
        cycle_count: u64,
        proving_millis: u64,
    ) -> Result<()> {
        let payload = ProofPayload {
            block_number,
            proof: proof_bytes,
            cycle_count,
            proving_millis,
            cluster_id: self.config.cluster_id.as_deref(),
            hook_id: self.config.hook_id.as_deref(),
        };

        let url = format!("{}/proofs", self.config.endpoint.trim_end_matches('/'));
        debug!(target = "ethproofs", %block_number, "posting proof to ethproofs");
        let res = self
            .client
            .post(url)
            .json(&payload)
            .send()
            .await
            .wrap_err("failed to POST proof to ethproofs")?;

        let status = res.status();
        let body = res.text().await.unwrap_or_default();
        if !status.is_success() {
            eyre::bail!("ethproofs responded with {}: {}", status, body);
        }

        info!(target = "ethproofs", %block_number, "successfully posted proof to ethproofs");
        Ok(())
    }
}