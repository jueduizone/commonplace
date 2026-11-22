# iOS validation ledger

Development branch: `codex/ios-port`. No App Store/TestFlight release or upstream PR is created by this work.

## Local evidence — 2026-11-23

Host: Apple M5 Pro, 64 GiB RAM, macOS arm64. Xcode 27.2 (27B52), iPhoneOS SDK 27.2,
Rust 1.95.0. Initial development build stamp: `e7f3370-dirty`.

- iPhone arm64 Rust static library with CPU llama.cpp and statically linked ONNX Runtime: built.
- Full Swift 6 iPhone application, unsigned Debug configuration: `xcodebuild` succeeded.
- Swift model-policy and history checks: passed (memory admission, unsupported models/formats, overflow,
  saved scope/citations, atomic replacement, corrupt-history isolation).
- Rust mounted-pack safety checks: four passed (no copy/destruction of source, moved directory removal,
  checksum and path traversal rejection, symlink escape and size-cap rejection).
- Real Swift → UniFFI → Rust → ONNX smoke: passed (index a local document, retrieve its known passage,
  open the source, switch its pack and remove it). This is a Mac plumbing check, not answer-quality evidence.
- Real MiniCPM5-2B GGUF: loaded and generated a streamed, cited fixture answer on the Mac host;
  model SHA-256 `d998b9433fe6e9b20e0dde7780e6c435a8a9cd893538ea70cbf1e09ce28cd5ae`.
  This checks generation plumbing, not accuracy or iPhone performance.
- Apple peak-RSS unit check: passed (native byte accounting).
- Offline source/build regression check: passed. Build-only HTTP/TLS dependencies are absent from the
  selected normal iOS dependency graph. This does not create an OS network permission boundary.
- Encoder assets: fetched at the existing immutable revisions and verified against Git/LFS object hashes.
- Full notices: generated for the selected Rust graph, native runtimes, font and models.

See docs/BENCHMARKS.md for the measurement record. Updated clean-build receipts and simulator results are
recorded there as they become available; the initial dirty stamp is not represented as a release build.

## Physical acceptance required

The paired iPhone was **unavailable** during initial checks. No physical-iPhone answer-quality, thermal,
background, jetsam or 11 GB pack result is claimed.

- [ ] Connect and trust a physical iPhone; sign/install with the user's development team.
- [ ] MiniCPM5-2B and Gemma E2B GGUF: foreground loading and answer generation with documented hashes.
- [ ] Two-roll accuracy gate on every supported model, including canary, abstention, robust and recent sets;
      required conversation checks; judge and pairwise checks on the desktop.
- [ ] Separate nine-prompt speed runs from measured ≤34 °C starts, interleaved A/B/A/B.
- [ ] Hide and lock during generation; record admission/expiration and inspect jetsam/termination reports.
- [ ] Compare resident and mmap weights using available-memory, physical-footprint and RSS snapshots.
- [ ] Open an unpacked approximately 11 GB pack in place from Files; verify no import copy, bookmark
      restoration across process restart, and safe behavior after provider move/removal.
- [ ] Verify all networking remains absent while offline; inspect App Privacy Report without claiming it
      replaces Android's network permission guarantee.
- [ ] Shared changes pass Android CI; never block an Android release on this checklist.

Ling is deliberately not selectable. Metal, on-device speech recognition and bundled TTS are later work;
no accelerated/background-GPU or voice-performance claim is made by this initial implementation.
