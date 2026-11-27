// Dialog routing and scrim. Each dialog owns its own editable content.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Item {
    id: host
    // Compatibility type used by the professional and node views.
    component VTextField: DialogTextField {}
    anchors.fill: parent
    z: 100

    // Active dialog: screen/translation/audio/save/manage.
    property string dialog: ""
    property bool onboardingActive: false
    function open(key) {
        if (key === "save") saveDialog.resetForOpen()
        if (key === "manage") {
            manageDialog.mode = veyra.nodeMode === 1 ? "node" : "list"
            manageDialog.feedback = ""
        }
        veyra.logUi("ui-dialog", "open " + key + " (was " + (host.dialog || "none") + ")")
        host.dialog = key
    }
    function close() { host.dialog = "" }

    signal startScreen()
    signal startScreenCrop()

    // Scrim (M16): the design dims the page behind the dialog, opacity .2s linear.
    // The native video window cannot be dimmed from QML; only the dialog panel is cut
    // out of it (videoCover below), so the picture beside the dialog stays undimmed.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.55)
        opacity: host.dialog !== "" && !host.onboardingActive ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Theme.d(200) } }
        TapHandler { onTapped: host.close() }
    }
    // For the motion probe: the open dialog's scale.
    property real motionScale: 1

    LiveTranslationDialog {
        dialogHost: host
    }

    // --- 另存为预设 -------------------------------------------------------
    // The design lists every part that will be saved before asking for a name, so
    // the user can see what they are about to store.
    SavePresetDialog {
        id: saveDialog
        dialogHost: host
    }

    // --- 管理预设 ---------------------------------------------------------
    ManagePresetsDialog {
        id: manageDialog
        dialogHost: host
    }

    // --- small building blocks the design's dialogs use --------------------

}
