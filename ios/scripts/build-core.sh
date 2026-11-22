#!/usr/bin/env bash
# Apple toolchains are supplied by Xcode. No network code is linked into the app.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
if [[ -z "${IN_NIX_SHELL:-}" && -x "$HOME/.cargo/bin/cargo" ]]; then export PATH="$HOME/.cargo/bin:$PATH"; fi
export IPHONEOS_DEPLOYMENT_TARGET=${IPHONEOS_DEPLOYMENT_TARGET:-17.0}
export MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-14.0}
TARGETS=("${@:-aarch64-apple-ios}")
PROFILE=${CP_IOS_PROFILE:-dev}
if [[ "$PROFILE" == release ]] && [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
    echo "Commit the working tree before a release build so its stamp is reproducible." >&2
    exit 1
fi
CARGO_PROFILE_ARGS=(--profile "$PROFILE")
PROFILE_DIR=$PROFILE
[[ "$PROFILE" != dev ]] || PROFILE_DIR=debug
mkdir -p ios/Generated ios/Frameworks ios/build/headers
# Swift bindings are generated from host metadata, with the default dynamic-ORT configuration.
(cd core && cargo build --locked -p commonplace-ffi --jobs "${CP_BUILD_JOBS:-4}")
(cd core && target/debug/uniffi-bindgen generate --library target/debug/libcommonplace_ffi.dylib --language swift --out-dir ../ios/Generated --no-format)
cp ios/Generated/commonplace_ffiFFI.h ios/build/headers/
cp ios/Generated/commonplace_ffiFFI.modulemap ios/build/headers/module.modulemap
python3 ios/scripts/fetch-runtime-notices.py
# License extraction is offline and needs the target-specific crate archives first.
(cd core && cargo fetch --locked --target aarch64-apple-ios)
python3 scripts/licenses.py --ios --ort-dir ios/build/runtime-notices
XCARGS=()
for target in "${TARGETS[@]}"; do
    case "$target" in aarch64-apple-ios|aarch64-apple-ios-sim) ;; *) echo "Unsupported iOS target: $target" >&2; exit 2 ;; esac
    if [[ -z "${IN_NIX_SHELL:-}" ]]; then rustup target add "$target"; fi
    # The crate pins URLs and SHA-256 in ort-sys. ORT_IOS_XCFWK_PATH also supports an independently supplied framework.
    (cd core && cargo build --locked -p commonplace-ffi --lib --target "$target" "${CARGO_PROFILE_ARGS[@]}" --no-default-features --features ort-static,ort-download --jobs "${CP_BUILD_JOBS:-4}")
    mkdir -p "ios/build/$target"
    cp "core/target/$target/$PROFILE_DIR/libcommonplace_ffi.a" "ios/build/$target/libcommonplace_ffi.a"
    xcrun strip -S "ios/build/$target/libcommonplace_ffi.a"
    XCARGS+=(-library "$ROOT/ios/build/$target/libcommonplace_ffi.a" -headers "$ROOT/ios/build/headers")
done
rm -rf ios/Frameworks/CommonplaceCore.xcframework
xcodebuild -create-xcframework "${XCARGS[@]}" -output "$ROOT/ios/Frameworks/CommonplaceCore.xcframework"
python3 ios/scripts/generate-project.py
