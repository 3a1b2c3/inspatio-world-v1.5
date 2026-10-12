#!/usr/bin/env bash
# Downloads the InSpatio-World 1.5 checkpoints into checkpoints/ using the venv from setup_env.sh.
# The work is done by download_models.py (shared with download_models.bat); see its docstring for the
# layout and how the Hugging Face cache is reused. Set HF_TOKEN in the environment if a repo needs it.
# Usage: ./download_models.sh
set -euo pipefail

VENV_DIR="${VENV_DIR:-.venv}"
cd "$(dirname "$0")"

if [ ! -x "$VENV_DIR/bin/python" ]; then
    echo "No venv at $VENV_DIR. Run ./setup_env.sh first." >&2
    exit 1
fi

exec "$VENV_DIR/bin/python" download_models.py
