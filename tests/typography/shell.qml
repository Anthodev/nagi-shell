import Quickshell
import QtQuick
import QtQuick.Layouts
import "qml"

ShellRoot {
    id: root

    readonly property bool holdForCapture: Quickshell.env("NAGI_TYPOGRAPHY_HOLD") === "1"
    property bool checked: false
    readonly property int captureWidth: 700
    readonly property int captureHeight: 480

    function fail(message) {
        console.error("FAIL: " + message);
        Qt.exit(1);
    }
    function require(condition, message) {
        if (!condition) {
            fail(message);
        }
    }

    function verifyScopedTypography() {
        const previous = UserConfig.snapshot;
        const candidate = UserConfig.mutableSnapshot(previous);
        candidate.appearance.idleFontFamily = interLoader.name;
        candidate.appearance.idleBaseFontSize = 11;
        candidate.appearance.expandedFontFamily = notoLoader.name;
        candidate.appearance.expandedBaseFontSize = 16;
        candidate.appearance.controlCenterFontFamily = sourceSansLoader.name;
        candidate.appearance.controlCenterBaseFontSize = 18;
        const normalized = UserConfig.validateCandidate(candidate);
        require(normalized !== null, "scoped typography fixture satisfies settings bounds");
        UserConfig.publish(normalized);
        require(Theme.type.familyFor("idle") === interLoader.name && Theme.type.familyFor(
                    "expanded") === notoLoader.name && Theme.type.familyFor("controlCenter")
                === sourceSansLoader.name,
                "each typography scope resolves its selected installed family");
        require(Theme.type.sizeFor("idle", "body") === 11 && Theme.type.sizeFor("expanded", "body")
                === 16 && Theme.type.sizeFor("controlCenter", "body") === 18,
                "each typography scope resolves its independent base size");
        require(Theme.type.sizeFor("idle", "caption") === Math.round(11 * 11 / 13) && Theme.type.sizeFor(
                    "expanded", "title") === Math.round(16 * 15 / 13) && Theme.type.sizeFor("controlCenter",
                                                                                            "display")
                === Math.round(18 * 48 / 13) && Theme.type.sizeFor("controlCenter", "muted")
                === Theme.type.sizeFor("controlCenter", "caption"),
                "semantic and muted roles preserve their proportional scale");
        require(Theme.type.scopeFor(idleProbe) === "idle" && Theme.type.scopeFor(expandedProbe)
                === "expanded" && Theme.type.scopeFor(controlCenterProbe) === "controlCenter",
                "descendants resolve the nearest explicit typography scope");
        UserConfig.publish(previous);
    }

    function verifyLoaders() {
        if (interLoader.status !== FontLoader.Ready || notoLoader.status !== FontLoader.Ready
                || sourceSansLoader.status !== FontLoader.Ready) {
            return;
        }

        verifyScopedTypography();
        checked = true;
        readyPoll.running = false;
        guard.running = false;
        console.log("typography matrix font loaders ready");
        if (!holdForCapture) {
            Qt.exit(0);
        }
    }

    FontLoader {
        id: interLoader

        source: "fonts/Inter-Regular.ttf"
    }

    FontLoader {
        id: notoLoader

        source: "fonts/NotoSans-Regular.ttf"
    }

    FontLoader {
        id: sourceSansLoader

        source: "fonts/SourceSans3-Regular.ttf"
    }
    Item {
        id: idleScope
        readonly property string nagiTypographyScope: "idle"
        Item {
            id: idleProbe
        }
    }

    Item {
        id: expandedScope
        readonly property string nagiTypographyScope: "expanded"
        Item {
            id: expandedProbe
        }
    }

    Item {
        id: controlCenterScope
        readonly property string nagiTypographyScope: "controlCenter"
        Item {
            id: controlCenterProbe
        }
    }

    Timer {
        id: readyPoll

        interval: 50
        repeat: true
        running: true
        onTriggered: root.verifyLoaders()
    }

    Timer {
        id: guard

        interval: 5000
        running: true
        onTriggered: root.fail("typography font loaders did not become ready")
    }

    component CandidateColumn: Rectangle {
        id: candidate
        required property string candidateName
        required property string primaryFamily
        required property string fallbackChain

        color: Theme.color.surface
        radius: Theme.radius.md
        border.width: Theme.size.hairlineWidth
        border.color: Theme.color.surfaceBorder
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacing.sm
            spacing: Theme.spacing.xs

            Text {
                text: parent.parent.candidateName
                color: Theme.color.textPrimary
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.title
                font.weight: Theme.type.weightSemibold
            }

            Text {
                text: candidate.fallbackChain
                color: Theme.color.textMuted
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.caption
                font.weight: Theme.type.weightRegular
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Rectangle {
                color: Theme.color.surfaceHover
                radius: Theme.radius.sm
                Layout.fillWidth: true
                implicitHeight: Theme.size.controlHeightLg

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacing.sm
                    spacing: Theme.spacing.xs

                    Rectangle {
                        color: Theme.snapshot.accent
                        radius: Theme.radius.sm
                        implicitWidth: Theme.size.iconSizeMd
                        implicitHeight: Theme.size.iconSizeMd
                    }

                    Text {
                        text: "Workspace 2"
                        color: Theme.color.textPrimary
                        font.family: candidate.primaryFamily
                        font.pixelSize: Theme.type.body
                        font.weight: Theme.type.weightMedium
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "09:41"
                        color: Theme.color.textPrimary
                        font.family: candidate.primaryFamily
                        font.pixelSize: Theme.type.body
                        font.weight: Theme.type.weightSemibold
                    }

                    Text {
                        text: "21° Cloudy"
                        color: Theme.color.textSecondary
                        font.family: candidate.primaryFamily
                        font.pixelSize: Theme.type.caption
                        font.weight: Theme.type.weightRegular
                    }
                }
            }

            Text {
                text: "18:42"
                color: Theme.color.textPrimary
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.display
                font.weight: Theme.type.weightRegular
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Saturday, 23 August"
                color: Theme.color.textSecondary
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.caption
                font.weight: Theme.type.weightMedium
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Boards of Canada — Dayvan Cowboy"
                color: Theme.color.textPrimary
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.title
                font.weight: Theme.type.weightSemibold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Text {
                text: "MusicBox USB DAC  •  Built-in Microphone"
                color: Theme.color.textSecondary
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.body
                font.weight: Theme.type.weightRegular
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Rectangle {
                color: Theme.color.controlFill
                radius: Theme.radius.sm
                Layout.fillWidth: true
                implicitHeight: notificationColumn.implicitHeight + Theme.spacing.md * 2

                ColumnLayout {
                    id: notificationColumn

                    anchors.fill: parent
                    anchors.margins: Theme.spacing.sm
                    spacing: Theme.spacing.xs

                    Text {
                        text: "Signal"
                        color: Theme.color.textMuted
                        font.family: candidate.primaryFamily
                        font.pixelSize: Theme.type.caption
                        font.weight: Theme.type.weightMedium
                    }

                    Text {
                        text: "Maya sent a message"
                        color: Theme.color.textPrimary
                        font.family: candidate.primaryFamily
                        font.pixelSize: Theme.type.title
                        font.weight: Theme.type.weightSemibold
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    Text {
                        text: "The next release candidate is ready for a quick visual comparison before we lock the shell typeface."
                        color: Theme.color.textSecondary
                        font.family: candidate.primaryFamily
                        font.pixelSize: Theme.type.caption
                        font.weight: Theme.type.weightRegular
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
            }

            Text {
                text: "00:00  100%  −12.5 dB"
                color: Theme.snapshot.accent
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.title
                font.weight: Theme.type.weightMedium
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "مرحبا — नमस्ते — こんにちは"
                color: Theme.color.textSecondary
                font.family: candidate.primaryFamily
                font.pixelSize: Theme.type.caption
                font.weight: Theme.type.weightRegular
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }
        }
    }

    PanelWindow {
        id: window

        anchors {
            top: true
            left: true
        }
        color: Theme.color.surface
        exclusiveZone: 0
        implicitWidth: root.captureWidth
        implicitHeight: root.captureHeight

        Rectangle {
            anchors.fill: parent
            color: Theme.color.surface
            radius: Theme.radius.outer
            border.width: Theme.size.hairlineWidth
            border.color: Theme.color.surfaceBorder

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Theme.spacing.lg
                spacing: Theme.spacing.md

                Text {
                    text: "Nagi typography matrix"
                    color: Theme.color.textPrimary
                    font.pixelSize: Theme.type.title
                    font.weight: Theme.type.weightSemibold
                }

                Text {
                    text: "Idle • Expanded • notification • numerals • non-Latin  |  Qt logical pixels"
                    color: Theme.color.textMuted
                    font.pixelSize: Theme.type.caption
                    font.weight: Theme.type.weightRegular
                }

                RowLayout {
                    spacing: Theme.spacing.sm
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    CandidateColumn {
                        candidateName: "Inter"
                        primaryFamily: "Inter"
                        fallbackChain: "Inter → Noto Sans → DejaVu Sans → sans-serif"
                    }

                    CandidateColumn {
                        candidateName: "Noto Sans"
                        primaryFamily: "Noto Sans"
                        fallbackChain: "Noto Sans → Inter → DejaVu Sans → sans-serif"
                    }

                    CandidateColumn {
                        candidateName: "Source Sans 3"
                        primaryFamily: "Source Sans 3"
                        fallbackChain: "Source Sans 3 → Noto Sans → DejaVu Sans → sans-serif"
                    }
                }
            }
        }
    }
}
