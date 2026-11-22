"""Check resumable model downloads reject short or mismatched data before promotion."""
import hashlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("prepare_model", Path(__file__).resolve().parents[1] / "scripts/prepare-model.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class Response(io.BytesIO):
    status = 206
    def __init__(self, data, content_range):
        super().__init__(data)
        self.headers = {"Content-Range": content_range}

class DownloadTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.model = Path(self.directory.name) / "model.gguf"
        self.data = b"GGUF-test-original-model"
        self.digest = hashlib.sha256(self.data).hexdigest()
        self.partial = self.model.with_suffix(".gguf.part")

    def test_resume_truncated_unverified_file(self):
        self.model.write_bytes(self.data[:7])
        with patch.object(module.urllib.request, "urlopen", return_value=Response(self.data[7:], f"bytes 7-{len(self.data)-1}/{len(self.data)}")) as fetch:
            module.download("https://example.invalid/model", self.model, len(self.data), self.digest)
        self.assertEqual(fetch.call_args.args[0].get_header("Range"), f"bytes=7-{len(self.data)-1}")
        self.assertEqual(self.model.read_bytes(), self.data)
        self.assertFalse(self.partial.exists())

    def test_short_response_not_promoted_or_appended(self):
        self.partial.write_bytes(self.data[:7])
        with patch.object(module.urllib.request, "urlopen", side_effect=lambda *a, **k: Response(b"bad", f"bytes 7-{len(self.data)-1}/{len(self.data)}")), patch.object(module.time, "sleep"):
            with self.assertRaises(SystemExit):
                module.download("https://example.invalid/model", self.model, len(self.data), self.digest)
        self.assertFalse(self.model.exists())
        self.assertEqual(self.partial.read_bytes(), self.data[:7])

    def test_checksum_failure_not_promoted(self):
        self.partial.write_bytes(b"x" * len(self.data))
        with self.assertRaises(SystemExit):
            module.download("https://example.invalid/model", self.model, len(self.data), self.digest)
        self.assertFalse(self.model.exists())

    def test_verified_existing_file_needs_no_network(self):
        self.model.write_bytes(self.data)
        with patch.object(module.urllib.request, "urlopen") as fetch:
            module.download("https://example.invalid/model", self.model, len(self.data), self.digest)
        fetch.assert_not_called()

if __name__ == "__main__":
    unittest.main()
