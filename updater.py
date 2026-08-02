"""
updater.py
----------
Logica de self-update pentru ShotPut Lite: verificare versiune noua,
descarcare, si instalare (Windows: inlocuire .exe; Mac: instalare .pkg
cu prompt nativ de parola admin). Foloseste doar biblioteca standard
Python - fara dependinte externe.

SIGURANTA: instalarea efectiva (perform_update_windows/perform_update_mac)
functioneaza DOAR cand aplicatia ruleaza compilata (.exe/.app), verificat
prin `getattr(sys, "frozen", False)`. Cand ruleaza din sursa (python3
main.py), sys.executable e interpretul Python insusi, NU aplicatia - a
incerca sa-l suprascrie ar fi periculos. In acest caz, functiile de mai
jos refuza sa continue si returneaza un mesaj explicativ.
"""

import os
import sys
import json
import re
import urllib.request
import urllib.error
import subprocess
import zipfile
import shutil


def _version_tuple(version_string):
    """Transforma '1.10.2' in (1, 10, 2), pentru comparatie numerica
    corecta (nu alfabetica - '1.10.0' > '1.9.0' ca text e FALS, desi
    1.10.0 e versiunea mai noua)."""
    parts = []
    for piece in re.split(r"[.\-]", version_string.strip().lstrip("vV")):
        match = re.match(r"\d+", piece)
        parts.append(int(match.group()) if match else 0)
    return tuple(parts) if parts else (0,)


def is_newer_version(candidate, current):
    return _version_tuple(candidate) > _version_tuple(current)


def check_for_updates(current_version, update_url, timeout=10):
    """Verifica daca exista o versiune noua, citind fisierul JSON de la
    update_url. Returneaza un dict cu 'available' (True/False) si, daca e
    disponibila o versiune noua, detaliile ei."""
    try:
        request = urllib.request.Request(update_url, headers={"User-Agent": "ShotPutLite-Updater"})
        with urllib.request.urlopen(request, timeout=timeout) as response:
            data = json.loads(response.read().decode("utf-8"))

        latest_version = str(data.get("version", "")).strip()
        if not latest_version:
            return {"available": False, "error": "Raspuns invalid de la serverul de actualizari."}

        if is_newer_version(latest_version, current_version):
            return {
                "available": True,
                "version": latest_version,
                "changes": data.get("changes", ""),
                "download_url": data.get("download_url", {}),
                "mandatory": bool(data.get("mandatory", False)),
                "release_date": data.get("release_date", ""),
            }
        return {"available": False}
    except urllib.error.URLError as e:
        return {"available": False, "error": f"Nu am putut contacta serverul de actualizari: {e.reason}"}
    except Exception as e:
        return {"available": False, "error": str(e)}


def download_update(download_urls, temp_dir, retry_count=3, timeout=60):
    """Descarca fisierul de actualizare potrivit platformei curente
    (.zip pe Windows, .pkg pe Mac - extensia se determina din URL, nu e
    presupusa fixa). Reincearca de 'retry_count' ori la esec de retea."""
    platform_key = "windows" if sys.platform == "win32" else "mac"
    url = download_urls.get(platform_key)
    if not url:
        return None, f"Nu exista un link de descarcare pentru platforma '{platform_key}'."

    ext = os.path.splitext(url.split("?")[0])[1] or ".bin"
    download_path = os.path.join(temp_dir, f"shotput_update_{platform_key}{ext}")

    last_error = None
    for attempt in range(1, retry_count + 1):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "ShotPutLite-Updater"})
            with urllib.request.urlopen(request, timeout=timeout) as response, \
                    open(download_path, "wb") as out_file:
                shutil.copyfileobj(response, out_file)
            return download_path, None
        except Exception as e:
            last_error = str(e)
    return None, f"Descarcarea a esuat dupa {retry_count} incercari ({last_error})."


def extract_archive(archive_path, extract_dir):
    """Extrage o arhiva .zip. NU se foloseste pentru .pkg (acela se
    instaleaza direct, nu se extrage)."""
    with zipfile.ZipFile(archive_path, "r") as zip_ref:
        zip_ref.extractall(extract_dir)
    return extract_dir


def _find_file(directory, exact_name):
    for root, _dirs, files in os.walk(directory):
        for f in files:
            if f == exact_name:
                return os.path.join(root, f)
    return None


def perform_update_windows(extract_dir, overall_temp_dir):
    """Inlocuieste 'ShotPut Lite.exe' curent cu cel nou-descarcat, printr-un
    script .bat auxiliar care asteapta (in bucla, nu cu un timp fix) ca
    procesul curent sa elibereze fisierul, apoi il inlocuieste si reporneste
    aplicatia. Functioneaza DOAR daca aplicatia ruleaza compilata."""
    if not getattr(sys, "frozen", False):
        return False, ("Actualizarea automata functioneaza doar in versiunea compilata "
                        "(.exe) - nu si cand rulezi din sursa cu 'python3 main.py'.")

    new_exe = _find_file(extract_dir, "ShotPut Lite.exe")
    if not new_exe:
        return False, "Nu am gasit 'ShotPut Lite.exe' in arhiva descarcata."

    current_exe = sys.executable
    bat_path = os.path.join(overall_temp_dir, "shotput_update.bat")
    log_path = os.path.join(overall_temp_dir, "shotput_update.log")

    bat_content = f"""@echo off
setlocal enabledelayedexpansion
set "NEWEXE={new_exe}"
set "CUREXE={current_exe}"
set "LOG={log_path}"
echo Se asteapta inchiderea aplicatiei... > "%LOG%"
set /a tries=0

:retry
timeout /t 1 /nobreak > nul
copy /Y "%NEWEXE%" "%CUREXE%" >> "%LOG%" 2>&1
if errorlevel 1 (
    set /a tries+=1
    if !tries! lss 25 goto retry
    echo Copierea a esuat dupa 25 de incercari. >> "%LOG%"
    exit /b 1
)

echo Copiere reusita, pornesc aplicatia actualizata... >> "%LOG%"
start "" "%CUREXE%"
rmdir /S /Q "{overall_temp_dir}"
"""
    with open(bat_path, "w", encoding="utf-8") as f:
        f.write(bat_content)

    creationflags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
    try:
        subprocess.Popen(["cmd", "/c", bat_path], creationflags=creationflags)
    except Exception as e:
        return False, f"Nu am putut porni scriptul de actualizare: {e}"
    return True, None


def perform_update_mac(pkg_path, overall_temp_dir):
    """Instaleaza .pkg-ul descarcat folosind promptul NATIV macOS de parola
    de administrator ('osascript ... with administrator privileges') - nu
    deschide o fereastra Terminal si nu foloseste 'sudo' fara TTY (care s-ar
    bloca). Functioneaza DOAR daca aplicatia ruleaza compilata."""
    if not getattr(sys, "frozen", False):
        return False, ("Actualizarea automata functioneaza doar in versiunea compilata "
                        "(.app) - nu si cand rulezi din sursa cu 'python3 main.py'.")
    if not pkg_path or not os.path.isfile(pkg_path):
        return False, "Nu am gasit fisierul .pkg descarcat."

    script_path = os.path.join(overall_temp_dir, "shotput_update.sh")
    log_path = os.path.join(overall_temp_dir, "shotput_update.log")

    script_content = f"""#!/bin/bash
exec > "{log_path}" 2>&1
sleep 2
echo "Instalez actualizarea..."
installer -pkg "{pkg_path}" -target /
status=$?
if [ $status -ne 0 ]; then
    echo "Instalarea a esuat (cod $status)."
    exit $status
fi
echo "Pornesc aplicatia actualizata..."
open -a "ShotPut Lite"
rm -rf "{overall_temp_dir}"
"""
    with open(script_path, "w", encoding="utf-8") as f:
        f.write(script_content)
    os.chmod(script_path, 0o755)

    # "with administrator privileges" declanseaza fereastra NATIVA macOS de
    # parola admin (aceeasi pe care o vezi la orice instalator .pkg normal),
    # fara sa deschidem Terminal si fara sudo interactiv fara TTY.
    escaped_path = script_path.replace('"', '\\"')
    apple_script = f'do shell script "{escaped_path}" with administrator privileges'
    try:
        subprocess.Popen(["osascript", "-e", apple_script])
    except Exception as e:
        return False, f"Nu am putut porni instalarea: {e}"
    return True, None


def cleanup_update(temp_dir):
    """Curata fisierele temporare. Folosit doar cand actualizarea a esuat
    INAINTE de a porni scriptul auxiliar - dupa ce scriptul porneste, el
    insusi se ocupa de curatare (nu mai putem sterge noi, procesul curent
    urmeaza sa fie inlocuit/inchis)."""
    try:
        shutil.rmtree(temp_dir, ignore_errors=True)
    except Exception:
        pass
