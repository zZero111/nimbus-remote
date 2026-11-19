import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

Item {
    id: dialog
    property alias header: headerLabel.text
    property alias title: titleLabel.text
    property alias buttonText: okButton.text
    property alias buttonEnabled: okButton.enabled
    property alias buttonVisible: okButton.visible
    property Item restoreFocusItem
    default property Item mainItem: null

    signal accepted()
    signal rejected()

    function close() {
        root.closeDialog();
    }

    Keys.onEscapePressed: close()

    Keys.onMenuPressed: {
        if (okButton.enabled)
            okButton.clicked()
    }

    StackView.onDeactivating: {
        restoreFocusItem = Window.window.activeFocusItem;
    }

    StackView.onActivated: {
        if (!restoreFocusItem) {
            let item = mainItem.nextItemInFocusChain();
            if (item)
                item.forceActiveFocus(Qt.TabFocusReason);
        } else {
            restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
            restoreFocusItem = null;
        }
    }

    onMainItemChanged: {
        if (mainItem) {
            mainItem.parent = dialogContent;
            mainItem.anchors.fill = dialogContent;
        }
    }

    // Text grows with the window so dialogs stay readable on large monitors
    // (1.0 up to a 1600x900 window, at most 1.4x)
    readonly property real ui: Math.max(1.0, Math.min(1.4, Math.min(width / 1600, height / 900)))

    // Controls and labels inside inherit this font size
    Control {
    id: fontScope
    anchors.fill: parent
    padding: 0
    font.pixelSize: Math.round(15 * dialog.ui)

    // PS5-style backdrop shared by every full-screen dialog (settings, registration, ...)
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#123a78" }
            GradientStop { position: 0.45; color: "#0a1f48" }
            GradientStop { position: 1.0; color: "#020814" }
        }
    }

    Item {
        id: toolBar
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 84

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 20
                rightMargin: 24
            }
            spacing: 14

            RoundButton {
                flat: true
                implicitWidth: 52
                implicitHeight: 52
                text: "❮"
                font.pixelSize: 22
                focusPolicy: Qt.NoFocus
                onClicked: {
                    dialog.rejected();
                    dialog.close();
                }
                ToolTip.visible: hovered
                ToolTip.delay: 400
                ToolTip.text: qsTr("Back (Circle / Esc)")
            }

            Label {
                id: titleLabel
                font.pixelSize: 30
                font.weight: Font.Light
            }

            Label {
                id: headerLabel
                Layout.fillWidth: true
                Layout.leftMargin: 18
                elide: Text.ElideRight
                font.pixelSize: 13
                color: Qt.rgba(1, 1, 1, 0.5)
            }

            Button {
                id: okButton
                padding: 14
                leftPadding: 20
                rightPadding: 22
                font.pixelSize: 18
                font.weight: Font.DemiBold
                focusPolicy: Qt.NoFocus
                Material.background: "white"
                Material.foreground: "#0b0f17"
                Material.roundedScale: Material.SmallScale
                onClicked: dialog.accepted()
                icon.source: "qrc:/icons/options.svg";
                icon.width: 28
                icon.height: 28
                icon.color: "transparent"
            }
        }
    }

    Item {
        id: dialogContent
        anchors {
            top: toolBar.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
    }
    } // fontScope
}
