#!/usr/bin/env python3
"""Build-time only: fetch the existing Android encoder revisions and verify each Git/LFS object.

No full-precision teacher models or LLM weights are downloaded. The app has no fetch code.
"""
from pathlib import Path
import hashlib
import json
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'ios/Resources/Encoders'
MODELS = [
    ('MongoDB/mdbr-leaf-mt', '1ed41b22ce166d66c24f88ebfc340e1f03adb20f', 'leaf-mt',
     ['tokenizer.json', 'onnx/model_quantized.onnx', 'onnx/model_quantized.onnx_data']),
    ('0xPD33/ettin-reranker-17m-commonplace', 'ebc0d6c8afdce3af49e12c6fd0b7cc6a6c398769', 'ettin-17m',
     ['tokenizer.json', 'onnx/model_sel8.onnx', '2_Dense/model.safetensors', '3_LayerNorm/model.safetensors', '4_Dense/model.safetensors']),
]

def fetch(url):
    with urllib.request.urlopen(url, timeout=90) as response:
        return response.read()


def main():
    manifest = []
    for repo, revision, directory, files in MODELS:
        # The immutable commit gives both small-file Git blob IDs and large-file LFS SHA-256 values.
        listing = json.loads(fetch(f'https://huggingface.co/api/models/{repo}/tree/{revision}?recursive=true&limit=1000'))
        by_path = {entry['path']: entry for entry in listing}
        for name in files:
            entry = by_path[name]
            dest = OUT / directory / name
            data = dest.read_bytes() if dest.exists() else fetch(f'https://huggingface.co/{repo}/resolve/{revision}/{name}')
            sha256 = hashlib.sha256(data).hexdigest()
            if entry.get('lfs'):
                expected = entry['lfs'].get('oid') or entry['lfs'].get('sha256')
                valid = expected == sha256
            else:
                valid = hashlib.sha1(f'blob {len(data)}\0'.encode() + data).hexdigest() == entry['oid']
            if not valid:
                raise SystemExit(f'hash mismatch: {repo}@{revision}/{name}')
            dest.parent.mkdir(parents=True, exist_ok=True)
            if not dest.exists():
                temporary = dest.with_suffix(dest.suffix + '.part')
                temporary.write_bytes(data)
                temporary.replace(dest)
            manifest.append({'repo': repo, 'revision': revision, 'path': f'{directory}/{name}', 'sha256': sha256, 'bytes': len(data)})
            print(f'verified {dest.relative_to(ROOT)} ({len(data):,} bytes)', flush=True)
    (OUT / 'SHA256SUMS.json').write_text(json.dumps(manifest, indent=2) + '\n')

if __name__ == '__main__':
    main()
