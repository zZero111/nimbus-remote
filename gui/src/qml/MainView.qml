import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtCore

import org.streetpea.chiaking
import "presets.js" as Presets

Pane {
    padding: 0
    id: consolePane

    // Visual tokens for the home screen
    readonly property color accent: Material.accent
    readonly property color surface: Qt.rgba(1, 1, 1, 0.045)
    readonly property color surfaceHover: Qt.rgba(1, 1, 1, 0.075)
    readonly property color hairline: Qt.rgba(1, 1, 1, 0.09)
    readonly property color textDim: Qt.rgba(1, 1, 1, 0.62)
    readonly property color textFaint: Qt.rgba(1, 1, 1, 0.40)

    background: Rectangle {
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#121826" }
            GradientStop { position: 0.55; color: "#0d1119" }
            GradientStop { position: 1.0; color: "#090b10" }
        }
        // Faint accent wash along the top
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 260
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0.65, 1, 0.08) }
                GradientStop { position: 1.0; color: "transparent" }
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
    Keys.onUpPressed: {
        if(hostsView.currentItem && hostsView.currentItem.visible)
        {
            hostsView.decrementCurrentIndex()
            while(!hostsView.currentItem.visible)
                hostsView.decrementCurrentIndex()
        }
    }
    Keys.onDownPressed: {
        if(hostsView.currentItem && hostsView.currentItem.visible)
        {
            hostsView.incrementCurrentIndex()
            while(!hostsView.currentItem.visible)
                 hostsView.incrementCurrentIndex()
        }
    }
    Keys.onMenuPressed: settingsButton.clicked()
    Keys.onReturnPressed: if (hostsView.currentItem) hostsView.currentItem.connectToHost()
    Keys.onYesPressed: if (hostsView.currentItem) hostsView.currentItem.wakeUpHost()
    Keys.onNoPressed: if (hostsView.currentItem) hostsView.currentItem.deleteHost()
    Keys.onEscapePressed: root.showConfirmDialog(qsTr("Quit"), qsTr("Are you sure you want to quit?"), () => Qt.quit())
    Keys.onPressed: (event) => {
        if (event.modifiers)
            return;
        switch (event.key) {
        case Qt.Key_PageUp:
            if (hostsView.currentItem) hostsView.currentItem.setConsolePin();
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

    // Round icon button with a tooltip, used in the header
    component HeaderIconButton: RoundButton {
        id: hib
        property string tip
        property string hint // controller/keyboard shortcut shown in the tooltip
        flat: true
        focusPolicy: Qt.NoFocus
        implicitWidth: 52
        implicitHeight: 52
        icon.width: 24
        icon.height: 24
        icon.color: hovered ? "white" : Qt.rgba(1, 1, 1, 0.78)
        ToolTip.visible: hovered && tip.length > 0
        ToolTip.delay: 350
        ToolTip.text: hint ? tip + "  (" + hint + ")" : tip
    }

    // Small text action under a console's main button; shows its controller button when selected
    component SecondaryAction: Button {
        id: sa
        property string buttonIcon
        property bool showIcon: false
        flat: true
        focusPolicy: Qt.NoFocus
        font.pixelSize: 13
        leftPadding: showIcon && buttonIcon ? 34 : 12
        rightPadding: 12
        Material.roundedScale: Material.SmallScale
        Material.foreground: consolePane.textDim
        Image {
            anchors {
                left: parent.left
                leftMargin: 8
                verticalCenter: parent.verticalCenter
            }
            width: 20
            height: 20
            sourceSize: Qt.size(width, height)
            source: sa.buttonIcon
            visible: sa.showIcon && !!sa.buttonIcon
        }
    }

    // Header: brand on the left, actions on the right
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
                leftMargin: 32
                rightMargin: 20
            }
            spacing: 6

            // App mark: play symbol on an accent tile
            Rectangle {
                Layout.preferredWidth: 44
                Layout.preferredHeight: 44
                radius: 12
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#18b4ff" }
                    GradientStop { position: 1.0; color: "#0062c4" }
                }
                Image {
                    anchors.centerIn: parent
                    anchors.horizontalCenterOffset: 2
                    width: 26
                    height: 26
                    sourceSize: Qt.size(52, 52)
                    source: "qrc:/icons/play-24px.svg"
                }
            }
            ColumnLayout {
                Layout.leftMargin: 10
                spacing: 0
                Label {
                    text: "Nimbus Remote"
                    font.pixelSize: 22
                    font.bold: true
                    font.letterSpacing: 0.3
                }
                Label {
                    text: qsTr("PlayStation Remote Play")
                    font.pixelSize: 12
                    color: consolePane.textFaint
                    font.letterSpacing: 1.2
                }
            }

            Item { Layout.fillWidth: true }

            HeaderIconButton {
                icon.source: "qrc:/icons/refresh-24px.svg"
                tip: qsTr("Refresh consoles on your PSN account")
                hint: "R1"
                visible: !!Chiaki.settings.psnAuthToken
                onClicked: Chiaki.refreshPsnToken()
            }
            HeaderIconButton {
                icon.source: "qrc:/icons/add-24px.svg"
                tip: qsTr("Add a console by IP address")
                hint: "R3 / F2"
                onClicked: root.showManualHostDialog()
            }
            HeaderIconButton {
                icon.source: "qrc:/icons/gamepad-24px.svg"
                tip: qsTr("Create Steam shortcut")
                hint: "L3 / F1"
                visible: typeof Chiaki.createSteamShortcut === "function"
                onClicked: root.showSteamShortcutDialog(false)
            }
            HeaderIconButton {
                id: settingsButton
                icon.source: "qrc:/icons/settings-20px.svg"
                tip: qsTr("Settings")
                hint: "Options"
                onClicked: root.showSettingsDialog()
            }
            Rectangle {
                Layout.preferredWidth: 1
                Layout.preferredHeight: 28
                Layout.leftMargin: 6
                Layout.rightMargin: 6
                color: consolePane.hairline
            }
            HeaderIconButton {
                icon.source: "qrc:/icons/close-24px.svg"
                tip: qsTr("Quit")
                onClicked: Qt.quit()
            }
        }
    }

    Label {
        id: sectionTitle
        visible: !consolePane.noConsoles
        anchors {
            top: toolBar.bottom
            topMargin: 8
            left: hostsView.left
            leftMargin: 4
        }
        text: qsTr("YOUR CONSOLES")
        font.pixelSize: 12
        font.bold: true
        font.letterSpacing: 2
        color: consolePane.textFaint
    }

    ListView {
        id: hostsView
        keyNavigationWraps: true
        readonly property real contentMaxWidth: 1180
        anchors {
            top: sectionTitle.bottom
            topMargin: 12
            bottom: statusBar.top
            bottomMargin: 8
            horizontalCenter: parent.horizontalCenter
        }
        width: Math.min(parent.width - 48, contentMaxWidth)
        spacing: 14
        clip: true
        model: Chiaki.hosts
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
        delegate: ItemDelegate {
            visible: modelData.display
            id: delegate
            width: ListView.view ? ListView.view.width : 0
            height: modelData.display ? 196 : 0
            highlighted: ListView.isCurrentItem
            padding: 0
            onClicked: connectToHost()

            readonly property var host: modelData
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
            readonly property bool isPlay: primaryActionLabel === qsTr("Play") || primaryActionLabel === qsTr("Wake & Play")

            background: Rectangle {
                radius: 18
                color: delegate.highlighted ? Qt.rgba(1, 1, 1, 0.07) : (delegate.hovered ? consolePane.surfaceHover : consolePane.surface)
                border.width: delegate.highlighted ? 2 : 1
                border.color: delegate.highlighted ? consolePane.accent : consolePane.hairline
                Behavior on color { ColorAnimation { duration: 140 } }
                Behavior on border.color { ColorAnimation { duration: 140 } }
            }

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

            contentItem: RowLayout {
                spacing: 28

                // Console art on a tinted panel that glows in the status colour
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 236
                    Layout.margins: 12
                    radius: 12
                    clip: true
                    // Light backdrop so the (dark) console artwork stands out
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#3a4560" }
                        GradientStop { position: 1.0; color: "#232a3a" }
                    }
                    Rectangle {
                        anchors {
                            left: parent.left
                            right: parent.right
                            bottom: parent.bottom
                        }
                        height: 3
                        color: delegate.statusColor
                        opacity: 0.85
                    }
                    Image {
                        anchors.fill: parent
                        anchors.margins: 18
                        fillMode: Image.PreserveAspectFit
                        source: "image://svg/console-ps" + (modelData.ps5 ? "5" : "4") + (modelData.state == "standby" ? "#light_standby" : "#light_on")
                        sourceSize: Qt.size(width, height)
                    }
                    Label {
                        anchors {
                            left: parent.left
                            top: parent.top
                            margins: 10
                        }
                        text: modelData.ps5 ? "PS5" : "PS4"
                        font.pixelSize: 11
                        font.bold: true
                        font.letterSpacing: 1.5
                        color: consolePane.textFaint
                    }
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.fillWidth: true
                    spacing: 8

                    Label {
                        text: modelData.name || qsTr("Console")
                        font.pixelSize: 28
                        font.bold: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    RowLayout {
                        spacing: 8
                        Rectangle {
                            width: 10
                            height: 10
                            radius: 5
                            color: delegate.statusColor
                            // Gentle pulse while the console is reachable
                            SequentialAnimation on opacity {
                                running: delegate.statusLabel !== qsTr("Not found")
                                loops: Animation.Infinite
                                NumberAnimation { from: 1.0; to: 0.45; duration: 1100; easing.type: Easing.InOutSine }
                                NumberAnimation { from: 0.45; to: 1.0; duration: 1100; easing.type: Easing.InOutSine }
                            }
                        }
                        Label {
                            text: delegate.statusLabel
                            color: delegate.statusColor
                            font.pixelSize: 15
                            font.bold: true
                        }
                        Label {
                            text: "·  " + delegate.connectionLabel
                            color: consolePane.textDim
                            font.pixelSize: 15
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    Label {
                        visible: !!(modelData.discovered && modelData.app)
                        text: qsTr("Playing %1").arg(modelData.app || "")
                        font.pixelSize: 16
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }

                    // Per-console stream preset: Auto uses the global setting below
                    RowLayout {
                        visible: !!modelData.registered
                        Layout.topMargin: 6
                        spacing: 10
                        readonly property string key: {
                            consolePresetStore.map; // re-evaluate when the store changes
                            return consolePane.consolePresetKey(modelData);
                        }
                        Label {
                            text: qsTr("Stream")
                            color: consolePane.textFaint
                            font.pixelSize: 13
                        }
                        Rectangle {
                            id: segTrack
                            radius: 10
                            color: Qt.rgba(0, 0, 0, 0.30)
                            border.color: consolePane.hairline
                            implicitHeight: 32
                            implicitWidth: segRow.implicitWidth + 6
                            Row {
                                id: segRow
                                anchors.centerIn: parent
                                spacing: 2
                                Repeater {
                                    model: [{ key: "", name: qsTr("Auto"), hint: qsTr("Use the quality selected at the bottom of the screen") }].concat(Presets.list)
                                    delegate: Rectangle {
                                        required property var modelData
                                        readonly property bool active: segTrack.parent.key === modelData.key
                                        radius: 8
                                        height: 26
                                        width: segLabel.implicitWidth + 22
                                        color: active ? consolePane.accent : (segArea.containsMouse ? Qt.rgba(1, 1, 1, 0.08) : "transparent")
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Label {
                                            id: segLabel
                                            anchors.centerIn: parent
                                            text: parent.modelData.key ? qsTr(parent.modelData.name) : parent.modelData.name
                                            font.pixelSize: 13
                                            font.bold: parent.active
                                            color: parent.active ? "#05131c" : consolePane.textDim
                                        }
                                        MouseArea {
                                            id: segArea
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: consolePane.setConsolePresetKey(delegate.host, parent.modelData.key)
                                        }
                                        ToolTip.visible: segArea.containsMouse
                                        ToolTip.delay: 450
                                        ToolTip.text: parent.modelData.key ? qsTr(parent.modelData.hint) : parent.modelData.hint
                                    }
                                }
                            }
                        }
                    }

                    Label {
                        text: {
                            let parts = [];
                            if (modelData.address && modelData.address !== modelData.name)
                                parts.push(Chiaki.settings.streamerMode ? qsTr("address hidden") : modelData.address);
                            if (modelData.mac)
                                parts.push(Chiaki.settings.streamerMode ? qsTr("ID hidden") : modelData.mac);
                            return parts.join("  ·  ");
                        }
                        visible: text.length > 0
                        color: consolePane.textFaint
                        font.pixelSize: 12
                    }
                }

                // Actions: big primary button, small secondary links under it
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.rightMargin: 28
                    spacing: 8

                    Rectangle {
                        id: primaryButton
                        Layout.alignment: Qt.AlignRight
                        radius: 14
                        implicitHeight: 60
                        implicitWidth: Math.max(190, primaryRow.implicitWidth + 48)
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: primaryArea.containsMouse || delegate.highlighted ? "#18b4ff" : Qt.rgba(1, 1, 1, 0.10) }
                            GradientStop { position: 1.0; color: primaryArea.containsMouse || delegate.highlighted ? "#0077e6" : Qt.rgba(1, 1, 1, 0.07) }
                        }
                        scale: primaryArea.pressed ? 0.97 : 1.0
                        Behavior on scale { NumberAnimation { duration: 90 } }
                        RowLayout {
                            id: primaryRow
                            anchors.centerIn: parent
                            spacing: 10
                            Image {
                                Layout.preferredWidth: 26
                                Layout.preferredHeight: 26
                                sourceSize: Qt.size(26, 26)
                                source: delegate.highlighted ? root.controllerButton("cross") : "qrc:/icons/play-24px.svg"
                                visible: delegate.highlighted || delegate.isPlay
                            }
                            Label {
                                text: delegate.primaryActionLabel
                                font.pixelSize: 19
                                font.bold: true
                                color: "white"
                            }
                        }
                        MouseArea {
                            id: primaryArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: delegate.connectToHost()
                        }
                    }

                    RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 2

                        SecondaryAction {
                            showIcon: delegate.highlighted
                            text: qsTr("Wake up")
                            buttonIcon: root.controllerButton("pyramid")
                            visible: modelData.registered && !modelData.duid && !modelData.discovered
                            onClicked: delegate.wakeUpHost()
                        }
                        SecondaryAction {
                            showIcon: delegate.highlighted
                            text: qsTr("Console PIN")
                            buttonIcon: "qrc:/icons/l1.svg"
                            visible: modelData.registered
                            onClicked: delegate.setConsolePin()
                        }
                        SecondaryAction {
                            showIcon: delegate.highlighted
                            text: modelData.manual ? qsTr("Delete") : qsTr("Hide")
                            buttonIcon: root.controllerButton("box")
                            visible: modelData.manual || (modelData.discovered && !modelData.registered)
                            onClicked: delegate.deleteHost()
                        }
                    }
                }
            }
        }
    }

    // Advice after a rough session (filled in by Main.qml when a session ends)
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: statusBar.top
            bottomMargin: 12
        }
        visible: root.sessionAdvice.length > 0
        radius: 12
        color: Qt.rgba(0.94, 0.66, 0.18, 0.14)
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

    // Bottom status bar: discovery, controllers, stream quality, version / updates
    Rectangle {
        id: statusBar
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
        }
        height: 68
        color: Qt.rgba(0, 0, 0, 0.30)
        Rectangle {
            anchors {
                left: parent.left
                right: parent.right
                top: parent.top
            }
            height: 1
            color: consolePane.hairline
        }

        // Left: discovery toggle + controllers
        RowLayout {
            anchors {
                left: parent.left
                leftMargin: 20
                verticalCenter: parent.verticalCenter
            }
            spacing: 12

            Rectangle {
                id: discoveryToggle
                readonly property bool on: Chiaki.discoveryEnabled
                radius: 17
                implicitHeight: 34
                implicitWidth: discoveryRow.implicitWidth + 24
                color: on ? Qt.rgba(0, 0.65, 1, discoveryArea.containsMouse ? 0.26 : 0.16) : (discoveryArea.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.05))
                border.width: 1
                border.color: on ? Qt.rgba(0, 0.65, 1, 0.6) : consolePane.hairline
                RowLayout {
                    id: discoveryRow
                    anchors.centerIn: parent
                    spacing: 6
                    Image {
                        Layout.preferredWidth: 18
                        Layout.preferredHeight: 18
                        sourceSize: Qt.size(18, 18)
                        source: "qrc:/icons/discover-" + (discoveryToggle.on ? "" : "off-") + "24px.svg"
                    }
                    Label {
                        text: discoveryToggle.on ? qsTr("Searching home network") : qsTr("Home network search off")
                        font.pixelSize: 13
                    }
                }
                MouseArea {
                    id: discoveryArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Chiaki.discoveryEnabled = !Chiaki.discoveryEnabled
                }
                ToolTip.visible: discoveryArea.containsMouse
                ToolTip.delay: 400
                ToolTip.text: qsTr("Look for consoles on this network. Click to turn on or off.")
            }

            // Which controllers are connected, so it's clear before connecting whether the pad was picked up
            Repeater {
                model: statusBar.pads
                delegate: Rectangle {
                    id: padPill
                    required property string modelData
                    radius: 17
                    implicitHeight: 34
                    implicitWidth: padRow.implicitWidth + 24
                    color: Qt.rgba(0.18, 0.8, 0.44, 0.12)
                    border.color: Qt.rgba(0.18, 0.8, 0.44, 0.55)
                    border.width: 1
                    RowLayout {
                        id: padRow
                        anchors.centerIn: parent
                        spacing: 6
                        Image {
                            Layout.preferredWidth: 18
                            Layout.preferredHeight: 18
                            sourceSize: Qt.size(18, 18)
                            source: "qrc:/icons/gamepad-24px.svg"
                        }
                        Label {
                            text: padPill.modelData
                            font.pixelSize: 13
                        }
                    }
                }
            }
            Label {
                visible: statusBar.pads.length === 0
                text: qsTr("No controller · keyboard + mouse")
                color: consolePane.textFaint
                font.pixelSize: 13
            }
        }

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

        StreamPresetBar {
            id: presetBar
            anchors.centerIn: parent
        }

        // Right: update status + version
        RowLayout {
            anchors {
                right: parent.right
                rightMargin: 20
                verticalCenter: parent.verticalCenter
            }
            spacing: 12

            Rectangle {
                id: updateBanner
                readonly property var upd: Chiaki.updater
                visible: upd && (upd.state === "downloading" || upd.state === "ready" || upd.state === "available")
                radius: 17
                implicitHeight: 38
                implicitWidth: updateRow.implicitWidth + 24
                color: Qt.rgba(0, 0.65, 1, 0.14)
                border.color: Qt.rgba(0, 0.65, 1, 0.6)
                border.width: 1
                RowLayout {
                    id: updateRow
                    anchors.centerIn: parent
                    spacing: 10
                    Label {
                        font.pixelSize: 13
                        text: !updateBanner.upd ? "" : updateBanner.upd.state === "downloading"
                            ? qsTr("Downloading update %1… %2%").arg(updateBanner.upd.latestVersion).arg(Math.round(updateBanner.upd.progress * 100))
                            : updateBanner.upd.state === "available"
                            ? qsTr("Update %1 is available").arg(updateBanner.upd.latestVersion)
                            : qsTr("Update %1 ready · installs when you close the app").arg(updateBanner.upd.latestVersion)
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

    // Empty state: shown only while no console is listed
    readonly property bool noConsoles: {
        for (let i = 0; i < Chiaki.hosts.length; i++)
            if (Chiaki.hosts[i].display)
                return false;
        return true;
    }

    ColumnLayout {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -20
        visible: consolePane.noConsoles
        spacing: 18
        width: Math.min(parent.width - 80, 760)

        Image {
            id: logoImage
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: Math.min(consolePane.width, consolePane.height) / 4
            Layout.preferredHeight: Layout.preferredWidth
            source: "qrc:/icons/nimbus-logo-white.svg"
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(Layout.preferredWidth, Layout.preferredHeight)
            opacity: 0.18
            SequentialAnimation on opacity {
                running: consolePane.noConsoles && consolePane.visible
                loops: Animation.Infinite
                NumberAnimation { from: 0.12; to: 0.26; duration: 1600; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.26; to: 0.12; duration: 1600; easing.type: Easing.InOutSine }
            }
        }

        Label {
            Layout.alignment: Qt.AlignHCenter
            text: consolePane.networkWarning ? qsTr("Can't see your home network") : (Chiaki.discoveryEnabled ? qsTr("Looking for consoles…") : qsTr("No consoles yet"))
            font.pixelSize: 26
            font.bold: true
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            color: consolePane.networkWarning ? "#ffcc80" : consolePane.textDim
            font.pixelSize: 16
            lineHeight: 1.25
            text: {
                if (consolePane.networkWarning && Chiaki.settings.psnAuthToken)
                    return consolePane.networkWarning + "\n\n"
                        + qsTr("You're signed in to PSN, but PSN lists no PS5 with Remote Play for this account. On the PS5: Settings > System > Remote Play > Enable Remote Play, and Power Saving > Features Available in Rest Mode > Stay Connected to the Internet. Then click Refresh.");
                if (consolePane.networkWarning)
                    return consolePane.networkWarning;
                return Chiaki.discoveryEnabled
                    ? qsTr("Make sure your PS5 is on or in rest mode with Remote Play enabled, or add it by IP address with the + button.")
                    : qsTr("Home network search is off. Turn it on at the bottom left, or add a console with the + button.");
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 12
            Button {
                text: qsTr("Refresh")
                visible: !!Chiaki.settings.psnAuthToken
                highlighted: true
                focusPolicy: Qt.NoFocus
                Material.roundedScale: Material.SmallScale
                onClicked: Chiaki.refreshPsnToken()
            }
            Button {
                text: qsTr("Sign in to PSN")
                visible: !Chiaki.settings.psnAuthToken
                highlighted: true
                focusPolicy: Qt.NoFocus
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
