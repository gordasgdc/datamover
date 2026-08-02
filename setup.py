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
ShotPut Lite -> About ShotPut Lite) vine acum automat din update_config.py
(APP_VERSION) - SINGURA sursa de adevar pentru numarul de versiune in tot
proiectul. Actualizeaz-o DOAR acolo, la fiecare "git tag" nou; setup.py o
citeste automat de aici, nu mai trebuie schimbata si aici separat.
"""
from setuptools import setup
from update_config import APP_VERSION

APP = ["main.py"]
DATA_FILES = [
    "offload_engine.py", "pdf_report.py", "config.py",
    "theme.py", "tooltip.py", "checkpoint.py",
    "update_config.py", "updater.py",
]
OPTIONS = {
    "argv_emulation": False,
    "packages": ["reportlab", "tkinterdnd2", "plyer"],
    "includes": [
        "offload_engine", "pdf_report", "config",
        "theme", "tooltip", "checkpoint",
        "update_config", "updater",
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
