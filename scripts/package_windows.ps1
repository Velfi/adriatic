[CmdletBinding()]
param(
	[string]$Version = "0.1.0",
	[string]$ZeldaEngineRoot = $env:ZELDA_ENGINE_ROOT,
	[string]$VcpkgRoot = $env:VCPKG_ROOT,
	[string]$Triplet = $(if ($env:VCPKG_DEFAULT_TRIPLET) { $env:VCPKG_DEFAULT_TRIPLET } else { "x64-windows" })
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $ZeldaEngineRoot) { $ZeldaEngineRoot = Join-Path $Root "../zelda-engine" }
if (-not $VcpkgRoot) { $VcpkgRoot = "C:\vcpkg" }
$ZeldaEngineRoot = [IO.Path]::GetFullPath($ZeldaEngineRoot)
$Installed = Join-Path $VcpkgRoot "installed/$Triplet"
$Include = Join-Path $Installed "include"
$Lib = Join-Path $Installed "lib"
$Bin = Join-Path $Installed "bin"
$Build = Join-Path $Root "build/release"
$Dist = Join-Path $Root "dist"
$Package = Join-Path $Dist "Adriatic-windows"
$Archive = Join-Path $Dist "Adriatic-windows.zip"

function Require-Command([string]$Name) {
	if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
		throw "Missing required tool: $Name"
	}
}

function Invoke-Checked([string]$File, [string[]]$Arguments) {
	Write-Host "> $File $($Arguments -join ' ')"
	& $File @Arguments
	if ($LASTEXITCODE -ne 0) { throw "$File failed with exit code $LASTEXITCODE" }
}

foreach ($tool in @("cl", "lib", "cmake", "dumpbin", "odin", "slangc")) {
	Require-Command $tool
}
foreach ($path in @(
	$ZeldaEngineRoot,
	(Join-Path $Include "SDL3"),
	(Join-Path $Lib "SDL3.lib"),
	(Join-Path $Lib "harfbuzz.lib"),
	(Join-Path $Lib "freetype.lib")
)) {
	if (-not (Test-Path $path)) { throw "Missing build dependency: $path" }
}

New-Item -ItemType Directory -Force -Path $Build, $Dist | Out-Null

# Build the two small native libraries imported by Zelda Engine.
$SignpostObject = Join-Path $Build "gfx_signposts.obj"
$SignpostLibrary = Join-Path $Build "gfx_signposts.lib"
Invoke-Checked "cl" @(
	"/nologo", "/O2", "/c",
	(Join-Path $ZeldaEngineRoot "packages/canvas2d/gfx_signposts.c"),
	"/Fo$SignpostObject"
)
Invoke-Checked "lib" @("/nologo", "/OUT:$SignpostLibrary", $SignpostObject)

$TextshapeObject = Join-Path $Build "textshape.obj"
$TextshapeLibrary = Join-Path $ZeldaEngineRoot "third_party/textshape/textshape.lib"
Invoke-Checked "cl" @(
	"/nologo", "/O2", "/DNDEBUG", "/std:c17",
	"/I$Include", "/I$(Join-Path $Include 'harfbuzz')", "/I$(Join-Path $Include 'freetype2')",
	"/c", (Join-Path $ZeldaEngineRoot "third_party/textshape/textshape.c"),
	"/Fo$TextshapeObject"
)
Invoke-Checked "lib" @("/nologo", "/OUT:$TextshapeLibrary", $TextshapeObject)

# Build the engine-owned Jolt bridge and put its import library where the Odin
# physics package's platform declaration expects it.
$JoltSource = Join-Path $ZeldaEngineRoot "third_party/jolt"
$JoltBuild = Join-Path $JoltSource "build"
if (-not (Test-Path (Join-Path $ZeldaEngineRoot "third_party/JoltPhysics/.git"))) {
	Invoke-Checked "git" @(
		"clone", "--depth", "1", "--branch", "v5.4.0",
		"https://github.com/jrouwe/JoltPhysics.git",
		(Join-Path $ZeldaEngineRoot "third_party/JoltPhysics")
	)
}
Invoke-Checked "cmake" @("-S", $JoltSource, "-B", $JoltBuild, "-A", "x64")
Invoke-Checked "cmake" @("--build", $JoltBuild, "--config", "Release", "--target", "zelda_physics")
$PhysicsImport = Get-ChildItem $JoltSource -Recurse -File -Filter "zelda_physics.lib" |
	Where-Object { $_.FullName -notlike "*Jolt.lib" } |
	Select-Object -First 1
$PhysicsDll = Get-ChildItem $JoltSource -Recurse -File -Filter "zelda_physics.dll" | Select-Object -First 1
if (-not $PhysicsImport -or -not $PhysicsDll) { throw "Jolt bridge build did not produce its import library and DLL" }
$ExpectedPhysicsImport = Join-Path $JoltSource "zelda_physics.lib"
if ($PhysicsImport.FullName -ne $ExpectedPhysicsImport) {
	Copy-Item $PhysicsImport.FullName $ExpectedPhysicsImport -Force
}

$Shaders = Join-Path $Build "shaders"
New-Item -ItemType Directory -Force -Path $Shaders | Out-Null
$ShaderJobs = @(
	@("world.slang", "vertex_main", "vertex", "world.vert.spv"),
	@("world.slang", "fragment_main", "fragment", "world.frag.spv"),
	@("sky.slang", "sky_vertex", "vertex", "world-sky.vert.spv"),
	@("sky.slang", "sky_fragment", "fragment", "world-sky.frag.spv"),
	@("wireframe.slang", "vertex_main", "vertex", "wireframe.vert.spv"),
	@("wireframe.slang", "fragment_main", "fragment", "wireframe.frag.spv"),
	@("canvas.slang", "vertex_main", "vertex", "canvas.vert.spv"),
	@("canvas.slang", "fragment_main", "fragment", "canvas.frag.spv"),
	@("canvas.slang", "post_vertex", "vertex", "canvas-post.vert.spv"),
	@("canvas.slang", "post_fragment", "fragment", "canvas-post.frag.spv"),
	@("particles.slang", "vertex_main", "vertex", "particles.vert.spv"),
	@("particles.slang", "fragment_main", "fragment", "particles.frag.spv"),
	@("foliage.slang", "vertex_main", "vertex", "foliage.vert.spv"),
	@("foliage.slang", "fragment_main", "fragment", "foliage.frag.spv")
)
foreach ($job in $ShaderJobs) {
	Invoke-Checked "slangc" @(
		(Join-Path $Root "assets/shaders/$($job[0])"),
		"-entry", $job[1], "-stage", $job[2],
		"-target", "spirv", "-profile", "spirv_1_5",
		"-o", (Join-Path $Shaders $job[3])
	)
}

$Assets = Join-Path $Build "assets"
New-Item -ItemType Directory -Force -Path (Join-Path $Assets "icons"), (Join-Path $Assets "fonts"), (Join-Path $Assets "textures/foliage") | Out-Null
Copy-Item (Join-Path $Root "assets/icons/ui-icon-atlas-garden.png") (Join-Path $Assets "icons") -Force
Copy-Item (Join-Path $Root "assets/fonts/*") (Join-Path $Assets "fonts") -Force
Copy-Item (Join-Path $Root "assets/textures/foliage/leaf-branches-atlas.png") (Join-Path $Assets "textures/foliage") -Force

$Exe = Join-Path $Build "adriatic.exe"
$LinkerFlags = "/LIBPATH:$Lib SDL3.lib harfbuzz.lib freetype.lib vulkan-1.lib /LIBPATH:$Build gfx_signposts.lib"
Invoke-Checked "odin" @(
	"build", (Join-Path $Root "src"),
	"-collection:zelda_engine=$(Join-Path $ZeldaEngineRoot 'packages')",
	"-o:speed", "-out:$Exe", "-extra-linker-flags:$LinkerFlags"
)

if (Test-Path $Package) { Remove-Item -Recurse -Force $Package }
if (Test-Path $Archive) { Remove-Item -Force $Archive }
New-Item -ItemType Directory -Force -Path $Package | Out-Null
Copy-Item $Exe (Join-Path $Package "Adriatic.exe")
Copy-Item $Assets (Join-Path $Package "assets") -Recurse
Copy-Item $Shaders (Join-Path $Package "shaders") -Recurse
Copy-Item $PhysicsDll.FullName $Package

function Get-Dependencies([string]$Binary) {
	& dumpbin /DEPENDENTS $Binary |
		ForEach-Object {
			if ($_ -match '^\s+([A-Za-z0-9_.+-]+\.dll)\s*$') { $matches[1] }
		}
}

$Queue = [Collections.Generic.Queue[string]]::new()
$Queue.Enqueue((Join-Path $Package "Adriatic.exe"))
$Queue.Enqueue((Join-Path $Package $PhysicsDll.Name))
$Seen = @{}
while ($Queue.Count -gt 0) {
	$Binary = $Queue.Dequeue()
	if ($Seen[$Binary]) { continue }
	$Seen[$Binary] = $true
	foreach ($dependency in Get-Dependencies $Binary) {
		$source = Join-Path $Bin $dependency
		if (-not (Test-Path $source)) { continue }
		$target = Join-Path $Package $dependency
		if (-not (Test-Path $target)) { Copy-Item $source $target }
		$Queue.Enqueue($target)
	}
}
if (Test-Path (Join-Path $Bin "vulkan-1.dll")) {
	Copy-Item (Join-Path $Bin "vulkan-1.dll") $Package -Force
}

Compress-Archive -Path $Package -DestinationPath $Archive -Force
Write-Host "Packaged Adriatic $Version"
Write-Host "Archive: $Archive"
