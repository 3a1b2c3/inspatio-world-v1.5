#!/usr/bin/env bash
# Sets up a uv virtual environment for InSpatio-World 1.5 (the .venv that WBench's inspatio driver uses).
# On aarch64 (GB300 / DGX Spark) pycolmap and decord have no wheels, so they are left out and Depth
# Anything 3's top-level pycolmap import is made lazy (see step 4); no conda is needed.
# Usage: ./setup_env.sh [cuda_tag]
#   cuda_tag defaults to cu130 (Blackwell: RTX 5090 / GB300). environment.yml pins torch 2.10.0+cu126,
#   which has no Blackwell kernels and no aarch64 build, so a current CUDA torch is installed instead.
# Optional environment variables:
#   VENV_DIR        default .venv
#   PYTHON_VERSION  unset by default: uv picks its default Python. Set it (for example 3.10, the version the
#                   README names) only if you want a specific one.
set -euo pipefail

CUDA_TAG="${1:-cu130}"
VENV_DIR="${VENV_DIR:-.venv}"
PYTHON_VERSION="${PYTHON_VERSION:-}"
TORCH_INDEX="https://download.pytorch.org/whl/${CUDA_TAG}"

cd "$(dirname "$0")"

if ! command -v uv >/dev/null 2>&1; then
    echo "uv not found. Install it first: https://docs.astral.sh/uv/getting-started/installation/" >&2
    exit 1
fi

if [ -e "$VENV_DIR" ]; then
    echo "$VENV_DIR already exists. Remove it (or set VENV_DIR) and rerun." >&2
    exit 1
fi

echo "[1/5] Creating $VENV_DIR (Python: ${PYTHON_VERSION:-uv default}) ..."
if [ -n "$PYTHON_VERSION" ]; then
    uv venv "$VENV_DIR" --python "$PYTHON_VERSION"
else
    uv venv "$VENV_DIR"
fi

if [ -x "$VENV_DIR/bin/python" ]; then
    PY="$VENV_DIR/bin/python"
elif [ -x "$VENV_DIR/Scripts/python.exe" ]; then
    PY="$VENV_DIR/Scripts/python.exe"
else
    echo "Virtual environment was not created at $VENV_DIR." >&2
    exit 1
fi

# Abort unless torch is a CUDA build that can see the GPU. Run after every install step: a later
# package must not be able to replace the CUDA torch with a CPU build.
check_cuda_torch() {
    "$PY" - <<'EOF' || { echo "[ERROR] torch is not a working CUDA build (see above). Aborting." >&2; exit 1; }
import sys

import torch

print(f"       torch {torch.__version__} | CUDA build: {torch.version.cuda} | available: {torch.cuda.is_available()}")
if not torch.cuda.is_available():
    sys.exit(1)
print(f"       device: {torch.cuda.get_device_name(0)} | capability: {torch.cuda.get_device_capability(0)}")
EOF
}

# --index-url (not --extra-index-url): with PyPI also in play, "best match" can pick a CPU-only torch.
echo "[2/5] Installing CUDA torch from $TORCH_INDEX ..."
uv pip install --python "$PY" torch torchvision --index-url "$TORCH_INDEX"
check_cuda_torch

echo "[3/5] Installing requirements.txt ..."
REQUIREMENTS="requirements.txt"
if [ "$(uname -m)" = "aarch64" ]; then
    # PyPI has no aarch64 wheel (and no source package) for pycolmap, and no aarch64 wheel for decord.
    echo "       aarch64: skipping pycolmap and decord (no wheels published)."
    REQUIREMENTS="$(mktemp)"
    grep -v -e '^pycolmap' -e '^decord' requirements.txt > "$REQUIREMENTS"
fi
uv pip install --python "$PY" -r "$REQUIREMENTS"
check_cuda_torch

echo "[4/5] Installing Depth Anything 3 without its app/benchmark dependencies ..."
uv pip install --python "$PY" --no-deps depth-anything-3==0.1.1
if ! "$PY" -c "import pycolmap" 2>/dev/null; then
    # depth_anything_3.api imports pycolmap at load time through utils/export/colmap.py, but only the
    # COLMAP export (never used here) calls it. Move that import into the function that needs it.
    echo "       pycolmap is not installed: making Depth Anything 3's pycolmap import lazy."
    "$PY" - <<'EOF'
import importlib.util
from pathlib import Path

package = importlib.util.find_spec("depth_anything_3").submodule_search_locations[0]
path = Path(package) / "utils" / "export" / "colmap.py"
source = path.read_text()
if "    import pycolmap" in source:
    print("       already lazy")
else:
    top_level = "import pycolmap\n"
    signature = ") -> None:\n"
    assert source.count(top_level) == 1 and source.count(signature) == 1, f"unexpected layout: {path}"
    source = source.replace(top_level, "", 1)
    source = source.replace(signature, signature + "    import pycolmap\n", 1)
    path.write_text(source)
    print(f"       patched {path}")
EOF
fi
check_cuda_torch

echo "[5/5] Checking that the depth step imports ..."
"$PY" -c "from depth_anything_3.api import DepthAnything3; print('       depth_anything_3 import: OK')"

echo "Done. Next: ./download_models.sh"
echo "Activate with: source $VENV_DIR/bin/activate"
