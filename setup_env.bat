@echo off
REM Sets up a uv virtual environment for InSpatio-World 1.5 on Windows (the .venv that WBench's inspatio driver uses).
REM Usage: setup_env.bat [cuda_tag]
REM   cuda_tag defaults to cu130 (Blackwell: RTX 5090). environment.yml pins torch 2.10.0+cu126, which has no
REM   Blackwell kernels, so a current CUDA torch is installed instead.
REM Optional environment variables: VENV_DIR (default .venv), PYTHON_VERSION (unset by default, so uv picks its default
REM Python; set it, for example 3.10 as the README names, only if you want a specific one).
setlocal

set "CUDA_TAG=%~1"
if "%CUDA_TAG%"=="" set "CUDA_TAG=cu130"
if "%VENV_DIR%"=="" set "VENV_DIR=.venv"

cd /d "%~dp0"

where uv >nul 2>&1
if errorlevel 1 (
    echo ERROR: uv not found. Install it first: https://docs.astral.sh/uv/getting-started/installation/
    exit /b 1
)

if exist "%VENV_DIR%" (
    echo ERROR: %VENV_DIR% already exists. Remove it or set VENV_DIR, then rerun.
    exit /b 1
)

echo [1/5] Creating %VENV_DIR% ...
if "%PYTHON_VERSION%"=="" (
    uv venv "%VENV_DIR%"
) else (
    uv venv "%VENV_DIR%" --python %PYTHON_VERSION%
)
if errorlevel 1 exit /b 1
set "PY=%CD%\%VENV_DIR%\Scripts\python.exe"

REM --index-url, not --extra-index-url: with PyPI also in play, best-match can pick a CPU-only torch.
echo [2/5] Installing CUDA torch from the %CUDA_TAG% index ...
uv pip install --python "%PY%" torch torchvision --index-url https://download.pytorch.org/whl/%CUDA_TAG%
if errorlevel 1 exit /b 1
call :check_cuda
if errorlevel 1 exit /b 1

echo [3/5] Installing requirements.txt ...
uv pip install --python "%PY%" -r requirements.txt
if errorlevel 1 exit /b 1
call :check_cuda
if errorlevel 1 exit /b 1

echo [4/5] Installing Depth Anything 3 without its app/benchmark dependencies ...
uv pip install --python "%PY%" --no-deps depth-anything-3==0.1.1
if errorlevel 1 exit /b 1
call :check_cuda
if errorlevel 1 exit /b 1

echo [5/5] Checking that the depth step imports ...
"%PY%" -c "from depth_anything_3.api import DepthAnything3; print('       depth_anything_3 import: OK')"
if errorlevel 1 exit /b 1

echo Done. Next: download_models.bat
echo Activate with: %VENV_DIR%\Scripts\activate.bat
exit /b 0

REM Abort unless torch is a CUDA build that can see the GPU. Run after every install step: a later package
REM must not be able to replace the CUDA torch with a CPU build.
:check_cuda
"%PY%" -c "import sys, torch; print('       torch', torch.__version__, '| CUDA build:', torch.version.cuda, '| available:', torch.cuda.is_available()); sys.exit(0 if torch.cuda.is_available() else 1)"
if errorlevel 1 (
    echo ERROR: torch is not a working CUDA build, see above. Aborting.
    exit /b 1
)
exit /b 0
