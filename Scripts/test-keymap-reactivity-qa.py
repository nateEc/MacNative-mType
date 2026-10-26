#!/usr/bin/env python3
"""Apply the same cache/publication/failure contracts to pinned Solid QA."""
import importlib.util
from pathlib import Path
import unittest

directory = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("archive_preparation_contracts", directory / "test-animation-engine-qa.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.SCRIPT = directory / "prepare-keymap-reactivity-qa.sh"
module.ARCHIVE_KEY = "TYPEBAR_SOLID_QA_ARCHIVE"
module.TEMP_PREFIX = "typebar-solid-qa."
if __name__ == "__main__":
    unittest.main(module=module)
