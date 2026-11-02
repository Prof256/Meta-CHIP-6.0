#!/usr/bin/env bash
# Wrapper to run the interactive C.H.I.P. Yocto setup assistant
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 "${SCRIPT_DIR}/scripts/setup-chip.py" "$@"

