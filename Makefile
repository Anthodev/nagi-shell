SHELL := /bin/sh

QS ?= qs
QMLFORMAT ?= qmlformat-qt6
QMLLINT ?= qmllint-qt6
QML_SOURCES := shell.qml $(wildcard qml/*.qml)
CXX ?= c++
CMAKE ?= cmake
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
BRIGHTNESS_HELPER := $(BUILD_DIR)/nagi-brightness
BRIGHTNESS_MOC := $(BUILD_DIR)/brightness/main.moc
BRIGHTNESS_DBUS_TEST := $(BUILD_DIR)/brightness-dbus-test
BRIGHTNESS_DBUS_TEST_MOC := $(BUILD_DIR)/brightness_dbus_test.moc
SESSION_HELPER := $(BUILD_DIR)/nagi-session
SESSION_MOC := $(BUILD_DIR)/session/main.moc
SESSION_DBUS_TEST := $(BUILD_DIR)/session-dbus-test
SESSION_DBUS_TEST_MOC := $(BUILD_DIR)/session_dbus_test.moc
APPLICATION_HELPER := $(BUILD_DIR)/nagi-applications
LAUNCHER_SHORTCUT_BUILD_DIR := $(BUILD_DIR)/launcher-shortcut
LAUNCHER_SHORTCUT_HELPER := $(LAUNCHER_SHORTCUT_BUILD_DIR)/nagi-launcher-shortcut
LAUNCHER_SHORTCUT_TEST := $(LAUNCHER_SHORTCUT_BUILD_DIR)/nagi-launcher-shortcut-test
LAUNCHER_SHORTCUT_TEST_DIR := $(BUILD_DIR)/launcher-shortcut-test
CONNECTIVITY_TEST_DIR := $(BUILD_DIR)/connectivity-test
CONNECTIVITY_LIVE_WRITE_TEST_DIR := $(BUILD_DIR)/connectivity-live-write-test
BRIGHTNESS_TEST_DIR := $(BUILD_DIR)/brightness-test
BRIGHTNESS_LIVE_WRITE_TEST_DIR := $(BUILD_DIR)/brightness-live-write-test
SESSION_TEST_DIR := $(BUILD_DIR)/session-test
COORDINATOR_TEST_DIR := $(BUILD_DIR)/coordinator-test
TRANSIENT_TEST_DIR := $(BUILD_DIR)/transient-test
WEATHER_TEST_DIR := $(BUILD_DIR)/weather-test
MEDIA_TEST_DIR := $(BUILD_DIR)/media-test
AUDIO_TEST_DIR := $(BUILD_DIR)/audio-test
AUDIO_LIVE_TEST_DIR := $(BUILD_DIR)/audio-live-test
AUDIO_LIVE_WRITE_TEST_DIR := $(BUILD_DIR)/audio-live-write-test
SURFACE_STATE_TEST_DIR := $(BUILD_DIR)/surface-state-test
UI_PRIMITIVES_TEST_DIR := $(BUILD_DIR)/ui-primitives-test
IDLE_TEST_DIR := $(BUILD_DIR)/idle-test
TRAY_TEST_DIR := $(BUILD_DIR)/tray-test
TRAY_LIVE_TEST_DIR := $(BUILD_DIR)/tray-live-test
TRAY_LIVE_TEST := $(BUILD_DIR)/tray-live-test-runner
APPLICATION_TEST := $(BUILD_DIR)/applications-helper-test
APPLICATION_QML_TEST_DIR := $(BUILD_DIR)/applications-test
LAUNCHER_TEST_DIR := $(BUILD_DIR)/launcher-test
NOTIFICATION_BUILD_DIR := $(BUILD_DIR)/notifications
NOTIFICATION_MODULE_DIR := $(BUILD_DIR)/qml/Nagi/Notifications
NOTIFICATION_PLUGIN := $(NOTIFICATION_MODULE_DIR)/libnaginotificationsplugin.so
NOTIFICATION_RUNTIME_MOC := $(NOTIFICATION_BUILD_DIR)/moc_runtime.cpp
NOTIFICATION_PLUGIN_MOC := $(NOTIFICATION_BUILD_DIR)/plugin.moc
NOTIFICATION_TEST := $(BUILD_DIR)/notification-runtime-test
NOTIFICATION_TEST_MOC := $(NOTIFICATION_BUILD_DIR)/notification_runtime_test.moc
NOTIFICATION_DBUS_TEST := $(BUILD_DIR)/notification-dbus-test
NOTIFICATION_DBUS_TEST_MOC := $(NOTIFICATION_BUILD_DIR)/notifications_dbus_test.moc
NOTIFICATION_QML_TEST_DIR := $(BUILD_DIR)/notifications-test
NOTIFICATION_HISTORY_TEST_DIR := $(BUILD_DIR)/notification-history-test
HELPER_SOURCES := src/kwin-virtual-desktops/main.cpp src/kwin-virtual-desktops/desktop_snapshot.cpp
HELPER_HEADERS := src/kwin-virtual-desktops/desktop_snapshot.h
AUDIO_HELPER_SOURCES := src/pipewire-audio/main.cpp src/pipewire-audio/protocol.cpp src/pipewire-audio/volume.cpp
AUDIO_HELPER_HEADERS := src/pipewire-audio/protocol.h src/pipewire-audio/volume.h
APPLICATION_HELPER_SOURCE := src/applications/main.cpp
NOTIFICATION_SOURCES := src/notifications/runtime.cpp src/notifications/notification_text.cpp
NOTIFICATION_HEADERS := src/notifications/runtime.h src/notifications/notification_text.h
QT_CFLAGS := $(shell $(PKG_CONFIG) --cflags Qt6Core Qt6DBus)
QT_LIBS := $(shell $(PKG_CONFIG) --libs Qt6Core Qt6DBus)
NOTIFICATION_QT_CFLAGS := $(shell $(PKG_CONFIG) --cflags Qt6Core Qt6DBus Qt6Qml)
NOTIFICATION_QT_LIBS := $(shell $(PKG_CONFIG) --libs Qt6Core Qt6DBus Qt6Qml)
TRAY_QT_CFLAGS := $(shell $(PKG_CONFIG) --cflags Qt6Core Qt6Gui Qt6Widgets)
TRAY_QT_LIBS := $(shell $(PKG_CONFIG) --libs Qt6Core Qt6Gui Qt6Widgets)
PIPEWIRE_CFLAGS := $(shell $(PKG_CONFIG) --cflags libpipewire-0.3)
PIPEWIRE_LIBS := $(shell $(PKG_CONFIG) --libs libpipewire-0.3)
GIO_CFLAGS := $(shell $(PKG_CONFIG) --cflags gio-unix-2.0)
GIO_LIBS := $(shell $(PKG_CONFIG) --libs gio-unix-2.0)
NATIVE_CXXFLAGS := -std=c++20 -O2 -Wall -Wextra -Wpedantic
AUDIO_NATIVE_CXXFLAGS := -std=gnu++20 -O2 -Wall -Wextra -Wno-sfinae-incomplete


QUICKSHELL_MIN_VERSION := 0.3.0
QUICKSHELL_CHANNEL := stable
FEDORA_QUICKSHELL_COPR := errornointernet/quickshell
FEDORA_QUICKSHELL_PACKAGE := quickshell

.PHONY: help requirements prepare check-quickshell check-helper-toolchain check-audio-toolchain check-application-toolchain check-launcher-shortcut-toolchain check-notification-toolchain check-tray-toolchain helper audio-helper connectivity-helper brightness-helper session-helper application-helper launcher-shortcut-helper notification-plugin test-native test-owner-lifecycle test-audio-protocol test-audio-volume test-connectivity-dbus test-brightness-dbus test-brightness test-brightness-live-write test-session-dbus test-session test-applications test-launcher test-launcher-shortcut test-notifications test-adapter test-coordinator test-transients test-weather test-media test-audio test-audio-live test-audio-live-write test-connectivity test-connectivity-live-write test-tray test-tray-live test-idle test-surface-state test-ui-primitives check-nondisplay check format format-check lint-advisory launch diagnose instances logs logs-follow stop

help:
	@printf '%s\n' \
		'make requirements    Show and verify runtime/build dependencies' \
		'make helper          Build the KWin virtual desktop helper' \
		'make audio-helper    Build the confirmed PipeWire audio bridge' \
		'make connectivity-helper  Build the Wi-Fi and Bluetooth bridge' \
		'make brightness-helper  Build the PowerDevil brightness bridge' \
		'make session-helper  Build the KDE session action bridge' \
		'make application-helper  Build desktop-entry and persistence bridge' \
		'make launcher-shortcut-helper  Build the KF6 KGlobalAccel launcher shortcut helper' \
		'make notification-plugin  Build the process-scoped notification runtime' \
		'make test-native     Test KWin tuple normalization' \
		'make test-owner-lifecycle  Test KWin owner loss and replacement' \
		'make test-audio-protocol  Test the audio bridge command boundary' \
		'make test-audio-volume  Test proportional average-volume writes' \
		'make test-connectivity-dbus  Test D-Bus state, denial, and lifecycle' \
		'make test-brightness-dbus  Test PowerDevil state, writes, and lifecycle' \
		'make test-brightness  Test normalized brightness adapter state' \
		'make test-brightness-live-write  Change and restore live PowerDevil brightness' \
		'make test-session-dbus  Test KDE session dispatch, denial, and cleanup' \
		'make test-session   Test session service and interaction state' \
		'make test-launcher   Test launcher search, ordering, pin actions, and dispatch' \
		'make test-applications  Test desktop discovery and persistence bridge' \
		'make test-launcher-shortcut  Test KGlobalAccel conflict, persistence, activation, and lifecycle' \
		'make test-notifications  Test notification lifecycle, bounds, and history view' \
		'make test-adapter    Test the QML adapter boundary' \
		'make test-coordinator  Test island ownership and restoration' \
		'make test-transients  Test workspace, brightness, audio, and notification routing' \
		'make test-surface-state  Exercise coordinator in the actual island surface' \
		'make test-weather    Test compact clock and weather adapter state' \
		'make test-media      Test the MPRIS media adapter state' \
		'make test-audio      Test the PipeWire audio adapter state' \
		'make test-audio-live Probe the live PipeWire graph without changing it' \
		'make test-audio-live-write  Change and restore live default audio state' \
		'make test-connectivity  Test Wi-Fi and Bluetooth adapter state' \
		'make test-connectivity-live-write  Change and restore live radios' \
		'make test-tray       Test system tray lifecycle and actions' \
		'make test-tray-live  Exercise a controlled real tray item on KDE' \
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
	@printf 'Install: sudo dnf copr enable %s && sudo dnf install %s pipewire-devel glib2-devel kf6-kglobalaccel-devel qt6-qtbase-devel qt6-qtdeclarative-devel cmake\n' '$(FEDORA_QUICKSHELL_COPR)' '$(FEDORA_QUICKSHELL_PACKAGE)'
	@printf 'Native builds: C++20, Qt 6 Core/DBus/GUI/Widgets/QML, KF6 GlobalAccel, libpipewire 0.3, and GIO Unix development files\n'
	@$(MAKE) --no-print-directory check-quickshell
	@$(MAKE) --no-print-directory check-helper-toolchain
	@$(MAKE) --no-print-directory check-audio-toolchain
	@$(MAKE) --no-print-directory check-application-toolchain
	@$(MAKE) --no-print-directory check-launcher-shortcut-toolchain
	@$(MAKE) --no-print-directory check-notification-toolchain
	@$(MAKE) --no-print-directory check-tray-toolchain

prepare:
	@touch .qmlls.ini

check-helper-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core Qt6DBus
	@test -x '$(MOC)'

check-audio-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core libpipewire-0.3

check-application-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core gio-unix-2.0


check-launcher-shortcut-toolchain:
	@command -v '$(CMAKE)' >/dev/null
	@$(CMAKE) -S src/launcher-shortcut -B '$(LAUNCHER_SHORTCUT_BUILD_DIR)' >/dev/null
check-notification-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core Qt6DBus Qt6Qml
	@test -x '$(MOC)'

check-tray-toolchain:
	@$(PKG_CONFIG) --exists Qt6Core Qt6Gui Qt6Widgets

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(NOTIFICATION_BUILD_DIR):
	mkdir -p $(NOTIFICATION_BUILD_DIR)

$(NOTIFICATION_MODULE_DIR):
	mkdir -p $(NOTIFICATION_MODULE_DIR)

$(HELPER_MOC): src/kwin-virtual-desktops/main.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(OWNER_TEST_MOC): tests/kwin_owner_lifecycle_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(CONNECTIVITY_MOC): src/connectivity/main.cpp | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(MOC) $< -o $@

$(BRIGHTNESS_MOC): src/brightness/main.cpp | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(MOC) $< -o $@

$(SESSION_MOC): src/session/main.cpp | $(BUILD_DIR)
	mkdir -p $(dir $@)
	$(MOC) $< -o $@

$(CONNECTIVITY_DBUS_TEST_MOC): tests/connectivity_dbus_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(BRIGHTNESS_DBUS_TEST_MOC): tests/brightness_dbus_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(SESSION_DBUS_TEST_MOC): tests/session_dbus_test.cpp | $(BUILD_DIR)
	$(MOC) $< -o $@

$(NOTIFICATION_RUNTIME_MOC): src/notifications/runtime.h | $(NOTIFICATION_BUILD_DIR)
	$(MOC) $< -o $@

$(NOTIFICATION_PLUGIN_MOC): src/notifications/plugin.cpp | $(NOTIFICATION_BUILD_DIR)
	$(MOC) $< -o $@

$(NOTIFICATION_TEST_MOC): tests/notification_runtime_test.cpp | $(NOTIFICATION_BUILD_DIR)
	$(MOC) $< -o $@

$(NOTIFICATION_DBUS_TEST_MOC): tests/notifications_dbus_test.cpp | $(NOTIFICATION_BUILD_DIR)
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

$(BRIGHTNESS_HELPER): src/brightness/main.cpp $(BRIGHTNESS_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(dir $(BRIGHTNESS_MOC)) src/brightness/main.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(SESSION_HELPER): src/session/main.cpp $(SESSION_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(dir $(SESSION_MOC)) src/session/main.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(CONNECTIVITY_DBUS_TEST): tests/connectivity_dbus_test.cpp $(CONNECTIVITY_DBUS_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) tests/connectivity_dbus_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(BRIGHTNESS_DBUS_TEST): tests/brightness_dbus_test.cpp $(BRIGHTNESS_DBUS_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) tests/brightness_dbus_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(SESSION_DBUS_TEST): tests/session_dbus_test.cpp $(SESSION_DBUS_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(BUILD_DIR) tests/session_dbus_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(APPLICATION_HELPER): $(APPLICATION_HELPER_SOURCE) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) $(GIO_CFLAGS) $(APPLICATION_HELPER_SOURCE) -o $@ $(LDFLAGS) $(QT_LIBS) $(GIO_LIBS)

$(LAUNCHER_SHORTCUT_HELPER): src/launcher-shortcut/main.cpp src/launcher-shortcut/registration_policy.h src/launcher-shortcut/CMakeLists.txt | $(BUILD_DIR)
	$(CMAKE) -S src/launcher-shortcut -B '$(LAUNCHER_SHORTCUT_BUILD_DIR)'
	$(CMAKE) --build '$(LAUNCHER_SHORTCUT_BUILD_DIR)' --target nagi-launcher-shortcut


$(LAUNCHER_SHORTCUT_TEST): tests/launcher_shortcut_test.cpp src/launcher-shortcut/registration_policy.h src/launcher-shortcut/CMakeLists.txt | $(BUILD_DIR)
	$(CMAKE) -S src/launcher-shortcut -B '$(LAUNCHER_SHORTCUT_BUILD_DIR)'
	$(CMAKE) --build '$(LAUNCHER_SHORTCUT_BUILD_DIR)' --target nagi-launcher-shortcut-test

$(APPLICATION_TEST): tests/applications_helper_test.cpp | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) tests/applications_helper_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(NOTIFICATION_PLUGIN): $(NOTIFICATION_SOURCES) $(NOTIFICATION_HEADERS) src/notifications/plugin.cpp src/notifications/qmldir $(NOTIFICATION_RUNTIME_MOC) $(NOTIFICATION_PLUGIN_MOC) | $(NOTIFICATION_MODULE_DIR)
	cp src/notifications/qmldir $(NOTIFICATION_MODULE_DIR)/qmldir
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) -fPIC -shared $(NOTIFICATION_QT_CFLAGS) -Isrc/notifications -I$(NOTIFICATION_BUILD_DIR) $(NOTIFICATION_SOURCES) src/notifications/plugin.cpp $(NOTIFICATION_RUNTIME_MOC) -o $@ $(LDFLAGS) $(NOTIFICATION_QT_LIBS)

$(NOTIFICATION_TEST): tests/notification_runtime_test.cpp $(NOTIFICATION_TEST_MOC) $(NOTIFICATION_SOURCES) $(NOTIFICATION_HEADERS) $(NOTIFICATION_RUNTIME_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(NOTIFICATION_QT_CFLAGS) -Isrc/notifications -I$(NOTIFICATION_BUILD_DIR) tests/notification_runtime_test.cpp $(NOTIFICATION_SOURCES) $(NOTIFICATION_RUNTIME_MOC) -o $@ $(LDFLAGS) $(NOTIFICATION_QT_LIBS)

$(NOTIFICATION_DBUS_TEST): tests/notifications_dbus_test.cpp $(NOTIFICATION_DBUS_TEST_MOC) | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(QT_CFLAGS) -I$(NOTIFICATION_BUILD_DIR) tests/notifications_dbus_test.cpp -o $@ $(LDFLAGS) $(QT_LIBS)

$(TRAY_LIVE_TEST): tests/tray_live_test.cpp | $(BUILD_DIR)
	$(CXX) $(CPPFLAGS) $(CXXFLAGS) $(NATIVE_CXXFLAGS) $(TRAY_QT_CFLAGS) tests/tray_live_test.cpp -o $@ $(LDFLAGS) $(TRAY_QT_LIBS)

helper: check-helper-toolchain $(HELPER)

audio-helper: check-audio-toolchain $(AUDIO_HELPER)

connectivity-helper: check-helper-toolchain $(CONNECTIVITY_HELPER)

brightness-helper: check-helper-toolchain $(BRIGHTNESS_HELPER)

session-helper: check-helper-toolchain $(SESSION_HELPER)

application-helper: check-application-toolchain $(APPLICATION_HELPER)

launcher-shortcut-helper: check-launcher-shortcut-toolchain $(LAUNCHER_SHORTCUT_HELPER)

notification-plugin: check-notification-toolchain $(NOTIFICATION_PLUGIN)

test-applications: check-application-toolchain $(APPLICATION_HELPER) $(APPLICATION_TEST)
	$(APPLICATION_TEST) $(abspath $(APPLICATION_HELPER))
	rm -rf $(APPLICATION_QML_TEST_DIR)
	mkdir -p $(APPLICATION_QML_TEST_DIR)/qml $(APPLICATION_QML_TEST_DIR)/empty-data
	cp -R tests/applications/fixtures/. $(APPLICATION_QML_TEST_DIR)/
	chmod 0700 $(APPLICATION_QML_TEST_DIR)/config/nagi-shell $(APPLICATION_QML_TEST_DIR)/state/nagi-shell
	chmod 0600 $(APPLICATION_QML_TEST_DIR)/config/nagi-shell/application-pins.json $(APPLICATION_QML_TEST_DIR)/state/nagi-shell/application-recency.json
	cp tests/applications/shell.qml $(APPLICATION_QML_TEST_DIR)/shell.qml
	cp qml/ApplicationModel.qml qml/ApplicationBridge.qml $(APPLICATION_QML_TEST_DIR)/qml/
	XDG_DATA_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/data' XDG_DATA_DIRS='$(abspath $(APPLICATION_QML_TEST_DIR))/empty-data' XDG_CONFIG_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/config' XDG_STATE_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/state' HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/home' XDG_CURRENT_DESKTOP='KDE' NAGI_APPLICATION_HELPER='$(abspath $(APPLICATION_HELPER))' NAGI_APPLICATION_TEST_PHASE='mutate' $(QS) -p $(APPLICATION_QML_TEST_DIR) --no-duplicate
	XDG_DATA_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/data' XDG_DATA_DIRS='$(abspath $(APPLICATION_QML_TEST_DIR))/empty-data' XDG_CONFIG_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/config' XDG_STATE_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/state' HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/home' XDG_CURRENT_DESKTOP='KDE' NAGI_APPLICATION_HELPER='$(abspath $(APPLICATION_HELPER))' NAGI_APPLICATION_TEST_PHASE='restart' $(QS) -p $(APPLICATION_QML_TEST_DIR) --no-duplicate
	chmod 0644 $(APPLICATION_QML_TEST_DIR)/config/nagi-shell/application-pins.json
	XDG_DATA_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/data' XDG_DATA_DIRS='$(abspath $(APPLICATION_QML_TEST_DIR))/empty-data' XDG_CONFIG_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/config' XDG_STATE_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/state' HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/home' XDG_CURRENT_DESKTOP='KDE' NAGI_APPLICATION_HELPER='$(abspath $(APPLICATION_HELPER))' NAGI_APPLICATION_TEST_PHASE='unsafe' $(QS) -p $(APPLICATION_QML_TEST_DIR) --no-duplicate
	rm -rf $(APPLICATION_QML_TEST_DIR)/default-home
	mkdir -p $(APPLICATION_QML_TEST_DIR)/default-home
	XDG_DATA_HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/data' XDG_DATA_DIRS='$(abspath $(APPLICATION_QML_TEST_DIR))/empty-data' XDG_CONFIG_HOME='relative-config' XDG_STATE_HOME='relative-state' HOME='$(abspath $(APPLICATION_QML_TEST_DIR))/default-home' XDG_CURRENT_DESKTOP='KDE' NAGI_APPLICATION_HELPER='$(abspath $(APPLICATION_HELPER))' NAGI_APPLICATION_TEST_PHASE='defaults' $(QS) -p $(APPLICATION_QML_TEST_DIR) --no-duplicate

test-notifications: check-quickshell check-notification-toolchain $(NOTIFICATION_PLUGIN) $(NOTIFICATION_TEST) $(NOTIFICATION_DBUS_TEST)
	$(NOTIFICATION_TEST)
	rm -rf $(NOTIFICATION_HISTORY_TEST_DIR)
	mkdir -p $(NOTIFICATION_HISTORY_TEST_DIR)/qml
	cp tests/notification-history/shell.qml $(NOTIFICATION_HISTORY_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/NotificationHistoryView.qml $(NOTIFICATION_HISTORY_TEST_DIR)/qml/
	$(QS) -p $(NOTIFICATION_HISTORY_TEST_DIR) --no-duplicate
	rm -rf $(NOTIFICATION_QML_TEST_DIR)
	mkdir -p $(NOTIFICATION_QML_TEST_DIR)/qml
	cp tests/notifications/shell.qml $(NOTIFICATION_QML_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/NotificationHistoryView.qml qml/NotificationService.qml $(NOTIFICATION_QML_TEST_DIR)/qml/
	QT_QPA_PLATFORM='offscreen' GTK_USE_PORTAL='0' $(DBUS_RUN_SESSION) -- env QML_IMPORT_PATH='$(abspath $(BUILD_DIR)/qml)' $(NOTIFICATION_DBUS_TEST) '$(QS)' '$(abspath $(NOTIFICATION_QML_TEST_DIR))'

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

test-brightness-dbus: check-helper-toolchain $(BRIGHTNESS_HELPER) $(BRIGHTNESS_DBUS_TEST)
	@command -v '$(DBUS_RUN_SESSION)' >/dev/null
	$(DBUS_RUN_SESSION) -- $(BRIGHTNESS_DBUS_TEST) $(abspath $(BRIGHTNESS_HELPER))

test-session-dbus: check-helper-toolchain $(SESSION_HELPER) $(SESSION_DBUS_TEST)
	@command -v '$(DBUS_RUN_SESSION)' >/dev/null
	$(DBUS_RUN_SESSION) -- $(SESSION_DBUS_TEST) $(abspath $(SESSION_HELPER))

test-session: check-quickshell | $(BUILD_DIR)
	mkdir -p $(SESSION_TEST_DIR)/qml
	cp tests/session/shell.qml $(SESSION_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/SessionBridge.qml qml/SessionService.qml qml/SessionEntry.qml qml/SessionView.qml $(SESSION_TEST_DIR)/qml/
	$(QS) -p $(SESSION_TEST_DIR) --no-duplicate

test-adapter: check-quickshell | $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)/adapter-test/qml
	cp tests/adapter/shell.qml $(BUILD_DIR)/adapter-test/shell.qml
	cp qml/KWinVirtualDesktopAdapter.qml $(BUILD_DIR)/adapter-test/qml/KWinVirtualDesktopAdapter.qml
	$(QS) -p $(BUILD_DIR)/adapter-test --no-duplicate

test-brightness: check-quickshell | $(BUILD_DIR)
	mkdir -p $(BRIGHTNESS_TEST_DIR)/qml
	cp tests/brightness/shell.qml $(BRIGHTNESS_TEST_DIR)/shell.qml
	cp qml/BrightnessBridge.qml qml/BrightnessAdapter.qml $(BRIGHTNESS_TEST_DIR)/qml/
	$(QS) -p $(BRIGHTNESS_TEST_DIR) --no-duplicate

test-coordinator: check-quickshell | $(BUILD_DIR)
	mkdir -p $(COORDINATOR_TEST_DIR)/qml
	cp tests/coordinator/shell.qml $(COORDINATOR_TEST_DIR)/shell.qml
	cp qml/IslandStateCoordinator.qml $(COORDINATOR_TEST_DIR)/qml/
	$(QS) -p $(COORDINATOR_TEST_DIR) --no-duplicate

test-transients: check-quickshell | $(BUILD_DIR)
	mkdir -p $(TRANSIENT_TEST_DIR)/qml
	cp tests/transients/shell.qml $(TRANSIENT_TEST_DIR)/shell.qml
	cp qml/IslandStateCoordinator.qml qml/TransientCoordinatorBridge.qml $(TRANSIENT_TEST_DIR)/qml/
	$(QS) -p $(TRANSIENT_TEST_DIR) --no-duplicate

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

test-brightness-live-write: check-quickshell brightness-helper | $(BUILD_DIR)
	mkdir -p $(BRIGHTNESS_LIVE_WRITE_TEST_DIR)/qml
	cp tests/brightness/live-write.qml $(BRIGHTNESS_LIVE_WRITE_TEST_DIR)/shell.qml
	cp qml/BrightnessBridge.qml qml/BrightnessAdapter.qml $(BRIGHTNESS_LIVE_WRITE_TEST_DIR)/qml/
	NAGI_BRIGHTNESS_HELPER='$(abspath $(BRIGHTNESS_HELPER))' $(QS) -p $(BRIGHTNESS_LIVE_WRITE_TEST_DIR) --no-duplicate

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

test-tray: check-quickshell | $(BUILD_DIR)
	mkdir -p $(TRAY_TEST_DIR)/qml
	cp tests/tray/shell.qml $(TRAY_TEST_DIR)/shell.qml
	cp qml/TrayAdapter.qml $(TRAY_TEST_DIR)/qml/
	$(QS) -p $(TRAY_TEST_DIR) --no-duplicate

test-tray-live: check-quickshell check-tray-toolchain $(TRAY_LIVE_TEST) | $(BUILD_DIR)
	mkdir -p $(TRAY_LIVE_TEST_DIR)/qml
	cp tests/tray/live.qml $(TRAY_LIVE_TEST_DIR)/shell.qml
	cp qml/TrayAdapter.qml $(TRAY_LIVE_TEST_DIR)/qml/
	$(TRAY_LIVE_TEST) '$(QS)' '$(abspath $(TRAY_LIVE_TEST_DIR))'

test-launcher-shortcut: check-launcher-shortcut-toolchain $(LAUNCHER_SHORTCUT_HELPER) $(LAUNCHER_SHORTCUT_TEST)
	rm -rf $(LAUNCHER_SHORTCUT_TEST_DIR)
	mkdir -p $(LAUNCHER_SHORTCUT_TEST_DIR)/config
	QT_QPA_PLATFORM='offscreen' QT_ACCESSIBILITY='0' GTK_USE_PORTAL='0' XDG_CURRENT_DESKTOP='KDE' XDG_CONFIG_HOME='$(abspath $(LAUNCHER_SHORTCUT_TEST_DIR))/config' $(DBUS_RUN_SESSION) -- $(LAUNCHER_SHORTCUT_TEST) '$(abspath $(LAUNCHER_SHORTCUT_HELPER))'

test-launcher: check-quickshell | $(BUILD_DIR)
	rm -rf $(LAUNCHER_TEST_DIR)
	mkdir -p $(LAUNCHER_TEST_DIR)/qml
	cp tests/launcher/shell.qml $(LAUNCHER_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/LauncherView.qml qml/LauncherShortcutAdapter.qml $(LAUNCHER_TEST_DIR)/qml/
	QT_QPA_PLATFORM='offscreen' $(QS) -p $(LAUNCHER_TEST_DIR) --no-duplicate

test-surface-state: check-quickshell | $(BUILD_DIR)
	mkdir -p $(SURFACE_STATE_TEST_DIR)/qml
	cp tests/surface-state/shell.qml $(SURFACE_STATE_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IslandProgressBar.qml qml/TransientView.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/DashboardRegion.qml qml/ExpandedDashboard.qml qml/LauncherView.qml qml/NotificationHistoryView.qml qml/SessionView.qml qml/IdleIsland.qml qml/IdleMediaText.qml qml/WeatherGlyph.qml qml/IslandStateCoordinator.qml qml/IslandSurfaceHost.qml qml/IslandSurface.qml $(SURFACE_STATE_TEST_DIR)/qml/
	$(QS) -p $(SURFACE_STATE_TEST_DIR) --no-duplicate

test-ui-primitives: check-quickshell | $(BUILD_DIR)
	mkdir -p $(UI_PRIMITIVES_TEST_DIR)/qml
	cp tests/ui/shell.qml $(UI_PRIMITIVES_TEST_DIR)/shell.qml
	cp qml/Theme.qml qml/IslandPanel.qml qml/IslandText.qml qml/IdleIsland.qml qml/IdleMediaText.qml qml/WeatherGlyph.qml qml/IslandFocusRing.qml qml/IslandButton.qml qml/IslandIconButton.qml qml/IslandProgressBar.qml qml/TransientView.qml qml/DashboardRegion.qml qml/ExpandedDashboard.qml qml/LauncherView.qml qml/NotificationHistoryView.qml qml/SessionView.qml qml/IslandStateCoordinator.qml qml/IslandSurface.qml qml/TrayView.qml $(UI_PRIMITIVES_TEST_DIR)/qml/
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

launch: check-quickshell prepare helper audio-helper connectivity-helper brightness-helper session-helper application-helper launcher-shortcut-helper notification-plugin
	QML_IMPORT_PATH='$(abspath $(BUILD_DIR)/qml)' $(QS) -p . --no-duplicate

diagnose: check-quickshell prepare helper audio-helper connectivity-helper brightness-helper session-helper application-helper launcher-shortcut-helper notification-plugin
	QML_IMPORT_PATH='$(abspath $(BUILD_DIR)/qml)' $(QS) -p . --no-duplicate -vv --log-times

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

check-nondisplay: check-quickshell format-check audio-helper connectivity-helper brightness-helper session-helper application-helper launcher-shortcut-helper notification-plugin test-native test-owner-lifecycle test-audio-protocol test-audio-volume test-connectivity-dbus test-brightness-dbus test-brightness test-session-dbus test-session test-applications test-launcher test-launcher-shortcut test-notifications test-adapter test-coordinator test-transients test-weather test-media test-audio test-connectivity test-tray test-idle

clean:
	rm -rf $(BUILD_DIR)
