#!/usr/bin/env python3
"""Validate the plugin manifest and Lua syntax."""
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "plugin.json").read_text())
assert manifest["name"] == "Metronome"
assert manifest["requiredDependencies"]["prettyui"] == 6398181
assert manifest["requiredPermissions"] == []
assert manifest["hasSettingsIcon"] is True
assert not (ROOT / "resources").exists(), "Custom audio resources must stay outside plugin discovery"
print("Manifest valid")

files = sorted(ROOT.rglob("*.lua"))
for path in files:
    subprocess.run(["luac", "-p", str(path)], check=True)
print(f"Parsed {len(files)} Lua files")
