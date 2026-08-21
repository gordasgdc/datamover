# Refactor: UI separat per OS, backend comun

## Structura noua

```
datamover/
  core/                  <- backend, neschimbat, OS-agnostic
    offload_engine.py
    checkpoint.py
    config.py
    license_core.py
    license_validator.py
    machine_id.py
    activation.py
    update_config.py
    updater.py
    pdf_report.py
    translations.py
  ui/
    common/
      theme.py
      tooltip.py
    windows/
      app.py             <- DataMoverApp actual, mutat AS-IS, zero modificari de logica
    mac/
      app.py              <- UI noua, 3 coloane (schelet atasat)
  main.py                 <- dispatcher: alege ui.windows.app sau ui.mac.app dupa sys.platform
```

`core/` ramane sursa unica de adevar pentru transfer/verificare — ambele UI-uri o importa, niciodata invers.

## Pasi git (ruleaza tu, in ordine)

```bash
cd /Users/gordasgdc/Downloads/datamover
git checkout -b feature/mac-native-ui

mkdir -p core ui/common ui/windows ui/mac
git mv offload_engine.py checkpoint.py config.py license_core.py license_validator.py machine_id.py activation.py update_config.py updater.py pdf_report.py translations.py core/
git mv theme.py tooltip.py ui/common/
git mv main.py ui/windows/app.py

git add -A
git commit -m "Restructurare: core/ backend + ui/windows/ (fara modificari de logica)"
```

## Ce ramane de facut manual dupa mutare

1. **Import-uri**: fiecare `import offload_engine` / `from theme import ...` etc. din `ui/windows/app.py` trebuie sa devina `from core import offload_engine` / `from ui.common import theme` (find & replace, ~15-20 linii, nicio logica schimbata).
2. **main.py nou** (in radacina, inlocuieste vechiul):
   ```python
   import sys
   if sys.platform == "darwin":
       from ui.mac.app import run
   else:
       from ui.windows.app import run
   run()
   ```
   `ui/windows/app.py` are nevoie de o functie `run()` la final care porneste `DataMoverApp` (azi probabil e cod la nivel de modul sub `if __name__ == "__main__":` — il transformi in functie).
3. **setup.py / PyInstaller spec-uri**: `DATA_FILES`/`includes` trebuie sa refere noile path-uri (`core.offload_engine` etc.) — altfel build-ul de Mac/Windows nu mai gaseste modulele.
4. **CI** (`build-mac.yml`, `build-windows.yml`): neschimbate ca declansator, dar verifica dupa primul build ca py2app/PyInstaller au prins toate modulele din `core/` si `ui/`.

Nu am rulat nimic din pasii de mai sus — e checklist pentru tine, ca sa revizuiesti fiecare mutare inainte de commit.
