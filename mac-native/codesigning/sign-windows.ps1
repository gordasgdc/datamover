# sign-windows.ps1
#
# Semneaza un executabil Windows cu certificatul Self-Signed incarcat ca
# secret CI (vezi README-windows.md + CLAUDE.md Regula 34). Apelat din
# .github/workflows/build-windows-wpf.yml, DOAR cand secretele exista -
# fara ele, build-ul continua nesemnat (fluxul actual, neschimbat).
#
# Certificatul e COMUN tuturor aplicatiilor GDC (secrete numite IDENTIC
# in fiecare repo: WIN_SELFSIGN_PFX_BASE64/WIN_SELFSIGN_PFX_PASSWORD) -
# acelasi .pfx, deja generat/incarcat pentru CGConvertor, e reincarcat ca
# secret propriu si aici (Cristi, direct pe Windows real - certificatul
# nu trece niciodata prin conversatia cu Claude).
#
# Nu face nimic (exit 0) daca WIN_SELFSIGN_PFX_BASE64 nu e setat - sigur
# de adaugat in CI inainte sa existe efectiv secretele (acelasi tipar ca
# ci-import-certs.sh, varianta Mac).

param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

$ErrorActionPreference = "Stop"

if (-not $env:WIN_SELFSIGN_PFX_BASE64) {
    Write-Host "==> [codesigning] WIN_SELFSIGN_PFX_BASE64 nesetat - sar peste semnare ($TargetPath ramane nesemnat)."
    exit 0
}

if (-not (Test-Path $TargetPath)) {
    Write-Error "==> [codesigning] $TargetPath nu exista - nimic de semnat."
    exit 1
}

$pfxPath = Join-Path $env:RUNNER_TEMP "datamover-selfsign.pfx"
# Secretul GitHub poate ajunge cu spatii/newline-uri parazite (copiere din
# terminal/caseta web), care strica decodarea Base64 - curatam orice
# caracter alb inainte de decodare (fix deja confirmat pe CGConvertor).
$cleanBase64 = ($env:WIN_SELFSIGN_PFX_BASE64 -replace '\s', '')
[IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($cleanBase64))

try {
    $signtool = Get-ChildItem -Path "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter "signtool.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like "*x64*" } |
                Sort-Object FullName -Descending |
                Select-Object -First 1 -ExpandProperty FullName

    if (-not $signtool) {
        Write-Error "==> [codesigning] signtool.exe nu a fost gasit (Windows Kits 10) pe acest runner."
        exit 1
    }

    Write-Host "==> [codesigning] Semnez $TargetPath cu $signtool..."
    & $signtool sign /f $pfxPath /p $env:WIN_SELFSIGN_PFX_PASSWORD /fd sha256 `
        /tr http://timestamp.digicert.com /td sha256 $TargetPath
    if ($LASTEXITCODE -ne 0) {
        Write-Error "==> [codesigning] signtool sign a esuat (cod $LASTEXITCODE)."
        exit 1
    }

    # NU "signtool verify /pa" - valideaza lantul de incredere complet si
    # esueaza mereu pe un runner CI proaspat, care nu are certificatul
    # self-signed in Trusted Root (normal, nu un bug - vezi CGConvertor,
    # unde asta a picat CI-ul chiar dupa o semnare reusita). Verificam DOAR
    # ca fisierul are efectiv o semnatura Authenticode atasata.
    Write-Host "==> [codesigning] Verific semnatura ($TargetPath)..."
    $sig = Get-AuthenticodeSignature -FilePath $TargetPath
    if (-not $sig.SignerCertificate) {
        Write-Error "==> [codesigning] Fisierul nu are nicio semnatura Authenticode atasata dupa signtool sign."
        exit 1
    }
    Write-Host "==> [codesigning] Semnatura prezenta (Subject: $($sig.SignerCertificate.Subject))."
    Write-Host "==> [codesigning] Status lant de incredere pe acest runner: $($sig.Status) - 'UnknownError'/'NotTrusted' e NORMAL aici (self-signed, CI nu are certificatul in Trusted Root); userii finali il au dupa import manual."

    Write-Host "==> [codesigning] Gata: $TargetPath semnat."
}
finally {
    # Fisierul .pfx temporar NU trebuie sa supravietuiasca dincolo de acest
    # pas - sters imediat, indiferent de rezultat (succes sau eroare).
    if (Test-Path $pfxPath) {
        Remove-Item $pfxPath -Force
    }
}
