[CmdletBinding()]
param(
	[string]$Version = "0.1.0",
	[string]$ZeldaEngineRoot = $env:ZELDA_ENGINE_ROOT,
	[string]$VcpkgRoot = $env:VCPKG_ROOT,
	[string]$Triplet = $(if ($env:VCPKG_DEFAULT_TRIPLET) { $env:VCPKG_DEFAULT_TRIPLET } else { "x64-windows" })
)

$ErrorActionPreference = "Stop"
$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
if (-not $ZeldaEngineRoot) { $ZeldaEngineRoot = Join-Path $Root "zelda-engine" }
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

$CgltfSource = Join-Path $ZeldaEngineRoot "packages/cgltf/src/cgltf.c"
$CgltfObject = Join-Path $Build "cgltf.obj"
$CgltfLibrary = Join-Path $ZeldaEngineRoot "packages/cgltf/lib/cgltf.lib"
New-Item -ItemType Directory -Force -Path (Split-Path $CgltfLibrary -Parent) | Out-Null
Invoke-Checked "cl" @(
	"/nologo", "/O2", "/DNDEBUG", "/MT", "/TC",
	"/c", $CgltfSource,
	"/Fo$CgltfObject"
)
Invoke-Checked "lib" @("/nologo", "/OUT:$CgltfLibrary", $CgltfObject)

$TextshapeObject = Join-Path $Build "textshape.obj"
$TextshapeLibrary = Join-Path $ZeldaEngineRoot "third_party/textshape/textshape.lib"
$UnicodeRoot = Join-Path $ZeldaEngineRoot "third_party/unicode"
$SheenBidiRoot = Join-Path $UnicodeRoot "sheenbidi"
$LibgraphemeRoot = Join-Path $UnicodeRoot "libgrapheme"
Invoke-Checked "cl" @(
	"/nologo", "/O2", "/DNDEBUG", "/std:c17",
	"/I$Include", "/I$(Join-Path $Include 'harfbuzz')", "/I$(Join-Path $Include 'freetype2')",
	"/I$(Join-Path $SheenBidiRoot 'Headers')", "/I$(Join-Path $SheenBidiRoot 'Source')",
	"/I$LibgraphemeRoot",
	"/c", (Join-Path $ZeldaEngineRoot "third_party/textshape/textshape.c"),
	"/Fo$TextshapeObject"
)
$UnicodeObjects = @()
$SheenBidiObject = Join-Path $Build "SheenBidi.obj"
Invoke-Checked "cl" @(
	"/nologo", "/O2", "/DNDEBUG", "/std:c17", "/DSB_CONFIG_UNITY",
	"/I$(Join-Path $SheenBidiRoot 'Headers')", "/I$(Join-Path $SheenBidiRoot 'Source')",
	"/c", (Join-Path $SheenBidiRoot "Source/SheenBidi.c"),
	"/Fo$SheenBidiObject"
)
$UnicodeObjects += $SheenBidiObject
foreach ($source in @("character.c", "line.c", "utf8.c", "util.c", "word.c")) {
	$object = Join-Path $Build ("grapheme_" + [IO.Path]::GetFileNameWithoutExtension($source) + ".obj")
	Invoke-Checked "cl" @(
		"/nologo", "/O2", "/DNDEBUG", "/std:c17", "/I$LibgraphemeRoot",
		"/c", (Join-Path $LibgraphemeRoot "src/$source"),
		"/Fo$object"
	)
	$UnicodeObjects += $object
}
Invoke-Checked "lib" (@("/nologo", "/OUT:$TextshapeLibrary", $TextshapeObject) + $UnicodeObjects)

# Build Adriatic's xatlas/meshoptimizer bridge imported by the world and vehicle
# packages. Keep the source list aligned with the native archive rules in the
# Makefile.
$MeshSources = @(
	"native/adriatic_xatlas.cpp",
	"third_party/xatlas/source/xatlas/xatlas.cpp",
	"third_party/meshoptimizer/src/allocator.cpp",
	"third_party/meshoptimizer/src/indexgenerator.cpp",
	"third_party/meshoptimizer/src/vcacheoptimizer.cpp",
	"third_party/meshoptimizer/src/vfetchoptimizer.cpp"
)
$MeshObjects = @()
foreach ($source in $MeshSources) {
	$object = Join-Path $Build (([IO.Path]::GetFileNameWithoutExtension($source)) + ".obj")
	Invoke-Checked "cl" @(
		"/nologo", "/O2", "/DNDEBUG", "/EHsc", "/std:c++17",
		"/I$(Join-Path $Root 'third_party/xatlas/source/xatlas')",
		"/I$(Join-Path $Root 'third_party/meshoptimizer/src')",
		"/c", (Join-Path $Root $source),
		"/Fo$object"
	)
	$MeshObjects += $object
}
$MeshLibrary = Join-Path $Build "adriatic_mesh.lib"
Invoke-Checked "lib" (@("/nologo", "/OUT:$MeshLibrary") + $MeshObjects)

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
Invoke-Checked "cmake" @(
	"-S", $JoltSource,
	"-B", $JoltBuild,
	"-A", "x64",
	"-DUSE_STATIC_MSVC_RUNTIME_LIBRARY=OFF"
)
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
if (Test-Path $Assets) { Remove-Item -Recurse -Force $Assets }
Copy-Item (Join-Path $Root "assets") $Assets -Recurse

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
