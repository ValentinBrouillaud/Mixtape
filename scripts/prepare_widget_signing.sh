#!/bin/bash
# Embed the requested App Group in temporary ad-hoc signatures for a re-signer.
# This does not create an Apple provisioning profile or authorize installation.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/validate_widget_signing.py" --prepare "$@"
