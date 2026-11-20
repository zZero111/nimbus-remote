import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Controls.Material
import QtCore

import org.streetpea.chiaking
import "presets.js" as Presets

Item {
    id: root
    property list<Item> restoreFocusItems
    property bool initialAsk: false
    readonly property bool preferSeparateStreamSettingsWindows: Chiaki.window.runtimeRendererBackend === 1 && Chiaki.session
    property bool useSeparateStreamSettingsWindows: false
    Material.theme: Material.Dark
    Material.accent: "#00a7ff"

    function controllerButton(name) {
        let type = "deck";
        for (let i = 0; i < Chiaki.controllers.length; ++i) {
            if (Chiaki.controllers[i].playStation) {
                type = "ps";
                break;
            }
        }
        return "image://svg/button-%1#%2".arg(type).arg(name);
    }
    function grabInput(item) {
        Chiaki.window.grabInput();
        restoreFocusItems.push(Window.window.activeFocusItem);
        if (item)
            item.forceActiveFocus(Qt.TabFocusReason);
    }

    function releaseInput() {
        Chiaki.window.releaseInput();
        let item = restoreFocusItems.pop();
        if (item && item.visible)
            item.forceActiveFocus(Qt.TabFocusReason);
    }

    function autoRegister(auto, host, ps5) {
        if(auto)
            Chiaki.autoRegister()
        else
            showRegistDialog(host, ps5);
    }

    function openDisplaySettings() {
        useSeparateStreamSettingsWindows = preferSeparateStreamSettingsWindows;
        const loader = useSeparateStreamSettingsWindows ? separateDisplaySettingsLoader : displaySettingsLoader;
        if(loader.status == Loader.Ready)
        {
            if(placeboSettingsRect.opacity || displaySettingsRect.opacity || colorMappingSettingsRect.opacity)
                closeDialog();
            displaySettingsRect.opacity = 0.8;
            grabInput(loader);
            if (!loader.item.restoreFocusItem) {
                let item = loader.item.mainItem.nextItemInFocusChain();
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
            } else {
                loader.item.restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
                loader.item.restoreFocusItem = null;
            }
        }
    }
    function openPlaceboSettings() {
        if (!displaySettingsRect.opacity && !placeboSettingsRect.opacity && !colorMappingSettingsRect.opacity)
            useSeparateStreamSettingsWindows = preferSeparateStreamSettingsWindows;
        const loader = useSeparateStreamSettingsWindows ? separatePlaceboSettingsLoader : placeboSettingsLoader;
        if(loader.status == Loader.Ready)
        {
            if(placeboSettingsRect.opacity || displaySettingsRect.opacity || colorMappingSettingsRect.opacity)
                closeDialog();
            placeboSettingsRect.opacity = 0.8;
            grabInput(loader);
            if (!loader.item.restoreFocusItem) {
                let item = loader.item.mainItem.nextItemInFocusChain();
                if (item)
                    item.forceActiveFocus(Qt.TabFocusReason);
            } else {
                loader.item.restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
                loader.item.restoreFocusItem = null;
            }
        }
    }

    function closeDialog() {
       if(displaySettingsRect.opacity) {
        displaySettingsRect.opacity = 0.0;
        const loader = useSeparateStreamSettingsWindows ? separateDisplaySettingsLoader : displaySettingsLoader;
        loader.item.restoreFocusItem = Window.window.activeFocusItem;
        releaseInput();
        useSeparateStreamSettingsWindows = false;
       }
       else if(placeboSettingsRect.opacity) {
        placeboSettingsRect.opacity = 0.0;
        const loader = useSeparateStreamSettingsWindows ? separatePlaceboSettingsLoader : placeboSettingsLoader;
        loader.item.restoreFocusItem = Window.window.activeFocusItem;
        releaseInput();
        useSeparateStreamSettingsWindows = false;
       }
       else if(colorMappingSettingsRect.opacity) {
        releaseInput();
        colorMappingSettingsRect.opacity = 0.0;
        const loader = useSeparateStreamSettingsWindows ? separateColorMappingSettingsLoader : colorMappingSettingsLoader;
        loader.item.restoreFocusItem = Window.window.activeFocusItem;
        root.openPlaceboSettings();
       }
       else
        stack.pop();
    }

    function showMainView() {
        if(displaySettingsRect.opacity) {
            displaySettingsRect.opacity = 0.0;
            const loader = useSeparateStreamSettingsWindows ? separateDisplaySettingsLoader : displaySettingsLoader;
            loader.item.restoreFocusItem = Window.window.activeFocusItem;
            releaseInput();
            useSeparateStreamSettingsWindows = false;
        }
        else if(placeboSettingsRect.opacity) {
            placeboSettingsRect.opacity = 0.0;
            const loader = useSeparateStreamSettingsWindows ? separatePlaceboSettingsLoader : placeboSettingsLoader;
            loader.item.restoreFocusItem = Window.window.activeFocusItem;
            releaseInput();
            useSeparateStreamSettingsWindows = false;
        }
        else if(colorMappingSettingsRect.opacity) {
            colorMappingSettingsRect.opacity = 0.0;
            const loader = useSeparateStreamSettingsWindows ? separateColorMappingSettingsLoader : colorMappingSettingsLoader;
            loader.item.restoreFocusItem = Window.window.activeFocusItem;
            releaseInput();
            useSeparateStreamSettingsWindows = false;
        }
        if (stack.depth > 1)
            stack.pop(stack.get(0));
        else
            stack.replace(stack.get(0), mainViewComponent);
    }

    function showStreamView() {
        stack.replace(stack.get(0), streamViewComponent);
    }

    function showPsnView() {
        stack.replace(stack.get(0), psnViewComponent, {}, StackView.Immediate)
    }

    function showManualHostDialog() {
        stack.push(manualHostDialogComponent);
    }

    function showConfirmDialog(title, text, callback, rejectCallback = null) {
        confirmDialog.title = title;
        confirmDialog.text = text;
        confirmDialog.callback = callback;
        confirmDialog.rejectCallback = rejectCallback;
        confirmDialog.restoreFocusItem = Window.window.activeFocusItem;
        confirmDialog.open();
    }

    function showInfoDialog(title, text) {
        infoDialog.title = title;
        infoDialog.text = text;
        infoDialog.restoreFocusItem = Window.window.activeFocusItem;
        infoDialog.open();
    }

    function showRendererFallbackDialog(reason) {
        showInfoDialog(qsTr("Renderer Fallback"),
                       qsTr("Vulkan renderer is unavailable and Nimbus Remote switched to OpenGL.\n\nReason: %1").arg(reason));
    }

    function showRemindDialog(title, text, remotePlay, callback) {
        remindDialog.title = title;
        remindDialog.text = text;
        remindDialog.remotePlay = remotePlay;
        remindDialog.callback = callback;
        remindDialog.restoreFocusItem = Window.window.activeFocusItem;
        remindDialog.open();
    }


    function showRegistDialog(host, ps5) {
        stack.push(registDialogComponent, {host: host, ps5: ps5});
    }

    function showSettingsDialog() {
        stack.push(settingsDialogComponent);
    }

    function showDisplaySettingsDialog() {
        stack.push(displaySettingsDialogComponent);
    }

    function showPlaceboSettingsDialog() {
        stack.push(placeboSettingsDialogComponent);
    }

    function showPlaceboColorMappingDialog() {
        if(placeboSettingsRect.opacity)
        {
            root.closeDialog();
            useSeparateStreamSettingsWindows = preferSeparateStreamSettingsWindows;
            const loader = useSeparateStreamSettingsWindows ? separateColorMappingSettingsLoader : colorMappingSettingsLoader;
            if(loader.status == Loader.Ready)
            {
                grabInput(loader);
                colorMappingSettingsRect.opacity = 0.8;
                if (!loader.item.restoreFocusItem) {
                    let item = loader.item.mainItem.nextItemInFocusChain();
                    if (item)
                        item.forceActiveFocus(Qt.TabFocusReason);
                } else {
                    loader.item.restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
                    loader.item.restoreFocusItem = null;
                }
            }
        }
        else
            stack.push(placeboColorMappingDialogComponent);
    }

    function showProfileDialog() {
        stack.push(profileDialogComponent)
    }

    function showConsolePinDialog(consoleIndex) {
        stack.push(consolePinDialogComponent, {consoleIndex: consoleIndex});
    }

    function showSteamShortcutDialog(fromReminder) {
        stack.push(steamShortcutDialogComponent, {fromReminder: fromReminder});
    }

    function showPSNTokenDialog(psnurl, expired) {
        stack.push(psnTokenDialogComponent, {psnurl: psnurl, expired: expired});
    }

    function showControllerMappingDialog() {
        stack.push(controllerMappingDialogComponent)
    }

    Component.onCompleted: {
        if (Chiaki.session)
            stack.replace(stack.get(0), streamViewComponent, {}, StackView.Immediate);
        else if (Chiaki.autoConnect)
            stack.replace(stack.get(0), autoConnectViewComponent, {}, StackView.Immediate);
    }

    Pane {
        anchors.fill: parent
        visible: !Chiaki.window.hasVideo && !Chiaki.window.keepVideo
    }

    StackView {
        id: stack
        anchors.fill: parent
        hoverEnabled: false
        initialItem: mainViewComponent
        font.pixelSize: 20

        replaceEnter: Transition {
            PropertyAnimation {
                property: "opacity"
                from: 0.01
                to: 1.0
                duration: 200
            }
        }

        replaceExit: Transition {
            PropertyAnimation {
                property: "opacity"
                from: 1.0
                to: 0.0
                duration: 200
            }
        }
    }

    Rectangle {
        id: placeboSettingsRect
        opacity: 0.0
        visible: opacity && !useSeparateStreamSettingsWindows
        height: 650
        width: 1200
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        color: Material.background
        Loader {
            anchors.fill: parent
            id: placeboSettingsLoader
            sourceComponent: placeboSettingsDialogComponent
        }
    }
    Rectangle {
        id: displaySettingsRect
        opacity: 0.0
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        height: 500
        width: 1200
        visible: opacity && !useSeparateStreamSettingsWindows
        color: Material.background
        Loader {
            anchors.fill: parent
            id: displaySettingsLoader
            sourceComponent: displaySettingsDialogComponent
        }
    }
    Rectangle {
        id: colorMappingSettingsRect
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        opacity: 0.0
        height: 600
        width: 1200
        visible: opacity && !useSeparateStreamSettingsWindows
        color: Material.background
        Loader {
            anchors.fill: parent
            id: colorMappingSettingsLoader
            sourceComponent: placeboColorMappingDialogComponent
        }
    }

    Window {
        id: separateDisplaySettingsWindow
        visible: useSeparateStreamSettingsWindows && displaySettingsRect.opacity > 0.0
        transientParent: Chiaki.window
        flags: Qt.Dialog | Qt.FramelessWindowHint
        color: Material.background
        modality: Qt.NonModal
        x: Math.round(root.mapToGlobal(0, 0).x)
        y: Math.round(root.mapToGlobal(0, 0).y)
        width: Math.round(root.width)
        height: separateDisplaySettingsLoader.item ? Math.min(Math.round(root.height), Math.round(separateDisplaySettingsLoader.item.gridHeight + 140)) : 500
        onVisibleChanged: if (visible) requestActivate()

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.closeDialog()
        }

        Shortcut {
            sequence: StandardKey.Cancel
            onActivated: root.closeDialog()
        }

        Loader {
            anchors.fill: parent
            id: separateDisplaySettingsLoader
            sourceComponent: displaySettingsDialogComponent
        }
    }

    Window {
        id: separatePlaceboSettingsWindow
        visible: useSeparateStreamSettingsWindows && placeboSettingsRect.opacity > 0.0
        transientParent: Chiaki.window
        flags: Qt.Dialog | Qt.FramelessWindowHint
        color: Material.background
        modality: Qt.NonModal
        x: Math.round(root.mapToGlobal(0, 0).x)
        y: Math.round(root.mapToGlobal(0, 0).y)
        width: Math.round(root.width)
        height: Math.min(Math.round(root.height), 650)
        onVisibleChanged: if (visible) requestActivate()

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.closeDialog()
        }

        Shortcut {
            sequence: StandardKey.Cancel
            onActivated: root.closeDialog()
        }

        Loader {
            anchors.fill: parent
            id: separatePlaceboSettingsLoader
            sourceComponent: placeboSettingsDialogComponent
        }
    }

    Window {
        id: separateColorMappingSettingsWindow
        visible: useSeparateStreamSettingsWindows && colorMappingSettingsRect.opacity > 0.0
        transientParent: Chiaki.window
        flags: Qt.Dialog | Qt.FramelessWindowHint
        color: Material.background
        modality: Qt.NonModal
        x: Math.round(root.mapToGlobal(0, 0).x)
        y: Math.round(root.mapToGlobal(0, 0).y)
        width: Math.round(root.width)
        height: Math.min(Math.round(root.height), 600)
        onVisibleChanged: if (visible) requestActivate()

        Shortcut {
            sequence: "Ctrl+O"
            onActivated: root.closeDialog()
        }

        Shortcut {
            sequence: StandardKey.Cancel
            onActivated: root.closeDialog()
        }

        Loader {
            anchors.fill: parent
            id: separateColorMappingSettingsLoader
            sourceComponent: placeboColorMappingDialogComponent
        }
    }
    Rectangle {
        anchors {
            bottom: parent.bottom
            horizontalCenter: parent.horizontalCenter
            bottomMargin: 30
        }
        color: Material.accent
        width: errorLayout.width + 40
        height: errorLayout.height + 20
        radius: 8
        opacity: errorHideTimer.running ? 0.8 : 0.0

        Behavior on opacity { NumberAnimation { duration: 500 } }

        ColumnLayout {
            id: errorLayout
            anchors.centerIn: parent

            Label {
                id: errorTitleLabel
                Layout.alignment: Qt.AlignCenter
                font.bold: true
                font.pixelSize: 24
            }

            Label {
                id: errorTextLabel
                Layout.alignment: Qt.AlignCenter
                horizontalAlignment: Text.AlignHCenter
                font.pixelSize: 20
            }
        }

        Timer {
            id: errorHideTimer
            interval: 2000
        }
    }

    Dialog {
        id: infoDialog
        property alias text: infoDialogLabel.text
        property Item restoreFocusItem
        parent: Overlay.overlay
        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)
        modal: true
        Material.roundedScale: Material.MediumScale
        onOpened: infoDialogLabel.forceActiveFocus(Qt.TabFocusReason)
        onClosed: {
            if (restoreFocusItem)
                restoreFocusItem.forceActiveFocus(Qt.TabFocusReason);
            infoDialogLabel.focus = false;
        }

        Component.onCompleted: {
            header.horizontalAlignment = Text.AlignHCenter;
            header.background = null;
        }

        ColumnLayout {
            spacing: 20

            Label {
                id: infoDialogLabel
                Keys.onEscapePressed: infoDialog.close()
                Keys.onReturnPressed: infoDialog.close()
            }

            RowLayout {
                Layout.alignment: Qt.AlignCenter

                Button {
                    text: qsTr("OK")
                    Material.background: Material.accent
                    flat: true
                    leftPadding: 50
                    onClicked: infoDialog.close()
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
                        source: root.controllerButton("cross")
                    }
                }
            }
        }
    }

    ConfirmDialog {
        id: confirmDialog
    }

    RemindDialog {
        id: remindDialog
    }

    // Connection-quality tracking for the current session, turned into advice when it ends
    property string sessionAdvice: ""
    property var lastConsole: null
    property var sessionQuality: ({ samples: 0, lossSum: 0, lossMax: 0, pingSum: 0, pingSamples: 0, bitrateSum: 0, dropped: 0 })
    // Plain-text numbers from the last session, included in "Copy diagnostics"
    property string lastSessionStats: ""

    Timer {
        id: sessionQualitySampler
        interval: 2000
        repeat: true
        running: !!Chiaki.session && Chiaki.session.connected
        onTriggered: {
            const q = root.sessionQuality;
            const loss = Chiaki.session.averagePacketLoss;
            if (isFinite(loss)) {
                q.samples++;
                q.lossSum += loss;
                q.lossMax = Math.max(q.lossMax, loss);
                q.bitrateSum += Chiaki.session.measuredBitrate;
            }
            const ping = Chiaki.session.pingMs;
            if (ping > 0) {
                q.pingSum += ping;
                q.pingSamples++;
            }
            q.dropped = Chiaki.window.droppedFrames;
        }
    }

    function copyDiagnostics() {
        if (Chiaki.copyDiagnostics(root.lastSessionStats))
            root.showToast(qsTr("Diagnostics copied. Paste them into a message."));
    }

    // Short message at the bottom of the screen
    function showToast(text) {
        homeToastLabel.text = text;
        homeToast.opacity = 1;
        homeToastTimer.restart();
    }
    Rectangle {
        id: homeToast
        z: 1000
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: 110
        }
        radius: 20
        color: Qt.rgba(0.05, 0.07, 0.11, 0.94)
        border.color: Qt.rgba(1, 1, 1, 0.2)
        implicitWidth: homeToastLabel.implicitWidth + 40
        implicitHeight: homeToastLabel.implicitHeight + 20
        opacity: 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Label {
            id: homeToastLabel
            anchors.centerIn: parent
            font.pixelSize: 15
        }
        Timer {
            id: homeToastTimer
            interval: 3500
            onTriggered: homeToast.opacity = 0
        }
    }

    // ---- Connection test: a short stream at Quality settings, measured, then a recommendation ----
    readonly property int connectionTestSeconds: 12
    // null when no test runs; otherwise { host, saved, samples, lossSum, lossMax, pingSum, pingSamples,
    // bitrateSum, droppedStart, droppedEnd, framesLostStart, framesLostEnd, done }
    property var connectionTest: null

    readonly property var presetSettingKeys: ["resolutionLocalPS5", "fpsLocalPS5", "bitrateLocalPS5", "codecLocalPS5",
        "resolutionRemotePS5", "fpsRemotePS5", "bitrateRemotePS5", "codecRemotePS5"]

    function startConnectionTest(host, index) {
        if (Chiaki.session || connectionTest)
            return;
        let saved = {};
        for (const k of presetSettingKeys)
            saved[k] = Chiaki.settings[k];
        // Test at the heaviest preset: if that streams cleanly, everything lighter will too
        Presets.apply(Chiaki.settings, Presets.byKey("quality"));
        connectionTest = { host: host, saved: saved, samples: 0, lossSum: 0, lossMax: 0, pingSum: 0, pingSamples: 0,
            bitrateSum: 0, droppedStart: -1, droppedEnd: 0, framesLostStart: -1, framesLostEnd: 0, done: false };
        lastConsole = host;
        if (host.discovered)
            Chiaki.connectToHost(index, host.name);
        else
            Chiaki.connectToHost(index);
    }

    function restoreAfterConnectionTest() {
        const t = connectionTest;
        if (!t)
            return;
        for (const k in t.saved)
            Chiaki.settings[k] = t.saved[k];
    }

    Timer {
        id: connectionTestSampler
        interval: 500
        repeat: true
        running: !!root.connectionTest && !root.connectionTest.done && !!Chiaki.session && Chiaki.session.connected && Chiaki.window.hasVideo
        onTriggered: {
            const t = root.connectionTest;
            if (t.droppedStart < 0) {
                t.droppedStart = Chiaki.window.droppedFrames;
                t.framesLostStart = Chiaki.session.framesLost;
            }
            t.samples++;
            const loss = Chiaki.session.averagePacketLoss;
            if (isFinite(loss)) {
                t.lossSum += loss;
                t.lossMax = Math.max(t.lossMax, loss);
            }
            t.bitrateSum += Chiaki.session.measuredBitrate;
            if (Chiaki.session.pingMs > 0) {
                t.pingSum += Chiaki.session.pingMs;
                t.pingSamples++;
            }
            t.droppedEnd = Chiaki.window.droppedFrames;
            t.framesLostEnd = Chiaki.session.framesLost;
            root.connectionTestProgress = t.samples / (root.connectionTestSeconds * 2);
            if (t.samples >= root.connectionTestSeconds * 2) {
                t.done = true;
                // End the stream without putting the console to sleep
                Chiaki.stopSession(false);
            }
        }
    }
    property real connectionTestProgress: 0

    function finishConnectionTest() {
        const t = connectionTest;
        connectionTest = null;
        connectionTestProgress = 0;
        if (!t)
            return;
        for (const k in t.saved)
            Chiaki.settings[k] = t.saved[k];
        if (!t.done || t.samples < 6) {
            showConfirmDialog(qsTr("Connection test"),
                qsTr("The test stopped before it could measure enough. Make sure the console is on and try again."),
                () => {});
            return;
        }
        const seconds = t.samples / 2;
        const loss = t.lossSum / t.samples;
        const ping = t.pingSamples ? t.pingSum / t.pingSamples : 0;
        const bitrate = t.bitrateSum / t.samples;
        const dropped = Math.max(0, t.droppedEnd - t.droppedStart) + Math.max(0, t.framesLostEnd - t.framesLostStart);
        const droppedPerSec = dropped / seconds;

        let key, why;
        if (loss < 0.005 && t.lossMax < 0.03 && droppedPerSec < 0.3 && (ping === 0 || ping < 40)) {
            key = "quality";
            why = qsTr("The connection kept up with the heaviest stream.");
        } else if (loss < 0.02 && droppedPerSec < 1.5 && (ping === 0 || ping < 70)) {
            key = "balanced";
            why = qsTr("The heaviest stream lost a little data; Balanced leaves headroom.");
        } else {
            key = "performance";
            why = qsTr("The connection struggled with the heaviest stream; Performance keeps it smooth.");
        }
        const preset = Presets.byKey(key);
        const name = t.host.name || qsTr("this console");
        const numbers = qsTr("Ping %1 · packet loss %2% (worst %3%) · %4 Mbps · %5 dropped frames in %6 s")
            .arg(ping > 0 ? ping.toFixed(0) + " ms" : qsTr("n/a"))
            .arg((loss * 100).toFixed(1)).arg((t.lossMax * 100).toFixed(1))
            .arg(bitrate.toFixed(1)).arg(dropped).arg(seconds.toFixed(0));
        lastSessionStats = qsTr("Connection test: %1, recommended %2").arg(numbers).arg(preset.name);
        showConfirmDialog(qsTr("Connection test: %1 recommended").arg(qsTr(preset.name)),
            numbers + "\n\n" + why + "\n\n" + qsTr("Use %1 for %2?").arg(qsTr(preset.name)).arg(name),
            () => { root.connectionTestApplied(t.host, key); });
    }
    // MainView stores the per-console preset
    signal connectionTestApplied(var host, string key)

    // ---- Preferences that live outside the C++ settings ----
    Settings {
        id: nimbusPrefs
        category: "nimbus_prefs"
        property bool replayEnabled: false
    }
    property alias replayPreferred: nimbusPrefs.replayEnabled

    // Turn instant replay back on for each new stream if it was on last time
    Connections {
        target: Chiaki.session
        ignoreUnknownSignals: true
        function onConnectedChanged() {
            if (Chiaki.session && Chiaki.session.connected && root.replayPreferred && !Chiaki.session.replayEnabled)
                Chiaki.session.replayEnabled = true;
        }
    }

    // ---- Lighter quality during a stream ----
    // The PS5 fixes the stream quality when a session starts, so changing it means reconnecting.
    // When the connection keeps struggling, the stream offers that; the in-game menu always can.
    readonly property var currentPreset: {
        Chiaki.settings.resolutionLocalPS5; Chiaki.settings.resolutionRemotePS5; Chiaki.settings.bitrateLocalPS5;
        for (const p of Presets.list)
            if (Presets.matches(Chiaki.settings, p))
                return p;
        return null; // custom settings
    }
    // Next lighter preset, or null if already on the lightest
    readonly property var lighterPreset: {
        if (!currentPreset)
            return Presets.byKey("performance");
        // "30 fps games" is its own choice, not a step on the Performance-Balanced-Quality ladder
        if (currentPreset.special)
            return null;
        const i = Presets.list.indexOf(currentPreset);
        return i > 0 ? Presets.list[i - 1] : null;
    }
    property string reconnectConsoleId: ""
    property bool struggleOffered: false
    property int struggleSeconds: 0

    function switchToLighterAndReconnect() {
        const p = lighterPreset;
        if (!p || !Chiaki.session)
            return;
        Presets.apply(Chiaki.settings, p);
        if (lastConsole) {
            // Remember it for this console so the next session starts lighter too
            connectionTestApplied(lastConsole, p.key);
            reconnectConsoleId = Presets.consoleId(lastConsole);
        }
        Chiaki.stopSession(false);
    }

    Timer {
        // Reconnect shortly after the old session has closed
        id: reconnectTimer
        interval: 1500
        onTriggered: {
            const id = root.reconnectConsoleId;
            root.reconnectConsoleId = "";
            for (let i = 0; i < Chiaki.hosts.length; i++) {
                const h = Chiaki.hosts[i];
                if (h.display && Presets.consoleId(h) === id) {
                    root.lastConsole = h;
                    if (h.discovered)
                        Chiaki.connectToHost(i, h.name);
                    else
                        Chiaki.connectToHost(i);
                    return;
                }
            }
            root.showToast(qsTr("Couldn't find the console to reconnect. Press Play to start again."));
        }
    }

    // Watches the stream: about 20 s of sustained trouble -> offer a lighter preset (once per session)
    Timer {
        interval: 1000
        repeat: true
        running: !!Chiaki.session && Chiaki.session.connected && !root.connectionTest && !root.struggleOffered
        property int lastDropped: -1
        onTriggered: {
            const loss = isFinite(Chiaki.session.averagePacketLoss) ? Chiaki.session.averagePacketLoss : 0;
            const dropped = Chiaki.window.droppedFrames;
            const droppedNow = lastDropped >= 0 ? dropped - lastDropped : 0;
            lastDropped = dropped;
            const bad = loss > 0.04 || droppedNow >= 4;
            root.struggleSeconds = bad ? root.struggleSeconds + 1 : Math.max(0, root.struggleSeconds - 2);
            if (root.struggleSeconds >= 20 && root.lighterPreset) {
                root.struggleOffered = true;
                root.struggleLoss = loss;
            }
        }
    }
    property real struggleLoss: 0

    function finishSessionQuality() {
        const q = sessionQuality;
        sessionQuality = { samples: 0, lossSum: 0, lossMax: 0, pingSum: 0, pingSamples: 0, bitrateSum: 0, dropped: 0 };
        if (q.samples > 0 && !connectionTest) {
            lastSessionStats = qsTr("Measured over %1 s: average packet loss %2% (worst %3%), average ping %4 ms, average bitrate %5 Mbps, dropped frames %6")
                .arg(q.samples * 2)
                .arg((q.lossSum / q.samples * 100).toFixed(1)).arg((q.lossMax * 100).toFixed(1))
                .arg(q.pingSamples ? (q.pingSum / q.pingSamples).toFixed(0) : "n/a")
                .arg((q.bitrateSum / q.samples).toFixed(1)).arg(q.dropped);
        }
        // A connection test reports on its own
        if (connectionTest)
            return;
        // Need ~20 s of data before judging
        if (q.samples < 10)
            return;
        const avgLoss = q.lossSum / q.samples;
        const avgPing = q.pingSamples ? q.pingSum / q.pingSamples : 0;
        let problems = [];
        if (avgLoss > 0.02)
            problems.push(qsTr("%1% average packet loss").arg((avgLoss * 100).toFixed(1)));
        if (avgPing > 60)
            problems.push(qsTr("%1 ms average ping").arg(avgPing.toFixed(0)));
        sessionAdvice = problems.length
            ? qsTr("Last session had %1. A lighter preset or a wired connection should make it smoother.").arg(problems.join(qsTr(" and ")))
            : "";
    }

    Connections {
        target: Chiaki

        function onSessionChanged() {
            if (Chiaki.session) {
                root.sessionQuality = { samples: 0, lossSum: 0, lossMax: 0, pingSum: 0, pingSamples: 0, bitrateSum: 0, dropped: 0 };
                root.sessionAdvice = "";
                root.struggleOffered = false;
                root.struggleSeconds = 0;
                root.showStreamView();
            } else {
                root.finishSessionQuality();
                if (root.connectionTest)
                    root.finishConnectionTest();
                if (root.reconnectConsoleId) {
                    root.sessionAdvice = "";
                    reconnectTimer.restart();
                }
            }
        }

        function onShowPsnView() {
            root.showPsnView();
        }

        function onPsnCredsExpired() {
            Chiaki.settings.psnRefreshToken = ""
            Chiaki.settings.psnAuthToken = ""
            Chiaki.settings.psnAuthTokenExpiry = ""
            Chiaki.settings.psnAccountId = ""
            root.showPSNTokenDialog(true);
        }

        function onError(title, text) {
            errorTitleLabel.text = title;
            errorTextLabel.text = text;
            errorHideTimer.start();
        }

        function onRegistDialogRequested(host, ps5, duid) {
            if(!duid)
                showRegistDialog(host, ps5);
            else
            {
                if(ps5)
                    root.showConfirmDialog(qsTr("Registration Type"), qsTr("Would you like to use automatic registration?"), () => root.autoRegister(true, host, ps5), () => root.autoRegister(false, host, ps5))
                else
                    root.showConfirmDialog(qsTr("Registration Type"), qsTr("Would you like to use automatic registration (must be main PS4 console registered to your PSN)?"), () => root.autoRegister(true, host, ps5), () => root.autoRegister(false, host, ps5))
            }
        }

        function onWakeupStartInitiated() {
            stack.replace(stack.get(0), autoConnectViewComponent, {}, StackView.Immediate);
        }
    }

    Component {
        id: mainViewComponent
        MainView { }
    }

    Component {
        id: streamViewComponent
        StreamView { }
    }

    Component {
        id: autoConnectViewComponent
        AutoConnectView { }
    }

    Component {
        id: psnViewComponent
        PsnView {}
    }

    Component {
        id: manualHostDialogComponent
        ManualHostDialog { }
    }

    Component {
        id: settingsDialogComponent
        SettingsDialog { }
    }

    Component {
        id: displaySettingsDialogComponent
        DisplaySettingsDialog { }
    }

    Component {
        id: placeboSettingsDialogComponent
        PlaceboSettingsDialog { }
    }

    Component {
        id: placeboColorMappingDialogComponent
        PlaceboColorMappingDialog { }
    }

    Component {
        id: profileDialogComponent
        ProfileDialog { }
    }

    Component {
        id: consolePinDialogComponent
        ConsolePinDialog { }
    }

    Component {
        id: steamShortcutDialogComponent
        SteamShortcutDialog { }
    }

    Component {
        id: psnTokenDialogComponent
        PSNTokenDialog { }
    }

    Component {
        id: registDialogComponent
        RegistDialog { }
    }

    Component {
        id: controllerMappingDialogComponent
        ControllerMappingDialog { }
    }
}
