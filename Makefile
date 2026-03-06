SHELL := /bin/bash

ASIDE_DIR := Aside
ASIDE_APP := $(ASIDE_DIR)/Aside.app
ASIDE_BUNDLE_BIN := $(ASIDE_APP)/Contents/MacOS/Aside

.PHONY: build build-release release install run dev watch test test-one clean

build:
	cd "$(ASIDE_DIR)" && swift build

build-release:
	cd "$(ASIDE_DIR)" && swift build -c release

release: build-release
	@rm -rf "$(ASIDE_APP)"
	@mkdir -p "$(ASIDE_APP)/Contents/MacOS" "$(ASIDE_APP)/Contents/Resources"
	@cp "$$(cd "$(ASIDE_DIR)" && swift build -c release --show-bin-path)/Aside" "$(ASIDE_BUNDLE_BIN)"
	@strip "$(ASIDE_BUNDLE_BIN)"
	@cp "$(ASIDE_DIR)/Sources/Aside/Info.plist" "$(ASIDE_APP)/Contents/Info.plist"
	@cp "$(ASIDE_DIR)/AppIcon.icns" "$(ASIDE_APP)/Contents/Resources/AppIcon.icns"
	@if [ -n "$(CODESIGN_IDENTITY)" ]; then \
		codesign --force --options runtime \
			--entitlements "$(ASIDE_DIR)/Sources/Aside/Aside.entitlements" \
			--sign "$(CODESIGN_IDENTITY)" \
			"$(ASIDE_APP)"; \
		echo "Signed $(ASIDE_APP) with $(CODESIGN_IDENTITY)"; \
	fi
	@echo "Built $(ASIDE_APP) (release)"

install:
	@BIN_PATH=$$(cd "$(ASIDE_DIR)" && swift build --show-bin-path)/Aside; \
	cp "$$BIN_PATH" "$(ASIDE_BUNDLE_BIN)"; \
	codesign --force --deep --sign "Developer ID Application: Eric Clemmons (D3TJHQZD9N)" --identifier com.ericclemmons.aside.app "$(ASIDE_APP)"; \
	/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$(ASIDE_APP)"

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
