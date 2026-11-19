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
    spacing: 8

    Label {
        text: qsTr("Stream:")
        opacity: 0.7
        Layout.alignment: Qt.AlignVCenter
    }

    Repeater {
        model: Presets.list
        delegate: Button {
            required property var modelData
            readonly property bool active: Presets.matches(Chiaki.settings, modelData)
            text: qsTr(modelData.name)
            checkable: true
            checked: active
            highlighted: active
            flat: !active
            focusPolicy: Qt.NoFocus
            Material.roundedScale: Material.SmallScale
            onClicked: Presets.apply(Chiaki.settings, modelData)
            ToolTip.visible: hovered
            ToolTip.delay: 400
            ToolTip.text: qsTr(modelData.hint)
        }
    }

    Label {
        text: qsTr("Custom")
        opacity: 0.5
        visible: !Presets.list.some(p => Presets.matches(Chiaki.settings, p))
        Layout.alignment: Qt.AlignVCenter
    }
}
