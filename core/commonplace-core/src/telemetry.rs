//! Per-query telemetry: stage timings, counts, token rates, RSS, thermal.

use crate::llm::GenStats;
use crate::retrieval::RetrievalStats;
use serde::Serialize;
use std::io::Write;
use std::path::Path;

pub const BUILD: &str = env!("CP_BUILD");

#[derive(Debug, Clone, Default, Serialize)]
pub struct QueryRecord {
    pub ts_ms: u64,
    pub query: String,
    /// What was searched: the rewritten question (or the raw one) plus any follow-up context.
    pub search_query: String,
    /// Article titles the rewrite model named as the question's topics.
    pub topics: Vec<String>,
    /// Thinking mode was on (reasoning tokens are in `synthesis.think_tokens`).
    pub think: bool,
    pub complex: bool,
    /// The intent head's best guess for the searched question: lookup, explain, compare or calc.
    pub intent: String,
    pub subqueries: Vec<String>,
    /// (stage, ms since the query started)
    pub stages: Vec<(String, f64)>,
    pub card_ms: f64,
    /// Extractive reader time and the shown span's margin (featured snippet).
    pub reader_ms: Option<f64>,
    pub featured_margin: Option<f32>,
    pub ttft_ms: Option<f64>,
    pub total_ms: f64,
    pub retrieval: RetrievalStats,
    /// The query-rewrite call (thinking-free, one line).
    pub rewrite: Option<GenStats>,
    pub compute: Option<GenStats>,
    pub synthesis: Option<GenStats>,
    pub evidence_tokens: usize,
    /// The evidence text the model read. Serve-eval prints it; telemetry files do not carry it.
    #[serde(skip)]
    pub evidence: String,
    pub n_sources: usize,
    pub unverified_sentences: usize,
    pub peak_rss_mb: f64,
    pub thermal_headroom: Option<f32>,
    pub threads: Option<u32>,
    pub model_id: Option<String>,
    /// The model's defaults (`profiles::ModelProfile::name`).
    pub profile: String,
    pub build: String,
    pub error: Option<String>,
}

pub fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

/// Peak resident set size in MiB. Apple reports ru_maxrss in bytes; Linux /proc reports KiB.
/// This is RSS, not Apple's physical footprint or its jetsam limit.
#[cfg(target_vendor = "apple")]
pub fn peak_rss_mb() -> f64 {
    let mut usage = std::mem::MaybeUninit::<libc::rusage>::uninit();
    // SAFETY: getrusage initializes the complete output on success, and the pointer is valid.
    if unsafe { libc::getrusage(libc::RUSAGE_SELF, usage.as_mut_ptr()) } == 0 {
        unsafe { usage.assume_init() }.ru_maxrss as f64 / (1024.0 * 1024.0)
    } else {
        0.0
    }
}

#[cfg(not(target_vendor = "apple"))]
pub fn peak_rss_mb() -> f64 {
    std::fs::read_to_string("/proc/self/status")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("VmHWM:"))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|kb| kb.parse::<f64>().ok())
        })
        .map(|kb| kb / 1024.0)
        .unwrap_or(0.0)
}

pub fn append_jsonl(path: &Path, rec: &QueryRecord) -> std::io::Result<()> {
    let mut f = std::fs::OpenOptions::new().create(true).append(true).open(path)?;
    let line = serde_json::to_string(rec).map_err(std::io::Error::other)?;
    writeln!(f, "{line}")
}

#[cfg(all(test, target_vendor = "apple"))]
mod apple_memory_tests {
    #[test]
    fn peak_rss_uses_bytes_rather_than_linux_kib() {
        let peak = super::peak_rss_mb();
        assert!(peak > 0.0 && peak < 1024.0 * 1024.0, "invalid Apple RSS in MiB: {peak}");
    }
}
