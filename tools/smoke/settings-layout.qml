//@ pragma Env IIW_PROCESS=settings
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.settingsPc.pages as Pages

ShellRoot {
    id: root
    property int testWidth: Number(Quickshell.env("IIW_UI_TEST_WIDTH"))
    property int index: 0
    property bool started: false
    property bool settled: false
    property var captures: ({})
    function find(item, name) {
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) {
            const result = find(child, name);
            if (result) return result;
        }
        return null;
    }
    function rectangle(item) {
        const p = item.mapToItem(window.contentItem, 0, 0);
        return {x: p.x, y: p.y, width: item.width, height: item.height};
    }
    function inside(rect) {
        return rect.width > 0 && rect.height > 0 && rect.x >= -1 && rect.y >= -1
            && rect.x + rect.width <= window.width + 1 && rect.y + rect.height <= window.height + 1;
    }
    function reset() {
        root.settled = false;
        Config.options.settings.collapsedSections = [];
        Config.options.windowsPort.wallpaperOwner = "auto";
        Config.options.windowsPort.nativeDesktopGlass = false;
        layoutTimer.restart();
    }
    function publish(state, imageItem) {
        const key = root.index + "-" + state.phase;
        if (imageItem && !root.captures[key]) {
            root.captures[key] = "pending";
            const ok = imageItem.grabToImage(result => {
                const saved = result.saveToFile(Quickshell.env("IIW_UI_TEST_IMAGES") + "/" + key + ".png");
                root.captures[key] = "done";
                if (!saved) state = {phase: "error", message: "Could not save owned-window screenshot"};
                output.setText(JSON.stringify(state));
                if (state.phase === "passed") advance.start();
            });
            if (!ok) { console.error("UI-LAYOUT-FAIL grabToImage"); Qt.exit(2); }
            return;
        }
        if (root.captures[key] === "pending") return;
        output.setText(JSON.stringify(state));
    }
    FileView { id: output; path: Quickshell.env("IIW_UI_TEST_STATE") }
    FloatingWindow {
        id: window
        title: "ii Settings layout test"
        visible: true
        implicitWidth: root.testWidth
        implicitHeight: 520
        color: "#18181b"
        Pages.BackgroundConfig { id: page; anchors.fill: parent }
    }
    Timer {
        id: layoutTimer
        interval: 1200
        onTriggered: {
            const owner = root.find(page, "wallpaperOwnerControl");
            if (!owner) { layoutTimer.restart(); return; }
            page.contentY = Math.max(0, page.contentY + owner.mapToItem(page, 0, 0).y - 64);
            scrollTimer.restart();
        }
    }
    Timer { id: scrollTimer; interval: 600; onTriggered: root.settled = true }
    Timer {
        id: advance
        interval: 1200
        onTriggered: Qt.exit(0)
    }
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            if (!Config.ready) return;
            if (!root.started) { root.started = true; root.reset(); }
            if (!root.settled) return;
            const owner = root.find(page, "wallpaperOwnerControl");
            const native = root.find(page, "nativeDesktopGlassControl");
            if (!owner?.comboBox || !native?.switchControl) return;
            const combo = owner.comboBox;
            const ownerRect = root.rectangle(combo);
            const switchRect = root.rectangle(native.switchControl);
            if (!root.inside(ownerRect) || !root.inside(switchRect)) {
                console.error("UI-LAYOUT-FAIL controls outside viewport", JSON.stringify({ownerRect, switchRect, width: window.width}));
                root.publish({phase: "error", message: "Control outside viewport", ownerRect, switchRect}, null);
                Qt.exit(2); return;
            }
            let target = null, imageItem = null, phase;
            if (Config.options.windowsPort.wallpaperOwner !== "external") {
                if (!combo.popup.visible) {
                    phase = "open-owner"; target = combo; imageItem = page;
                } else {
                    const row = combo.popup.contentItem.itemAtIndex(3);
                    if (!row || row.text !== "External app") return;
                    phase = "choose-external"; target = row; imageItem = combo.popup.contentItem;
                }
            } else if (combo.popup.visible) {
                return;
            } else if (!Config.options.windowsPort.nativeDesktopGlass) {
                phase = "enable-glass"; target = native.switchControl;
            } else {
                phase = "passed"; imageItem = page;
            }
            const point = target ? target.mapToGlobal(target.width / 2, target.height / 2) : {x: 0, y: 0};
            root.publish({phase, width: window.width, dpr: window.devicePixelRatio, target: point,
                owner: Config.options.windowsPort.wallpaperOwner,
                nativeGlass: Config.options.windowsPort.nativeDesktopGlass,
                glass: Config.options.background.widgets.glass.enable,
                behindIcons: Config.options.windowsPort.backgroundBehindIcons,
                ownerRect, switchRect}, imageItem);
        }
    }
}
