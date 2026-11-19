# Builds, packages and publishes a Nimbus Remote release in one go.
#
#   powershell -ExecutionPolicy Bypass -File nimbus\release.ps1 -Number 6 -Notes "What changed"
#
# Sets APP_RELEASE_TAG to v<chiaki version>-nimbus.<Number>, builds and packages with MSYS2,
# zips the app, commits, pushes and creates the GitHub release that the in-app updater picks up.
# Needs: MSYS2 at C:\msys64 with the packages from setup-msys2.sh, and gh logged in.
param(
    [Parameter(Mandatory = $true)][int]$Number,
    [Parameter(Mandatory = $true)][string]$Notes,
    [string]$Remote = 'nimbus',
    [string]$Repo = 'zZero111/nimbus-remote',
    [string]$CommitTrailer = ''
)
$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $PSScriptRoot
$parent = Split-Path -Parent $src
Set-Location $src

$cm = Get-Content (Join-Path $src 'CMakeLists.txt') -Raw
$ver = '{0}.{1}.{2}' -f ([regex]::Match($cm, 'CHIAKI_VERSION_MAJOR (\d+)').Groups[1].Value),
    ([regex]::Match($cm, 'CHIAKI_VERSION_MINOR (\d+)').Groups[1].Value),
    ([regex]::Match($cm, 'CHIAKI_VERSION_PATCH (\d+)').Groups[1].Value)
$tag = "v$ver-nimbus.$Number"
Write-Host "== Releasing $tag"

# 1. Stamp the version the updater compares against
$appinfo = Join-Path $src 'gui\include\appinfo.h'
$text = [IO.File]::ReadAllText($appinfo)
$text = [regex]::Replace($text, '#define APP_RELEASE_TAG "[^"]*"', "#define APP_RELEASE_TAG `"$tag`"")
[IO.File]::WriteAllText($appinfo, $text)

# 2. Build and package (the running app's files would be locked)
Get-Process chiaki -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$parent\*" } | Stop-Process
$env:MSYSTEM = 'MINGW64'; $env:CHERE_INVOKING = '1'
$msysSrc = '/' + $src.Substring(0, 1).ToLower() + ($src.Substring(2) -replace '\\', '/')
& C:\msys64\usr\bin\bash.exe -lc "cd '$msysSrc' && bash nimbus/build.sh && bash nimbus/deploy.sh"
if ($LASTEXITCODE -ne 0) { throw "build failed" }

# 3. Zip with a NimbusRemote\ root folder (the updater expects it)
$out = Join-Path $parent 'release'
New-Item -ItemType Directory -Force $out | Out-Null
$stage = Join-Path $out 'NimbusRemote'
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
Copy-Item -Recurse (Join-Path $parent 'dist') $stage
$zip = Join-Path $out "NimbusRemote-win64-$ver-nimbus.$Number.zip"
if (Test-Path $zip) { Remove-Item $zip }
& tar.exe -a -c -f $zip -C $out NimbusRemote
Remove-Item -Recurse -Force $stage

# 4. Commit, push, publish
git add -A
$msg = "Release $tag"
if ($CommitTrailer) { $msg += "`n`n$CommitTrailer" }
git commit -q -m $msg
git push -q $Remote HEAD:main
gh release create $tag $zip --repo $Repo --target main --title "Nimbus Remote $($tag.Substring(1))" --notes $Notes
Write-Host "== Published $tag"
