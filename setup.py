"""
DOAR PENTRU MAC. Optional: foloseste acest fisier daca vrei un ".app" real,
cu iconita, in loc de fisierul "Porneste DataMover.command".
Pentru Windows, vezi sectiunea despre PyInstaller din CITESTE-MA.md.
Pasi (in Terminal, pe Mac, in acest folder):
    python3 -m venv .venv-build
    source .venv-build/bin/activate
    pip install py2app reportlab tkinterdnd2 plyer
    python3 setup.py py2app
    deactivate
Rezultatul apare in folderul "dist/DataMover.app" - il poti muta apoi
in Applications si il lansezi cu dublu-click ca orice alta aplicatie Mac.
Iconita (DataMover.icns) e deja inclusa in acest folder, gata de folosit.

Versiunea afisata in fereastra nativa "About DataMover" (din meniul
DataMover -> About DataMover) vine acum automat din update_config.py
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
    "update_config.py", "updater.py", "translations.py",
    "license_core.py", "license_validator.py", "machine_id.py", "activation.py",
]
OPTIONS = {
    "argv_emulation": False,
    "packages": ["reportlab", "tkinterdnd2", "plyer", "cryptography", "cffi"],
    "includes": [
        "offload_engine", "pdf_report", "config",
        "theme", "tooltip", "checkpoint",
        "update_config", "updater", "translations",
        "license_core", "license_validator", "machine_id", "activation",
        "_cffi_backend",
    ],
    "iconfile": "DataMover.icns",
    "plist": {
        "CFBundleName": "DataMover",
        "CFBundleDisplayName": "DataMover",
        "CFBundleShortVersionString": APP_VERSION,
        "CFBundleVersion": APP_VERSION,
        "CFBundleIdentifier": "com.gordasgdc.datamover",
        "NSHumanReadableCopyright": "© 2026 Cristi Gordas",
    },
}
setup(
    app=APP,
    name="DataMover",
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
