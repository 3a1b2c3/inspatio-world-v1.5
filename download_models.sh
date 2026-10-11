#!/usr/bin/env bash
# Downloads the InSpatio-World 1.5 checkpoints into checkpoints/ using the venv from setup_env.sh.
#
#   checkpoints/InSpatio-World-1.3B/InSpatio-World-1.5-1.3B.safetensors   inspatio/world-1.5
#   checkpoints/Wan2.1-T2V-1.3B/                                          Wan-AI/Wan2.1-T2V-1.3B
#   checkpoints/depth/                                                    depth-anything/DA3NESTED-GIANT-LARGE
#
# Everything goes through the Hugging Face cache (HF_HUB_CACHE / HF_HOME, default ~/.cache/huggingface),
# so a model that is already cached is reused and only missing files are fetched. checkpoints/ holds
# symlinks into that cache. Wan2.1 is a directory of file symlinks instead of one symlink, because
# run_scene_inference.py writes the converted T5 safetensors file next to the original weights and that
# must not land inside the cache. Set HF_TOKEN in the environment if a repo needs authentication.
# Needs a filesystem with symlinks (Linux). Usage: ./download_models.sh
set -euo pipefail

VENV_DIR="${VENV_DIR:-.venv}"
cd "$(dirname "$0")"

if [ -x "$VENV_DIR/bin/python" ]; then
    PY="$VENV_DIR/bin/python"
else
    echo "No venv at $VENV_DIR. Run ./setup_env.sh first." >&2
    exit 1
fi

mkdir -p checkpoints/InSpatio-World-1.3B

"$PY" - <<'EOF'
import shutil
import subprocess
from pathlib import Path

from huggingface_hub import hf_hub_download, list_repo_files, snapshot_download

CHECKPOINTS = Path("checkpoints").resolve()


def link(target: Path, source: Path) -> None:
    if target.is_symlink() or target.is_file():
        target.unlink()
    elif target.is_dir():
        shutil.rmtree(target)
    target.symlink_to(source.resolve())


# --- InSpatio-World 1.5 checkpoint -------------------------------------------------
repo_id = "inspatio/world-1.5"
files = [name for name in list_repo_files(repo_id) if name.endswith(".safetensors")]
preferred = [name for name in files if Path(name).name in {
    "InSpatio-World-1.5-1.3B.safetensors",
    "InSpatio-World-1.5.safetensors",
}]
if len(preferred) == 1:
    filename = preferred[0]
elif len(files) == 1:
    filename = files[0]
else:
    raise RuntimeError(f"Cannot identify the 1.5 checkpoint in {repo_id}: {files}")
cached = Path(hf_hub_download(repo_id=repo_id, filename=filename))
target = CHECKPOINTS / "InSpatio-World-1.3B" / "InSpatio-World-1.5-1.3B.safetensors"
link(target, cached)
print(f"{repo_id}/{filename} -> {target}")

# --- Wan2.1-T2V-1.3B: text encoder, tokenizer, VAE, DiT config -----------------------
snapshot = Path(snapshot_download(repo_id="Wan-AI/Wan2.1-T2V-1.3B", ignore_patterns=["assets/*", "examples/*"]))
wan_dir = CHECKPOINTS / "Wan2.1-T2V-1.3B"
if wan_dir.is_symlink() or wan_dir.is_file():
    wan_dir.unlink()
wan_dir.mkdir(parents=True, exist_ok=True)
subprocess.run(["cp", "-rsf", f"{snapshot}/.", str(wan_dir)], check=True)
print(f"Wan-AI/Wan2.1-T2V-1.3B -> {wan_dir}")

# --- Depth Anything 3 -----------------------------------------------------------------
depth_snapshot = Path(snapshot_download(
    repo_id="depth-anything/DA3NESTED-GIANT-LARGE", allow_patterns=["config.json", "model.safetensors"]))
depth_dir = CHECKPOINTS / "depth"
link(depth_dir, depth_snapshot)
print(f"depth-anything/DA3NESTED-GIANT-LARGE -> {depth_dir}")

missing = [path for path in (
    target,
    wan_dir / "config.json",
    wan_dir / "Wan2.1_VAE.pth",
    wan_dir / "models_t5_umt5-xxl-enc-bf16.pth",
    depth_dir / "config.json",
    depth_dir / "model.safetensors",
) if not path.exists()]
if missing:
    raise RuntimeError("Missing after download: " + ", ".join(str(path) for path in missing))
print("All InSpatio-World 1.5 checkpoints are in place.")
EOF
