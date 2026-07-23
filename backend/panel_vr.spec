from pathlib import Path
import sys


backend_dir = Path(SPECPATH).resolve()
static_dir = backend_dir / "static" / "web"
brainaccess_lib_dir = backend_dir / "brainaccess" / "lib"

brainaccess_dlls = [
    (str(path), "brainaccess/lib")
    for path in sorted(brainaccess_lib_dir.glob("*.dll"))
]

analysis = Analysis(
    [str(backend_dir / "launcher.py")],
    pathex=[str(backend_dir)],
    binaries=[],
    datas=[
        (str(static_dir), "static/web"),
        *brainaccess_dlls,
    ],
    hiddenimports=[
        "anyio._backends._asyncio",
        "eeg_mock",
        "eeg_stream",
        "et_mock",
        "main",
        "uvicorn.logging",
        "uvicorn.loops.auto",
        "uvicorn.protocols.http.auto",
        "uvicorn.protocols.websockets.auto",
        "uvicorn.lifespan.on",
    ],
    hookspath=[str(backend_dir / "hooks")],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[
        "IPython",
        "jupyter",
        "notebook",
        "pytest",
    ],
    noarchive=False,
    optimize=1,
)

pyz = PYZ(analysis.pure)

executable = EXE(
    pyz,
    analysis.scripts,
    [],
    exclude_binaries=True,
    name="PanelVR",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=sys.platform != "win32",
    disable_windowed_traceback=False,
)

bundle = COLLECT(
    executable,
    analysis.binaries,
    analysis.datas,
    strip=False,
    upx=False,
    name="PanelVR",
)
