include toolchain.mk

APP := adriatic
BUILD_DIR := build
TOOLS_DIR := .tools

PROFILE ?= hot
PROFILE_ODIN_FLAGS_hot := -dynamic-map-calls -o:minimal -debug
PROFILE_DEFINE_FLAGS_hot := -define:HOT_RELOAD=true
PROFILE_CONFIG_hot := debug
PROFILE_ENTRY_hot := hot
PROFILE_LINK_MODE_hot := shared
PROFILE_VULKAN_VALIDATION_hot := false
PROFILE_ASAN_hot := false

PROFILE_ODIN_FLAGS_debug := -dynamic-map-calls -o:minimal -debug
PROFILE_DEFINE_FLAGS_debug :=
PROFILE_CONFIG_debug := debug
PROFILE_ENTRY_debug := cold
PROFILE_LINK_MODE_debug := system
PROFILE_VULKAN_VALIDATION_debug := false
PROFILE_ASAN_debug := false

PROFILE_ODIN_FLAGS_release := -dynamic-map-calls -o:speed -debug
PROFILE_DEFINE_FLAGS_release := -define:SHOW_STARTUP_MENU=true
PROFILE_CONFIG_release := release
PROFILE_ENTRY_release := cold
PROFILE_LINK_MODE_release := system
PROFILE_VULKAN_VALIDATION_release := false
PROFILE_ASAN_release := false

PROFILE_ODIN_FLAGS_validation := -debug -o:none -sanitize:address
PROFILE_DEFINE_FLAGS_validation :=
PROFILE_CONFIG_validation := debug
PROFILE_ENTRY_validation := cold
PROFILE_LINK_MODE_validation := system
PROFILE_VULKAN_VALIDATION_validation := true
PROFILE_ASAN_validation := true

PROFILE_ODIN_FLAGS_instrument := -dynamic-map-calls -o:minimal -debug
PROFILE_DEFINE_FLAGS_instrument := -define:DIO_FLAME_GRAPH=true -define:DIO_FLAME_GRAPH_DEVELOPER_EXPORTS=true
PROFILE_DEFINE_FLAGS_instrument_deep := -define:FLAME_AUTO_INSTRUMENT=true -define:DIO_FLAME_GRAPH_DEVELOPER_EXPORTS=true -define:BACK_OTHER_CUSTOM_INSTRUMENTATION=true -define:FLAME_AUTO_SLOT_CAP=50000
PROFILE_CONFIG_instrument := release
PROFILE_ENTRY_instrument := cold
PROFILE_LINK_MODE_instrument := system
PROFILE_VULKAN_VALIDATION_instrument := false
PROFILE_ASAN_instrument := false

VALIDATION_PROFILE_RUNTIME_ENV := env \
	MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0 \
	VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation \
	ASAN_OPTIONS=halt_on_error=1:abort_on_error=1
NON_VALIDATION_PROFILE_RUNTIME_ENV := env \
	-u VK_INSTANCE_LAYERS \
	-u VK_LOADER_LAYERS_ENABLE \
	MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS=0
PROFILE_RUNTIME_ENV_hot := $(NON_VALIDATION_PROFILE_RUNTIME_ENV)
PROFILE_RUNTIME_ENV_debug := $(NON_VALIDATION_PROFILE_RUNTIME_ENV)
PROFILE_RUNTIME_ENV_release := $(NON_VALIDATION_PROFILE_RUNTIME_ENV)
PROFILE_RUNTIME_ENV_validation := $(VALIDATION_PROFILE_RUNTIME_ENV)
PROFILE_RUNTIME_ENV_instrument := $(NON_VALIDATION_PROFILE_RUNTIME_ENV) \
	ZELDA_ENGINE_GPU_PROFILER=1

ZELDA_ENGINE_ROOT ?= $(CURDIR)/zelda-engine
ZELDA_ENGINE_PACKAGES := $(abspath $(ZELDA_ENGINE_ROOT))/packages
ZELDA_ENGINE_COLLECTION := -collection:zelda_engine=$(ZELDA_ENGINE_PACKAGES)
TEXTSHAPE_DIR := $(abspath $(ZELDA_ENGINE_ROOT))/third_party/textshape
TEXTSHAPE_LIB := $(TEXTSHAPE_DIR)/libtextshape.a
TEXTSHAPE_SOURCES := \
	$(TEXTSHAPE_DIR)/textshape.c \
	$(shell find "$(ZELDA_ENGINE_ROOT)/third_party/unicode" -type f \( -name '*.c' -o -name '*.h' \) 2>/dev/null)
CGLTF_DIR := $(ZELDA_ENGINE_PACKAGES)/cgltf
CGLTF_SOURCE := $(CGLTF_DIR)/src/cgltf.c
CGLTF_HEADER := $(CGLTF_DIR)/src/cgltf.h
CGLTF_BUILD_DIR := $(BUILD_DIR)/cgltf

ifeq ($(shell uname -s),Darwin)
CGLTF_LIB := $(CGLTF_DIR)/lib/darwin/cgltf.a
CGLTF_X86_OBJECT := $(CGLTF_BUILD_DIR)/cgltf-x86_64.o
CGLTF_ARM_OBJECT := $(CGLTF_BUILD_DIR)/cgltf-arm64.o
else ifeq ($(shell uname -s),Linux)
CGLTF_LIB := $(CGLTF_DIR)/lib/cgltf.a
CGLTF_OBJECT := $(CGLTF_BUILD_DIR)/cgltf.o
else
CGLTF_LIB := $(CGLTF_DIR)/lib/cgltf.lib
CGLTF_OBJECT := $(CGLTF_BUILD_DIR)/cgltf.o
endif

LOCAL_ODIN := $(TOOLS_DIR)/odin/$(ODIN_FORK_VERSION)/odin
LOCAL_SLANGC := $(TOOLS_DIR)/slang/$(SLANG_VERSION)/slangc
PATH_ODIN := $(shell command -v odin 2>/dev/null)
PATH_SLANGC := $(shell command -v slangc 2>/dev/null)
ODIN ?= $(if $(wildcard $(LOCAL_ODIN)),$(LOCAL_ODIN),$(PATH_ODIN))
ODIN_VET_FLAGS := -vet-shadowing -vet-cast -no-instrumentation-force-inline
SLANGC ?= $(if $(PATH_SLANGC),$(PATH_SLANGC),$(LOCAL_SLANGC))
ODINFMT ?= odinfmt
CC ?= cc
AR ?= ar
PYTHON ?= python3

ifeq ($(shell uname -s),Darwin)
HOMEBREW_LLVM_PREFIX := $(shell brew --prefix $(LLVM_HOMEBREW_FORMULA) 2>/dev/null)
ODIN_CLANG_PATH ?= $(HOMEBREW_LLVM_PREFIX)/bin/clang
export ODIN_CLANG_PATH
endif

ifeq ($(shell uname -s),Darwin)
LINKER_PLATFORM_FLAGS := -Wl,-no_warn_duplicate_libraries -framework Cocoa
endif

TEXTSHAPE_LIBS := $(shell pkg-config --libs harfbuzz freetype2 2>/dev/null)
link_flags = $(TEXTSHAPE_LIBS) -L$(abspath $(1)) -lgfx_signposts -lc++ $(LINKER_PLATFORM_FLAGS)

DEV_DIR := $(BUILD_DIR)/dev
RELEASE_DIR := $(BUILD_DIR)/release
VALIDATION_DIR := $(BUILD_DIR)/validation
INSTRUMENT_DIR := $(BUILD_DIR)/instrument
DEV_APP := $(DEV_DIR)/$(APP)
RELEASE_APP := $(RELEASE_DIR)/$(APP)
VALIDATION_APP := $(VALIDATION_DIR)/$(APP)
INSTRUMENT_APP := $(INSTRUMENT_DIR)/$(APP)
INSTRUMENT_RUNTIME_STAMP := $(INSTRUMENT_DIR)/runtime-assets.stamp
INSTRUMENT_ASSET_SOURCES := $(shell find assets -type f 2>/dev/null)
PHYSICS_STAMP := $(BUILD_DIR)/physics.stamp
PHYSICS_SOURCES := \
	$(ZELDA_ENGINE_ROOT)/Makefile \
	$(ZELDA_ENGINE_ROOT)/third_party/jolt/CMakeLists.txt \
	$(ZELDA_ENGINE_ROOT)/third_party/jolt/physics.cpp
ifeq ($(shell uname -s),Darwin)
SHARED_EXT := dylib
else ifeq ($(shell uname -s),Linux)
SHARED_EXT := so
else
SHARED_EXT := dll
endif
HOT_DIR := $(BUILD_DIR)/hot
HOT_APP := $(HOT_DIR)/$(APP).$(SHARED_EXT)
HOT_HOST := $(HOT_DIR)/$(APP)-hot
HOT_SHADER_DIR := $(HOT_DIR)/shaders
HOT_APP_STAMP := $(HOT_DIR)/app.stamp
HOT_SHADER_STAMP := $(HOT_DIR)/shader.stamp
LIVE_CAPTURE_PATH ?= $(abspath $(BUILD_DIR)/captures/$(APP)-live.png)
LIVE_CAPTURE_TIMEOUT ?= 30
LIVE_CAPTURE_REQUEST_PATH := $(abspath $(BUILD_DIR)/live-capture.request)
FIXTURE_HISTORY_VERSION ?= 1
FIXTURE_MIGRATION_FROM_VERSION ?= 1
FIXTURE_MIGRATION_TO_VERSION ?= 2
FIXTURE_HISTORY_PACKAGE := packages/fixture_history/v$(shell printf '%04d' "$(FIXTURE_HISTORY_VERSION)")
ODIN_SOURCES := $(shell find src packages tests -type f -name '*.odin' 2>/dev/null)
HOT_ODIN_SOURCES := $(shell find src packages "$(ZELDA_ENGINE_PACKAGES)" -type f -name '*.odin' 2>/dev/null)
HOT_SHADER_OUTPUTS := \
	$(HOT_SHADER_DIR)/world.vert.spv \
	$(HOT_SHADER_DIR)/world-instance.vert.spv \
	$(HOT_SHADER_DIR)/world.frag.spv \
	$(HOT_SHADER_DIR)/player-shadow.vert.spv \
	$(HOT_SHADER_DIR)/player-shadow.frag.spv \
	$(HOT_SHADER_DIR)/dynamic-shadow.vert.spv \
	$(HOT_SHADER_DIR)/world-sky.vert.spv \
	$(HOT_SHADER_DIR)/world-sky.frag.spv \
	$(HOT_SHADER_DIR)/wireframe.vert.spv \
	$(HOT_SHADER_DIR)/wireframe.frag.spv \
	$(HOT_SHADER_DIR)/canvas.vert.spv \
	$(HOT_SHADER_DIR)/canvas.frag.spv \
	$(HOT_SHADER_DIR)/canvas-post.vert.spv \
	$(HOT_SHADER_DIR)/canvas-post.frag.spv \
	$(HOT_SHADER_DIR)/particles.vert.spv \
	$(HOT_SHADER_DIR)/particles.frag.spv \
	$(HOT_SHADER_DIR)/foliage.vert.spv \
	$(HOT_SHADER_DIR)/bougainvillea.vert.spv \
	$(HOT_SHADER_DIR)/grass.vert.spv \
	$(HOT_SHADER_DIR)/foliage.frag.spv

.PHONY: all bootstrap bootstrap-fork check-odin-version doctor textshape-build cgltf-build physics-deps physics-build shaders assets-dev assets-release assets-hot assets-validation build release validation validation-build lldb instrument instrument-build instrument-deep profile profile-info dev debug hot hot-build hot-app hot-host hot-shaders run benchmark capture-live mcp fixture-schema-generate fixture-schema-check fixture-history-generate fixture-history-check fixture-migration-scaffold fixture-migration-scaffold-check fixture-codec-test fixture-editor-load-test fixture-editor-store-test fixture-upgrade-test fixture-lifecycle-test fixture-migration-test fmt check test test-src test-rondine clean

all: build

bootstrap:
	./tools/bootstrap-macos.sh
	./tools/bootstrap-odin-fork-macos.sh

bootstrap-fork:
	./tools/bootstrap-odin-fork-macos.sh

check-odin-version:
	@set -eu; \
	if [ ! -x "$(ODIN)" ] && ! command -v "$(ODIN)" >/dev/null 2>&1; then \
		echo "error: Odin is missing; run make bootstrap or set ODIN=/path/to/odin" >&2; exit 1; \
	fi; \
	actual="$$($(ODIN) version 2>/dev/null || true)"; \
	case "$$actual" in \
		*"$(ODIN_VERSION_OUTPUT)"*) ;; \
		*) \
			echo "error: wrong Odin compiler version" >&2; \
			echo "  expected: $(ODIN_VERSION_OUTPUT)" >&2; \
			echo "  actual:   $${actual:-<no version output>}" >&2; \
			echo "run 'make bootstrap-fork' or set ODIN=/path/to/the/locked/odin" >&2; \
			exit 1 ;; \
	esac; \
	echo "Odin: $$actual"

doctor: check-odin-version
	@set -eu; \
	if [ ! -d "$(ZELDA_ENGINE_PACKAGES)" ]; then \
		echo "error: Zelda Engine packages not found at $(ZELDA_ENGINE_PACKAGES)" >&2; exit 1; \
	fi; \
	echo "Zelda Engine: $$(git -C "$(ZELDA_ENGINE_ROOT)" rev-parse --short HEAD 2>/dev/null || echo unversioned)"; \
	echo "Toolchain lock: $(ODIN_FORK_VERSION)"

assets-dev:
	@mkdir -p "$(DEV_DIR)/assets"
	rsync -a --delete assets/ "$(DEV_DIR)/assets/"

assets-release:
	@mkdir -p "$(RELEASE_DIR)/assets"
	rsync -a --delete assets/ "$(RELEASE_DIR)/assets/"

assets-hot:
	@mkdir -p "$(HOT_DIR)/assets"
	rsync -a --delete assets/ "$(HOT_DIR)/assets/"

assets-validation: shaders
	@mkdir -p "$(VALIDATION_DIR)/assets" "$(VALIDATION_DIR)/shaders"
	rsync -a --delete assets/ "$(VALIDATION_DIR)/assets/"
	rsync -a --delete build/generated/shaders/ "$(VALIDATION_DIR)/shaders/"

build: doctor assets-dev $(DEV_APP)

shaders: build/generated/shaders/world.vert.spv build/generated/shaders/world-instance.vert.spv build/generated/shaders/world.frag.spv build/generated/shaders/player-shadow.vert.spv build/generated/shaders/player-shadow.frag.spv build/generated/shaders/dynamic-shadow.vert.spv build/generated/shaders/world-sky.vert.spv build/generated/shaders/world-sky.frag.spv build/generated/shaders/wireframe.vert.spv build/generated/shaders/wireframe.frag.spv build/generated/shaders/canvas.vert.spv build/generated/shaders/canvas.frag.spv build/generated/shaders/canvas-post.vert.spv build/generated/shaders/canvas-post.frag.spv build/generated/shaders/particles.vert.spv build/generated/shaders/particles.frag.spv build/generated/shaders/foliage.vert.spv build/generated/shaders/bougainvillea.vert.spv build/generated/shaders/grass.vert.spv build/generated/shaders/foliage.frag.spv

build/generated/shaders/foliage.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/bougainvillea.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry bougainvillea_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/grass.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry grass_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/foliage.frag.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/particles.vert.spv: assets/shaders/particles.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/particles.frag.spv: assets/shaders/particles.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/world.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/world-instance.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry instance_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/world.frag.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/player-shadow.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry shadow_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/dynamic-shadow.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry dynamic_shadow_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/player-shadow.frag.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry shadow_fragment -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/world-sky.vert.spv: assets/shaders/sky.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry sky_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/world-sky.frag.spv: assets/shaders/sky.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry sky_fragment -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/wireframe.vert.spv: assets/shaders/wireframe.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/wireframe.frag.spv: assets/shaders/wireframe.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/canvas.vert.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/canvas.frag.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/canvas-post.vert.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry post_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/canvas-post.frag.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry post_fragment -stage fragment -target spirv -profile spirv_1_5 -o $@

$(DEV_DIR)/shaders/wireframe.vert.spv: build/generated/shaders/wireframe.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/world.vert.spv: build/generated/shaders/world.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/world-instance.vert.spv: build/generated/shaders/world-instance.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/world.frag.spv: build/generated/shaders/world.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/player-shadow.vert.spv: build/generated/shaders/player-shadow.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/player-shadow.frag.spv: build/generated/shaders/player-shadow.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/dynamic-shadow.vert.spv: build/generated/shaders/dynamic-shadow.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/world-sky.vert.spv: build/generated/shaders/world-sky.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/world-sky.frag.spv: build/generated/shaders/world-sky.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/wireframe.frag.spv: build/generated/shaders/wireframe.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/canvas.vert.spv: build/generated/shaders/canvas.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/canvas.frag.spv: build/generated/shaders/canvas.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/canvas-post.vert.spv: build/generated/shaders/canvas-post.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/canvas-post.frag.spv: build/generated/shaders/canvas-post.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/particles.vert.spv: build/generated/shaders/particles.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/particles.frag.spv: build/generated/shaders/particles.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/foliage.vert.spv: build/generated/shaders/foliage.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/bougainvillea.vert.spv: build/generated/shaders/bougainvillea.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/grass.vert.spv: build/generated/shaders/grass.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/foliage.frag.spv: build/generated/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/wireframe.vert.spv: build/generated/shaders/wireframe.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/world.vert.spv: build/generated/shaders/world.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/world-instance.vert.spv: build/generated/shaders/world-instance.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/world.frag.spv: build/generated/shaders/world.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/player-shadow.vert.spv: build/generated/shaders/player-shadow.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/player-shadow.frag.spv: build/generated/shaders/player-shadow.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/dynamic-shadow.vert.spv: build/generated/shaders/dynamic-shadow.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_APP): $(DEV_DIR)/shaders/dynamic-shadow.vert.spv
$(RELEASE_APP): $(RELEASE_DIR)/shaders/dynamic-shadow.vert.spv
$(DEV_APP): $(DEV_DIR)/shaders/world-instance.vert.spv
$(RELEASE_APP): $(RELEASE_DIR)/shaders/world-instance.vert.spv

$(RELEASE_DIR)/shaders/world-sky.vert.spv: build/generated/shaders/world-sky.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/world-sky.frag.spv: build/generated/shaders/world-sky.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/wireframe.frag.spv: build/generated/shaders/wireframe.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/canvas.vert.spv: build/generated/shaders/canvas.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/canvas.frag.spv: build/generated/shaders/canvas.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/canvas-post.vert.spv: build/generated/shaders/canvas-post.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/canvas-post.frag.spv: build/generated/shaders/canvas-post.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/particles.vert.spv: build/generated/shaders/particles.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/particles.frag.spv: build/generated/shaders/particles.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/foliage.vert.spv: build/generated/shaders/foliage.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/bougainvillea.vert.spv: build/generated/shaders/bougainvillea.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/grass.vert.spv: build/generated/shaders/grass.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/foliage.frag.spv: build/generated/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	cp $< $@

release: doctor assets-release $(RELEASE_APP)

$(PHYSICS_STAMP): $(PHYSICS_SOURCES)
	@mkdir -p $(@D)
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" physics-build
	touch $@

$(HOT_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(HOT_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(HOT_DIR)/gfx_signposts.o

$(HOT_SHADER_DIR)/world.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/world-instance.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry instance_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/world.frag.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/player-shadow.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry shadow_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/dynamic-shadow.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry dynamic_shadow_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/player-shadow.frag.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry shadow_fragment -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/world-sky.vert.spv: assets/shaders/sky.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry sky_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/world-sky.frag.spv: assets/shaders/sky.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry sky_fragment -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/wireframe.vert.spv: assets/shaders/wireframe.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/wireframe.frag.spv: assets/shaders/wireframe.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/canvas.vert.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/canvas.frag.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/canvas-post.vert.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry post_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/canvas-post.frag.spv: assets/shaders/canvas.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry post_fragment -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/particles.vert.spv: assets/shaders/particles.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/particles.frag.spv: assets/shaders/particles.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/foliage.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/bougainvillea.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry bougainvillea_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/grass.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry grass_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/foliage.frag.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_STAMP): $(HOT_SHADER_OUTPUTS)
	@mkdir -p $(@D)
	touch $@

$(HOT_APP): $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(CGLTF_LIB) $(HOT_ODIN_SOURCES) Makefile toolchain.mk $(HOT_DIR)/libgfx_signposts.a
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_hot) -build-mode:shared $(PROFILE_DEFINE_FLAGS_hot) -out:$@ -extra-linker-flags:"$(call link_flags,$(HOT_DIR))"

$(HOT_APP_STAMP): $(HOT_APP)
	@mkdir -p $(@D)
	touch $@

$(HOT_HOST): hot/main.odin Makefile toolchain.mk
	@mkdir -p $(@D)
	$(ODIN) build hot/main.odin -file $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_hot) -out:$@

hot-app: $(HOT_APP_STAMP)

hot-host: $(HOT_HOST)

hot-shaders: $(HOT_SHADER_STAMP)

hot-build: doctor $(PHYSICS_STAMP) assets-hot hot-app hot-shaders hot-host

hot: hot-build
	$(PROFILE_RUNTIME_ENV_hot) ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" $(PYTHON) tools/hot_watch.py --root "$(CURDIR)" --engine-root "$(ZELDA_ENGINE_ROOT)" --host "$(abspath $(HOT_HOST))" --make "$(MAKE)"

# Zelda Engine's UI package imports this native archive directly. Build it
# before every Adriatic link instead of relying on a sibling checkout having
# produced it already.
$(TEXTSHAPE_LIB): $(TEXTSHAPE_SOURCES)
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" textshape-build

textshape-build: doctor $(TEXTSHAPE_LIB)

ifeq ($(shell uname -s),Darwin)
$(CGLTF_LIB): $(CGLTF_SOURCE) $(CGLTF_HEADER) Makefile
	@mkdir -p "$(CGLTF_BUILD_DIR)" "$(@D)"
	$(CC) -arch x86_64 -O2 -fPIC -c "$(CGLTF_SOURCE)" -o "$(CGLTF_X86_OBJECT)"
	$(CC) -arch arm64 -O2 -fPIC -c "$(CGLTF_SOURCE)" -o "$(CGLTF_ARM_OBJECT)"
	lipo -create "$(CGLTF_X86_OBJECT)" "$(CGLTF_ARM_OBJECT)" -output "$@"
else
$(CGLTF_LIB): $(CGLTF_SOURCE) $(CGLTF_HEADER) Makefile
	@mkdir -p "$(CGLTF_BUILD_DIR)" "$(@D)"
	$(CC) -O2 -fPIC -c "$(CGLTF_SOURCE)" -o "$(CGLTF_OBJECT)"
	$(AR) rcs "$@" "$(CGLTF_OBJECT)"
endif

cgltf-build: doctor $(CGLTF_LIB)

profile-info:
	@case "$(PROFILE)" in \
		hot|debug|release|validation|instrument) \
			echo "Profile: $(PROFILE)"; \
			echo "Config: $(PROFILE_CONFIG_$(PROFILE))"; \
			echo "Entry: $(PROFILE_ENTRY_$(PROFILE))"; \
			echo "Link mode: $(PROFILE_LINK_MODE_$(PROFILE))"; \
			echo "Odin flags: $(PROFILE_ODIN_FLAGS_$(PROFILE))"; \
			echo "Vulkan validation: $(PROFILE_VULKAN_VALIDATION_$(PROFILE))"; \
			echo "ASAN: $(PROFILE_ASAN_$(PROFILE))"; \
			;; \
		*) echo "error: unknown PROFILE=$(PROFILE); expected hot, debug, release, validation, or instrument" >&2; exit 2 ;; \
	esac

profile:
	@case "$(PROFILE)" in \
		hot) $(MAKE) hot-build ;; \
		debug) $(MAKE) build ;; \
		release) $(MAKE) release ;; \
		validation) $(MAKE) validation-build ;; \
		instrument) $(MAKE) instrument-build ;; \
		*) echo "error: unknown PROFILE=$(PROFILE); expected hot, debug, release, validation, or instrument" >&2; exit 2 ;; \
	esac

dev: PROFILE=hot
dev: hot

debug: PROFILE=debug
debug: profile

# The Zelda Engine physics package is backed by its pinned Jolt checkout. Keep
# the native build in the engine repository, but provision it before producing
# an application binary so importing zelda_engine:physics needs no manual step.
physics-deps: doctor
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" physics-deps

physics-build: doctor $(PHYSICS_STAMP)

$(DEV_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(DEV_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(DEV_DIR)/gfx_signposts.o

$(DEV_DIR)/libadriatic_mesh.a: native/adriatic_xatlas.cpp third_party/xatlas/source/xatlas/xatlas.cpp third_party/xatlas/source/xatlas/xatlas.h third_party/xatlas/source/xatlas/xatlas_c.h third_party/meshoptimizer/src/meshoptimizer.h third_party/meshoptimizer/src/allocator.cpp third_party/meshoptimizer/src/indexgenerator.cpp third_party/meshoptimizer/src/vcacheoptimizer.cpp third_party/meshoptimizer/src/vfetchoptimizer.cpp Makefile
	@mkdir -p $(@D)
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -Ithird_party/meshoptimizer/src -c native/adriatic_xatlas.cpp -o $(DEV_DIR)/adriatic_mesh_bridge.o
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -c third_party/xatlas/source/xatlas/xatlas.cpp -o $(DEV_DIR)/xatlas.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/allocator.cpp -o $(DEV_DIR)/meshopt_allocator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/indexgenerator.cpp -o $(DEV_DIR)/meshopt_indexgenerator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vcacheoptimizer.cpp -o $(DEV_DIR)/meshopt_vcacheoptimizer.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vfetchoptimizer.cpp -o $(DEV_DIR)/meshopt_vfetchoptimizer.o
	$(AR) rcs $@ $(DEV_DIR)/adriatic_mesh_bridge.o $(DEV_DIR)/xatlas.o $(DEV_DIR)/meshopt_allocator.o $(DEV_DIR)/meshopt_indexgenerator.o $(DEV_DIR)/meshopt_vcacheoptimizer.o $(DEV_DIR)/meshopt_vfetchoptimizer.o

$(HOT_DIR)/libadriatic_mesh.a: native/adriatic_xatlas.cpp third_party/xatlas/source/xatlas/xatlas.cpp third_party/xatlas/source/xatlas/xatlas.h third_party/xatlas/source/xatlas/xatlas_c.h third_party/meshoptimizer/src/meshoptimizer.h third_party/meshoptimizer/src/allocator.cpp third_party/meshoptimizer/src/indexgenerator.cpp third_party/meshoptimizer/src/vcacheoptimizer.cpp third_party/meshoptimizer/src/vfetchoptimizer.cpp Makefile
	@mkdir -p $(@D)
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -Ithird_party/meshoptimizer/src -c native/adriatic_xatlas.cpp -o $(HOT_DIR)/adriatic_mesh_bridge.o
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -c third_party/xatlas/source/xatlas/xatlas.cpp -o $(HOT_DIR)/xatlas.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/allocator.cpp -o $(HOT_DIR)/meshopt_allocator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/indexgenerator.cpp -o $(HOT_DIR)/meshopt_indexgenerator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vcacheoptimizer.cpp -o $(HOT_DIR)/meshopt_vcacheoptimizer.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vfetchoptimizer.cpp -o $(HOT_DIR)/meshopt_vfetchoptimizer.o
	$(AR) rcs $@ $(HOT_DIR)/adriatic_mesh_bridge.o $(HOT_DIR)/xatlas.o $(HOT_DIR)/meshopt_allocator.o $(HOT_DIR)/meshopt_indexgenerator.o $(HOT_DIR)/meshopt_vcacheoptimizer.o $(HOT_DIR)/meshopt_vfetchoptimizer.o

$(RELEASE_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(RELEASE_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(RELEASE_DIR)/gfx_signposts.o

$(RELEASE_DIR)/libadriatic_mesh.a: native/adriatic_xatlas.cpp third_party/xatlas/source/xatlas/xatlas.cpp third_party/xatlas/source/xatlas/xatlas.h third_party/xatlas/source/xatlas/xatlas_c.h third_party/meshoptimizer/src/meshoptimizer.h third_party/meshoptimizer/src/allocator.cpp third_party/meshoptimizer/src/indexgenerator.cpp third_party/meshoptimizer/src/vcacheoptimizer.cpp third_party/meshoptimizer/src/vfetchoptimizer.cpp Makefile
	@mkdir -p $(@D)
	$(CXX) -std=c++11 -O3 -Ithird_party/xatlas/source/xatlas -Ithird_party/meshoptimizer/src -c native/adriatic_xatlas.cpp -o $(RELEASE_DIR)/adriatic_mesh_bridge.o
	$(CXX) -std=c++11 -O3 -Ithird_party/xatlas/source/xatlas -c third_party/xatlas/source/xatlas/xatlas.cpp -o $(RELEASE_DIR)/xatlas.o
	$(CXX) -std=c++11 -O3 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/allocator.cpp -o $(RELEASE_DIR)/meshopt_allocator.o
	$(CXX) -std=c++11 -O3 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/indexgenerator.cpp -o $(RELEASE_DIR)/meshopt_indexgenerator.o
	$(CXX) -std=c++11 -O3 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vcacheoptimizer.cpp -o $(RELEASE_DIR)/meshopt_vcacheoptimizer.o
	$(CXX) -std=c++11 -O3 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vfetchoptimizer.cpp -o $(RELEASE_DIR)/meshopt_vfetchoptimizer.o
	$(AR) rcs $@ $(RELEASE_DIR)/adriatic_mesh_bridge.o $(RELEASE_DIR)/xatlas.o $(RELEASE_DIR)/meshopt_allocator.o $(RELEASE_DIR)/meshopt_indexgenerator.o $(RELEASE_DIR)/meshopt_vcacheoptimizer.o $(RELEASE_DIR)/meshopt_vfetchoptimizer.o

$(INSTRUMENT_DIR)/libadriatic_mesh.a: native/adriatic_xatlas.cpp third_party/xatlas/source/xatlas/xatlas.cpp third_party/xatlas/source/xatlas/xatlas.h third_party/xatlas/source/xatlas/xatlas_c.h third_party/meshoptimizer/src/meshoptimizer.h third_party/meshoptimizer/src/allocator.cpp third_party/meshoptimizer/src/indexgenerator.cpp third_party/meshoptimizer/src/vcacheoptimizer.cpp third_party/meshoptimizer/src/vfetchoptimizer.cpp Makefile
	@mkdir -p $(@D)
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -Ithird_party/meshoptimizer/src -c native/adriatic_xatlas.cpp -o $(INSTRUMENT_DIR)/adriatic_mesh_bridge.o
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -c third_party/xatlas/source/xatlas/xatlas.cpp -o $(INSTRUMENT_DIR)/xatlas.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/allocator.cpp -o $(INSTRUMENT_DIR)/meshopt_allocator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/indexgenerator.cpp -o $(INSTRUMENT_DIR)/meshopt_indexgenerator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vcacheoptimizer.cpp -o $(INSTRUMENT_DIR)/meshopt_vcacheoptimizer.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vfetchoptimizer.cpp -o $(INSTRUMENT_DIR)/meshopt_vfetchoptimizer.o
	$(AR) rcs $@ $(INSTRUMENT_DIR)/adriatic_mesh_bridge.o $(INSTRUMENT_DIR)/xatlas.o $(INSTRUMENT_DIR)/meshopt_allocator.o $(INSTRUMENT_DIR)/meshopt_indexgenerator.o $(INSTRUMENT_DIR)/meshopt_vcacheoptimizer.o $(INSTRUMENT_DIR)/meshopt_vfetchoptimizer.o

$(HOT_APP): $(HOT_DIR)/libadriatic_mesh.a
$(DEV_APP): $(DEV_DIR)/libadriatic_mesh.a
$(RELEASE_APP): $(RELEASE_DIR)/libadriatic_mesh.a

$(VALIDATION_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(VALIDATION_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(VALIDATION_DIR)/gfx_signposts.o

$(VALIDATION_DIR)/libadriatic_mesh.a: native/adriatic_xatlas.cpp third_party/xatlas/source/xatlas/xatlas.cpp third_party/xatlas/source/xatlas/xatlas.h third_party/xatlas/source/xatlas/xatlas_c.h third_party/meshoptimizer/src/meshoptimizer.h third_party/meshoptimizer/src/allocator.cpp third_party/meshoptimizer/src/indexgenerator.cpp third_party/meshoptimizer/src/vcacheoptimizer.cpp third_party/meshoptimizer/src/vfetchoptimizer.cpp Makefile
	@mkdir -p $(@D)
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -Ithird_party/meshoptimizer/src -c native/adriatic_xatlas.cpp -o $(VALIDATION_DIR)/adriatic_mesh_bridge.o
	$(CXX) -std=c++11 -O2 -Ithird_party/xatlas/source/xatlas -c third_party/xatlas/source/xatlas/xatlas.cpp -o $(VALIDATION_DIR)/xatlas.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/allocator.cpp -o $(VALIDATION_DIR)/meshopt_allocator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/indexgenerator.cpp -o $(VALIDATION_DIR)/meshopt_indexgenerator.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vcacheoptimizer.cpp -o $(VALIDATION_DIR)/meshopt_vcacheoptimizer.o
	$(CXX) -std=c++11 -O2 -Ithird_party/meshoptimizer/src -c third_party/meshoptimizer/src/vfetchoptimizer.cpp -o $(VALIDATION_DIR)/meshopt_vfetchoptimizer.o
	$(AR) rcs $@ $(VALIDATION_DIR)/adriatic_mesh_bridge.o $(VALIDATION_DIR)/xatlas.o $(VALIDATION_DIR)/meshopt_allocator.o $(VALIDATION_DIR)/meshopt_indexgenerator.o $(VALIDATION_DIR)/meshopt_vcacheoptimizer.o $(VALIDATION_DIR)/meshopt_vfetchoptimizer.o

$(INSTRUMENT_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(INSTRUMENT_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(INSTRUMENT_DIR)/gfx_signposts.o

$(DEV_APP): $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(CGLTF_LIB) $(ODIN_SOURCES) Makefile toolchain.mk $(DEV_DIR)/libgfx_signposts.a $(DEV_DIR)/shaders/world.vert.spv $(DEV_DIR)/shaders/world.frag.spv $(DEV_DIR)/shaders/player-shadow.vert.spv $(DEV_DIR)/shaders/player-shadow.frag.spv $(DEV_DIR)/shaders/world-sky.vert.spv $(DEV_DIR)/shaders/world-sky.frag.spv $(DEV_DIR)/shaders/wireframe.vert.spv $(DEV_DIR)/shaders/wireframe.frag.spv $(DEV_DIR)/shaders/canvas.vert.spv $(DEV_DIR)/shaders/canvas.frag.spv $(DEV_DIR)/shaders/canvas-post.vert.spv $(DEV_DIR)/shaders/canvas-post.frag.spv $(DEV_DIR)/shaders/particles.vert.spv $(DEV_DIR)/shaders/particles.frag.spv $(DEV_DIR)/shaders/foliage.vert.spv $(DEV_DIR)/shaders/bougainvillea.vert.spv $(DEV_DIR)/shaders/grass.vert.spv $(DEV_DIR)/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_debug) $(PROFILE_DEFINE_FLAGS_debug) -out:$@ -extra-linker-flags:"$(call link_flags,$(DEV_DIR))"

$(RELEASE_APP): $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(CGLTF_LIB) $(ODIN_SOURCES) Makefile toolchain.mk $(RELEASE_DIR)/libgfx_signposts.a $(RELEASE_DIR)/shaders/world.vert.spv $(RELEASE_DIR)/shaders/world.frag.spv $(RELEASE_DIR)/shaders/player-shadow.vert.spv $(RELEASE_DIR)/shaders/player-shadow.frag.spv $(RELEASE_DIR)/shaders/world-sky.vert.spv $(RELEASE_DIR)/shaders/world-sky.frag.spv $(RELEASE_DIR)/shaders/wireframe.vert.spv $(RELEASE_DIR)/shaders/wireframe.frag.spv $(RELEASE_DIR)/shaders/canvas.vert.spv $(RELEASE_DIR)/shaders/canvas.frag.spv $(RELEASE_DIR)/shaders/canvas-post.vert.spv $(RELEASE_DIR)/shaders/canvas-post.frag.spv $(RELEASE_DIR)/shaders/particles.vert.spv $(RELEASE_DIR)/shaders/particles.frag.spv $(RELEASE_DIR)/shaders/foliage.vert.spv $(RELEASE_DIR)/shaders/bougainvillea.vert.spv $(RELEASE_DIR)/shaders/grass.vert.spv $(RELEASE_DIR)/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_release) $(PROFILE_DEFINE_FLAGS_release) -out:$@ -extra-linker-flags:"$(call link_flags,$(RELEASE_DIR))"

$(VALIDATION_APP): $(PHYSICS_STAMP) $(CGLTF_LIB) $(HOT_ODIN_SOURCES) Makefile toolchain.mk $(VALIDATION_DIR)/libgfx_signposts.a $(VALIDATION_DIR)/libadriatic_mesh.a
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_validation) $(PROFILE_DEFINE_FLAGS_validation) -out:$@ -extra-linker-flags:"$(call link_flags,$(VALIDATION_DIR))"

validation-build: doctor assets-validation $(VALIDATION_APP)

validation: validation-build
	$(PROFILE_RUNTIME_ENV_validation) ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" "$(VALIDATION_APP)"

lldb: validation-build assets-validation
	$(PROFILE_RUNTIME_ENV_validation) ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" lldb -- "$(VALIDATION_APP)"


$(INSTRUMENT_APP): $(INSTRUMENT_DIR)/libadriatic_mesh.a
$(INSTRUMENT_APP): $(PHYSICS_STAMP) $(CGLTF_LIB) $(HOT_ODIN_SOURCES) Makefile toolchain.mk $(INSTRUMENT_DIR)/libgfx_signposts.a
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_instrument) $(PROFILE_DEFINE_FLAGS_instrument) -out:$@ -extra-linker-flags:"$(call link_flags,$(INSTRUMENT_DIR))"

instrument-build: doctor $(INSTRUMENT_APP)

$(INSTRUMENT_RUNTIME_STAMP): shaders $(INSTRUMENT_ASSET_SOURCES)
	@mkdir -p "$(INSTRUMENT_DIR)/assets" "$(INSTRUMENT_DIR)/shaders"
	cp -R assets/. "$(INSTRUMENT_DIR)/assets/"
	cp -R build/generated/shaders/. "$(INSTRUMENT_DIR)/shaders/"
	touch $@

instrument: instrument-build $(INSTRUMENT_RUNTIME_STAMP)
	$(PROFILE_RUNTIME_ENV_instrument) "$(INSTRUMENT_APP)" --instrument-seconds "$(INSTRUMENT_SECONDS)"

INSTRUMENT_SECONDS ?= 0
INSTRUMENT_DEEP_DIR := $(BUILD_DIR)/instrument-deep
INSTRUMENT_DEEP_APP := $(INSTRUMENT_DEEP_DIR)/$(APP)

instrument-deep: instrument-build $(INSTRUMENT_RUNTIME_STAMP)
	@mkdir -p "$(INSTRUMENT_DEEP_DIR)/assets" "$(INSTRUMENT_DEEP_DIR)/shaders"
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) $(PROFILE_ODIN_FLAGS_instrument) $(PROFILE_DEFINE_FLAGS_instrument_deep) -out:$(INSTRUMENT_DEEP_APP) -extra-linker-flags:"$(call link_flags,$(INSTRUMENT_DIR))"
	cp -R assets/. "$(INSTRUMENT_DEEP_DIR)/assets/"
	cp -R build/generated/shaders/. "$(INSTRUMENT_DEEP_DIR)/shaders/"
	$(PROFILE_RUNTIME_ENV_instrument) "$(INSTRUMENT_DEEP_APP)" --instrument-seconds "$(INSTRUMENT_SECONDS)"

run: build
	$(PROFILE_RUNTIME_ENV_debug) ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" "$(DEV_APP)"

benchmark: release
	$(PROFILE_RUNTIME_ENV_release) $(PYTHON) tools/perf.py run --scenario all --output "$(abspath $(BUILD_DIR)/perf/latest.json)"

capture-live:
	$(PYTHON) tools/live_capture.py --path "$(LIVE_CAPTURE_PATH)" --request "$(LIVE_CAPTURE_REQUEST_PATH)" --timeout "$(LIVE_CAPTURE_TIMEOUT)"

mcp:
	$(PYTHON) tools/adriatic_mcp.py

fixture-schema-generate: doctor
	$(ODIN) run tools/fixture_schema $(ZELDA_ENGINE_COLLECTION) -- generate "$(CURDIR)" "$(ZELDA_ENGINE_PACKAGES)"

fixture-schema-check: doctor
	$(ODIN) run tools/fixture_schema $(ZELDA_ENGINE_COLLECTION) -- check "$(CURDIR)" "$(ZELDA_ENGINE_PACKAGES)"

fixture-migration-scaffold: doctor
	$(ODIN) run tools/fixture_schema $(ZELDA_ENGINE_COLLECTION) -- migration-scaffold $(FIXTURE_MIGRATION_FROM_VERSION) $(FIXTURE_MIGRATION_TO_VERSION) "$(CURDIR)" "$(ZELDA_ENGINE_PACKAGES)"

fixture-migration-scaffold-check: doctor
	$(ODIN) run tools/fixture_schema $(ZELDA_ENGINE_COLLECTION) -- migration-scaffold-check $(FIXTURE_MIGRATION_FROM_VERSION) $(FIXTURE_MIGRATION_TO_VERSION) "$(CURDIR)" "$(ZELDA_ENGINE_PACKAGES)"

fixture-history-generate: doctor
	$(ODIN) run tools/fixture_schema $(ZELDA_ENGINE_COLLECTION) -- history-generate $(FIXTURE_HISTORY_VERSION) "$(CURDIR)"

fixture-history-check: doctor
	$(ODIN) run tools/fixture_schema $(ZELDA_ENGINE_COLLECTION) -- history-check $(FIXTURE_HISTORY_VERSION) "$(CURDIR)"
	$(ODIN) check $(FIXTURE_HISTORY_PACKAGE) $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point

fmt:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required" >&2; exit 1; }
	@# odinfmt cannot parse the fork-only #scope_exit syntax in this file yet.
	find hot src packages tests -type f -name '*.odin' ! -path 'packages/spy/span.odin' \
		-exec sh -c 'for file do "$$0" -w "$$file" || exit 1; done' "$(ODINFMT)" {} +

check: doctor
	$(ODIN) check src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS)
	$(ODIN) check packages/flight $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/third_person $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/wireframe $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/vehicles $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/machines $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/quest $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/terrain $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/postale $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/libellula $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/air_compare $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/air_style $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/atmosphere $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point
	$(ODIN) check packages/cinematic $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -no-entry-point

test-rondine: doctor
	$(ODIN) test packages/rondine $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS)

test-src: $(DEV_APP)
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -extra-linker-flags:"$(call link_flags,$(DEV_DIR))"

test: doctor $(DEV_DIR)/libadriatic_mesh.a test-rondine test-src
	$(ODIN) test tests $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -extra-linker-flags:"-L$(abspath $(DEV_DIR)) -lc++"

fixture-codec-test: doctor $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(DEV_DIR)/libadriatic_mesh.a $(DEV_DIR)/libgfx_signposts.a
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -define:ODIN_TEST_NAMES=main.fixture_codec_real_fixture_round_trip_and_failures,main.fixture_codec_owned_decode_allocation_failures_and_preflight -extra-linker-flags:"$(TEXTSHAPE_LIBS) -L$(abspath $(DEV_DIR)) -lgfx_signposts -lc++"

fixture-editor-load-test: doctor $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(DEV_DIR)/libadriatic_mesh.a $(DEV_DIR)/libgfx_signposts.a
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=main.fixture_editor_load_current_rebuilds_runtime_and_releases_replaced_state,main.fixture_editor_load_golden_v1_migrates_and_binds_destination,main.fixture_editor_load_failures_are_atomic_and_release_every_allocation -extra-linker-flags:"$(TEXTSHAPE_LIBS) -L$(abspath $(DEV_DIR)) -lgfx_signposts -lc++"

fixture-editor-store-test: doctor $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(DEV_DIR)/libadriatic_mesh.a $(DEV_DIR)/libgfx_signposts.a
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=main.fixture_editor_file_round_trip_restores_playground_and_preserves_root_state,main.fixture_editor_file_save_is_current_deterministic_and_load_reuses_migrations,main.fixture_editor_file_failures_are_atomic_and_clean -extra-linker-flags:"$(TEXTSHAPE_LIBS) -L$(abspath $(DEV_DIR)) -lgfx_signposts -lc++"

fixture-upgrade-test: doctor $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(DEV_DIR)/libadriatic_mesh.a $(DEV_DIR)/libgfx_signposts.a
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=main.fixture_upgrade_file_dry_run_current_and_historical_are_deterministic,main.fixture_upgrade_directory_is_recursive_sorted_and_ignores_other_files,main.fixture_upgrade_failures_preserve_targets_and_release_ownership -extra-linker-flags:"$(TEXTSHAPE_LIBS) -L$(abspath $(DEV_DIR)) -lgfx_signposts -lc++"

fixture-lifecycle-test: doctor $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(DEV_DIR)/libadriatic_mesh.a $(DEV_DIR)/libgfx_signposts.a
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -define:ODIN_TEST_THREADS=1 -define:ODIN_TEST_NAMES=main.fixture_lifecycle_detach_derives_all_identities_without_allocation,main.fixture_lifecycle_prepare_and_bind_use_destination_owned_addresses,main.fixture_lifecycle_hostile_states_fail_atomically,main.fixture_lifecycle_hot_state_round_trips_all_identities -extra-linker-flags:"$(TEXTSHAPE_LIBS) -L$(abspath $(DEV_DIR)) -lgfx_signposts -lc++"

fixture-migration-test: doctor $(PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(DEV_DIR)/libadriatic_mesh.a $(DEV_DIR)/libgfx_signposts.a
	$(ODIN) test src $(ZELDA_ENGINE_COLLECTION) $(ODIN_VET_FLAGS) -define:ODIN_TEST_NAMES=main.fixture_migration_transaction_paths_and_ownership,main.fixture_migration_rejects_invalid_registries_before_decode,main.fixture_migration_caller_allocation_failures_dispose_everything,main.fixture_migration_structural_migration_and_boundaries,main.fixture_migration_story_golden_matrix_and_failures,main.fixture_migration_v0002_to_v0003_direct_chained_and_failures,main.fixture_migration_v0003_to_v0004_runtime_direct_and_chains,main.fixture_migration_v0003_to_v0004_runtime_hostile_and_atomic,main.fixture_migration_v0003_to_v0004_runtime_allocation_failures,main.fixture_migration_v0004_to_v0005_structural_success_and_resolutions,main.fixture_migration_v0004_to_v0005_structural_basis_boundaries_and_hostile_sources,main.fixture_migration_v0004_to_v0005_structural_zero_rondine_and_nil,main.fixture_migration_v0004_to_v0005_runtime_direct_and_complete_chains,main.fixture_migration_v0004_to_v0005_runtime_hostile_contexts_and_payloads,main.fixture_migration_v0004_to_v0005_runtime_allocation_failures -extra-linker-flags:"$(TEXTSHAPE_LIBS) -L$(abspath $(DEV_DIR)) -lgfx_signposts -lc++"

clean:
	rm -rf "$(BUILD_DIR)"
