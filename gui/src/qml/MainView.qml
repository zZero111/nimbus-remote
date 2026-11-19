import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtCore

import org.streetpea.chiaking
import "presets.js" as Presets

// Home screen, laid out like the PS5 home screen: a row of console tiles at the top,
// the selected console's details large underneath, controller hints along the bottom.
Pane {
    padding: 0
    id: consolePane

    readonly property color textDim: Qt.rgba(1, 1, 1, 0.70)
    readonly property color textFaint: Qt.rgba(1, 1, 1, 0.45)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.12)

    // The selected console (null while none is listed)
    readonly property var current: hostsView.currentItem && hostsView.currentItem.visible ? hostsView.currentItem : null

    background: Rectangle {
        color: "#000814"
        // PS5-style deep blue wash, lighter at the top
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#123a78" }
                GradientStop { position: 0.45; color: "#0a1f48" }
                GradientStop { position: 1.0; color: "#020814" }
            }
        }
        // Colour of the selected console's status bleeds in from the right
        Rectangle {
            anchors.fill: parent
            opacity: consolePane.current ? 0.22 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.35; color: "transparent" }
                GradientStop { position: 1.0; color: consolePane.current ? consolePane.current.statusColor : "transparent" }
            }
        }
        // Big faded console art on the right, like a game's key art
        Image {
            anchors {
                right: parent.right
                rightMargin: parent.width * 0.04
                verticalCenter: parent.verticalCenter
                verticalCenterOffset: parent.height * 0.12
            }
            width: parent.width * 0.42
            height: parent.height * 0.55
            fillMode: Image.PreserveAspectFit
            opacity: consolePane.current ? 0.22 : 0.0
            Behavior on opacity { NumberAnimation { duration: 400 } }
            source: consolePane.current ? "image://svg/console-ps" + (consolePane.current.host.ps5 ? "5" : "4") + "#light_on" : ""
            sourceSize: Qt.size(width * 2, height * 2)
        }
        // Darken the bottom so the hint bar reads well
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                bottom: parent.bottom
            }
            height: parent.height * 0.35
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.55) }
            }
        }
    }

    // Per-console stream preset, saved in this app's settings as JSON {consoleId: presetKey}
    Settings {
        id: consolePresetStore
        category: "nimbus_console_presets"
        property string map: "{}"
        property string lastConsole: ""
    }
    property bool lastConsolePreselected: false
    function consolePresetKey(host) {
        try {
            return JSON.parse(consolePresetStore.map)[Presets.consoleId(host)] || "";
        } catch (e) {
            return "";
        }
    }
    function setConsolePresetKey(host, key) {
        let m = {};
        try { m = JSON.parse(consolePresetStore.map); } catch (e) {}
        if (key)
            m[Presets.consoleId(host)] = key;
        else
            delete m[Presets.consoleId(host)];
        consolePresetStore.map = JSON.stringify(m);
    }
    StackView.onActivated: {
        forceActiveFocus(Qt.TabFocusReason);
        if(!Chiaki.autoConnect && !root.initialAsk && !Chiaki.window.directStream)
        {
            root.initialAsk = true;
            if(Chiaki.settings.addSteamShortcutAsk && (typeof Chiaki.createSteamShortcut === "function"))
                root.showRemindDialog(qsTr("Official Steam artwork + controller layout"), qsTr("Would you like to either create a new non-Steam game for Nimbus Remote\nor update an existing non-Steam game with the official artwork and controller layout?") + "\n\n" + qsTr("(Note: If you select no now and want to do this later, click the button or press R3 from the main menu.)"), false, () => root.showSteamShortcutDialog(true));
            else if(Chiaki.settings.remotePlayAsk)
            {
                if(!Chiaki.settings.psnRefreshToken || !Chiaki.settings.psnAuthToken || !Chiaki.settings.psnAuthTokenExpiry || !Chiaki.settings.psnAccountId)
                    root.showRemindDialog(qsTr("Remote Play via PSN"), qsTr("Would you like to connect to PSN?\nThis enables:\n- Automatic registration\n- Playing outside of your home network without port forwarding?") + "\n\n" + qsTr("(Note: If you select no now and want to do this later, go to the Config section of the settings.)"), true, () => root.showPSNTokenDialog(false));
                else
                    Chiaki.settings.remotePlayAsk = false;
            }
        }
    }

    function selectPrevious() {
        if(hostsView.currentItem && hostsView.currentItem.visible)
        {
            hostsView.decrementCurrentIndex()
            while(!hostsView.currentItem.visible)
                hostsView.decrementCurrentIndex()
        }
    }
    function selectNext() {
        if(hostsView.currentItem && hostsView.currentItem.visible)
        {
            hostsView.incrementCurrentIndex()
            while(!hostsView.currentItem.visible)
                hostsView.incrementCurrentIndex()
        }
    }
    // The tiles run left to right, like the PS5; up/down still work for older muscle memory
    Keys.onLeftPressed: selectPrevious()
    Keys.onUpPressed: selectPrevious()
    Keys.onRightPressed: selectNext()
    Keys.onDownPressed: selectNext()
    Keys.onMenuPressed: settingsButton.clicked()
    Keys.onReturnPressed: if (consolePane.current) consolePane.current.connectToHost()
    Keys.onYesPressed: if (consolePane.current) consolePane.current.wakeUpHost()
    Keys.onNoPressed: if (consolePane.current) consolePane.current.deleteHost()
    Keys.onEscapePressed: root.showConfirmDialog(qsTr("Quit"), qsTr("Are you sure you want to quit?"), () => Qt.quit())
    Keys.onPressed: (event) => {
        if (event.modifiers)
            return;
        switch (event.key) {
        case Qt.Key_PageUp:
            if (consolePane.current) consolePane.current.setConsolePin();
            event.accepted = true;
            break;
        case Qt.Key_PageDown:
            if (Chiaki.settings.psnAuthToken) Chiaki.refreshPsnToken();
            event.accepted = true;
            break;
        case Qt.Key_F1:
            if (typeof Chiaki.createSteamShortcut === "function") root.showSteamShortcutDialog(false);
            event.accepted = true;
            break;
        case Qt.Key_F2:
            root.showManualHostDialog();
            event.accepted = true;
            break;
        }
    }

    // Round icon in the top-right corner, like the PS5's search / settings / profile icons
    component CornerIcon: RoundButton {
        property string tip
        flat: true
        focusPolicy: Qt.NoFocus
        implicitWidth: 48
        implicitHeight: 48
        icon.width: 24
        icon.height: 24
        icon.color: hovered ? "white" : Qt.rgba(1, 1, 1, 0.85)
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.delay: 350
        ToolTip.text: tip
    }

    // Round secondary action next to Play
    component RoundAction: RoundButton {
        property string tip
        focusPolicy: Qt.NoFocus
        implicitWidth: 76
        implicitHeight: 76
        font.pixelSize: 13
        Material.background: Qt.rgba(1, 1, 1, hovered ? 0.24 : 0.14)
        Material.foreground: "white"
        Material.elevation: 0
        ToolTip.visible: hovered
        ToolTip.delay: 300
        ToolTip.text: tip
    }

    // Controller button + label, as shown in the bottom hint bar
    component Hint: RowLayout {
        property string glyph
        property string glyphText
        property string label
        spacing: 8
        Image {
            visible: !!parent.glyph
            Layout.preferredWidth: 24
            Layout.preferredHeight: 24
            sourceSize: Qt.size(48, 48)
            source: parent.glyph
        }
        Rectangle {
            visible: !parent.glyph && !!parent.glyphText
            radius: 5
            implicitHeight: 22
            implicitWidth: glyphLabel.implicitWidth + 12
            color: "transparent"
            border.color: Qt.rgba(1, 1, 1, 0.6)
            Label {
                id: glyphLabel
                anchors.centerIn: parent
                text: parent.parent.glyphText
                font.pixelSize: 11
                font.bold: true
            }
        }
        Label {
            text: parent.label
            font.pixelSize: 15
            color: consolePane.textDim
        }
    }

    readonly property bool noConsoles: {
        for (let i = 0; i < Chiaki.hosts.length; i++)
            if (Chiaki.hosts[i].display)
                return false;
        return true;
    }

    // Everything below is laid out for a 1600x900 screen and scaled to fill the window,
    // so it looks the same on a laptop and on a large monitor (text stays sharp when scaled)
    readonly property real ui: Math.max(0.75, Math.min(width / 1600, height / 900))
    Item {
    id: stage
    width: consolePane.width / consolePane.ui
    height: consolePane.height / consolePane.ui
    scale: consolePane.ui
    transformOrigin: Item.TopLeft

    // ---- Top bar: section tabs on the left, icons and clock on the right ----
    RowLayout {
        id: topBar
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            topMargin: 22
            leftMargin: 56
            rightMargin: 40
        }
        spacing: 34

        Label {
            text: qsTr("Consoles")
            font.pixelSize: 22
            font.weight: Font.DemiBold
        }
        Label {
            text: "Nimbus Remote"
            font.pixelSize: 22
            font.weight: Font.Light
            color: consolePane.textFaint
        }

        Item { Layout.fillWidth: true }

        RowLayout {
            spacing: 4
            CornerIcon {
                icon.source: "qrc:/icons/refresh-24px.svg"
                tip: qsTr("Refresh consoles on your PSN account (R1)")
                visible: !!Chiaki.settings.psnAuthToken
                onClicked: Chiaki.refreshPsnToken()
            }
            CornerIcon {
                icon.source: "qrc:/icons/add-24px.svg"
                tip: qsTr("Add a console by IP address (R3 / F2)")
                onClicked: root.showManualHostDialog()
            }
            CornerIcon {
                icon.source: "qrc:/icons/gamepad-24px.svg"
                tip: qsTr("Create Steam shortcut (L3 / F1)")
                visible: typeof Chiaki.createSteamShortcut === "function"
                onClicked: root.showSteamShortcutDialog(false)
            }
            CornerIcon {
                id: settingsButton
                icon.source: "qrc:/icons/settings-20px.svg"
                tip: qsTr("Settings (Options)")
                onClicked: root.showSettingsDialog()
            }
            CornerIcon {
                icon.source: "qrc:/icons/close-24px.svg"
                tip: qsTr("Quit")
                onClicked: Qt.quit()
            }
        }

        Label {
            id: clock
            font.pixelSize: 22
            font.weight: Font.Light
            text: Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") >= 0 ? "h:mm AP" : "HH:mm")
            Timer {
                interval: 10000
                running: true
                repeat: true
                onTriggered: clock.text = Qt.formatTime(new Date(), Qt.locale().timeFormat(Locale.ShortFormat).indexOf("AP") >= 0 ? "h:mm AP" : "HH:mm")
            }
        }
    }

    // ---- Tile row ----
    ListView {
        id: hostsView
        orientation: ListView.Horizontal
        keyNavigationWraps: true
        anchors {
            top: topBar.bottom
            topMargin: 34
            left: parent.left
            right: parent.right
            leftMargin: 56
        }
        height: 240
        spacing: 18
        clip: false
        interactive: contentWidth > width
        model: Chiaki.hosts
        highlightMoveDuration: 180
        onCountChanged: {
            if(!hostsView.currentItem)
                hostsView.incrementCurrentIndex();
            if(!hostsView.currentItem)
                return;
            if(!hostsView.currentItem.visible)
            {
                for(var i = 0; i < hostsView.count; i++)
                {
                    hostsView.incrementCurrentIndex()
                    if(hostsView.currentItem.visible)
                    {
                        break;
                    }
                }
            }
            // Select the console played last, once, when it first shows up
            if(!consolePane.lastConsolePreselected && consolePresetStore.lastConsole)
            {
                for(let j = 0; j < Chiaki.hosts.length; j++)
                {
                    const h = Chiaki.hosts[j];
                    if(h.display && Presets.consoleId(h) === consolePresetStore.lastConsole)
                    {
                        hostsView.currentIndex = j;
                        consolePane.lastConsolePreselected = true;
                        break;
                    }
                }
            }
        }

        // "Add console" tile after the consoles, like the PS5's Game Library tile
        footer: Item {
            width: addTile.width + 18
            height: hostsView.height
            Rectangle {
                id: addTile
                x: 18
                y: 26
                width: 172
                height: 172
                radius: 16
                color: addArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                border.color: Qt.rgba(1, 1, 1, addArea.containsMouse ? 0.5 : 0.18)
                Behavior on color { ColorAnimation { duration: 120 } }
                Image {
                    anchors.centerIn: parent
                    width: 48
                    height: 48
                    sourceSize: Qt.size(96, 96)
                    source: "qrc:/icons/add-24px.svg"
                    opacity: 0.85
                }
                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.showManualHostDialog()
                }
                ToolTip.visible: addArea.containsMouse
                ToolTip.delay: 350
                ToolTip.text: qsTr("Add a console by IP address")
            }
        }

        delegate: Item {
            id: delegate
            visible: modelData.display
            readonly property bool selected: ListView.isCurrentItem
            readonly property var host: modelData
            readonly property int hostIndex: index
            width: modelData.display ? (selected ? 224 : 172) : 0
            height: hostsView.height
            Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

            // What the console is doing
            readonly property bool viaPsn: !!modelData.duid && !modelData.discovered
            readonly property string statusLabel: {
                if (viaPsn)
                    return qsTr("Available over the internet");
                if (!modelData.discovered)
                    return qsTr("Not found");
                if (modelData.state === "ready")
                    return qsTr("On");
                if (modelData.state === "standby")
                    return qsTr("Rest mode");
                return qsTr("Unknown");
            }
            readonly property color statusColor: {
                if (viaPsn)
                    return "#5b8cff";
                if (!modelData.discovered)
                    return "#7a7f8a";
                if (modelData.state === "ready")
                    return "#2ecc71";
                if (modelData.state === "standby")
                    return "#f0a92e";
                return "#7a7f8a";
            }
            readonly property string connectionLabel: {
                if (modelData.duid) {
                    if (modelData.discovered)
                        return qsTr("Ready to register automatically");
                    return modelData.registered ? qsTr("Connects through PSN") : qsTr("Found on your PSN account · not registered yet");
                }
                let how = modelData.discovered ? (modelData.manual ? qsTr("Home network + manual") : qsTr("Home network")) : qsTr("Manual address");
                return how + (modelData.registered ? "" : qsTr(" · not registered"));
            }
            readonly property string primaryActionLabel: {
                if (!modelData.registered && !modelData.duid)
                    return qsTr("Register");
                if (modelData.duid && modelData.discovered)
                    return qsTr("Register");
                if (modelData.duid && !modelData.registered)
                    return qsTr("Register via PSN");
                if (modelData.discovered && modelData.state === "standby")
                    return qsTr("Wake & Play");
                return qsTr("Play");
            }
            readonly property bool canWake: modelData.registered && !modelData.duid && !modelData.discovered
            readonly property bool canDelete: modelData.manual || (modelData.discovered && !modelData.registered)

            function connectToHost() {
                // Switch to this console's saved preset (if any) before the session starts
                root.lastConsole = modelData;
                if (modelData.registered)
                    consolePresetStore.lastConsole = Presets.consoleId(modelData);
                const preset = Presets.byKey(consolePane.consolePresetKey(modelData));
                if (preset && modelData.registered)
                    Presets.apply(Chiaki.settings, preset);
                if(modelData.discovered)
                    Chiaki.connectToHost(index, modelData.name);
                else
                    Chiaki.connectToHost(index);
            }

            function wakeUpHost() {
                if(!modelData.discovered && !modelData.duid)
                    Chiaki.wakeUpHost(index);
            }

            function deleteHost() {
                if (modelData.manual)
                    root.showConfirmDialog(qsTr("Delete Console"), qsTr("Are you sure you want to delete this console?"), () => {Chiaki.deleteHost(index)});
                else if (modelData.discovered && !modelData.registered)
                    root.showConfirmDialog(qsTr("Hide Console"), qsTr("Are you sure you want to hide this console?") + "\n\n" + qsTr("Note: You can unhide from the Consoles section of the Settings under Hidden Consoles"), () => Chiaki.hideHost(modelData.mac, modelData.name));
            }

            function setConsolePin() {
                root.showConsolePinDialog(index);
            }

            // The tile
            Rectangle {
                id: tile
                y: delegate.selected ? 0 : 26
                width: delegate.width
                height: delegate.selected ? 224 : 172
                radius: delegate.selected ? 20 : 16
                Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                Behavior on height { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#4a5a7c" }
                    GradientStop { position: 1.0; color: "#1c2436" }
                }
                border.width: delegate.selected ? 3 : 0
                border.color: "white"

                Image {
                    anchors.fill: parent
                    anchors.margins: delegate.selected ? 22 : 18
                    fillMode: Image.PreserveAspectFit
                    source: "image://svg/console-ps" + (modelData.ps5 ? "5" : "4") + (modelData.state == "standby" ? "#light_standby" : "#light_on")
                    sourceSize: Qt.size(width * 2, height * 2)
                }
                // Status light in the corner
                Rectangle {
                    anchors {
                        right: parent.right
                        top: parent.top
                        margins: 12
                    }
                    width: 12
                    height: 12
                    radius: 6
                    color: delegate.statusColor
                    border.color: Qt.rgba(0, 0, 0, 0.4)
                }
                Label {
                    anchors {
                        left: parent.left
                        bottom: parent.bottom
                        margins: 12
                    }
                    text: modelData.ps5 ? "PS5" : "PS4"
                    font.pixelSize: 12
                    font.bold: true
                    font.letterSpacing: 1.5
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
                MouseArea {
                    id: tileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    // One click selects, like moving the cursor on the PS5; Play starts the stream
                    onClicked: hostsView.currentIndex = delegate.hostIndex
                    onDoubleClicked: delegate.connectToHost()
                }
            }
            // Outer glow ring on the selected tile
            Rectangle {
                visible: delegate.selected
                x: tile.x - 5
                y: tile.y - 5
                width: tile.width + 10
                height: tile.height + 10
                radius: tile.radius + 5
                color: "transparent"
                border.width: 2
                border.color: Qt.rgba(1, 1, 1, 0.25)
            }
        }
    }

    // ---- Details of the selected console ----
    ColumnLayout {
        id: details
        visible: !!consolePane.current
        anchors {
            top: hostsView.bottom
            topMargin: 24
            left: parent.left
            leftMargin: 56
        }
        width: Math.min(parent.width * 0.55, 820)
        spacing: 14

        Label {
            text: consolePane.current ? (consolePane.current.host.name || qsTr("Console")) : ""
            font.pixelSize: 68
            font.weight: Font.Light
            elide: Text.ElideRight
            Layout.fillWidth: true
        }

        RowLayout {
            spacing: 10
            Rectangle {
                width: 10
                height: 10
                radius: 5
                color: consolePane.current ? consolePane.current.statusColor : "transparent"
            }
            Label {
                text: consolePane.current ? consolePane.current.statusLabel : ""
                font.pixelSize: 17
                font.weight: Font.DemiBold
            }
            Label {
                text: consolePane.current ? "·  " + consolePane.current.connectionLabel : ""
                font.pixelSize: 17
                color: consolePane.textDim
            }
        }

        Label {
            visible: !!(consolePane.current && consolePane.current.host.discovered && consolePane.current.host.app)
            text: consolePane.current ? qsTr("Playing %1").arg(consolePane.current.host.app || "") : ""
            font.pixelSize: 18
            color: consolePane.textDim
        }

        // Actions: white Play button and round secondary buttons, as on a PS5 game hub
        RowLayout {
            Layout.topMargin: 18
            spacing: 14

            Rectangle {
                id: playButton
                readonly property bool hot: playArea.containsMouse || playArea.pressed
                implicitWidth: Math.max(320, playRow.implicitWidth + 80)
                implicitHeight: 76
                radius: 12
                color: hot ? "white" : Qt.rgba(1, 1, 1, 0.92)
                scale: playArea.pressed ? 0.97 : 1.0
                Behavior on scale { NumberAnimation { duration: 90 } }
                // Focus ring, as the PS5 draws around the selected button
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -5
                    radius: parent.radius + 5
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(1, 1, 1, 0.55)
                }
                RowLayout {
                    id: playRow
                    anchors.centerIn: parent
                    spacing: 10
                    Label {
                        text: consolePane.current ? consolePane.current.primaryActionLabel : ""
                        font.pixelSize: 24
                        font.weight: Font.DemiBold
                        color: "#0b0f17"
                    }
                }
                MouseArea {
                    id: playArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (consolePane.current) consolePane.current.connectToHost()
                }
            }

            RoundAction {
                visible: !!(consolePane.current && consolePane.current.canWake)
                icon.source: root.controllerButton("pyramid")
                icon.color: "transparent"
                tip: qsTr("Wake up")
                onClicked: consolePane.current.wakeUpHost()
            }
            RoundAction {
                visible: !!(consolePane.current && consolePane.current.host.registered)
                text: "PIN"
                tip: qsTr("Set console PIN")
                onClicked: consolePane.current.setConsolePin()
            }
            RoundAction {
                visible: !!(consolePane.current && consolePane.current.canDelete)
                icon.source: "qrc:/icons/close-24px.svg"
                tip: consolePane.current && consolePane.current.host.manual ? qsTr("Delete console") : qsTr("Hide console")
                onClicked: consolePane.current.deleteHost()
            }
        }

        // Per-console stream quality; Auto uses the one in the bottom bar
        RowLayout {
            visible: !!(consolePane.current && consolePane.current.host.registered)
            Layout.topMargin: 22
            spacing: 14
            readonly property string key: {
                consolePresetStore.map; // re-evaluate when the store changes
                return consolePane.current ? consolePane.consolePresetKey(consolePane.current.host) : "";
            }
            Label {
                text: qsTr("Stream quality for this console")
                font.pixelSize: 14
                color: consolePane.textFaint
            }
            Row {
                id: qualityRow
                spacing: 8
                Repeater {
                    model: [{ key: "", name: qsTr("Auto"), hint: qsTr("Use the quality selected at the bottom of the screen") }].concat(Presets.list)
                    delegate: Rectangle {
                        id: q
                        required property var modelData
                        readonly property bool active: qualityRow.parent.key === modelData.key
                        radius: height / 2
                        height: 40
                        width: qLabel.implicitWidth + 30
                        color: active ? "white" : (qArea.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.08))
                        Behavior on color { ColorAnimation { duration: 120 } }
                        Label {
                            id: qLabel
                            anchors.centerIn: parent
                            text: q.modelData.key ? qsTr(q.modelData.name) : q.modelData.name
                            font.pixelSize: 14
                            font.weight: q.active ? Font.DemiBold : Font.Normal
                            color: q.active ? "#0b0f17" : consolePane.textDim
                        }
                        MouseArea {
                            id: qArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (consolePane.current) consolePane.setConsolePresetKey(consolePane.current.host, q.modelData.key)
                        }
                        ToolTip.visible: qArea.containsMouse
                        ToolTip.delay: 450
                        ToolTip.text: q.modelData.key ? qsTr(q.modelData.hint) : q.modelData.hint
                    }
                }
            }
        }

        Label {
            text: {
                const h = consolePane.current ? consolePane.current.host : null;
                if (!h)
                    return "";
                let parts = [];
                if (h.address && h.address !== h.name)
                    parts.push(Chiaki.settings.streamerMode ? qsTr("address hidden") : h.address);
                if (h.mac)
                    parts.push(Chiaki.settings.streamerMode ? qsTr("ID hidden") : h.mac);
                return parts.join("  ·  ");
            }
            visible: text.length > 0
            color: consolePane.textFaint
            font.pixelSize: 13
            Layout.topMargin: 6
        }
    }

    // Advice after a rough session (filled in by Main.qml when a session ends)
    Rectangle {
        anchors {
            left: parent.left
            leftMargin: 56
            bottom: bottomBar.top
            bottomMargin: 14
        }
        visible: root.sessionAdvice.length > 0
        radius: 12
        color: Qt.rgba(0.04, 0.06, 0.1, 0.8)
        border.color: "#f0a92e"
        border.width: 1
        implicitWidth: adviceRow.implicitWidth + 32
        implicitHeight: adviceRow.implicitHeight + 16
        RowLayout {
            id: adviceRow
            anchors.centerIn: parent
            spacing: 14
            Label {
                text: root.sessionAdvice
                wrapMode: Text.WordWrap
                Layout.maximumWidth: 640
            }
            Button {
                text: qsTr("Use Performance")
                flat: true
                focusPolicy: Qt.NoFocus
                visible: !Presets.matches(Chiaki.settings, Presets.byKey("performance"))
                onClicked: {
                    Presets.apply(Chiaki.settings, Presets.byKey("performance"));
                    // Keep a console's own saved preset in step, or it would win on the next connect
                    if (root.lastConsole && consolePane.consolePresetKey(root.lastConsole))
                        consolePane.setConsolePresetKey(root.lastConsole, "performance");
                    root.sessionAdvice = "";
                }
            }
            Button {
                text: qsTr("Dismiss")
                flat: true
                focusPolicy: Qt.NoFocus
                onClicked: root.sessionAdvice = ""
            }
        }
    }

    // ---- Bottom bar: status on the left, controller hints in the middle, updates on the right ----
    Item {
        id: bottomBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 76

        readonly property var pads: {
            let out = [];
            for (let i = 0; i < Chiaki.controllers.length; i++) {
                const c = Chiaki.controllers[i];
                if (c.steamVirtual)
                    continue;
                // SDL names can carry a GUID in brackets, e.g. "XInput Controller #2 (0300ba66...)"
                const cleanName = (c.name || "").replace(/\s*\([0-9a-fA-F]{8,}\)\s*$/, "").trim();
                out.push(c.dualSenseEdge ? qsTr("DualSense Edge") : (c.dualSense ? qsTr("DualSense") : (cleanName || qsTr("Controller"))));
            }
            return out;
        }

        RowLayout {
            anchors {
                left: parent.left
                leftMargin: 56
                verticalCenter: parent.verticalCenter
            }
            spacing: 18

            // Home network search toggle
            Rectangle {
                id: discoveryToggle
                readonly property bool on: Chiaki.discoveryEnabled
                radius: 17
                implicitHeight: 34
                implicitWidth: discoveryRow.implicitWidth + 24
                color: discoveryArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                RowLayout {
                    id: discoveryRow
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        sourceSize: Qt.size(36, 36)
                        source: "qrc:/icons/discover-" + (discoveryToggle.on ? "" : "off-") + "24px.svg"
                    }
                    Label {
                        text: discoveryToggle.on ? qsTr("Home network search on") : qsTr("Home network search off")
                        font.pixelSize: 13
                        color: consolePane.textDim
                    }
                }
                MouseArea {
                    id: discoveryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Chiaki.discoveryEnabled = !Chiaki.discoveryEnabled
                }
            }

            // Connected controllers
            Repeater {
                model: bottomBar.pads
                delegate: RowLayout {
                    id: padItem
                    required property string modelData
                    spacing: 6
                    Image {
                        Layout.preferredWidth: 20
                        Layout.preferredHeight: 20
                        sourceSize: Qt.size(40, 40)
                        source: "qrc:/icons/gamepad-24px.svg"
                    }
                    Label {
                        text: padItem.modelData
                        font.pixelSize: 13
                        color: consolePane.textDim
                    }
                }
            }
            Label {
                visible: bottomBar.pads.length === 0
                text: qsTr("No controller · keyboard + mouse")
                color: consolePane.textFaint
                font.pixelSize: 13
            }
        }

        // Controller hints, PS5 style
        RowLayout {
            anchors.centerIn: parent
            spacing: 28
            // Room for the hints only on wide windows; the buttons above do the same job
            visible: !!consolePane.current && stage.width > 1450
            Hint { glyph: root.controllerButton("cross"); label: consolePane.current ? consolePane.current.primaryActionLabel : "" }
            Hint { glyph: root.controllerButton("pyramid"); label: qsTr("Wake up"); visible: !!(consolePane.current && consolePane.current.canWake) }
            Hint { glyph: root.controllerButton("box"); label: consolePane.current && consolePane.current.host.manual ? qsTr("Delete") : qsTr("Hide"); visible: !!(consolePane.current && consolePane.current.canDelete) }
            Hint { glyph: "qrc:/icons/l1.svg"; label: qsTr("PIN"); visible: !!(consolePane.current && consolePane.current.host.registered) }
            Hint { glyph: "qrc:/icons/options.svg"; label: qsTr("Settings") }
        }

        RowLayout {
            anchors {
                right: parent.right
                rightMargin: 40
                verticalCenter: parent.verticalCenter
            }
            spacing: 16

            StreamPresetBar {
                id: presetBar
            }

            Rectangle {
                id: updateBanner
                readonly property var upd: Chiaki.updater
                visible: upd && (upd.state === "downloading" || upd.state === "ready" || upd.state === "available")
                radius: 17
                implicitHeight: 38
                implicitWidth: updateRow.implicitWidth + 24
                color: Qt.rgba(1, 1, 1, 0.10)
                border.color: Qt.rgba(1, 1, 1, 0.35)
                border.width: 1
                RowLayout {
                    id: updateRow
                    anchors.centerIn: parent
                    spacing: 10
                    Label {
                        font.pixelSize: 13
                        text: !updateBanner.upd ? "" : updateBanner.upd.state === "downloading"
                            ? qsTr("Downloading update… %1%").arg(Math.round(updateBanner.upd.progress * 100))
                            : updateBanner.upd.state === "available"
                            ? qsTr("Update %1 is available").arg(updateBanner.upd.latestVersion)
                            : qsTr("Update ready · installs when you close the app")
                    }
                    Button {
                        visible: updateBanner.upd && updateBanner.upd.state === "available"
                        text: qsTr("Download")
                        highlighted: true
                        focusPolicy: Qt.NoFocus
                        implicitHeight: 34
                        Material.roundedScale: Material.SmallScale
                        onClicked: Chiaki.updater.openReleasePage()
                    }
                    Button {
                        visible: updateBanner.upd && updateBanner.upd.state === "ready"
                        text: qsTr("Restart & update")
                        highlighted: true
                        focusPolicy: Qt.NoFocus
                        implicitHeight: 34
                        Material.roundedScale: Material.SmallScale
                        onClicked: Chiaki.updater.installAndRestart()
                    }
                }
            }

            Label {
                id: versionLabel
                text: Chiaki.updater ? Chiaki.updater.currentVersion : Qt.application.version
                color: consolePane.textFaint
                font.pixelSize: 12
            }
        }
    }

    // ---- Empty state: shown only while no console is listed ----
    ColumnLayout {
        anchors {
            left: parent.left
            leftMargin: 56
            top: hostsView.bottom
            topMargin: 10
        }
        visible: consolePane.noConsoles
        spacing: 16
        width: Math.min(parent.width - 112, 820)

        Label {
            text: consolePane.networkWarning ? qsTr("Can't see your home network") : (Chiaki.discoveryEnabled ? qsTr("Looking for consoles…") : qsTr("No consoles yet"))
            font.pixelSize: 48
            font.weight: Font.Light
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: consolePane.networkWarning ? "#ffcc80" : consolePane.textDim
            font.pixelSize: 17
            lineHeight: 1.25
            text: {
                if (consolePane.networkWarning && Chiaki.settings.psnAuthToken)
                    return consolePane.networkWarning + "\n\n"
                        + qsTr("You're signed in to PSN, but PSN lists no PS5 with Remote Play for this account. On the PS5: Settings > System > Remote Play > Enable Remote Play, and Power Saving > Features Available in Rest Mode > Stay Connected to the Internet. Then click Refresh.");
                if (consolePane.networkWarning)
                    return consolePane.networkWarning;
                return Chiaki.discoveryEnabled
                    ? qsTr("Make sure your PS5 is on or in rest mode with Remote Play enabled, or add it by IP address with the + tile.")
                    : qsTr("Home network search is off. Turn it on at the bottom left, or add a console with the + tile.");
            }
        }

        RowLayout {
            Layout.topMargin: 10
            spacing: 14
            Button {
                text: qsTr("Refresh")
                visible: !!Chiaki.settings.psnAuthToken
                focusPolicy: Qt.NoFocus
                Material.background: "white"
                Material.foreground: "#0b0f17"
                Material.roundedScale: Material.SmallScale
                onClicked: Chiaki.refreshPsnToken()
            }
            Button {
                text: qsTr("Sign in to PSN")
                visible: !Chiaki.settings.psnAuthToken
                focusPolicy: Qt.NoFocus
                Material.background: "white"
                Material.foreground: "#0b0f17"
                Material.roundedScale: Material.SmallScale
                onClicked: root.showPSNTokenDialog(false)
            }
            Button {
                text: qsTr("Add by IP address")
                flat: true
                focusPolicy: Qt.NoFocus
                Material.roundedScale: Material.SmallScale
                onClicked: root.showManualHostDialog()
            }
        }
    }

    } // stage

    // Re-check the PC's network every few seconds while no console is listed,
    // so the hint updates as soon as a cable is plugged in
    property string networkWarning: ""
    Timer {
        interval: 4000
        repeat: true
        triggeredOnStart: true
        running: consolePane.noConsoles && consolePane.visible
        onTriggered: consolePane.networkWarning = Chiaki.localNetworkWarning()
    }
}
