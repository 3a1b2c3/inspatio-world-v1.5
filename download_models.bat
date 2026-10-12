@echo off
REM Downloads the InSpatio-World 1.5 checkpoints into checkpoints\ using the venv from setup_env.bat.
REM The work is done by download_models.py (shared with download_models.sh); see its docstring for the layout
REM and how the Hugging Face cache is reused (hard links on Windows, so no extra disk space on the same drive).
REM Set HF_TOKEN in the environment if a repo needs it.
REM Usage: download_models.bat
setlocal

if "%VENV_DIR%"=="" set "VENV_DIR=.venv"
cd /d "%~dp0"

if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo ERROR: No venv at %VENV_DIR%. Run setup_env.bat first.
    exit /b 1
)

"%VENV_DIR%\Scripts\python.exe" download_models.py
exit /b %errorlevel%
