# Commonplace for iOS

A native SwiftUI app using Commonplace's Rust core, the same format-v1 packs, and local GGUF inference.
This is a development port. An unsigned build is not a release, and simulator checks do not satisfy the
physical-iPhone release gate. See [VALIDATION.md](VALIDATION.md) for evidence and outstanding acceptance checks.

The upstream maintainer accepted an `ios/` sibling to `android/` and use of the Commonplace name in
[issue #1](https://github.com/0xPD33/commonplace/issues/1#issuecomment-6872125089). This branch does not
publish an app, upload weights or open an upstream PR.

## What works

- Native Ask, Library, History and Settings screens, including Dark Mode and Dynamic Type.
- Streaming evidence cards, answers, thinking text, numbered citations and local passage/article reading.
- Source-scoped conversations, local history, stopping answers and sharing answers with source credits.
- Streaming tar/multipart imports through file descriptors, SHA-256 checks, pack switches and removal.
- In-place access to an **unpacked pack directory**, with a persistent security-scoped Files bookmark.
  Removing its library entry unlinks it; it does not delete the original directory. A tar still has to be
  unpacked: this is not random-access retrieval directly inside an 11 GB tar archive.
- Text, Markdown and text-PDF indexing on the device, with page references. Scanned PDFs need text recognition first.
- MiniCPM5-2B and Gemma 4 E2B **GGUF** model packs through llama.cpp's CPU backend. Pixel's `.litertlm`
  files and Tensor dispatch library are not used. Metal is intentionally disabled for the initial gate;
  CPU performance has to be measured before adding an accelerated path.
- Model admission from `os_proc_available_memory`, not installed RAM. File size plus 1 GiB is an explicit,
  uncalibrated admission estimate, not a guaranteed peak. Ling is excluded until its separate hardware tests pass.
- CPU continued processing on iOS 26+, when admitted by the OS; a short background task on earlier versions.
  Expiration cancels the answer. All models are unloaded while idle off screen, and reloaded on the next question.
- Diagnostics for available memory, RSS, physical footprint, resident/mmap comparison and a bounded Files probe.
- Separate accuracy/speed JSONL runs and export into the existing desktop evaluation harness.

Voice capture and bundled Phonon playback are not part of this initial port. No online substitute is used.

## The offline claim

**The app contains no network code, analytics or crash-reporting SDKs, and requests no network entitlements.**
Browser downloads are explicit external-browser actions. Packs and models are never fetched by the running app.

Unlike Android's missing `INTERNET` permission, iOS offers no universal per-app declaration that blocks every
network connection. This app cannot claim that Android guarantee. App Privacy Report can show reported activity;
it is not a firewall or proof of absence. For a hard offline check, use Airplane Mode **and turn Wi-Fi off**,
then ask questions and open sources. The first-run screen explains this distinction.

History, book marks, telemetry and installed packs live in Application Support, excluded from iCloud backup,
with protection until first unlock. Reports are shared only through an explicit share action. Accuracy exports
include questions and answers; device-only reports do not. A folder mounted from Files remains subject to the
storage/backup policy of its original provider. Choose already-local files before going offline.

## Build

Requires an Apple Silicon Mac, Xcode 26 or later with the iPhoneOS SDK, Rust, CMake and Python 3.
The locally verified toolchain is recorded in VALIDATION.md. The deployment target is iOS 17.

The flake now also defines an `aarch64-darwin` development shell. Xcode and its SDKs are installed separately:

```sh
nix develop
python3 ios/scripts/fetch-encoders.py
# One device slice; add aarch64-apple-ios-sim for the simulator slice.
ios/scripts/build-core.sh aarch64-apple-ios
xcodebuild -project ios/Commonplace.xcodeproj -scheme Commonplace \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath ios/build/DerivedData CODE_SIGNING_ALLOWED=NO build
python3 ios/scripts/check-offline.py \
  --app ios/build/DerivedData/Build/Products/Debug-iphoneos/Commonplace.app
```

On a Mac without Nix, the same script uses Xcode and the rustup toolchain. The original Linux Android shell
and CI remain separate. This native fallback is needed because the original flake was Linux-only; the added
Darwin shell still needs a Nix-equipped Mac check.

`build-core.sh` creates a static XCFramework and Swift bindings, and prepares the license notices. The
optional `ort-download` feature downloads the ort-sys **hash-pinned** ONNX Runtime 1.28 Apple archive at build
time only. Its TLS client is a build dependency, not an app runtime dependency. To use an independently
provided static framework, set `ORT_IOS_XCFWK_PATH` and keep the proper notices. See `ort-sys`'s build options.
Microsoft's matching official PyPI wheel supplies the complete ONNX legal notices; no Python runtime is shipped.

The encoders use the existing immutable Android revisions. The fetch script verifies Git blob IDs or LFS
SHA-256 before writing assets. Teacher models and LLM weights are not bundled. Generated files, build outputs,
weights and machine-specific signing state are git-ignored. The checked-in Xcode project is regenerated by
`python3 ios/scripts/generate-project.py`, with no third-party project generator.

For a release build, commit first and set `CP_IOS_PROFILE=release` for `build-core.sh`; choose Release in
Xcode. The script refuses a dirty release build. This does not bypass the physical-device release gate.

## Models and Files

Prepare the already-approved MiniCPM conversion locally:

```sh
python3 ios/scripts/prepare-model.py --minicpm
# Output: data/library/packs/minicpm5-2b; 1.42 GB download, checked against docs/MODELS.md.
```

`python3 ios/scripts/prepare-model.py --gemma` prepares the pinned Apache-2.0 Unsloth Gemma E2B
conversion listed in docs/MODELS.md (3.04 GB). For another Gemma GGUF that you already have, preserve its provenance:

```sh
python3 ios/scripts/prepare-model.py --gemma-file /path/to/gemma-4-E2B-it-Q4_0.gguf \
  --source-repo <repository> --revision <immutable-commit> --sha256 <expected-sha256> \
  --conversion-notice /path/to/conversion-NOTICE.txt
```

Transfer the **whole pack directory** to local Files storage, then choose Library → Add to your library →
Open an unpacked pack folder in place. Alternatively, archive the pack as `<pack_id>/...` in a tar and import
it. Downloaded existing knowledge/bundle tars use the original import format. Files security scopes must be
restored before Rust opens any index. A moved or unavailable directory is shown under Needs attention;
remove its stale link and select the directory again. Mounting hashes all listed files before admitting a pack.
The selected directory must not change while it is open; detach it before replacing files.

Opening an 11 GB directory in place, its long-term bookmark behavior, and memory mapping on device remain
hardware acceptance checks. The Files diagnostic maps a selected file without copying and touches at most
64 MiB spread across it; it **does not** show that all 11 GB can be resident.

## Tests and evaluation

```sh
swiftc ios/Commonplace/ModelPolicy.swift ios/Commonplace/ResearchRecord.swift \
  ios/Tests/PolicyAndStorageTests.swift -o /tmp/commonplace-policy-tests
/tmp/commonplace-policy-tests
cargo test --manifest-path core/Cargo.toml --locked \
  -p commonplace-core -p commonplace-llm -p commonplace-ffi --lib
```

For the real Swift/Rust/ONNX plumbing check on a Mac (no answer model, accuracy or phone-speed claim):

```sh
python3 ios/scripts/fetch-runtime-notices.py --host-runtime
swiftc -swift-version 6 -I ios/build/headers -L core/target/debug -lcommonplace_ffi \
  -Xlinker -rpath -Xlinker "$PWD/core/target/debug" \
  ios/Generated/commonplace_ffi.swift ios/Tests/CoreSmoke.swift -o /tmp/commonplace-core-smoke
ORT_DYLIB_PATH="$PWD/ios/build/host-runtime/libonnxruntime.dylib" \
  /tmp/commonplace-core-smoke "$PWD/ios/Resources/Encoders"
```

On a **physical iPhone**, Diagnostics → Accuracy accepts a JSONL question set. Import each required gated
file (or a concatenation with unique IDs), share the answers and metadata, then run the existing harness:

```sh
nix develop -c python3 eval/import.py --answers <export.answers.jsonl> \
  --queries eval/test.jsonl,eval/canary.jsonl,eval/abstention.jsonl,eval/robust.jsonl,eval/recent.jsonl \
  --metadata <export.answers.jsonl.meta.json> --require-physical \
  --run-id <ios-candidate> --system 'Commonplace iOS on <device>, build <hash>' \
  --model '<GGUF filename and SHA-256>' --library '<pack snapshots and manifests>'
# judge.py, abstain.py and pairwise.py as described in eval/README.md, for both rolls.
nix develop -c python3 eval/report.py --run <ios-candidate> --roll2 <ios-candidate2> \
  --gate <reference>,<reference2>
```

Keep the locked split for reporting. Do not use it to tune. Export records preserve citation segments and
timings. The original desktop report must still be paired with the correct model, library and build metadata;
a successful import alone is not a passed gate. Conversation-set exports currently use their supplied fixed
history, matching `run.py` without `--live-history`.

Speed mode accepts **only the unchanged `scripts/bench/perf.jsonl` bytes**, no judge. It requires confirmation
of an externally measured ≤34 °C start: iOS's thermal-state API does not supply a Celsius reading. Interleave
builds A/B/A/B. For background measurements, hide and lock the phone during a run, retain the foreground flag
and task-admission/expiration records, and inspect termination/jetsam reports. Record every measurement in
`docs/BENCHMARKS.md` with device, clean build hash and date. Do not substitute simulator numbers.
