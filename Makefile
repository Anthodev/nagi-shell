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
AUDIO_HELPER := $(BUILD_DIR)/nagi-pipewire-audio
AUDIO_PROTOCOL_TEST := $(BUILD_DIR)/pipewire-audio-protocol-test
AUDIO_VOLUME_TEST := $(BUILD_DIR)/pipewire-audio-volume-test
CONNECTIVITY_HELPER := $(BUILD_DIR)/nagi-connectivity
CONNECTIVITY_MOC := $(BUILD_DIR)/connectivity/main.moc
CONNECTIVITY_DBUS_TEST := $(BUILD_DIR)/connectivity-dbus-test
CONNECTIVITY_DBUS_TEST_MOC := $(BUILD_DIR)/connectivity_dbus_test.moc
CONNECTIVITY_TEST_DIR := $(BUILD_DIR)/connectivity-test
CONNECTIVITY_LIVE_WRITE_TEST_DIR := $(BUILD_DIR)/connectivity-live-write-test
COORDINATOR_TEST_DIR := $(BUILD_DIR)/coordinator-test
WEATHER_TEST_DIR := $(BUILD_DIR)/weather-test
MEDIA_TEST_DIR := $(BUILD_DIR)/media-test
AUDIO_TEST_DIR := $(BUILD_DIR)/audio-test
AUDIO_LIVE_TEST_DIR := $(BUILD_DIR)/audio-live-test
AUDIO_LIVE_WRITE_TEST_DIR := $(BUILD_DIR)/audio-live-write-test
SURFACE_STATE_TEST_DIR := $(BUILD_DIR)/surface-state-test
UI_PRIMITIVES_TEST_DIR := $(BUILD_DIR)/ui-primitives-test
IDLE_TEST_DIR := $(BUILD_DIR)/idle-test
HELPER_SOURCES := src/kwin-virtual-desktops/main.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp
HELPER_HEADERS := src/kwin-virtual-desktops/desktop_snapshot.h
AUDIO_HELPER_SOURCES := src/pipewire-audio/main.cpp src/pipewire-audio/protocol.cpp src/pipewire-audio/volume.cpp
AUDIO_HELPER_HEADERS := src/pipewire-audio/protocol.h src/pipewire-audio/volume.h
QT_CFLAGS := $(shell $(PKG_CONFIG) --cflags Qt6Core Qt6DBus)
QT_LIBS := $(shell $(PKG_CONFIG) --libs Qt6Core Qt6DBus)
PIPEWIRE_CFLAGS := $(shell $(PKG_CONFIG) --cflags libpipewire-0.3)
PIPEWIRE_LIBS := $(shell $(PKG_CONFIG) --libs libpipewire-0.3)
NATIVE_CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wpedantic
AUDIO_NATIVE_CXXFLAGS := -std=gnu++20 -O2 -Wall -Wextra -Wno-sfinae-incomplete


QUICKSHELL_MIN_VERSION := 0.3.0
QUICKSHELL_CHANNEL := stable
FEDORA_QUICKSHELL_COPR := errornointernet/quickshell
FEDORA_QUICKSHELL_PACKAGE := quickshell

.PHONY: help requirements prepare check-quickshell check-helper-toolchain check-audio-toolchain helper audio-helper connectivity-helper test-native test-owner-lifecycle test-audio-protocol test-audio-volume test-connectivity-dbus test-adapter test-coordinator test-weather test-media test-audio test-audio-live test-audio-live-write test-connectivity test-connectivity-live-write test-idle test-surface-state test-ui-primitives check-nondisplay launch diagnose instances logs logs-follow stop format format-check lint-advisory check clean

help:
	@printf '%s\n' \
		'make requirements    Show and verify runtime/build dependencies' \
		'make helper          Build the KWin virtual desktop helper' \
		'make audio-helper    Build the confirmed PipeWire audio bridge' \
		'make connectivity-helper  Build the Wi-Fi and Bluetooth bridge' \
		'make test-native     Test KWin tuple normalization' \
		'make test-owner-lifecycle  Test KWin owner loss and replacement' \
		'make test-audio-protocol  Test the audio bridge command boundary' \
		'make test-audio-volume  Test proportional average-volume writes' \
		'make test-connectivity-dbus  Test D-Bus state, denial, and lifecycle' \
		'make test-adapter    Test the QML adapter boundary' \
		'make test-coordinator  Test island ownership and restoration' \
		'make test-surface-state  Exercise coordinator in the actual island surface' \
		'make test-weather    Test compact clock and weather adapter state' \
		'make test-media      Test the MPRIS media adapter state' \
		'make test-audio      Test the PipeWire audio adapter state' \
		'make test-audio-live Probe the live PipeWire graph without changing it' \
		'make test-audio-live-write  Change and restore live default audio state' \
		'make test-connectivity  Test Wi-Fi and Bluetooth adapter state' \
		'make test-connectivity-live-write  Change and restore live radios' \
		'make test-ui-primitives  Render theme tokens and primitives in the island surface' \
		'make test-idle       Test idle island composition and collapse' \
		'make launch          Run this checkout in the foreground' \
		'make diagnose        Run with authoritative verbose diagnostics' \
		'make instances       List this checkout instance as JSON' \
		'make logs            Show the latest 200 log lines' \
		'make logs-follow     Follow the runtime log' \
		'make stop            Stop this checkout and wait for its exit' \
		'make format          Format the QML configuration' \
		'make format-check    Verify committed QML formatting' \
		'make lint-advisory   Run non-authoritative qmllint diagnostics' \
		'make check-nondisplay  Run checks that need no display server' \
		'make check           Run repository-defined non-visual checks'

requirements:
	@printf 'Quickshell >= %s from the %s release channel\n' '$(QUICKSHELL_MIN_VERSION)' '$(QUICKSHELL_CHANNEL)'
	@printf 'Fedora 44 source: COPR %s, package %s (never quickshell-git)\n' '$(FEDORA_QUICKSHELL_COPR)' '$(FEDORA_QUICKSHELL_PACKAGE)'
	@printf 'Install: sudo dnf copr enable %s && sudo dnf install %s pipewire-devel\n' '$(FEDORA_QUICKSHELL_COPR)' '$(FEDORA_QUICKSHELL_PACKAGE)'
	@printf 'Native builds: C++20, Qt 6 Core/DBus, and libpipewire 0.3 development files\n'
	@$(MAKE) --no-print-directory check-quickshell
	@$(MAKE) --no-print-directory check-helper-toolchain
	@$(MAKE) --no-print-directory check-audio-toolchain

prepare:
	@touch .qmlls.ini

check-helper-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core Qt6DBus
	@test -x '$(MOC)'

check-audio-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core libpipewire-0.3

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(HELPER_MOC): src/kwin-virtual-desktops/main.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(OWNER_TEST_MOC): tests/kwin_owner_lifecycle_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(CONNECTIVITY_MOC): src/connectivity/main.cpp | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(MOC) $< -o $@

$(CONNECTIVITY_DBUS_TEST_MOC): tests/connectivity_dbus_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(HELPER): $(HELPER_SOURCES) $(HELPER_HEADERS) $(HELPER_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) -Isrc/kwin-virtual-desktops $(HELPER_SOURCES) -o $@ $(LDFLAGS) $(QT_LIBS)

$(HELPER_TEST): tests/kwin_virtual_desktops_test.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp $(HELPER_HEADERS) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -Isrc/kwin-virtual-desktops tests/kwin_virtual_desktops_test.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(OWNER_TEST): tests/kwin_owner_lifecycle_test.cpp $(OWNER_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) tests/kwin_owner_lifecycle_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(AUDIO_HELPER): $(AUDIO_HELPER_SOURCES) $(AUDIO_HELPER_HEADERS) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(AUDIO_NATIVE_CXXFLAGS) $(QT_CFLAGS) $(PIPEWIRE_CFLAGS) -Isrc/pipewire-audio $(AUDIO_HELPER_SOURCES) -o $@ $(LDFLAGS) $(QT_LIBS) $(PIPEWIRE_LIBS)

$(AUDIO_PROTOCOL_TEST): tests/pipewire_audio_protocol_test.cpp src/pipewire-audio/protocol.cpp $(AUDIO_HELPER_HEADERS) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(AUDIO_NATIVE_CXXFLAGS) $(QT_CFLAGS) -Isrc/pipewire-audio tests/pipewire_audio_protocol_test.cpp src/pipewire-audio/protocol.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(AUDIO_VOLUME_TEST): tests/pipewire_audio_volume_test.cpp src/pipewire-audio/volume.cpp src/pipewire-audio/volume.h | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(AUDIO_NATIVE_CXXFLAGS) -Isrc/pipewire-audio tests/pipewire_audio_volume_test.cpp src/pipewire-audio/volume.cpp -o $@ $(LDFLAGS)

$(CONNECTIVITY_HELPER): src/connectivity/main.cpp $(CONNECTIVITY_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(dir $(CONNECTIVITY_MOC)) src/connectivity/main.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(CONNECTIVITY_DBUS_TEST): tests/connectivity_dbus_test.cpp $(CONNECTIVITY_DBUS_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) tests/connectivity_dbus_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

helper: check-helper-toolchain $(HELPER)

audio-helper: check-audio-toolchain $(AUDIO_HELPER)

connectivity-helper: check-helper-toolchain $(CONNECTIVITY_HELPER)

test-native: check-helper-toolchain $(HELPER_TEST)
	$(HELPER_TEST)

test-audio-protocol: check-audio-toolchain $(AUDIO_PROTOCOL_TEST)
	$(AUDIO_PROTOCOL_TEST)

test-audio-volume: $(AUDIO_VOLUME_TEST)
	$(AUDIO_VOLUME_TEST)

test-owner-lifecycle: check-helper-toolchain $(HELPER) $(OWNER_TEST)
	@command -v '$(DBUS_RUN_SESSION)' >/dev/null
	$(DBUS_RUN_SESSION) -- $(OWNER_TEST) $(abspath $(HELPER))

test-connectivity-dbus: check-helper-toolchain $(CONNECTIVITY_HELPER) $(CONNECTIVITY_DBUS_TEST)
	@command -v '$(DBUS_RUN_SESSION)' >/dev/null
	$(DBUS_RUN_SESSION) -- $(CONNECTIVITY_DBUS_TEST) $(abspath $(CONNECTIVITY_HELPER))

test-adapter: check-quickshell | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/adapter-test/qml
	cp tests/adapter/shell.qml $(BUILD_DIR)/adapter-test/shell.qml
	cp qml/KWinVirtualDesktopAdapter.qml $(BUILD_DIR)/adapter-test/qml/KWinVirtualDesktopAdapter.qml
	$(QS) -p $(BUILD_DIR)/adapter-test --no-duplicate

test-coordinator: check-quickshell | $(BUILD_DIR)
	mkdir -p $(COORDINATOR_TEST_DIR)/qml
	cp tests/coordinator/shell.qml $(COORDINATOR_TEST_DIR)/shell.qml
	cp qml/IslandStateCoordinator.qml $(COORDINATOR_TEST_DIR)/qml/
	$(QS) -p $(COORDINATOR_TEST_DIR) --no-duplicate

test-weather: check-quickshell | $(BUILD_DIR)
	mkdir -p $(WEATHER_TEST_DIR)/qml
	cp tests/weather/shell.qml $(WEATHER_TEST_DIR)/shell.qml
	cp qml/WeatherAdapter.qml qml/CompactClock.qml $(WEATHER_TEST_DIR)/qml/
	$(QS) -p $(WEATHER_TEST_DIR) --no-duplicate

test-media: check-quickshell | $(BUILD_DIR)
	mkdir -p $(MEDIA_TEST_DIR)/qml
	cp tests/media/shell.qml $(MEDIA_TEST_DIR)/shell.qml
	cp qml/MediaAdapter.qml $(MEDIA_TEST_DIR)/qml/
	$(QS) -p $(MEDIA_TEST_DIR) --no-duplicate

test-audio: check-quickshell | $(BUILD_DIR)
	mkdir -p $(AUDIO_TEST_DIR)/qml
	cp tests/audio/shell.qml $(AUDIO_TEST_DIR)/shell.qml
	cp qml/AudioAdapter.qml qml/PipeWireAudioBridge.qml $(AUDIO_TEST_DIR)/qml/
	$(QS) -p $(AUDIO_TEST_DIR) --no-duplicate

test-audio-live: check-quickshell audio-helper | $(BUILD_DIR)
	mkdir -p $(AUDIO_LIVE_TEST_DIR)/qml
	cp tests/audio/live.qml $(AUDIO_LIVE_TEST_DIR)/shell.qml
	cp qml/AudioAdapter.qml qml/PipeWireAudioBridge.qml $(AUDIO_LIVE_TEST_DIR)/qml/
	NAGI_AUDIO_HELPER='$(abspath $(AUDIO_HELPER))' $(QS) -p $(AUDIO_LIVE_TEST_DIR) --no-duplicate

test-audio-live-write: check-quickshell audio-helper | $(BUILD_DIR)
	mkdir -p $(AUDIO_LIVE_WRITE_TEST_DIR)/qml
	cp tests/audio/live-write.qml $(AUDIO_LIVE_WRITE_TEST_DIR)/shell.qml
	cp qml/AudioAdapter.qml qml/PipeWireAudioBridge.qml $(AUDIO_LIVE_WRITE_TEST_DIR)/qml/
	NAGI_AUDIO_HELPER='$(abspath $(AUDIO_HELPER))' $(QS) -p $(AUDIO_LIVE_WRITE_TEST_DIR) --no-duplicate

test-connectivity: check-quickshell | $(BUILD_DIR)
	mkdir -p $(CONNECTIVITY_TEST_DIR)/qml
	cp tests/connectivity/shell.qml $(CONNECTIVITY_TEST_DIR)/shell.qml
	cp qml/ConnectivityAdapter.qml qml/ConnectivityBridge.qml $(CONNECTIVITY_TEST_DIR)/qml/
	$(QS) -p $(CONNECTIVITY_TEST_DIR) --no-duplicate

test-connectivity-live-write: check-quickshell connectivity-helper | $(BUILD_DIR)
	mkdir -p $(CONNECTIVITY_LIVE_WRITE_TEST_DIR)/qml
	cp tests/connectivity/live-write.qml $(CONNECTIVITY_LIVE_WRITE_TEST_DIR)/shell.qml
	cp qml/ConnectivityAdapter.qml qml/ConnectivityBridge.qml $(CONNECTIVITY_LIVE_WRITE_TEST_DIR)/qml/
	NAGI_CONNECTIVITY_HELPER='$(abspath $(CONNECTIVITY_HELPER))' $(QS) -p $(CONNECTIVITY_LIVE_WRITE_TEST_DIR) --no-duplicate

test-surface-state: check-quickshell | $(BUILD_DIR)
	mkdir -p $(SURFACE_STATE_TEST_DIR)/qml
	cp tests/surface-state/shell.qml $(SURFACE_STATE_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/DashboardRegion.qml qml/ExpandedDashboard.qml qml/IdleIsland.qml qml/IdleMediaText.qml qml/WeatherGlyph.qml qml/IslandStateCoordinator.qml qml/IslandSurfaceHost.qml qml/IslandSurface.qml $(SURFACE_STATE_TEST_DIR)/qml/
	$(QS) -p $(SURFACE_STATE_TEST_DIR) --no-duplicate

test-ui-primitives: check-quickshell | $(BUILD_DIR)
	mkdir -p $(UI_PRIMITIVES_TEST_DIR)/qml
	cp tests/ui/shell.qml $(UI_PRIMITIVES_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IdleIsland.qml qml/IdleMediaText.qml qml/WeatherGlyph.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/IslandIconButton.qml qml/IslandProgressBar.qml qml/DashboardRegion.qml qml/ExpandedDashboard.qml qml/IslandStateCoordinator.qml qml/IslandSurface.qml $(UI_PRIMITIVES_TEST_DIR)/qml/
	$(QS) -p $(UI_PRIMITIVES_TEST_DIR) --no-duplicate

test-idle: check-quickshell | $(BUILD_DIR)
	mkdir -p $(IDLE_TEST_DIR)/qml
	cp tests/idle/shell.qml $(IDLE_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandText.qml qml/IdleIsland.qml qml/IdleMediaText.qml qml/WeatherGlyph.qml qml/ReducedMotion.qml $(IDLE_TEST_DIR)/qml/
	$(QS) -p $(IDLE_TEST_DIR) --no-duplicate

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

launch: check-quickshell prepare helper audio-helper connectivity-helper
	$(QS) -p . --no-duplicate

diagnose: check-quickshell prepare helper audio-helper connectivity-helper
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

check: check-nondisplay test-surface-state test-ui-primitives

check-nondisplay: check-quickshell format-check audio-helper connectivity-helper test-native test-owner-lifecycle test-audio-protocol test-audio-volume test-connectivity-dbus test-adapter test-coordinator test-weather test-media test-audio test-connectivity test-idle
clean:
	rm -rf $(BUILD_DIR)
