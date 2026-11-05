import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Windows as Win

ShellRoot {
    id: root
    property string phase: "starting"
    property int step: 0
    function report() {
        output.setText(JSON.stringify({phase: root.phase, available: Win.DesktopLayer.nativeGlassAvailable}));
    }
    Component.onCompleted: {
        Win.DesktopLayer.enabled = true;
        Win.DesktopLayer.nativeGlassNamespaces = [];
    }
    Connections {
        target: Win.DesktopLayer
        function onNativeGlassAvailableChanged() { root.report(); }
    }
    FileView {
        id: output
        path: Quickshell.env("IIW_GLASS_TEST_PHASE")
    }
    PanelWindow {
        title: "ii native glass lifecycle test"
        visible: true
        implicitWidth: 240
        implicitHeight: 160
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:desktopGlassTest"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        Rectangle {
            anchors.fill: parent
            radius: 24
            color: "#48203040"
        }
    }
    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: {
            const phases = ["embedded", "native", "embedded-again", "native-again"];
            if (root.step >= phases.length) {
                Win.DesktopLayer.nativeGlassNamespaces = [];
                Qt.quit();
                return;
            }
            root.phase = phases[root.step];
            Win.DesktopLayer.nativeGlassNamespaces = root.step % 2 === 1 ? ["quickshell:desktopGlassTest"] : [];
            root.report();
            root.step++;
        }
    }
}
