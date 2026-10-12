"""Download the InSpatio-World 1.5 checkpoints into checkpoints/ through the Hugging Face cache.

    checkpoints/InSpatio-World-1.3B/InSpatio-World-1.5-1.3B.safetensors   inspatio/world-1.5
    checkpoints/Wan2.1-T2V-1.3B/                                          Wan-AI/Wan2.1-T2V-1.3B
    checkpoints/depth/                                                    depth-anything/DA3NESTED-GIANT-LARGE

Everything goes through the Hugging Face cache (HF_HUB_CACHE / HF_HOME), so a model that is already cached
is reused and only missing files are fetched; set HF_TOKEN in the environment if a repo needs authentication.
Files in checkpoints/ are symlinks into the cache on Linux and hard links on Windows (no extra disk space,
no privileges needed); a hard link across drives is not possible, so there the file is copied instead.
Directories are real directories of per-file links, because run_scene_inference.py writes the converted T5
safetensors file next to the original weights and that must not land inside the cache.

Run with the venv from setup_env: python download_models.py
"""
import os
import shutil
from pathlib import Path

from huggingface_hub import hf_hub_download, list_repo_files, snapshot_download

CHECKPOINTS = Path(__file__).resolve().parent / "checkpoints"


def materialize(target: Path, source: Path) -> None:
    """Make target refer to the cached file source."""
    source = source.resolve()
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_symlink() or target.exists():
        target.unlink()
    if os.name != "nt":
        target.symlink_to(source)
        return
    try:
        os.link(source, target)
    except OSError:
        shutil.copy2(source, target)


def mirror_tree(snapshot: Path, destination: Path) -> None:
    """Recreate a cached snapshot as a real directory whose files link to the cache."""
    for source in sorted(snapshot.rglob("*")):
        if source.is_file():
            materialize(destination / source.relative_to(snapshot), source)


def main() -> None:
    # InSpatio-World 1.5 checkpoint
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
    checkpoint = CHECKPOINTS / "InSpatio-World-1.3B" / "InSpatio-World-1.5-1.3B.safetensors"
    materialize(checkpoint, Path(hf_hub_download(repo_id=repo_id, filename=filename)))
    print(f"{repo_id}/{filename} -> {checkpoint}")

    # Wan2.1-T2V-1.3B: text encoder, tokenizer, VAE, DiT config
    wan_dir = CHECKPOINTS / "Wan2.1-T2V-1.3B"
    wan_snapshot = Path(snapshot_download(repo_id="Wan-AI/Wan2.1-T2V-1.3B", ignore_patterns=["assets/*", "examples/*"]))
    mirror_tree(wan_snapshot, wan_dir)
    print(f"Wan-AI/Wan2.1-T2V-1.3B -> {wan_dir}")

    # Depth Anything 3
    depth_dir = CHECKPOINTS / "depth"
    depth_snapshot = Path(snapshot_download(
        repo_id="depth-anything/DA3NESTED-GIANT-LARGE", allow_patterns=["config.json", "model.safetensors"]))
    mirror_tree(depth_snapshot, depth_dir)
    print(f"depth-anything/DA3NESTED-GIANT-LARGE -> {depth_dir}")

    missing = [path for path in (
        checkpoint,
        wan_dir / "config.json",
        wan_dir / "Wan2.1_VAE.pth",
        wan_dir / "models_t5_umt5-xxl-enc-bf16.pth",
        depth_dir / "config.json",
        depth_dir / "model.safetensors",
    ) if not path.exists()]
    if missing:
        raise RuntimeError("Missing after download: " + ", ".join(str(path) for path in missing))
    print("All InSpatio-World 1.5 checkpoints are in place.")


if __name__ == "__main__":
    main()
