"""
update_config.py
-----------------
Configuratii pentru functia de self-update (verificare + instalare automata
de versiuni noi). Fisier fara dependinte externe - doar Python standard -
ca sa poata fi importat in siguranta atat de main.py, cat si de setup.py
(la momentul compilarii, intr-un mediu izolat care nu are inca instalate
reportlab/tkinterdnd2/plyer).

IMPORTANT: acesta e SINGURA sursa de adevar pentru numarul de versiune al
aplicatiei. La fiecare "git tag vX.Y.Z" nou, actualizeaza DOAR valoarea
APP_VERSION de mai jos - se propaga automat si in setup.py (fereastra
nativa "About DataMover") si in verificarea de actualizari.
"""

APP_VERSION = "2.7.0"  # actualizeaza aici la fiecare "git tag vX.Y.Z"

# URL-ul fisierului JSON care anunta cea mai noua versiune disponibila.
# Trebuie sa fie gazduit static (ex: GitHub Pages) si actualizat manual
# la fiecare release - vezi docs/update.json si sectiunea "Actualizari
# automate" din CITESTE-MA.md.
APP_VERSION_URL = "https://gordasgdc.github.io/datamover/update.json"

UPDATE_CHECK_TIMEOUT = 10   # secunde, pentru verificarea update.json
DOWNLOAD_TIMEOUT = 60       # secunde, pentru descarcarea arhivei/instalatorului
DOWNLOAD_RETRY_COUNT = 3

# URL-uri pentru descarcare - "latest" inseamna intotdeauna cel mai recent
# Release publicat (vezi .github/workflows/release.yml).
DOWNLOAD_URLS = {
    "windows": "https://github.com/gordasgdc/datamover/releases/latest/download/DataMover-Windows.zip",
    "mac": "https://github.com/gordasgdc/datamover/releases/latest/download/DataMover-Mac-Installer.pkg",
}
