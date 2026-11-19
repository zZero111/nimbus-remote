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
                root.showRemindDialog(qsTr("Official Steam artwork + controller layout"), qsTr("Would you like to either create a new non-Steam game for chiaki-ng\nor update an existing non-Steam game with the official artwork and controller layout?") + "\n\n" + qsTr("(Note: If you select no now and want to do this later, click the button or press R3 from the main menu.)"), false, () => root.showSteamShortcutDialog(true));
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

    ToolBar {
        id: toolBar
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
        }
        height: 80

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 10
                rightMargin: 10
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                flat: true
                text: "×"
                font.pixelSize: 60
                focusPolicy: Qt.NoFocus
                onClicked: Qt.quit()
                Material.roundedScale: Material.SmallScale
            }

            Item { Layout.fillWidth: true }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 350
                flat: true
                text: "Create Steam Shortcut"
                focusPolicy: Qt.NoFocus
                onClicked: root.showSteamShortcutDialog(false)
                Material.roundedScale: Material.SmallScale
                visible: typeof Chiaki.createSteamShortcut === "function"
                Image {
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }
                    width: 28
                    height: 28
                    sourceSize: Qt.size(width, height)
                    source: "qrc:/icons/l3.svg"
                }
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 400
                flat: true
                text: "Refresh PSN Hosts"
                icon.source: "qrc:/icons/r1.svg"
                focusPolicy: Qt.NoFocus
                onClicked: Chiaki.refreshPsnToken();
                Material.roundedScale: Material.SmallScale
                visible: Chiaki.settings.psnAuthToken
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 400
                flat: true
                focusPolicy: Qt.NoFocus
                Material.roundedScale: Material.SmallScale
                visible: !Chiaki.settings.psnAuthToken
            }

            Button {
                Layout.fillHeight: true
                Layout.preferredWidth: 300
                flat: true
                text: "Add Manual Host"
                focusPolicy: Qt.NoFocus
                onClicked: root.showManualHostDialog()
                Material.roundedScale: Material.SmallScale
                Image {
                    anchors {
                        left: parent.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                    }
                    width: 28
                    height: 28
                    sourceSize: Qt.size(width, height)
                    source: "qrc:/icons/r3.svg"
                }
            }

            Button {
                id: settingsButton
                Layout.fillHeight: true
                Layout.preferredWidth: 100
                flat: true
                icon.source: "qrc:/icons/settings-20px.svg";
                icon.width: 50
                icon.height: 50
                focusPolicy: Qt.NoFocus
                onClicked: root.showSettingsDialog()
                Material.roundedScale: Material.SmallScale
            }
        }
    }

    ListView {
        id: hostsView
        keyNavigationWraps: true
        anchors {
            top: toolBar.bottom
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            bottomMargin: 50
        }
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
            width: parent ? parent.width : 0
            height: modelData.display ? 180 : 0
            highlighted: ListView.isCurrentItem
            onClicked: connectToHost()

            // What the console is doing, shown as a coloured pill
            readonly property bool viaPsn: !!modelData.duid && !modelData.discovered
            readonly property string statusLabel: {
                if (viaPsn)
                    return qsTr("Internet");
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
                    return "#3d6fd6";
                if (!modelData.discovered)
                    return "#5a5a5a";
                if (modelData.state === "ready")
                    return "#1e9e57";
                if (modelData.state === "standby")
                    return "#c98a12";
                return "#5a5a5a";
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

            background: Rectangle {
                anchors {
                    fill: parent
                    leftMargin: 16
                    rightMargin: 16
                    topMargin: 8
                    bottomMargin: 8
                }
                radius: 14
                color: delegate.highlighted ? Qt.rgba(1, 1, 1, 0.10) : (delegate.hovered ? Qt.rgba(1, 1, 1, 0.06) : Qt.rgba(1, 1, 1, 0.035))
                border.width: delegate.highlighted ? 2 : 0
                border.color: Material.accent
                Behavior on color { ColorAnimation { duration: 120 } }
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

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 44
                    rightMargin: 34
                    topMargin: 18
                    bottomMargin: 18
                }
                spacing: 36

                Image {
                    Layout.fillHeight: true
                    Layout.preferredWidth: 150
                    fillMode: Image.PreserveAspectFit
                    source: "image://svg/console-ps" + (modelData.ps5 ? "5" : "4") + (modelData.state == "standby" ? "#light_standby" : "#light_on")
                    sourceSize: Qt.size(width, height)
                }

                ColumnLayout {
                    Layout.alignment: Qt.AlignLeft | Qt.AlignVCenter
                    spacing: 6

                    Label {
                        text: modelData.name || qsTr("Console")
                        font.pixelSize: 26
                        font.bold: true
                    }

                    RowLayout {
                        spacing: 10
                        // Status pill: what the console is doing right now
                        Rectangle {
                            radius: height / 2
                            implicitHeight: 28
                            implicitWidth: statusText.implicitWidth + 28
                            color: delegate.statusColor
                            Label {
                                id: statusText
                                anchors.centerIn: parent
                                text: delegate.statusLabel
                                color: "white"
                                font.pixelSize: 14
                                font.bold: true
                            }
                        }
                        Label {
                            text: delegate.connectionLabel
                            opacity: 0.7
                            font.pixelSize: 15
                        }

                        // Per-console preset chip: click cycles Default → Performance → Balanced → Quality
                        Rectangle {
                            visible: !!modelData.registered
                            readonly property string key: {
                                consolePresetStore.map; // re-evaluate when the store changes
                                return consolePane.consolePresetKey(modelData);
                            }
                            readonly property var preset: Presets.byKey(key)
                            radius: height / 2
                            implicitHeight: 28
                            implicitWidth: chipText.implicitWidth + 24
                            color: chipArea.containsMouse ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)
                            border.width: 1
                            border.color: preset ? Material.accent : Qt.rgba(1, 1, 1, 0.2)
                            Label {
                                id: chipText
                                anchors.centerIn: parent
                                text: parent.preset ? qsTr("Preset: %1").arg(qsTr(parent.preset.name)) : qsTr("Preset: current")
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: chipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: consolePane.setConsolePresetKey(modelData, Presets.nextKey(parent.key))
                            }
                            ToolTip.visible: chipArea.containsMouse
                            ToolTip.delay: 400
                            ToolTip.text: qsTr("Stream preset used for this console. Click to change.")
                        }
                    }

                    Label {
                        visible: !!(modelData.discovered && modelData.app)
                        text: qsTr("Playing: %1").arg(modelData.app || "")
                        font.pixelSize: 17
                        elide: Text.ElideRight
                        Layout.maximumWidth: 520
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
                        opacity: 0.45
                        font.pixelSize: 13
                    }
                }

                Item { Layout.fillWidth: true }

                // Primary action, triggered by click / Enter / Cross
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    radius: 8
                    implicitHeight: 56
                    implicitWidth: primaryText.implicitWidth + (delegate.highlighted ? 84 : 48)
                    color: delegate.highlighted ? Material.accent : Qt.rgba(1, 1, 1, 0.08)
                    Image {
                        anchors {
                            left: parent.left
                            leftMargin: 14
                            verticalCenter: parent.verticalCenter
                        }
                        width: 28
                        height: 28
                        sourceSize: Qt.size(width, height)
                        source: root.controllerButton("cross")
                        visible: delegate.highlighted
                    }
                    Label {
                        id: primaryText
                        anchors {
                            verticalCenter: parent.verticalCenter
                            horizontalCenter: parent.horizontalCenter
                            horizontalCenterOffset: delegate.highlighted ? 18 : 0
                        }
                        text: delegate.primaryActionLabel
                        font.pixelSize: 18
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: delegate.connectToHost()
                    }
                }

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 0

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        text: modelData.manual ? qsTr("Delete") : qsTr("Hide")
                        flat: true
                        padding: 20
                        leftPadding: delegate.highlighted ? 50 : undefined
                        focusPolicy: Qt.NoFocus
                        visible: modelData.manual || (modelData.discovered && !modelData.registered)
                        onClicked: delegate.deleteHost()
                        Material.roundedScale: Material.SmallScale

                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: root.controllerButton("box")
                            visible: delegate.highlighted
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        text: qsTr("Wake Up")
                        flat: true
                        padding: 20
                        leftPadding: delegate.highlighted ? 50 : undefined
                        visible: modelData.registered && !modelData.duid && !modelData.discovered
                        focusPolicy: Qt.NoFocus
                        onClicked: delegate.wakeUpHost()
                        Material.roundedScale: Material.SmallScale

                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: root.controllerButton("pyramid")
                            visible: delegate.highlighted
                        }
                    }

                    Button {
                        Layout.alignment: Qt.AlignCenter
                        text: qsTr("Update Console Pin")
                        flat: true
                        padding: 20
                        leftPadding: delegate.highlighted ? 50 : undefined
                        visible: modelData.registered
                        focusPolicy: Qt.NoFocus
                        onClicked: delegate.setConsolePin()
                        Material.roundedScale: Material.SmallScale

                        Image {
                            anchors {
                                left: parent.left
                                verticalCenter: parent.verticalCenter
                                leftMargin: 12
                            }
                            width: 28
                            height: 28
                            sourceSize: Qt.size(width, height)
                            source: "qrc:/icons/l1.svg"
                            visible: delegate.highlighted
                        }
                    }
                } 
            } 
        }
    }     

    RoundButton {
        anchors {
            left: parent.left
            bottom: parent.bottom
            margins: 20
        }
        icon.source: "qrc:/icons/discover-" + (checked ? "" : "off-") + "24px.svg"
        icon.width: 50
        icon.height: 50
        padding: 20
        focusPolicy: Qt.NoFocus
        checkable: true
        checked: Chiaki.discoveryEnabled
        onToggled: Chiaki.discoveryEnabled = !Chiaki.discoveryEnabled
        Material.background: Material.accent
    }

    // Which controllers are connected, so it's clear before connecting whether the pad was picked up
    Row {
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 120
            bottomMargin: 18
        }
        spacing: 8
        readonly property var pads: {
            let out = [];
            for (let i = 0; i < Chiaki.controllers.length; i++) {
                const c = Chiaki.controllers[i];
                if (c.steamVirtual)
                    continue;
                // SDL names can carry a GUID in brackets, e.g. "XInput Controller #2 (0300ba66...)"
                const cleanName = (c.name || "").replace(/\s*\([0-9a-fA-F]{8,}\)\s*$/, "").trim();
                let label = c.dualSenseEdge ? qsTr("DualSense Edge") : (c.dualSense ? qsTr("DualSense") : (cleanName || qsTr("Controller")));
                out.push(label);
            }
            return out;
        }
        Repeater {
            model: parent.pads
            delegate: Rectangle {
                required property string modelData
                radius: height / 2
                height: 30
                width: padLabel.implicitWidth + 26
                color: Qt.rgba(0.12, 0.62, 0.34, 0.25)
                border.color: "#1e9e57"
                border.width: 1
                Label {
                    id: padLabel
                    anchors.centerIn: parent
                    text: "● " + parent.modelData
                    font.pixelSize: 13
                }
            }
        }
        Label {
            visible: parent.pads.length === 0
            height: 30
            verticalAlignment: Text.AlignVCenter
            text: qsTr("No controller · keyboard + mouse")
            opacity: 0.55
            font.pixelSize: 13
        }
    }

    StreamPresetBar {
        id: presetBar
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 12
        }
    }

    // Advice after a rough session (filled in by Main.qml when a session ends)
    Rectangle {
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: presetBar.top
            bottomMargin: 10
        }
        visible: root.sessionAdvice.length > 0
        radius: 10
        color: Qt.rgba(0.79, 0.54, 0.07, 0.18)
        border.color: "#c98a12"
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

    Label {
        anchors {
            right: parent.right
            bottom: parent.bottom
            margins: 20
        }
        text: Qt.application.version
    }

    // Empty state: shown only while no console is listed
    readonly property bool noConsoles: {
        for (let i = 0; i < Chiaki.hosts.length; i++)
            if (Chiaki.hosts[i].display)
                return false;
        return true;
    }

    Label {
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: logoImage.bottom
            topMargin: 24
        }
        visible: consolePane.noConsoles
        horizontalAlignment: Text.AlignHCenter
        opacity: consolePane.networkWarning ? 0.95 : 0.6
        color: consolePane.networkWarning ? "#ffcc80" : Material.foreground
        font.pixelSize: 18
        text: {
            if (consolePane.networkWarning && Chiaki.settings.psnAuthToken)
                return consolePane.networkWarning + "\n\n"
                    + qsTr("You're signed in to PSN, but PSN lists no PS5 with Remote Play for this account.\nOn the PS5: Settings > System > Remote Play > Enable Remote Play, and\nPower Saving > Features Available in Rest Mode > Stay Connected to the Internet.\nThen click Refresh PSN Hosts.");
            if (consolePane.networkWarning)
                return consolePane.networkWarning;
            return Chiaki.discoveryEnabled
                ? qsTr("Looking for consoles on your network…\nMake sure your PS5 is on or in rest mode with Remote Play enabled,\nor use Add Manual Host.")
                : qsTr("Console discovery is off. Turn it on with the button in the corner,\nor use Add Manual Host.");
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

    Image {
        id: logoImage
        visible: consolePane.noConsoles
        anchors.centerIn: parent
        source: "qrc:/icons/nimbus-logo-white.svg"
        fillMode: Image.PreserveAspectFit
        sourceSize: Qt.size(Math.min(parent.width, parent.height) / 2, Math.min(parent.width, parent.height) / 2)

        PropertyAnimation {
            target: logoImage
            property: "opacity"
            from: 0.05
            to: 0.20
            duration: 1000
            easing.type: Easing.OutCubic
            running: true
        }
    }
}
