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

PROFILE_ODIN_FLAGS_debug := -dynamic-map-calls -o:speed -debug
PROFILE_DEFINE_FLAGS_debug :=
PROFILE_CONFIG_debug := debug
PROFILE_ENTRY_debug := cold
PROFILE_LINK_MODE_debug := system
PROFILE_VULKAN_VALIDATION_debug := false
PROFILE_ASAN_debug := false

PROFILE_ODIN_FLAGS_release := -dynamic-map-calls -o:minimal -debug
PROFILE_DEFINE_FLAGS_release :=
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

VALIDATION_PROFILE_RUNTIME_ENV := env \
	VK_INSTANCE_LAYERS=VK_LAYER_KHRONOS_validation \
	ASAN_OPTIONS=halt_on_error=1:abort_on_error=1

ZELDA_ENGINE_ROOT ?= $(CURDIR)/zelda-engine
ZELDA_ENGINE_PACKAGES := $(abspath $(ZELDA_ENGINE_ROOT))/packages
ZELDA_ENGINE_COLLECTION := -collection:zelda_engine=$(ZELDA_ENGINE_PACKAGES)
TEXTSHAPE_DIR := $(abspath $(ZELDA_ENGINE_ROOT))/third_party/textshape
TEXTSHAPE_LIB := $(TEXTSHAPE_DIR)/libtextshape.a

LOCAL_ODIN := $(TOOLS_DIR)/odin/$(ODIN_FORK_VERSION)/odin
LOCAL_SLANGC := $(TOOLS_DIR)/slang/$(SLANG_VERSION)/slangc
PATH_ODIN := $(shell command -v odin 2>/dev/null)
PATH_SLANGC := $(shell command -v slangc 2>/dev/null)
ODIN ?= $(if $(wildcard $(LOCAL_ODIN)),$(LOCAL_ODIN),$(PATH_ODIN))
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
DEV_APP := $(DEV_DIR)/$(APP)
RELEASE_APP := $(RELEASE_DIR)/$(APP)
VALIDATION_APP := $(VALIDATION_DIR)/$(APP)
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
HOT_PHYSICS_STAMP := $(HOT_DIR)/physics.stamp
HOT_APP_STAMP := $(HOT_DIR)/app.stamp
HOT_SHADER_STAMP := $(HOT_DIR)/shader.stamp
LIVE_CAPTURE_PATH ?= $(abspath $(BUILD_DIR)/captures/$(APP)-live.png)
LIVE_CAPTURE_TIMEOUT ?= 30
LIVE_CAPTURE_REQUEST_PATH := $(abspath $(BUILD_DIR)/live-capture.request)
ODIN_SOURCES := $(shell find src packages tests -type f -name '*.odin' 2>/dev/null)
HOT_ODIN_SOURCES := $(shell find src packages "$(ZELDA_ENGINE_PACKAGES)" -type f -name '*.odin' 2>/dev/null)
HOT_SHADER_OUTPUTS := \
	$(HOT_SHADER_DIR)/world.vert.spv \
	$(HOT_SHADER_DIR)/world.frag.spv \
	$(HOT_SHADER_DIR)/player-shadow.vert.spv \
	$(HOT_SHADER_DIR)/player-shadow.frag.spv \
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
	$(HOT_SHADER_DIR)/grass.vert.spv \
	$(HOT_SHADER_DIR)/foliage.frag.spv

.PHONY: all bootstrap bootstrap-fork doctor textshape-build physics-deps physics-build shaders assets-dev assets-release assets-hot assets-validation build release validation validation-build lldb profile profile-info dev debug hot hot-build hot-app hot-host hot-shaders run benchmark capture-live fmt check test clean

all: build

bootstrap:
	./tools/bootstrap-macos.sh
	./tools/bootstrap-odin-fork-macos.sh

bootstrap-fork:
	./tools/bootstrap-odin-fork-macos.sh

doctor:
	@set -eu; \
	if [ ! -d "$(ZELDA_ENGINE_PACKAGES)" ]; then \
		echo "error: Zelda Engine packages not found at $(ZELDA_ENGINE_PACKAGES)" >&2; exit 1; \
	fi; \
	if [ ! -x "$(ODIN)" ] && ! command -v "$(ODIN)" >/dev/null 2>&1; then \
		echo "error: Odin is missing; run make bootstrap or set ODIN=/path/to/odin" >&2; exit 1; \
	fi; \
	actual="$$($(ODIN) version 2>/dev/null || true)"; \
	echo "Zelda Engine: $$(git -C "$(ZELDA_ENGINE_ROOT)" rev-parse --short HEAD 2>/dev/null || echo unversioned)"; \
	echo "Toolchain: $$actual"

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

shaders: build/generated/shaders/world.vert.spv build/generated/shaders/world.frag.spv build/generated/shaders/player-shadow.vert.spv build/generated/shaders/player-shadow.frag.spv build/generated/shaders/world-sky.vert.spv build/generated/shaders/world-sky.frag.spv build/generated/shaders/wireframe.vert.spv build/generated/shaders/wireframe.frag.spv build/generated/shaders/canvas.vert.spv build/generated/shaders/canvas.frag.spv build/generated/shaders/canvas-post.vert.spv build/generated/shaders/canvas-post.frag.spv build/generated/shaders/particles.vert.spv build/generated/shaders/particles.frag.spv build/generated/shaders/foliage.vert.spv build/generated/shaders/grass.vert.spv build/generated/shaders/foliage.frag.spv

build/generated/shaders/foliage.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

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

build/generated/shaders/world.frag.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

build/generated/shaders/player-shadow.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry shadow_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

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

$(DEV_DIR)/shaders/world.frag.spv: build/generated/shaders/world.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/player-shadow.vert.spv: build/generated/shaders/player-shadow.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/shaders/player-shadow.frag.spv: build/generated/shaders/player-shadow.frag.spv
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

$(RELEASE_DIR)/shaders/world.frag.spv: build/generated/shaders/world.frag.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/player-shadow.vert.spv: build/generated/shaders/player-shadow.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/player-shadow.frag.spv: build/generated/shaders/player-shadow.frag.spv
	@mkdir -p $(@D)
	cp $< $@

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

$(RELEASE_DIR)/shaders/grass.vert.spv: build/generated/shaders/grass.vert.spv
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/shaders/foliage.frag.spv: build/generated/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	cp $< $@

release: doctor assets-release $(RELEASE_APP)

$(HOT_PHYSICS_STAMP): Makefile
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

$(HOT_SHADER_DIR)/world.frag.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/player-shadow.vert.spv: assets/shaders/world.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry shadow_vertex -stage vertex -target spirv -profile spirv_1_5 -o $@

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

$(HOT_SHADER_DIR)/grass.vert.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry grass_vertex_main -stage vertex -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_DIR)/foliage.frag.spv: assets/shaders/foliage.slang
	@mkdir -p $(@D)
	$(SLANGC) $< -entry fragment_main -stage fragment -target spirv -profile spirv_1_5 -o $@

$(HOT_SHADER_STAMP): $(HOT_SHADER_OUTPUTS)
	@mkdir -p $(@D)
	touch $@

$(HOT_APP): $(HOT_PHYSICS_STAMP) $(TEXTSHAPE_LIB) $(HOT_ODIN_SOURCES) Makefile toolchain.mk $(HOT_DIR)/libgfx_signposts.a
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(PROFILE_ODIN_FLAGS_hot) -build-mode:shared $(PROFILE_DEFINE_FLAGS_hot) -out:$@ -extra-linker-flags:"$(call link_flags,$(HOT_DIR))"

$(HOT_APP_STAMP): $(HOT_APP)
	@mkdir -p $(@D)
	touch $@

$(HOT_HOST): hot/main.odin Makefile toolchain.mk
	@mkdir -p $(@D)
	$(ODIN) build hot/main.odin -file $(PROFILE_ODIN_FLAGS_hot) -out:$@

hot-app: $(HOT_APP_STAMP)

hot-host: $(HOT_HOST)

hot-shaders: $(HOT_SHADER_STAMP)

hot-build: doctor $(HOT_PHYSICS_STAMP) assets-hot hot-app hot-shaders hot-host

hot: hot-build
	ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" $(PYTHON) tools/hot_watch.py --root "$(CURDIR)" --engine-root "$(ZELDA_ENGINE_ROOT)" --host "$(abspath $(HOT_HOST))" --make "$(MAKE)"

# Zelda Engine's UI package imports this native archive directly. Build it
# before every Adriatic link instead of relying on a sibling checkout having
# produced it already.
$(TEXTSHAPE_LIB): $(TEXTSHAPE_DIR)/textshape.c
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" textshape-build

textshape-build: doctor $(TEXTSHAPE_LIB)

profile-info:
	@case "$(PROFILE)" in \
		hot|debug|release|validation) \
			echo "Profile: $(PROFILE)"; \
			echo "Config: $(PROFILE_CONFIG_$(PROFILE))"; \
			echo "Entry: $(PROFILE_ENTRY_$(PROFILE))"; \
			echo "Link mode: $(PROFILE_LINK_MODE_$(PROFILE))"; \
			echo "Odin flags: $(PROFILE_ODIN_FLAGS_$(PROFILE))"; \
			echo "Vulkan validation: $(PROFILE_VULKAN_VALIDATION_$(PROFILE))"; \
			echo "ASAN: $(PROFILE_ASAN_$(PROFILE))"; \
			;; \
		*) echo "error: unknown PROFILE=$(PROFILE); expected hot, debug, release, or validation" >&2; exit 2 ;; \
	esac

profile:
	@case "$(PROFILE)" in \
		hot) $(MAKE) hot-build ;; \
		debug) $(MAKE) build ;; \
		release) $(MAKE) release ;; \
		validation) $(MAKE) validation-build ;; \
		*) echo "error: unknown PROFILE=$(PROFILE); expected hot, debug, release, or validation" >&2; exit 2 ;; \
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

physics-build: doctor
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" physics-build

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

$(HOT_APP): $(HOT_DIR)/libadriatic_mesh.a
$(DEV_APP): $(DEV_DIR)/libadriatic_mesh.a
$(RELEASE_APP): $(RELEASE_DIR)/libadriatic_mesh.a

$(VALIDATION_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(VALIDATION_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(VALIDATION_DIR)/gfx_signposts.o

$(DEV_APP): physics-build $(TEXTSHAPE_LIB) $(ODIN_SOURCES) Makefile toolchain.mk $(DEV_DIR)/libgfx_signposts.a $(DEV_DIR)/shaders/world.vert.spv $(DEV_DIR)/shaders/world.frag.spv $(DEV_DIR)/shaders/player-shadow.vert.spv $(DEV_DIR)/shaders/player-shadow.frag.spv $(DEV_DIR)/shaders/world-sky.vert.spv $(DEV_DIR)/shaders/world-sky.frag.spv $(DEV_DIR)/shaders/wireframe.vert.spv $(DEV_DIR)/shaders/wireframe.frag.spv $(DEV_DIR)/shaders/canvas.vert.spv $(DEV_DIR)/shaders/canvas.frag.spv $(DEV_DIR)/shaders/canvas-post.vert.spv $(DEV_DIR)/shaders/canvas-post.frag.spv $(DEV_DIR)/shaders/particles.vert.spv $(DEV_DIR)/shaders/particles.frag.spv $(DEV_DIR)/shaders/foliage.vert.spv $(DEV_DIR)/shaders/grass.vert.spv $(DEV_DIR)/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(PROFILE_ODIN_FLAGS_debug) $(PROFILE_DEFINE_FLAGS_debug) -out:$@ -extra-linker-flags:"$(call link_flags,$(DEV_DIR))"

$(RELEASE_APP): physics-build $(TEXTSHAPE_LIB) $(ODIN_SOURCES) Makefile toolchain.mk $(RELEASE_DIR)/libgfx_signposts.a $(RELEASE_DIR)/shaders/world.vert.spv $(RELEASE_DIR)/shaders/world.frag.spv $(RELEASE_DIR)/shaders/player-shadow.vert.spv $(RELEASE_DIR)/shaders/player-shadow.frag.spv $(RELEASE_DIR)/shaders/world-sky.vert.spv $(RELEASE_DIR)/shaders/world-sky.frag.spv $(RELEASE_DIR)/shaders/wireframe.vert.spv $(RELEASE_DIR)/shaders/wireframe.frag.spv $(RELEASE_DIR)/shaders/canvas.vert.spv $(RELEASE_DIR)/shaders/canvas.frag.spv $(RELEASE_DIR)/shaders/canvas-post.vert.spv $(RELEASE_DIR)/shaders/canvas-post.frag.spv $(RELEASE_DIR)/shaders/particles.vert.spv $(RELEASE_DIR)/shaders/particles.frag.spv $(RELEASE_DIR)/shaders/foliage.vert.spv $(RELEASE_DIR)/shaders/grass.vert.spv $(RELEASE_DIR)/shaders/foliage.frag.spv
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(PROFILE_ODIN_FLAGS_release) $(PROFILE_DEFINE_FLAGS_release) -out:$@ -extra-linker-flags:"$(call link_flags,$(RELEASE_DIR))"

$(VALIDATION_APP): physics-build $(HOT_ODIN_SOURCES) Makefile toolchain.mk $(VALIDATION_DIR)/libgfx_signposts.a
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) $(PROFILE_ODIN_FLAGS_validation) $(PROFILE_DEFINE_FLAGS_validation) -out:$@ -extra-linker-flags:"$(call link_flags,$(VALIDATION_DIR))"

validation-build: doctor $(VALIDATION_APP)

validation: validation-build
	$(VALIDATION_PROFILE_RUNTIME_ENV) ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" "$(VALIDATION_APP)"

lldb: validation-build assets-validation
	$(VALIDATION_PROFILE_RUNTIME_ENV) ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" lldb -- "$(VALIDATION_APP)"

run: build
	ADRIATIC_LIVE_CAPTURE_REQUEST="$(LIVE_CAPTURE_REQUEST_PATH)" $(DEV_APP)

benchmark: release
	$(PYTHON) tools/perf.py run --scenario all --output "$(abspath $(BUILD_DIR)/perf/latest.json)"

capture-live:
	$(PYTHON) tools/live_capture.py --path "$(LIVE_CAPTURE_PATH)" --request "$(LIVE_CAPTURE_REQUEST_PATH)" --timeout "$(LIVE_CAPTURE_TIMEOUT)"

fmt:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required" >&2; exit 1; }
	@# odinfmt cannot parse the fork-only #scope_exit syntax in this file yet.
	find hot src packages tests -type f -name '*.odin' ! -path 'packages/spy/span.odin' \
		-exec sh -c 'for file do "$$0" -w "$$file" || exit 1; done' "$(ODINFMT)" {} +

check: doctor
	$(ODIN) check src $(ZELDA_ENGINE_COLLECTION)
	$(ODIN) check packages/flight $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/third_person $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/wireframe $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/vehicles $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/machines $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/terrain $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/postale $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/libellula $(ZELDA_ENGINE_COLLECTION) -no-entry-point
	$(ODIN) check packages/atmosphere $(ZELDA_ENGINE_COLLECTION) -no-entry-point

test: doctor $(DEV_DIR)/libadriatic_mesh.a
	$(ODIN) test tests $(ZELDA_ENGINE_COLLECTION) -extra-linker-flags:"-L$(abspath $(DEV_DIR)) -lc++"

clean:
	rm -rf "$(BUILD_DIR)"
