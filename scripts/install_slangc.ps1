[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$VersionLine = Get-Content (Join-Path $Root "toolchain.mk") |
	Where-Object { $_ -match '^SLANG_VERSION=' } |
	Select-Object -First 1
if (-not $VersionLine) { throw "Missing SLANG_VERSION in toolchain.mk" }
$Version = ($VersionLine -split '=', 2)[1].Trim()
$Headers = @{
	"Accept" = "application/vnd.github+json"
	"X-GitHub-Api-Version" = "2022-11-28"
}
if ($env:GITHUB_TOKEN) { $Headers["Authorization"] = "Bearer $env:GITHUB_TOKEN" }

$Release = Invoke-RestMethod `
	-Uri "https://api.github.com/repos/shader-slang/slang/releases/tags/$Version" `
	-Headers $Headers
$Asset = $Release.assets |
	Where-Object {
		$_.name -match '(?i)(windows|win).*(x86_64|amd64|x64).*\.zip$' -and
		$_.name -notmatch '(?i)(debug|source)'
	} |
	Select-Object -First 1
if (-not $Asset) { throw "No Windows x64 Slang archive found for $Version" }

$Temp = Join-Path ([System.IO.Path]::GetTempPath()) ("adriatic-slang-" + [guid]::NewGuid())
$Archive = Join-Path $Temp $Asset.name
$Extract = Join-Path $Temp "extract"
$Install = Join-Path $Root ".tools/slang"
New-Item -ItemType Directory -Force -Path $Extract | Out-Null
try {
	Invoke-WebRequest -Uri $Asset.browser_download_url -Headers $Headers -OutFile $Archive
	Expand-Archive $Archive $Extract -Force
	$Compiler = Get-ChildItem $Extract -Recurse -File -Filter slangc.exe | Select-Object -First 1
	if (-not $Compiler) { throw "Slang archive did not contain slangc.exe" }
	$PackageRoot = Split-Path $Compiler.DirectoryName -Parent
	if ((Split-Path $Compiler.DirectoryName -Leaf) -ne "bin") {
		$PackageRoot = $Compiler.DirectoryName
	}
	if (Test-Path $Install) { Remove-Item -Recurse -Force $Install }
	New-Item -ItemType Directory -Force -Path $Install | Out-Null
	Copy-Item (Join-Path $PackageRoot "*") $Install -Recurse -Force
	$Installed = Get-ChildItem $Install -Recurse -File -Filter slangc.exe | Select-Object -First 1
	$Bin = Join-Path $Install "bin"
	New-Item -ItemType Directory -Force -Path $Bin | Out-Null
	if ($Installed.FullName -ne (Join-Path $Bin "slangc.exe")) {
		Copy-Item $Installed.FullName (Join-Path $Bin "slangc.exe") -Force
	}
	& (Join-Path $Bin "slangc.exe") -version
} finally {
	if (Test-Path $Temp) { Remove-Item -Recurse -Force $Temp }
}
