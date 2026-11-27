// The cinema control pill (pages-a.js .cine-bar, pages.css .cine-bar), shared by the
// minimal page and the fullscreen control window (G2.5). Only the pill: where it
// sits and how it enters belong to the owner.
//
// .cine-bar: three columns, 92px tall, radius 30. The design's
// frosted glass cannot sample a native video window, so the fill is the opaque
// approximation rgba(22,22,26,.86) (D5).
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

Rectangle {
    id: bar
    signal requestPage(string page)
    // Opens one of the main window's dialogs (字幕设置 / 音频设置).
    signal requestDialog(string key)
    signal requestFullscreen()
    signal requestLock()
    // Windowed 极简: a drag on the pill's empty space moves the window, like a title bar.
    signal requestMove()
    signal requestHide()
    // Set on the fullscreen bar: shows the lock button.
    property bool fullscreen: false
    // Set by FullscreenBar so upward menus stop above the playback pill.
    property real menuBottomLimit: -1
    // Any popover needs the owner window's full mask, not just the preset menu.
    readonly property bool menuOpen: presetMenu.visible
    // The pointer is over the pill.
    readonly property bool hovered: barHover.hovered
    readonly property bool compact: width < 820
    // OverRez: no volume slider (screen capture has no sound of its own), so nothing edits.
    readonly property bool editing: false
    readonly property bool interacting: false
    function finishEditing() { }
    HoverHandler { id: barHover }
    // Buttons, the seek rail and the volume slider take their own presses first; only
    // a drag that starts on empty pill reaches this one.
    DragHandler {
        objectName: "cine-move"
        target: null
        enabled: !bar.fullscreen && !bar.interacting
        // Never take a drag over from a control: by default a DragHandler steals the grab
        // from an item once the pointer passes the drag threshold, so scrubbing the seek
        // rail moved the window instead (field report 2026-10-02).
        grabPermissions: PointerHandler.CanTakeOverFromHandlersOfDifferentType | PointerHandler.ApprovesTakeOverByAnything
        onActiveChanged: if (active) bar.requestMove()
    }
    implicitHeight: 92
    radius: 30
    color: Theme.shade(22, 22, 26, 0.86)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.1)

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 12

        // --- left: source icon and title -----------------------------
        RowLayout {
            Layout.preferredWidth: 230; Layout.minimumWidth: 112; Layout.maximumWidth: 230
            Layout.fillHeight: true
            spacing: 10
            Rectangle {
                id: coverPlate
                implicitWidth: 46; implicitHeight: 46; radius: 12
                color: Theme.videoBlack
                border.width: 1
                border.color: Theme.stroke
                VIcon { anchors.centerIn: parent; name: "monitor"; color: Theme.t2 }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: veyra.sourceName.length > 0 ? veyra.sourceName : qsTr("未打开")
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: 13
                    font.weight: Font.DemiBold; font.variableAxes: Theme.axesDemiBold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    text: veyra.sourceSummary
                    color: Theme.t3
                    font.family: Theme.fontUi
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
        }

        // --- middle: transport + seek --------------------------------
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: transport.implicitWidth
            Layout.alignment: Qt.AlignVCenter
            spacing: 4

            RowLayout {
                id: transport
                Layout.alignment: Qt.AlignHCenter
                spacing: bar.compact ? 4 : 6

                // .cbtn: 32px round, muted, brightens on hover.
                component CBtn: Item {
                    id: cbtn
                    property string glyph: ""
                    property string tip: ""
                    property bool highlighted: false
                    // The signal has to be declared: an inline component does not
                    // inherit the TapHandler's signal, so callers cannot assign
                    // onTapped without it.
                    signal tapped()
                    implicitWidth: 32
                    implicitHeight: 32
                    Rectangle {
                        anchors.fill: parent
                        radius: 16
                        color: cHover.hovered ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    }
                    VIcon {
                        anchors.centerIn: parent
                        name: glyph
                        color: cbtn.highlighted ? Theme.warn : cHover.hovered ? "#FFFFFF" : Theme.t2
                    }
                    scale: cTap.pressed ? 0.86 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.d(400); easing.bezierCurve: Theme.spring } }
                    HoverHandler { id: cHover; cursorShape: Qt.PointingHandCursor }
                    ToolTip.visible: cHover.hovered && cbtn.tip.length > 0
                    ToolTip.text: cbtn.tip
                    TapHandler { id: cTap; gesturePolicy: TapHandler.WithinBounds; onTapped: cbtn.tapped() }
                }

                // 载入: screen capture without leaving 极简.
                CBtn { objectName: "cine-load"; glyph: "monitor"; tip: qsTr("屏幕捕获"); onTapped: veyra.openScreenCaptureDialog() }

                // .play: 40px white circle with the play/pause glyph.
                Item {
                    implicitWidth: 40
                    implicitHeight: 40
                    Rectangle {
                        anchors.fill: parent
                        radius: 20
                        color: "#FFFFFF"
                    }
                    VIcon {
                        anchors.centerIn: parent
                        name: (veyra.running && !veyra.paused) ? "pausefill" : "playfill"
                        filled: true
                        color: "#0A0A0C"
                    }
                    scale: playTap.pressed ? 0.88 : (playHover.hovered ? 1.06 : 1.0)
                    Behavior on scale { NumberAnimation { duration: Theme.d(450); easing.bezierCurve: Theme.spring } }
                    HoverHandler { id: playHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { id: playTap; gesturePolicy: TapHandler.WithinBounds; onTapped: veyra.togglePlayPause() }
                }
            }

        }

        // --- right: preset, volume, picture and bar controls ----------
        RowLayout {
            Layout.fillWidth: false
            Layout.minimumWidth: implicitWidth
            Layout.alignment: Qt.AlignVCenter | Qt.AlignRight
            spacing: 6

            // .pill with a status dot: the dot reports the engine's state, and
            // the label is the preset actually in use.
            VPill {
                key: ""
                value: veyra.currentPresetName
                maximumValueWidth: bar.compact ? 52 : 80
                onClicked: presetMenu.openAt(this, "up")
                Rectangle {
                    width: 7; height: 7; radius: 3.5
                    color: veyra.failed ? Theme.err : veyra.captureRecovering ? Theme.warn : Theme.ok
                }
            }

            RotateButton { objectName: "cine-rotate" }

            Item {
                implicitWidth: 32; implicitHeight: 32
                VIcon {
                    anchors.centerIn: parent
                    name: "max"
                    color: Theme.t2
                }
                HoverHandler { cursorShape: Qt.PointingHandCursor }
                // The design's "全屏" button (title="全屏"). It used to call an
                // undefined root.requestPage("pro").
                TapHandler { onTapped: bar.requestFullscreen() }
            }
            // Hide the pill (field request 2026-10-01: it covers the game when playing
            // through a capture card or a stream). The dock's eye button brings it back.
            Item {
                objectName: "cine-hide"
                implicitWidth: 32; implicitHeight: 32
                VIcon { anchors.centerIn: parent; name: "eyeoff"; color: hideHover.hovered ? "#FFFFFF" : Theme.t2 }
                HoverHandler { id: hideHover; cursorShape: Qt.PointingHandCursor }
                ToolTip.visible: hideHover.hovered
                ToolTip.text: qsTr("隐藏播放条（顶部胶囊里可重新打开）")
                TapHandler { onTapped: bar.requestHide() }
            }
        }
    }

    // The preset menu: list presets and node presets in one menu, as designed.
    // pages-a.js presetMenu: list presets, node presets, then the way to manage them.
    VMenu {
        id: presetMenu
        aboveLimit: bar.menuBottomLimit
        title: qsTr("预设")
        readonly property var mk: p => ({ label: p.name, note: p.note, checked: p.name === veyra.currentPresetName,
                                          tag: p.nodeMode ? qsTr("节点") : "", preset: p.index })
        items: [{ head: qsTr("列表预设") }].concat(veyra.presets.filter(p => !p.nodeMode).map(mk))
            .concat([{ head: qsTr("节点预设") }]).concat(veyra.presets.filter(p => p.nodeMode).map(mk))
            .concat([{ sep: true }, { label: qsTr("去专业模式管理预设…"), icon: "sliders", act: "pro" }])
        onPicked: (i, o) => {
            if (o.act === "pro") bar.requestPage("pro")
            else veyra.applyPresetIndex(o.preset)
        }
    }
}
