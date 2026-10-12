# InSpatio-World 1.5 in WBench

This checkout has setup and download scripts for a Blackwell GPU (RTX 5090, GB300), and WBench drives it as the `inspatio` model. Status: the scripts and the pose math were checked in isolation; nothing has been run end to end on a GPU.

## Files

| File | Purpose |
| --- | --- |
| `requirements.txt` | The pip pins from `environment.yml`, without torch/torchvision |
| `setup_env.sh`, `setup_env.bat` | Create `.venv` with uv and Python 3.10, install a CUDA torch (default `cu130`), then `requirements.txt` and `depth-anything-3` |
| `download_models.py` | Fetch the three checkpoints through the Hugging Face cache into `checkpoints/` |
| `download_models.sh`, `download_models.bat` | Thin wrappers that call `download_models.py` with the venv |
| `..\WBench\src\models\camera\inspatio_model.py` | WBench driver, registered as `inspatio` in `src\models\__init__.py` |
| `..\WBench\src\models\camera\inspatio_prepare_scene.py` | Builds an InSpatio scene (depth, cameras) from a WBench case; runs inside this venv |
| `..\WBench\run_inspatio.sh`, `run_inspatio.bat` | Generate (and optionally evaluate) WBench cases with `inspatio` |

## Setup

```
./setup_env.sh
```
```
./download_models.sh
```

On Windows use `setup_env.bat` and `download_models.bat`. Both setup scripts refuse to run if `.venv` already exists; remove it or set `VENV_DIR`. They check after every install step that torch is still a CUDA build that sees the GPU, and stop otherwise.

- **Why not `environment.yml`:** it pins torch 2.10.0+cu126, which has no Blackwell kernels and no aarch64 build. The scripts install the current CUDA torch from `https://download.pytorch.org/whl/<tag>` instead (pass another tag as the first argument). The repository itself is only tested with torch 2.10, so a failure at import or run time may come from the newer torch.
- **aarch64 (GB300 / DGX):** PyPI has no aarch64 wheel for `pycolmap` (and no source package) or for `decord`, so both are left out. Depth Anything 3's `api` module imports `pycolmap` at the top of `utils/export/colmap.py`, although only the COLMAP export uses it. `setup_env.sh` therefore moves that import into the function that needs it (idempotent; skipped when `pycolmap` is installed). The last step imports Depth Anything 3 for real, so a missing package is reported there. conda is not needed.
- **Windows:** wheels for both packages exist, so everything installs from `requirements.txt` unchanged.

## Checkpoints

`download_models.py` places these under `checkpoints/`, reusing anything already in the Hugging Face cache (`HF_HUB_CACHE` / `HF_HOME`) and fetching only what is missing. Set `HF_TOKEN` in the environment if a repo needs it.

| Path | Repo |
| --- | --- |
| `checkpoints/InSpatio-World-1.3B/InSpatio-World-1.5-1.3B.safetensors` | `inspatio/world-1.5` |
| `checkpoints/Wan2.1-T2V-1.3B/` | `Wan-AI/Wan2.1-T2V-1.3B` (without `assets/` and `examples/`) |
| `checkpoints/depth/` | `depth-anything/DA3NESTED-GIANT-LARGE` (`config.json`, `model.safetensors`) |

Files are symlinks into the cache on Linux and hard links on Windows (no extra disk space on the same drive; copied if the cache is on another drive). The Wan folder is a real directory of per-file links because `run_scene_inference.py` writes the converted T5 safetensors file next to the original weights.

## Running through WBench

```
./run_inspatio.sh --limit 1
```

Arguments pass through to `generate.py` (`--cases`, `--limit`); `--evaluate` also runs `main.py --model inspatio`. Set `WBENCH_PYTHON` to the WBench environment's Python (default `~/wbench-venv/bin/python`, or `%USERPROFILE%\wbench-venv\Scripts\python.exe` for the `.bat`). Check `nvidia-smi` first if the GPU is shared.

How a case becomes an InSpatio scene:

1. The first frame is scaled to cover 832x480 and center-cropped.
2. Depth Anything 3 estimates its depth and camera intrinsics, using InSpatio's own `DepthEstimator`.
3. WBench's camera-to-world poses (one per latent frame, 6 per second) are interpolated to 24 fps (linear translation, slerp rotation, last pose held), made relative to the first camera, and inverted to the OpenCV world-to-camera matrices that `scene.json` expects.
4. `run_scene_inference.py --scene_dir` renders and infers; the result `output/<id>/pred.mp4` is trimmed or last-frame-padded to the requested length.

Details to know:

- WBench's intrinsics are not used; InSpatio fixes the target intrinsics to the estimated source intrinsics.
- WBench moves 0.08 world units per latent step while Depth Anything 3 depth is in metres. The `translation_scale` constructor argument of `InSpatioModel` rescales the trajectory if the motion looks too small or too large; the navigation metric normalises absolute scale.
- Output is always 832x480. There is no per-case text in WBench, so the prompt is a generic default; pass `prompt=` to override.
- Scenes are kept in `wbench_scenes/<id>/`. The id hashes the image, trajectory, prompt and scale, so an unchanged case reuses InSpatio's finished result. InSpatio refuses to reuse an output id whose scene directory was deleted, so do not delete a scene directory without also removing its entry from `output/manifest.json`.
