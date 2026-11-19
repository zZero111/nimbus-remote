import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking
import "presets.js" as Presets

// One-click PS5 stream quality presets shown on the home screen.
// Each preset sets resolution, frame rate, bitrate and codec for both
// local (home network) and remote (internet) play in one go.
RowLayout {
    id: bar
    spacing: 10

    Label {
        text: qsTr("STREAM")
        font.pixelSize: 11
        font.bold: true
        font.letterSpacing: 1.6
        opacity: 0.45
        Layout.alignment: Qt.AlignVCenter
    }

    // Segmented control
    Rectangle {
        radius: 19
        color: Qt.rgba(0, 0, 0, 0.35)
        border.color: Qt.rgba(1, 1, 1, 0.12)
        implicitHeight: 38
        implicitWidth: segs.implicitWidth + 8
        Row {
            id: segs
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: Presets.list
                delegate: Rectangle {
                    id: seg
                    required property var modelData
                    readonly property bool active: Presets.matches(Chiaki.settings, modelData)
                    radius: 15
                    height: 30
                    width: segText.implicitWidth + 30
                    color: active ? "white" : (segMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Label {
                        id: segText
                        anchors.centerIn: parent
                        text: qsTr(seg.modelData.name)
                        font.pixelSize: 14
                        font.bold: seg.active
                        color: seg.active ? "#0b0f17" : Qt.rgba(1, 1, 1, 0.75)
                    }
                    MouseArea {
                        id: segMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Presets.apply(Chiaki.settings, seg.modelData)
                    }
                    ToolTip.visible: segMouse.containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: qsTr(seg.modelData.hint)
                }
            }
        }
    }

    Label {
        text: qsTr("Custom")
        font.pixelSize: 13
        opacity: 0.5
        visible: !Presets.list.some(p => Presets.matches(Chiaki.settings, p))
        Layout.alignment: Qt.AlignVCenter
    }
}
