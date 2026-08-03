@echo off
REM Porneste DataMover pe Windows - dublu-click pe acest fisier
setlocal

cd /d "%~dp0"

set VENV_DIR=.venv

REM Prima rulare: cream un mediu Python izolat (venv), separat de Python-ul
REM de sistem, exact ca pe Mac - evita conflicte cu alte instalari Python.
if not exist "%VENV_DIR%\Scripts\python.exe" (
    echo Prima rulare: se pregateste mediul aplicatiei ^(dureaza cateva secunde^)...

    where python >nul 2>nul
    if errorlevel 1 (
        echo.
        echo EROARE: Python 3 nu a fost gasit in PATH.
        echo Instaleaza Python de pe https://www.python.org/downloads/windows/
        echo IMPORTANT: la instalare, bifeaza optiunea "Add python.exe to PATH".
        pause
        exit /b 1
    )

    python -m venv "%VENV_DIR%"
    if errorlevel 1 (
        echo.
        echo EROARE: nu am putut crea mediul Python ^(venv^).
        pause
        exit /b 1
    )

    "%VENV_DIR%\Scripts\python.exe" -m pip install --upgrade pip --quiet
    "%VENV_DIR%\Scripts\python.exe" -m pip install reportlab tkinterdnd2 plyer --quiet
    if errorlevel 1 (
        echo.
        echo AVERTISMENT: nu am putut instala toate dependintele optionale
        echo ^(rapoartele PDF, drag-and-drop sau notificarile pot sa nu
        echo functioneze, dar restul aplicatiei merge normal^). Verifica
        echo conexiunea la internet si incearca din nou data viitoare
        echo ^(sterge folderul .venv si reporneste^).
        pause
    )
)

REM Folosim pythonw.exe daca exista (porneste fara fereastra neagra de consola);
REM altfel ne intoarcem la python.exe normal.
if exist "%VENV_DIR%\Scripts\pythonw.exe" (
    start "" "%VENV_DIR%\Scripts\pythonw.exe" main.py
) else (
    "%VENV_DIR%\Scripts\python.exe" main.py
)

endlocal
