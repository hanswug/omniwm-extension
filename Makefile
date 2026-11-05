# OmniWM Extension — see PDR §7.2.
# Note: `make release VERSION=x.y.z` sets VERSION on the command line, so the
# app version read from the VERSION file lives in APP_VERSION.

APP_NAME      := OmniWM Extension
BUNDLE_ID     := com.omniwm.extension
SCHEME        := OmniWMExtension
PROJECT       := OmniWMExtension.xcodeproj
IDENTITY      := OmniWM Extension Self-Signed
BUILD_DIR     := build
DERIVED       := $(BUILD_DIR)/DerivedData
BUILT_APP     := $(DERIVED)/Build/Products/Release/$(APP_NAME).app
APP           := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_APP   := /Applications/$(APP_NAME).app

APP_VERSION    = $(shell cat VERSION)
BUILD_NUMBER   = $(shell git rev-list --count HEAD 2>/dev/null || echo 1)

.PHONY: gen test build run install release check-identity clean

gen:
	xcodegen generate --quiet

test:
	swift test --package-path Packages/Core

check-identity:
	@security find-identity -v -p codesigning | grep -Fq '"$(IDENTITY)"' || { \
	  echo 'error: signing identity "$(IDENTITY)" not found or not trusted.'; \
	  echo '       Run scripts/create-signing-cert.sh once.'; exit 1; }

build: check-identity gen
	@mkdir -p $(BUILD_DIR)
	@rm -rf "$(BUILT_APP)"
	@set -o pipefail; xcodebuild \
	  -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
	  -derivedDataPath $(DERIVED) \
	  MARKETING_VERSION=$(APP_VERSION) \
	  CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) \
	  CODE_SIGN_IDENTITY="$(IDENTITY)" \
	  build 2>&1 | tee $(BUILD_DIR)/xcodebuild.log | grep -E '(error:|warning: |BUILD (SUCCEEDED|FAILED))' \
	  || { echo "error: xcodebuild failed, see $(BUILD_DIR)/xcodebuild.log"; exit 1; }
	rm -rf "$(APP)"
	ditto "$(BUILT_APP)" "$(APP)"
	codesign --verify --deep --strict --verbose=1 "$(APP)"
	@codesign -dv "$(APP)" 2>&1 | tee /dev/stderr | grep -Fq 'Authority=$(IDENTITY)' || { \
	  echo 'error: app is not signed by "$(IDENTITY)"'; exit 1; }
	@codesign -dv "$(APP)" 2>&1 | grep -Eq 'flags=.*runtime' || { \
	  echo 'error: hardened runtime is not enabled'; exit 1; }
	@echo "Built $(APP) ($(APP_VERSION) build $(BUILD_NUMBER))"

run: build
	open "$(APP)"

install: build
	@# SIGTERM, not an Apple Event: avoids an Automation (TCC) prompt.
	-@pkill -TERM -x "$(APP_NAME)" 2>/dev/null; true
	@for i in 1 2 3 4 5 6 7 8 9 10; do pgrep -xq "$(APP_NAME)" || break; sleep 0.3; done
	-@pkill -KILL -x "$(APP_NAME)" 2>/dev/null; true
	rm -rf "$(INSTALL_APP)"
	ditto "$(APP)" "$(INSTALL_APP)"
	open "$(INSTALL_APP)"
	@echo "Installed $(INSTALL_APP)"

release:
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 1; }
	scripts/release.sh "$(VERSION)"

clean:
	rm -rf "$(BUILD_DIR)"
