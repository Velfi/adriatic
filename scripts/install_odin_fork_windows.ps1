[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
$Toolchain = Get-Content (Join-Path $Root "toolchain.mk")

function Read-ToolchainValue([string]$Name) {
	foreach ($line in $Toolchain) {
		if ($line -match "^$([regex]::Escape($Name))=(.+)$") {
			return $matches[1].Trim()
		}
	}
	throw "Missing $Name in toolchain.mk"
}

$Repository = Read-ToolchainValue "ODIN_FORK_REPOSITORY"
$Commit = Read-ToolchainValue "ODIN_FORK_COMMIT"
$Version = Read-ToolchainValue "ODIN_FORK_VERSION"
$ExpectedVersion = Read-ToolchainValue "ODIN_VERSION_OUTPUT"
$Source = Join-Path $Root ".tools/odin/catermujo-src"
$Install = Join-Path $Root ".tools/odin/$Version"

if (-not (Test-Path (Join-Path $Source ".git"))) {
	New-Item -ItemType Directory -Force -Path (Split-Path $Source -Parent) | Out-Null
	& git clone $Repository $Source
	if ($LASTEXITCODE -ne 0) { throw "Failed to clone the Odin fork" }
}

& git -C $Source fetch --quiet origin $Commit
if ($LASTEXITCODE -ne 0) { throw "Failed to fetch Odin commit $Commit" }
& git -C $Source checkout --quiet --detach $Commit
if ($LASTEXITCODE -ne 0) { throw "Failed to check out Odin commit $Commit" }

Push-Location $Source
try {
	& cmd /c build.bat release
	if ($LASTEXITCODE -ne 0) { throw "Odin build failed" }
} finally {
	Pop-Location
}

New-Item -ItemType Directory -Force -Path $Install | Out-Null
Copy-Item (Join-Path $Source "odin.exe") (Join-Path $Install "odin.exe") -Force
foreach ($directory in @("base", "core", "vendor")) {
	$target = Join-Path $Install $directory
	if (Test-Path $target) { Remove-Item -Recurse -Force $target }
	Copy-Item (Join-Path $Source $directory) $target -Recurse
}

$Actual = & (Join-Path $Install "odin.exe") version
if ("$Actual" -notlike "*$ExpectedVersion*") {
	throw "Installed Odin reports '$Actual'; expected '$ExpectedVersion'"
}
Write-Host "Installed pinned Odin fork: $Actual"
