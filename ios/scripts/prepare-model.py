#!/usr/bin/env python3
"""Prepare an existing licensed GGUF as a format-v1 model pack. No upload or publication.

--minicpm downloads exactly the existing project's pinned 1.42 GB model.
For Gemma, provide a conversion with known attribution/revision/hash; no source is guessed.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import urllib.request
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[2]
MINI_REPO = '0xPD33/MiniCPM5-2B-pureQ4_0-GGUF'
MINI_REV = '76674264cc1a1b11939b0e6875571d4aae84cb18'
MINI_NAME = 'MiniCPM5-2B-pureQ4_0.gguf'
MINI_SHA = 'd998b9433fe6e9b20e0dde7780e6c435a8a9cd893538ea70cbf1e09ce28cd5ae'
GEMMA_REPO = 'unsloth/gemma-4-E2B-it-GGUF'
GEMMA_REV = '0314792d7f1f7e229411f620751375812bb9faf2'
GEMMA_NAME = 'gemma-4-E2B-it-Q4_0.gguf'
GEMMA_SHA = '31d3a3c630d4e71a7416498c42660dd3805066948acaec76a47e1ffac7010132'


def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as file:
        for data in iter(lambda: file.read(4 * 1024 * 1024), b''):
            digest.update(data)
    return digest.hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument('--minicpm', action='store_true')
    group.add_argument('--gemma', action='store_true', help='download the pinned Apache-2.0 Unsloth GGUF conversion')
    group.add_argument('--gemma-file', type=Path)
    ap.add_argument('--source-repo')
    ap.add_argument('--revision')
    ap.add_argument('--sha256')
    ap.add_argument('--conversion-notice', type=Path)
    ap.add_argument('--out', type=Path)
    args = ap.parse_args()
    if args.minicpm:
        pack_id, title, role, profile = 'minicpm5-2b', 'MiniCPM5-2B (GGUF)', 'llm-small', 'default'
        repo, revision, name, expected = MINI_REPO, MINI_REV, MINI_NAME, MINI_SHA
        notice_path = ROOT / 'pipeline/notices/minicpm5-2b.txt'
    elif args.gemma:
        pack_id, title, role, profile = 'gemma4-e2b-ios', 'Gemma 4 E2B (GGUF)', 'llm-fast', 'gemma4'
        repo, revision, name, expected = GEMMA_REPO, GEMMA_REV, GEMMA_NAME, GEMMA_SHA
        notice_path = ROOT / 'pipeline/notices/gemma4-e2b-ios.txt'
    else:
        if not all([args.source_repo, args.revision, args.sha256]):
            ap.error('Gemma requires --source-repo, --revision and --sha256 for traceability')
        pack_id, title, role, profile = 'gemma4-e2b-ios', 'Gemma 4 E2B (GGUF)', 'llm-fast', 'gemma4'
        repo, revision, name, expected = args.source_repo, args.revision, args.gemma_file.name, args.sha256
        if 'gemma-4-e2b' not in name.lower() or not name.lower().endswith('.gguf'):
            ap.error('the Gemma filename must identify gemma-4-E2B and end in .gguf')
        notice_path = ROOT / 'pipeline/notices/gemma4-e2b-ios.txt'
    output = args.out or ROOT / 'data/library/packs' / pack_id
    output.mkdir(parents=True, exist_ok=True)
    model = output / name
    if not args.gemma_file and not model.exists():
        partial = model.with_suffix(model.suffix + '.part')
        offset = partial.stat().st_size if partial.exists() else 0
        request = urllib.request.Request(f'https://huggingface.co/{repo}/resolve/{revision}/{name}')
        if offset:
            request.add_header('Range', f'bytes={offset}-')
        with urllib.request.urlopen(request, timeout=120) as response:
            append = offset > 0 and response.status == 206
            with partial.open('ab' if append else 'wb') as file:
                shutil.copyfileobj(response, file, 4 * 1024 * 1024)
        partial.replace(model)
    elif args.gemma_file and args.gemma_file.resolve() != model.resolve():
        shutil.copy2(args.gemma_file, model)
    with model.open('rb') as file:
        if file.read(4) != b'GGUF':
            raise SystemExit('not a GGUF model')
    actual = sha256(model)
    if actual.lower() != expected.lower():
        raise SystemExit(f'model hash mismatch: {actual}')
    notice = f'File: {name}\nSource: {repo}@{revision}\nSHA-256: {actual}\n\n' + notice_path.read_text()
    if args.conversion_notice:
        notice += '\n\nGGUF conversion notice\n' + args.conversion_notice.read_text()
    (output / 'NOTICE.txt').write_text(notice)
    files = [{'path': path.name, 'bytes': path.stat().st_size, 'sha256': sha256(path)} for path in [model, output / 'NOTICE.txt']]
    manifest = {'format_version': 1, 'pack_id': pack_id, 'pack_type': 'model', 'title': title,
        'snapshot_date': '', 'build_date': datetime.now(timezone.utc).date().isoformat(),
        'license': 'Apache-2.0', 'attribution': f'{repo}; original model authors; {revision}',
        'model': {'role': role, 'file': name, 'hf_repo': repo, 'revision': revision, 'n_ctx': 4096, 'profile': profile},
        'files': files, 'size_bytes': sum(item['bytes'] for item in files)}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print(f'{output}: verified {actual}; no weights uploaded', flush=True)


if __name__ == '__main__':
    main()
