include toolchain.mk

APP := adriatic
BUILD_DIR := build
TOOLS_DIR := .tools
ZELDA_ENGINE_ROOT ?= ../zelda-engine
ZELDA_ENGINE_PACKAGES := $(abspath $(ZELDA_ENGINE_ROOT))/packages
ZELDA_ENGINE_COLLECTION := -collection:zelda_engine=$(ZELDA_ENGINE_PACKAGES)

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
DEV_APP := $(DEV_DIR)/$(APP)
RELEASE_APP := $(RELEASE_DIR)/$(APP)
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
CAPTURE_PATH ?= $(abspath $(BUILD_DIR)/captures/$(APP).png)
ODIN_SOURCES := $(shell find src packages tests -type f -name '*.odin' 2>/dev/null)
HOT_ODIN_SOURCES := $(shell find src packages "$(ZELDA_ENGINE_PACKAGES)" -type f -name '*.odin' 2>/dev/null)
HOT_SHADER_OUTPUTS := \
	$(HOT_SHADER_DIR)/world.vert.spv \
	$(HOT_SHADER_DIR)/world.frag.spv \
	$(HOT_SHADER_DIR)/world-sky.vert.spv \
	$(HOT_SHADER_DIR)/world-sky.frag.spv \
	$(HOT_SHADER_DIR)/wireframe.vert.spv \
	$(HOT_SHADER_DIR)/wireframe.frag.spv \
	$(HOT_SHADER_DIR)/canvas.vert.spv \
	$(HOT_SHADER_DIR)/canvas.frag.spv \
	$(HOT_SHADER_DIR)/canvas-post.vert.spv \
	$(HOT_SHADER_DIR)/canvas-post.frag.spv

.PHONY: all bootstrap bootstrap-fork doctor physics-deps physics-build shaders build release hot hot-build hot-app hot-host hot-shaders run capture capture-car fmt check test clean

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

build: doctor $(DEV_APP)

shaders: build/generated/shaders/world.vert.spv build/generated/shaders/world.frag.spv build/generated/shaders/world-sky.vert.spv build/generated/shaders/world-sky.frag.spv build/generated/shaders/wireframe.vert.spv build/generated/shaders/wireframe.frag.spv build/generated/shaders/canvas.vert.spv build/generated/shaders/canvas.frag.spv build/generated/shaders/canvas-post.vert.spv build/generated/shaders/canvas-post.frag.spv build/generated/shaders/particles.vert.spv build/generated/shaders/particles.frag.spv

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

$(DEV_DIR)/assets/icons/ui-icon-atlas-garden.png: assets/icons/ui-icon-atlas-garden.png
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/assets/fonts/ZeldaSans-Regular-v1.otf: assets/fonts/ZeldaSans-Regular-v1.otf
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/assets/fonts/ZeldaSerif-Regular-v0_1.otf: assets/fonts/ZeldaSerif-Regular-v0_1.otf
	@mkdir -p $(@D)
	cp $< $@

$(DEV_DIR)/assets/fonts/MomoTrustDisplay-Regular.ttf: assets/fonts/MomoTrustDisplay-Regular.ttf
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

$(RELEASE_DIR)/assets/icons/ui-icon-atlas-garden.png: assets/icons/ui-icon-atlas-garden.png
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/assets/fonts/ZeldaSans-Regular-v1.otf: assets/fonts/ZeldaSans-Regular-v1.otf
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/assets/fonts/ZeldaSerif-Regular-v0_1.otf: assets/fonts/ZeldaSerif-Regular-v0_1.otf
	@mkdir -p $(@D)
	cp $< $@

$(RELEASE_DIR)/assets/fonts/MomoTrustDisplay-Regular.ttf: assets/fonts/MomoTrustDisplay-Regular.ttf
	@mkdir -p $(@D)
	cp $< $@

release: doctor $(RELEASE_APP)

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

$(HOT_SHADER_STAMP): $(HOT_SHADER_OUTPUTS)
	@mkdir -p $(@D)
	touch $@

$(HOT_APP): $(HOT_PHYSICS_STAMP) $(HOT_ODIN_SOURCES) Makefile toolchain.mk $(HOT_DIR)/libgfx_signposts.a
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) -debug -o:minimal -build-mode:shared -define:HOT_RELOAD=true -out:$@ -extra-linker-flags:"$(call link_flags,$(HOT_DIR))"

$(HOT_APP_STAMP): $(HOT_APP)
	@mkdir -p $(@D)
	touch $@

$(HOT_HOST): hot/main.odin Makefile toolchain.mk
	@mkdir -p $(@D)
	$(ODIN) build hot/main.odin -file -debug -o:minimal -out:$@

hot-app: $(HOT_APP_STAMP)

hot-host: $(HOT_HOST)

hot-shaders: $(HOT_SHADER_STAMP)

hot-build: doctor $(HOT_PHYSICS_STAMP) hot-app hot-shaders hot-host

hot: hot-build
	$(PYTHON) tools/hot_watch.py --root "$(CURDIR)" --engine-root "$(ZELDA_ENGINE_ROOT)" --host "$(abspath $(HOT_HOST))" --make "$(MAKE)"

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

$(RELEASE_DIR)/libgfx_signposts.a: $(ZELDA_ENGINE_PACKAGES)/canvas2d/gfx_signposts.c Makefile
	@mkdir -p $(@D)
	$(CC) -O2 -c $< -o $(RELEASE_DIR)/gfx_signposts.o
	$(AR) rcs $@ $(RELEASE_DIR)/gfx_signposts.o

$(DEV_APP): physics-build $(ODIN_SOURCES) Makefile toolchain.mk $(DEV_DIR)/libgfx_signposts.a $(DEV_DIR)/assets/icons/ui-icon-atlas-garden.png $(DEV_DIR)/assets/fonts/ZeldaSans-Regular-v1.otf $(DEV_DIR)/assets/fonts/ZeldaSerif-Regular-v0_1.otf $(DEV_DIR)/assets/fonts/MomoTrustDisplay-Regular.ttf $(DEV_DIR)/shaders/world.vert.spv $(DEV_DIR)/shaders/world.frag.spv $(DEV_DIR)/shaders/world-sky.vert.spv $(DEV_DIR)/shaders/world-sky.frag.spv $(DEV_DIR)/shaders/wireframe.vert.spv $(DEV_DIR)/shaders/wireframe.frag.spv $(DEV_DIR)/shaders/canvas.vert.spv $(DEV_DIR)/shaders/canvas.frag.spv $(DEV_DIR)/shaders/canvas-post.vert.spv $(DEV_DIR)/shaders/canvas-post.frag.spv $(DEV_DIR)/shaders/particles.vert.spv $(DEV_DIR)/shaders/particles.frag.spv
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) -debug -o:minimal -out:$@ -extra-linker-flags:"$(call link_flags,$(DEV_DIR))"

$(RELEASE_APP): physics-build $(ODIN_SOURCES) Makefile toolchain.mk $(RELEASE_DIR)/libgfx_signposts.a $(RELEASE_DIR)/assets/icons/ui-icon-atlas-garden.png $(RELEASE_DIR)/assets/fonts/ZeldaSans-Regular-v1.otf $(RELEASE_DIR)/assets/fonts/ZeldaSerif-Regular-v0_1.otf $(RELEASE_DIR)/assets/fonts/MomoTrustDisplay-Regular.ttf $(RELEASE_DIR)/shaders/world.vert.spv $(RELEASE_DIR)/shaders/world.frag.spv $(RELEASE_DIR)/shaders/world-sky.vert.spv $(RELEASE_DIR)/shaders/world-sky.frag.spv $(RELEASE_DIR)/shaders/wireframe.vert.spv $(RELEASE_DIR)/shaders/wireframe.frag.spv $(RELEASE_DIR)/shaders/canvas.vert.spv $(RELEASE_DIR)/shaders/canvas.frag.spv $(RELEASE_DIR)/shaders/canvas-post.vert.spv $(RELEASE_DIR)/shaders/canvas-post.frag.spv $(RELEASE_DIR)/shaders/particles.vert.spv $(RELEASE_DIR)/shaders/particles.frag.spv
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) -o:speed -out:$@ -extra-linker-flags:"$(call link_flags,$(RELEASE_DIR))"

run: build
	$(DEV_APP)

capture: build
	@mkdir -p "$(dir $(CAPTURE_PATH))"
	$(DEV_APP) --capture "$(CAPTURE_PATH)"
	@test -s "$(CAPTURE_PATH)" || { echo "error: screenshot was not written to $(CAPTURE_PATH)" >&2; exit 1; }
	@echo "Screenshot: $(CAPTURE_PATH)"

capture-car: build
	@mkdir -p "$(dir $(CAPTURE_PATH))"
	$(DEV_APP) --capture-car "$(CAPTURE_PATH)"
	@test -s "$(CAPTURE_PATH)" || { echo "error: screenshot was not written to $(CAPTURE_PATH)" >&2; exit 1; }
	@echo "Screenshot: $(CAPTURE_PATH)"

fmt:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required" >&2; exit 1; }
	find src packages tests -type f -name '*.odin' -exec $(ODINFMT) -w {} +

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

test: doctor
	$(ODIN) test tests $(ZELDA_ENGINE_COLLECTION)

clean:
	rm -rf "$(BUILD_DIR)"
