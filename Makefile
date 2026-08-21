SHELL := /bin/sh

QS ?= qs
QMLFORMAT ?= qmlformat-qt6
QMLLINT ?= qmllint-qt6
QML_SOURCES := shell.qml $(wildcard qml/*.qml)
CXX ?= c++
PKG_CONFIG ?= pkg-config
QT_PATHS ?= qtpaths6
MOC ?= $(shell $(QT_PATHS) --query QT_HOST_LIBEXECS)/moc
DBUS_RUN_SESSION ?= dbus-run-session
BUILD_DIR := build
HELPER := $(BUILD_DIR)/nagi-kwin-virtual-desktops
HELPER_TEST := $(BUILD_DIR)/kwin-virtual-desktops-test
HELPER_MOC := $(BUILD_DIR)/main.moc
OWNER_TEST := $(BUILD_DIR)/kwin-owner-lifecycle-test
OWNER_TEST_MOC := $(BUILD_DIR)/kwin_owner_lifecycle_test.moc
HELPER_SOURCES := src/kwin-virtual-desktops/main.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp
HELPER_HEADERS := src/kwin-virtual-desktops/desktop_snapshot.h
QT_CFLAGS := $(shell $(PKG_CONFIG) --cflags Qt6Core Qt6DBus)
QT_LIBS := $(shell $(PKG_CONFIG) --libs Qt6Core Qt6DBus)
NATIVE_CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wpedantic


QUICKSHELL_MIN_VERSION := 0.3.0
QUICKSHELL_CHANNEL := stable
FEDORA_QUICKSHELL_COPR := errornointernet/quickshell
FEDORA_QUICKSHELL_PACKAGE := quickshell

.PHONY: help requirements prepare check-quickshell check-helper-toolchain helper test-native test-owner-lifecycle test-adapter launch diagnose instances logs logs-follow stop format format-check lint-advisory check clean

help:
	@printf '%s\n' \
		'make requirements    Show and verify the Quickshell dependency' \
		'make helper          Build the KWin virtual desktop helper' \
		'make test-native     Test KWin tuple normalization' \
		'make test-owner-lifecycle  Test KWin owner loss and replacement' \
		'make test-adapter    Test the QML adapter boundary' \
		'make launch          Run this checkout in the foreground' \
		'make diagnose        Run with authoritative verbose diagnostics' \
		'make instances       List this checkout instance as JSON' \
		'make logs            Show the latest 200 log lines' \
		'make logs-follow     Follow the runtime log' \
		'make stop            Stop this checkout and wait for its exit' \
		'make format          Format the QML configuration' \
		'make format-check    Verify committed QML formatting' \
		'make lint-advisory   Run non-authoritative qmllint diagnostics' \
		'make check           Run repository-defined non-visual checks'

requirements:
	@printf 'Quickshell >= %s from the %s release channel\n' '$(QUICKSHELL_MIN_VERSION)' '$(QUICKSHELL_CHANNEL)'
	@printf 'Fedora 44 source: COPR %s, package %s (never quickshell-git)\n' '$(FEDORA_QUICKSHELL_COPR)' '$(FEDORA_QUICKSHELL_PACKAGE)'
	@printf 'Install: sudo dnf copr enable %s && sudo dnf install %s\n' '$(FEDORA_QUICKSHELL_COPR)' '$(FEDORA_QUICKSHELL_PACKAGE)'
	@printf 'Native helper build: C++20 plus Qt 6 Core and DBus development files\n'
	@$(MAKE) --no-print-directory check-quickshell
	@$(MAKE) --no-print-directory check-helper-toolchain

prepare:
	@touch .qmlls.ini

check-helper-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core Qt6DBus
	@test -x '$(MOC)'

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(HELPER_MOC): src/kwin-virtual-desktops/main.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(OWNER_TEST_MOC): tests/kwin_owner_lifecycle_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(HELPER): $(HELPER_SOURCES) $(HELPER_HEADERS) $(HELPER_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) -Isrc/kwin-virtual-desktops $(HELPER_SOURCES) -o $@ $(LDFLAGS) $(QT_LIBS)

$(HELPER_TEST): tests/kwin_virtual_desktops_test.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp $(HELPER_HEADERS) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -Isrc/kwin-virtual-desktops tests/kwin_virtual_desktops_test.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(OWNER_TEST): tests/kwin_owner_lifecycle_test.cpp $(OWNER_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) tests/kwin_owner_lifecycle_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

helper: check-helper-toolchain $(HELPER)

test-native: check-helper-toolchain $(HELPER_TEST)
	$(HELPER_TEST)

test-owner-lifecycle: check-helper-toolchain $(HELPER) $(OWNER_TEST)
	@command -v '$(DBUS_RUN_SESSION)' >/dev/null
	$(DBUS_RUN_SESSION) -- $(OWNER_TEST) $(abspath $(HELPER))

test-adapter: check-quickshell | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/adapter-test/qml
	cp tests/adapter/shell.qml $(BUILD_DIR)/adapter-test/shell.qml
	cp qml/KWinVirtualDesktopAdapter.qml $(BUILD_DIR)/adapter-test/qml/KWinVirtualDesktopAdapter.qml
	$(QS) -p $(BUILD_DIR)/adapter-test --no-duplicate

check-quickshell:
	@set -eu; \
	version="$$($(QS) --version | sed -n 's/^Quickshell \([0-9][0-9.]*\).*/\1/p')"; \
	if [ -z "$$version" ]; then \
		printf 'Unable to read the Quickshell version from `%s --version`.\n' '$(QS)' >&2; \
		exit 1; \
	fi; \
	lowest="$$(printf '%s\n%s\n' '$(QUICKSHELL_MIN_VERSION)' "$$version" | sort -V | sed -n '1p')"; \
	if [ "$$lowest" != '$(QUICKSHELL_MIN_VERSION)' ]; then \
		printf 'Quickshell %s is installed; version %s or newer is required.\n' "$$version" '$(QUICKSHELL_MIN_VERSION)' >&2; \
		exit 1; \
	fi; \
	printf 'Quickshell %s satisfies the >= %s requirement.\n' "$$version" '$(QUICKSHELL_MIN_VERSION)'

launch: check-quickshell prepare helper
	$(QS) -p . --no-duplicate

diagnose: check-quickshell prepare helper
	$(QS) -p . --no-duplicate -vv --log-times

instances:
	$(QS) list -p . --json

logs:
	$(QS) log -p . --tail 200

logs-follow:
	$(QS) log -p . --follow

stop:
	@set -eu; \
	$(QS) kill -p .; \
	attempts=0; \
	while :; do \
		instances="$$($(QS) list -p . --json 2>/dev/null || true)"; \
		case "$$instances" in *'"pid"'*) ;; *) break ;; esac; \
		attempts=$$((attempts + 1)); \
		if [ "$$attempts" -ge 100 ]; then \
			printf 'Quickshell did not stop within 5 seconds.\n' >&2; \
			exit 1; \
		fi; \
		sleep 0.05; \
	done

format:
	$(QMLFORMAT) -i $(QML_SOURCES)

format-check:
	@set -eu; \
	for source in $(QML_SOURCES); do \
		$(QMLFORMAT) "$$source" | cmp -s "$$source" - || { \
			printf '%s is not formatted; run `make format`.\n' "$$source" >&2; \
			exit 1; \
		}; \
	done

lint-advisory:
	@$(QMLLINT) $(QML_SOURCES) || { \
		printf 'qmllint is advisory because it cannot resolve a valid Quickshell PanelWindow; use runtime diagnostics as the clean gate.\n' >&2; \
		exit 0; \
	}

check: check-quickshell format-check test-native test-owner-lifecycle test-adapter

clean:
	rm -rf $(BUILD_DIR)
