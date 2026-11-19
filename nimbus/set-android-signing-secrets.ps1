# Stores the Android signing key as GitHub Actions secrets, so every Android release is signed
# with the same key and installs as an update over the previous version.
#
#   powershell -ExecutionPolicy Bypass -File nimbus\set-android-signing-secrets.ps1
#
# Reads the key from ..\android-signing (next to this repository, never committed).
# Needs the GitHub CLI (gh) signed in to an account that owns the repository.
param(
    [string]$Repo = 'zZero111/nimbus-remote',
    [string]$KeyDir = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'android-signing')
)
$ErrorActionPreference = 'Stop'
$ks = Join-Path $KeyDir 'nimbus-release.jks'
$pwFile = Join-Path $KeyDir 'keystore-password.txt'
if (-not (Test-Path $ks) -or -not (Test-Path $pwFile)) { throw "Signing key not found in $KeyDir" }

[Convert]::ToBase64String([IO.File]::ReadAllBytes($ks)) | gh secret set ANDROID_KEYSTORE_B64 --repo $Repo
(Get-Content $pwFile -Raw) | gh secret set ANDROID_KEYSTORE_PW --repo $Repo
'nimbus' | gh secret set ANDROID_KEY_ALIAS --repo $Repo
Write-Host "Android signing secrets set for $Repo"
gh secret list --repo $Repo
