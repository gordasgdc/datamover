"""
DOAR PENTRU MAC. Optional: foloseste acest fisier daca vrei un ".app" real,
cu iconita, in loc de fisierul "Porneste ShotPut Lite.command".
Pentru Windows, vezi sectiunea despre PyInstaller din CITESTE-MA.md.
Pasi (in Terminal, pe Mac, in acest folder):
    python3 -m venv .venv-build
    source .venv-build/bin/activate
    pip install py2app reportlab tkinterdnd2 plyer
    python3 setup.py py2app
    deactivate
Rezultatul apare in folderul "dist/ShotPut Lite.app" - il poti muta apoi
in Applications si il lansezi cu dublu-click ca orice alta aplicatie Mac.
Iconita (ShotPutLite.icns) e deja inclusa in acest folder, gata de folosit.

Versiunea afisata in fereastra nativa "About ShotPut Lite" (din meniul
ShotPut Lite -> About ShotPut Lite) vine din campurile "plist" de mai jos -
actualizeaza CFBundleShortVersionString/CFBundleVersion la fiecare "git tag"
nou, ca sa ramana sincronizata cu versiunea reala publicata pe GitHub.
"""
from setuptools import setup

APP_VERSION = "1.2.0"  # actualizeaza aici la fiecare release (git tag vX.Y.Z)

APP = ["main.py"]
DATA_FILES = [
    "offload_engine.py", "pdf_report.py", "config.py",
    "theme.py", "tooltip.py", "checkpoint.py",
]
OPTIONS = {
    "argv_emulation": False,
    "packages": ["reportlab", "tkinterdnd2", "plyer"],
    "includes": [
        "offload_engine", "pdf_report", "config",
        "theme", "tooltip", "checkpoint",
    ],
    "iconfile": "ShotPutLite.icns",
    "plist": {
        "CFBundleName": "ShotPut Lite",
        "CFBundleDisplayName": "ShotPut Lite",
        "CFBundleShortVersionString": APP_VERSION,
        "CFBundleVersion": APP_VERSION,
        "CFBundleIdentifier": "personal.shotputlite",
        "NSHumanReadableCopyright": "© 2026 Cristi Gordas",
    },
}
setup(
    app=APP,
    name="ShotPut Lite",
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
