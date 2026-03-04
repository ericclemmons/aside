SHELL := /bin/bash

ASIDE_DIR := Aside
ASIDE_APP := $(ASIDE_DIR)/Aside.app
ASIDE_BUNDLE_BIN := $(ASIDE_APP)/Contents/MacOS/Aside

.PHONY: build install run dev watch test test-one clean

build:
	cd "$(ASIDE_DIR)" && swift build

build-release:
	cd "$(ASIDE_DIR)" && swift build -c release

install:
	@BIN_PATH=$$(cd "$(ASIDE_DIR)" && swift build --show-bin-path)/Aside; \
	cp "$$BIN_PATH" "$(ASIDE_BUNDLE_BIN)"; \
	codesign --force --deep --sign - --identifier com.ericclemmons.aside.app "$(ASIDE_APP)"

run:
	pkill -x Aside 2>/dev/null || true
	sleep 0.3
	open "$(ASIDE_APP)"

dev: build install run

watch:
	cd "$(ASIDE_DIR)" && bash watch.sh

test:
	cd "$(ASIDE_DIR)" && swift test

test-one:
	@if [[ -z "$(TEST)" ]]; then \
		echo "Usage: make test-one TEST=ModuleTests/TestCaseName/testMethodName"; \
		exit 1; \
	fi
	cd "$(ASIDE_DIR)" && swift test --filter "$(TEST)"

clean:
	cd "$(ASIDE_DIR)" && swift package clean
