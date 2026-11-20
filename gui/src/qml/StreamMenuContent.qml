import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material

import org.streetpea.chiaking

// In-game menu, laid out like the PS5 control center: a dark panel along the bottom with the
// connection at the top and a row of large cards. Left/right moves between cards, Cross/Enter
// presses one, up/down changes the volume or zoom on those cards, Circle/Esc closes the menu.
// Shared by the inline menu (Vulkan) and the separate menu window (OpenGL).
FocusScope {
    id: menu

    signal closeRequested()
    signal mainViewRequested()
    signal displaySettingsRequested()
    signal placeboSettingsRequested()

    property alias initialFocusItem: closeCard

    readonly property var presets: [
        { value: ChiakiWindow.VideoPreset.Default, name: qsTr("Fast picture"), tip: qsTr("Lightest on the GPU") },
        { value: ChiakiWindow.VideoPreset.HighQuality, name: qsTr("Sharp picture"), tip: qsTr("High-quality scaling and debanding") },
        { value: ChiakiWindow.VideoPreset.HighQualitySpatial, name: qsTr("Upscale"), tip: qsTr("When the window is bigger than the stream, sharpens it with AMD FSR, or the FSRCNNX AI upscaler for big jumps (1080p to 1440p/4K)") },
        { value: ChiakiWindow.VideoPreset.HighQualityAdvancedSpatial, name: qsTr("Upscale Max"), tip: qsTr("Like Upscale with the larger FSRCNNX AI model: sharpest, needs a strong GPU") },
        { value: ChiakiWindow.VideoPreset.Custom, name: qsTr("Custom picture"), tip: qsTr("Your own libplacebo settings") }
    ]
    function presetIndex() {
        for (let i = 0; i < presets.length; i++)
            if (presets[i].value === Chiaki.window.videoPreset)
                return i;
        return 0;
    }
    function cyclePreset() {
        const next = presets[(presetIndex() + 1) % presets.length].value;
        Chiaki.window.videoPreset = next;
        Chiaki.settings.videoPreset = next;
    }

    // Left/right between the cards that are currently shown
    readonly property var order: [closeCard, volumeCard, micCard, statsCard, snapCard, recCard, replayCard, clipCard, lighterCard, pictureCard, sharpCard, advancedCard, zoomCard, zoomLevelCard, stretchCard, displayCard]
    function move(from, step) {
        const list = order.filter(c => c.visible && c.enabled);
        let i = list.indexOf(from);
        if (i < 0)
            i = 0;
        const next = list[(i + step + list.length) % list.length];
        if (next)
            next.forceActiveFocus(Qt.TabFocusReason);
    }

    // Scroll the card row so `card` is fully visible (with some margin)
    function ensureVisible(card) {
        const left = card.x + cards.x - 40;
        const right = card.x + cards.x + card.width + 40;
        const maxX = Math.max(0, cardsFlick.contentWidth - cardsFlick.width);
        if (left < cardsFlick.contentX)
            cardsFlick.contentX = Math.max(0, left);
        else if (right > cardsFlick.contentX + cardsFlick.width)
            cardsFlick.contentX = Math.min(maxX, right - cardsFlick.width);
    }

    Keys.onEscapePressed: closeRequested()
    Keys.onMenuPressed: closeRequested()

    // Panel
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0.03, 0.05, 0.10, 0.90) }
            GradientStop { position: 1.0; color: Qt.rgba(0.02, 0.03, 0.06, 0.97) }
        }
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 1
            color: Qt.rgba(1, 1, 1, 0.14)
        }
    }

    // ---- Top line: console + live connection numbers ----
    RowLayout {
        id: infoRow
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            leftMargin: 40
            rightMargin: 40
            topMargin: 16
        }
        spacing: 14

        Rectangle {
            width: 10
            height: 10
            radius: 5
            color: Chiaki.session && Chiaki.session.connected ? "#2ecc71" : "#f0a92e"
        }
        Label {
            text: {
                if (!Chiaki.session)
                    return "";
                const host = Chiaki.settings.streamerMode ? qsTr("hidden") : Chiaki.session.host;
                return Chiaki.session.connected ? qsTr("Connected to %1").arg(host) : qsTr("Connecting to %1…").arg(host);
            }
            font.pixelSize: 17
            font.weight: Font.DemiBold
        }

        Item { Layout.fillWidth: true }

        component Stat: RowLayout {
            property string caption
            property string value
            property color valueColor: "white"
            spacing: 6
            Label {
                text: parent.caption
                font.pixelSize: 14
                color: Qt.rgba(1, 1, 1, 0.55)
            }
            Label {
                text: parent.value
                font.pixelSize: 16
                font.weight: Font.DemiBold
                color: parent.valueColor
            }
        }

        Stat {
            visible: !!Chiaki.session
            caption: qsTr("Bitrate")
            value: Chiaki.session ? qsTr("%1 Mbps").arg(Chiaki.session.measuredBitrate.toFixed(1)) : ""
        }
        Stat {
            readonly property real ping: Chiaki.session ? Chiaki.session.pingMs : 0
            visible: ping > 0
            caption: qsTr("Ping")
            value: qsTr("%1 ms").arg(ping.toFixed(0))
            valueColor: ping < 30 ? "#a5d6a7" : (ping < 80 ? "#ffe082" : "#ef9a9a")
        }
        Stat {
            readonly property real loss: (Chiaki.session && isFinite(Chiaki.session.averagePacketLoss)) ? Chiaki.session.averagePacketLoss : 0
            visible: !!Chiaki.session
            caption: qsTr("Packet loss")
            value: (loss * 100).toFixed(1) + "%"
            valueColor: loss < 0.01 ? "#a5d6a7" : (loss < 0.05 ? "#ffe082" : "#ef9a9a")
        }
        Stat {
            visible: Chiaki.window.droppedFrames > 0
            caption: qsTr("Dropped")
            value: Chiaki.window.droppedFrames
            valueColor: "#ef9a9a"
        }
    }

    // ---- Card row ----
    component Card: AbstractButton {
        id: card
        property string iconSource
        property string caption
        property bool lit: false       // feature switched on: blue card
        property int cardWidth: 112
        focusPolicy: Qt.StrongFocus
        activeFocusOnTab: true
        implicitWidth: cardWidth
        implicitHeight: 112
        opacity: enabled ? 1.0 : 0.4
        scale: activeFocus ? 1.07 : (pressed ? 0.96 : 1.0)
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

        Keys.onLeftPressed: menu.move(card, -1)
        Keys.onRightPressed: menu.move(card, 1)
        Keys.onReturnPressed: clicked()
        Keys.onEnterPressed: clicked()
        Keys.onEscapePressed: menu.closeRequested()
        onHoveredChanged: if (hovered) forceActiveFocus(Qt.MouseFocusReason)
        onActiveFocusChanged: if (activeFocus) menu.ensureVisible(card)

        background: Rectangle {
            radius: 18
            color: card.lit ? "#0070d1" : (card.activeFocus ? Qt.rgba(1, 1, 1, 0.20) : Qt.rgba(1, 1, 1, 0.08))
            Behavior on color { ColorAnimation { duration: 120 } }
            // White focus ring, as on the PS5
            Rectangle {
                anchors.fill: parent
                anchors.margins: -4
                radius: parent.radius + 4
                color: "transparent"
                border.width: 3
                border.color: "white"
                visible: card.activeFocus
            }
        }
        contentItem: Item {
            Image {
                id: cardIcon
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 22
                }
                width: 34
                height: 34
                sourceSize: Qt.size(68, 68)
                source: card.iconSource
            }
            Label {
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    bottomMargin: 14
                    leftMargin: 6
                    rightMargin: 6
                }
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: card.caption
                font.pixelSize: 13
                font.weight: card.activeFocus ? Font.DemiBold : Font.Normal
                color: "white"
            }
        }
        ToolTip.visible: hovered && ToolTip.text.length > 0
        ToolTip.delay: 500
    }

    // Scrolls sideways when the cards don't fit; the selected card is kept in view
    Flickable {
        id: cardsFlick
        anchors {
            left: parent.left
            right: parent.right
            top: infoRow.bottom
            topMargin: 14
        }
        height: 132
        contentWidth: cards.width + 80
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        Behavior on contentX { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

    Row {
        id: cards
        x: 40
        y: 8
        spacing: 16

        Card {
            id: closeCard
            iconSource: "qrc:/icons/power-24px.svg"
            caption: Chiaki.session ? qsTr("Disconnect") : qsTr("Home")
            ToolTip.text: qsTr("End the stream")
            onClicked: {
                if (Chiaki.session)
                    Chiaki.window.close();
                else
                    menu.mainViewRequested();
            }
        }

        // Volume: up/down (or the slider) changes it
        Card {
            id: volumeCard
            cardWidth: 220
            caption: qsTr("Volume %1%").arg(Math.round(Chiaki.settings.audioVolume / 128 * 100))
            ToolTip.text: qsTr("Up / down to change")
            Keys.onUpPressed: Chiaki.settings.audioVolume = Math.min(128, Chiaki.settings.audioVolume + 8)
            Keys.onDownPressed: Chiaki.settings.audioVolume = Math.max(0, Chiaki.settings.audioVolume - 8)
            contentItem: Item {
                RowLayout {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 22
                        leftMargin: 14
                        rightMargin: 14
                    }
                    spacing: 8
                    Image {
                        Layout.preferredWidth: 30
                        Layout.preferredHeight: 30
                        sourceSize: Qt.size(60, 60)
                        source: "qrc:/icons/volume-24px.svg"
                    }
                    Slider {
                        Layout.fillWidth: true
                        from: 0
                        to: 128
                        stepSize: 1
                        focusPolicy: Qt.NoFocus
                        value: Chiaki.settings.audioVolume
                        onMoved: Chiaki.settings.audioVolume = value
                        Material.accent: "white"
                    }
                }
                Label {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: 14
                    }
                    text: volumeCard.caption
                    font.pixelSize: 13
                    font.weight: volumeCard.activeFocus ? Font.DemiBold : Font.Normal
                }
            }
        }

        Card {
            id: micCard
            readonly property bool micOn: !!(Chiaki.session && !Chiaki.session.muted)
            enabled: !!(Chiaki.session && Chiaki.session.connected)
            lit: micOn
            iconSource: micOn ? "qrc:/icons/mic-24px.svg" : "qrc:/icons/micoff-24px.svg"
            caption: micOn ? qsTr("Mic on") : qsTr("Mic off")
            ToolTip.text: qsTr("Microphone (Ctrl+M)")
            onClicked: Chiaki.session.muted = !Chiaki.session.muted
        }

        Card {
            id: statsCard
            lit: Chiaki.settings.showStreamStats
            iconSource: "qrc:/icons/stats-24px.svg"
            caption: lit ? qsTr("Stats on") : qsTr("Stats off")
            ToolTip.text: qsTr("Bitrate, ping, packet loss and dropped frames overlay")
            onClicked: Chiaki.settings.showStreamStats = !Chiaki.settings.showStreamStats
        }

        Card {
            id: snapCard
            enabled: Chiaki.window.hasVideo
            iconSource: "qrc:/icons/camera-24px.svg"
            caption: qsTr("Screenshot")
            ToolTip.text: qsTr("Save a screenshot (F12)")
            onClicked: Chiaki.window.takeScreenshot()
        }

        Card {
            id: recCard
            readonly property bool recording: !!(Chiaki.session && Chiaki.session.recording)
            enabled: !!(Chiaki.session && Chiaki.session.connected)
            lit: recording
            iconSource: recording ? "qrc:/icons/stop-24px.svg" : "qrc:/icons/record-24px.svg"
            caption: recording ? qsTr("Stop rec") : qsTr("Record")
            ToolTip.text: qsTr("Record the stream without re-encoding (F9)")
            onClicked: Chiaki.session.toggleRecording()
        }

        // Instant replay: on/off, and save the last ~30 s
        Card {
            id: replayCard
            readonly property bool replayOn: !!(Chiaki.session && Chiaki.session.replayEnabled)
            enabled: !!(Chiaki.session && Chiaki.session.connected)
            lit: replayOn
            iconSource: "qrc:/icons/replay-24px.svg"
            caption: replayOn ? qsTr("Replay on") : qsTr("Replay off")
            ToolTip.text: qsTr("Keeps the last 30 seconds so you can save them as a clip (F10). Uses a little more bandwidth while on.")
            onClicked: {
                const on = !Chiaki.session.replayEnabled;
                Chiaki.session.replayEnabled = on;
                root.replayPreferred = on;
            }
        }
        Card {
            id: clipCard
            readonly property real secs: Chiaki.session ? Chiaki.session.replaySeconds : 0
            visible: replayCard.replayOn
            enabled: secs >= 2
            cardWidth: 130
            iconSource: "qrc:/icons/save-24px.svg"
            caption: secs >= 2 ? qsTr("Save %1 s").arg(Math.min(30, Math.round(secs))) : qsTr("Filling…")
            ToolTip.text: qsTr("Save the last 30 seconds as a clip (F10)")
            onClicked: Chiaki.session.saveReplay()
        }

        Card {
            id: lighterCard
            visible: !!root.lighterPreset && !!(Chiaki.session && Chiaki.session.connected)
            cardWidth: 150
            iconSource: "qrc:/icons/refresh-24px.svg"
            caption: root.lighterPreset ? qsTr("Switch to %1").arg(qsTr(root.lighterPreset.name)) : ""
            ToolTip.text: qsTr("Reconnect at a lighter quality for a smoother stream (takes about 10 seconds)")
            onClicked: {
                menu.closeRequested();
                root.switchToLighterAndReconnect();
            }
        }

        Card {
            id: pictureCard
            cardWidth: 150
            iconSource: "qrc:/icons/picture-24px.svg"
            caption: menu.presets[menu.presetIndex()].name
            ToolTip.text: menu.presets[menu.presetIndex()].tip + " " + qsTr("(press to switch)")
            onClicked: menu.cyclePreset()
        }

        // Extra sharpening on the final image; press to step Off -> Low -> ... -> Max
        Card {
            id: sharpCard
            readonly property var names: [qsTr("Sharpen off"), qsTr("Sharpen low"), qsTr("Sharpen medium"), qsTr("Sharpen high"), qsTr("Sharpen max")]
            cardWidth: 150
            lit: Chiaki.window.sharpening > 0
            iconSource: "qrc:/icons/tune-24px.svg"
            caption: names[Math.max(0, Math.min(4, Chiaki.window.sharpening))]
            ToolTip.text: qsTr("AMD FidelityFX sharpening on the final picture, on top of any upscaling. Up / down or press to change.")
            Keys.onUpPressed: Chiaki.window.sharpening = Math.min(4, Chiaki.window.sharpening + 1)
            Keys.onDownPressed: Chiaki.window.sharpening = Math.max(0, Chiaki.window.sharpening - 1)
            onClicked: Chiaki.window.sharpening = (Chiaki.window.sharpening + 1) % 5
        }

        Card {
            id: advancedCard
            visible: Chiaki.window.videoPreset == ChiakiWindow.VideoPreset.Custom
            iconSource: "qrc:/icons/tune-24px.svg"
            caption: qsTr("Custom picture")
            onClicked: menu.placeboSettingsRequested()
        }

        Card {
            id: zoomCard
            lit: Chiaki.window.videoMode == ChiakiWindow.VideoMode.Zoom
            iconSource: "qrc:/icons/zoom-24px.svg"
            caption: qsTr("Zoom")
            ToolTip.text: qsTr("Zoom the picture to fill the screen (Ctrl+Z)")
            onClicked: Chiaki.window.videoMode = Chiaki.window.videoMode == ChiakiWindow.VideoMode.Zoom ? ChiakiWindow.VideoMode.Normal : ChiakiWindow.VideoMode.Zoom
        }

        Card {
            id: zoomLevelCard
            visible: Chiaki.window.videoMode == ChiakiWindow.VideoMode.Zoom
            cardWidth: 200
            caption: Chiaki.window.ZoomFactor === -1 ? qsTr("No black bars") : qsTr("Zoom %1x").arg((Chiaki.window.ZoomFactor >= 0 ? Chiaki.window.ZoomFactor + 1 : Chiaki.window.ZoomFactor).toFixed(2))
            ToolTip.text: qsTr("Up / down to change")
            function setZoom(v) {
                Chiaki.window.ZoomFactor = v;
                Chiaki.settings.sZoomFactor = v;
            }
            Keys.onUpPressed: setZoom(Math.min(4, Chiaki.window.ZoomFactor + 0.05))
            Keys.onDownPressed: setZoom(Math.max(-1, Chiaki.window.ZoomFactor - 0.05))
            contentItem: Item {
                Slider {
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        topMargin: 24
                        leftMargin: 12
                        rightMargin: 12
                    }
                    from: -1
                    to: 4
                    stepSize: 0.01
                    focusPolicy: Qt.NoFocus
                    value: Chiaki.window.ZoomFactor
                    onMoved: zoomLevelCard.setZoom(value)
                    Material.accent: "white"
                }
                Label {
                    anchors {
                        horizontalCenter: parent.horizontalCenter
                        bottom: parent.bottom
                        bottomMargin: 14
                    }
                    text: zoomLevelCard.caption
                    font.pixelSize: 13
                }
            }
        }

        Card {
            id: stretchCard
            lit: Chiaki.window.videoMode == ChiakiWindow.VideoMode.Stretch
            iconSource: "qrc:/icons/stretch-24px.svg"
            caption: qsTr("Stretch")
            ToolTip.text: qsTr("Stretch the picture to the window (Ctrl+S)")
            onClicked: Chiaki.window.videoMode = Chiaki.window.videoMode == ChiakiWindow.VideoMode.Stretch ? ChiakiWindow.VideoMode.Normal : ChiakiWindow.VideoMode.Stretch
        }

        Card {
            id: displayCard
            iconSource: "qrc:/icons/display-24px.svg"
            caption: qsTr("Display")
            ToolTip.text: qsTr("Display and HDR settings")
            onClicked: menu.displaySettingsRequested()
        }
    }
    } // cardsFlick

    // ---- Controller hints ----
    Row {
        anchors {
            right: parent.right
            rightMargin: 40
            bottom: parent.bottom
            bottomMargin: 16
        }
        spacing: 22
        Repeater {
            model: [
                { glyph: root.controllerButton("cross"), text: qsTr("Select") },
                { glyph: root.controllerButton("circle"), text: qsTr("Back") },
            ]
            delegate: Row {
                required property var modelData
                spacing: 6
                Image {
                    width: 20
                    height: 20
                    sourceSize: Qt.size(40, 40)
                    source: modelData.glyph
                    anchors.verticalCenter: parent.verticalCenter
                }
                Label {
                    text: modelData.text
                    font.pixelSize: 13
                    color: Qt.rgba(1, 1, 1, 0.6)
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
