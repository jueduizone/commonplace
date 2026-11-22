#!/usr/bin/env python3
"""Regression checks for the iOS offline contract. This cannot provide Android's OS guarantee."""
from pathlib import Path
import argparse
import json
import plistlib
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--app', type=Path, help='optional built .app for manifest checks')
    args = ap.parse_args()
    failures = []
    forbidden = re.compile(r'\b(URLSession|URLRequest|NSURLConnection|NWConnection|WKWebView|SFSafariViewController|Firebase|Crashlytics|Sentry)\b')
    for path in (ROOT / 'ios/Commonplace').rglob('*'):
        if path.suffix not in ('.swift', '.c', '.h'):
            continue
        if forbidden.search(path.read_text()):
            failures.append(f'network or telemetry API in {path.relative_to(ROOT)}')
    plist_path = args.app / 'Info.plist' if args.app else ROOT / 'ios/Info.plist'
    info = plistlib.loads(plist_path.read_bytes())
    for key in ('NSAppTransportSecurity', 'NSLocalNetworkUsageDescription', 'NSBonjourServices'):
        if key in info:
            failures.append(f'unexpected network configuration: {key}')
    if info.get('UIFileSharingEnabled') is not True or info.get('LSSupportsOpeningDocumentsInPlace') is not True:
        failures.append('Files import/export configuration missing')
    privacy = plistlib.loads((ROOT / 'ios/PrivacyInfo.xcprivacy').read_bytes())
    if privacy.get('NSPrivacyTracking') or privacy.get('NSPrivacyTrackingDomains') or privacy.get('NSPrivacyCollectedDataTypes'):
        failures.append('unexpected tracking or collection declaration')
    result = subprocess.run(['cargo', 'tree', '--manifest-path', str(ROOT / 'core/Cargo.toml'), '--locked', '--offline',
        '-p', 'commonplace-ffi', '--target', 'aarch64-apple-ios', '--no-default-features', '--features',
        'ort-static,ort-download', '-e', 'normal', '--prefix', 'none', '--format', '{p}'], check=True, text=True, capture_output=True)
    linked = {line.split()[0] for line in result.stdout.splitlines()}
    network = linked & {'ureq', 'reqwest', 'hyper', 'curl', 'tonic', 'aws-sdk-s3', 'sentry', 'openssl'}
    if network:
        failures.append('runtime network dependencies: ' + ', '.join(sorted(network)))
    if failures:
        raise SystemExit('\n'.join(failures))
    print('PASS: no iOS network/analytics API, no network configuration, no declared collection, no runtime HTTP/TLS dependency')
    print('This is a source/build regression check, not an iOS network permission or runtime traffic proof.')


if __name__ == '__main__':
    main()
