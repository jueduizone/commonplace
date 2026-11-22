#!/usr/bin/env python3
"""Fetch Microsoft ONNX Runtime 1.28 legal notices from its hash-pinned official PyPI wheel.
The ort-sys Apple static archive omits notices. Nothing from the wheel is installed or shipped as code.
"""
from pathlib import Path
from io import BytesIO
import hashlib
import urllib.request
import zipfile
import sys

URL = 'https://files.pythonhosted.org/packages/17/4d/5014667e2a3a77d6e1b74cc3d88948d06163b8e0a33a84c85073322b5dec/onnxruntime-1.28.0-cp311-cp311-macosx_14_0_arm64.whl'
SHA256 = 'f5c5daabd28aad610f83fdcf32acec8fb57e6adc6c6a39fe2a3c755db957b410'
ROOT = Path(__file__).resolve().parents[1]


def main():
    dest = ROOT / 'build/runtime-notices'
    dest.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(URL, timeout=90) as response:
        wheel = response.read()
    if hashlib.sha256(wheel).hexdigest() != SHA256:
        raise SystemExit('ONNX Runtime wheel checksum mismatch')
    with zipfile.ZipFile(BytesIO(wheel)) as archive:
        for name in archive.namelist():
            if '--host-runtime' in sys.argv and Path(name).name.startswith('libonnxruntime.') and name.endswith('.dylib'):
                runtime = ROOT / 'build/host-runtime/libonnxruntime.dylib'
                runtime.parent.mkdir(parents=True, exist_ok=True)
                runtime.write_bytes(archive.read(name))
                print('verified host-only runtime', runtime)
            if Path(name).name.lower() in ('license', 'license.txt', 'thirdpartynotices.txt'):
                (dest / Path(name).name).write_bytes(archive.read(name))
                print('verified', name)
    required = ['LICENSE', 'ThirdPartyNotices.txt']
    if not all((dest / name).exists() for name in required):
        raise SystemExit('Microsoft package did not contain the required notices')
    print(dest)


if __name__ == '__main__':
    main()
