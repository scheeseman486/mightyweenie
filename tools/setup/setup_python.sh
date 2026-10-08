#!/usr/bin/env bash
# Create/refresh this host's virtualenv (.venv-<hostname>) with the harness and
# PyGhidra. Safe to re-run. Python >= 3.10 required (stable-retro wheels).
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../bin/_common.sh"
venv="$MW_ROOT/.venv-$(hostname -s)"
py="${PYTHON:-python3}"
"$py" -c 'import sys; assert sys.version_info >= (3,10), sys.version' \
  || { echo "need Python >= 3.10 (set PYTHON=...)" >&2; exit 1; }
[[ -x "$venv/bin/python" ]] || "$py" -m venv "$venv"
"$venv/bin/pip" install -q --upgrade pip
"$venv/bin/pip" install -q -r "$MW_ROOT/harness/requirements.txt"
whl=$(ls "$MW_TOOLS"/ghidra/Ghidra/Features/PyGhidra/pypkg/dist/pyghidra-*.whl 2>/dev/null | head -1 || true)
if [[ -n "$whl" ]]; then "$venv/bin/pip" install -q --find-links "$(dirname "$whl")" "$whl"; else echo "note: Ghidra not fetched yet; skipping pyghidra" >&2; fi
echo "python env ready: $venv"
