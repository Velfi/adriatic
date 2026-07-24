include toolchain.mk

APP := adriatic
BUILD_DIR := build
TOOLS_DIR := .tools
ZELDA_ENGINE_ROOT ?= ../zelda-engine
ZELDA_ENGINE_PACKAGES := $(abspath $(ZELDA_ENGINE_ROOT))/packages
ZELDA_ENGINE_COLLECTION := -collection:zelda_engine=$(ZELDA_ENGINE_PACKAGES)

LOCAL_ODIN := $(TOOLS_DIR)/odin/$(ODIN_VERSION)/odin
ODIN ?= $(LOCAL_ODIN)
ODINFMT ?= odinfmt

ifeq ($(shell uname -s),Darwin)
HOMEBREW_LLVM_PREFIX := $(shell brew --prefix $(LLVM_HOMEBREW_FORMULA) 2>/dev/null)
ODIN_CLANG_PATH ?= $(HOMEBREW_LLVM_PREFIX)/bin/clang
export ODIN_CLANG_PATH
endif

DEV_DIR := $(BUILD_DIR)/dev
RELEASE_DIR := $(BUILD_DIR)/release
DEV_APP := $(DEV_DIR)/$(APP)
RELEASE_APP := $(RELEASE_DIR)/$(APP)
ODIN_SOURCES := $(shell find src packages tests -type f -name '*.odin' 2>/dev/null)

.PHONY: all bootstrap doctor physics-deps physics-build build release run fmt check test clean

all: build

bootstrap:
	./tools/bootstrap-macos.sh

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

release: doctor $(RELEASE_APP)

# The Zelda Engine physics package is backed by its pinned Jolt checkout. Keep
# the native build in the engine repository, but provision it before producing
# an application binary so importing zelda_engine:physics needs no manual step.
physics-deps: doctor
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" physics-deps

physics-build: doctor
	$(MAKE) -C "$(ZELDA_ENGINE_ROOT)" physics-build

$(DEV_APP): physics-build $(ODIN_SOURCES) Makefile toolchain.mk
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) -debug -o:minimal -out:$@

$(RELEASE_APP): physics-build $(ODIN_SOURCES) Makefile toolchain.mk
	@mkdir -p $(@D)
	$(ODIN) build src $(ZELDA_ENGINE_COLLECTION) -o:speed -out:$@

run: build
	$(DEV_APP)

fmt:
	@command -v $(ODINFMT) >/dev/null || { echo "odinfmt is required" >&2; exit 1; }
	find src packages tests -type f -name '*.odin' -exec $(ODINFMT) -w {} +

check: doctor
	$(ODIN) check src $(ZELDA_ENGINE_COLLECTION)

test: doctor physics-build
	$(ODIN) test tests -all-packages $(ZELDA_ENGINE_COLLECTION)

clean:
	rm -rf "$(BUILD_DIR)"
