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
    readonly property bool menuOpen: presetMenu.visible || audioMenu.visible
    // The pointer is over the pill.
    readonly property bool hovered: barHover.hovered
    readonly property bool compact: width < 820
    readonly property bool seekPreviewOpen: seekMouse.enabled && (seekMouse.containsMouse || seekArea.scrubbing)
    readonly property bool editing: volumeSlider.editing
    // Keep the control window active until a seek releases its mouse grab, too.
    // Returning focus to the owner during scrubbing cancels the MouseArea press.
    readonly property bool interacting: seekArea.scrubbing || volumeSlider.pressed || editing
    function finishEditing() { volumeSlider.closeEditor(true) }
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
                CBtn { glyph: "back10"; onTapped: veyra.seekBy(-10) }

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

                CBtn { glyph: "fwd10"; onTapped: veyra.seekBy(10) }
                CBtn {
                    objectName: "cine-audio-tracks"
                    glyph: audioMenu.captureSource ? "vol" : "music"
                    tip: audioMenu.buttonLabel
                    highlighted: audioMenu.monitorOff
                    onTapped: audioMenu.openAt(this, "up")
                }
            }

            // .seekrow: mono times either side of the rail.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: veyra.positionText
                    color: Theme.t3
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                Item {
                    id: seekArea
                    objectName: "cine-seek"
                    Layout.fillWidth: true
                    implicitHeight: 14
                    property bool scrubbing: false
                    property real scrubFrac: 0
                    // .seek:hover .thumb { left: 44% } - the thumb tracks the real
                    // progress, not the design's hard-coded 44%.
                    readonly property real frac: scrubbing ? scrubFrac : Math.max(0, Math.min(1, shownProgress))
                    // Twice a second, not every snapshot: the pill is its own window and a rail
                    // that moved every tick made it present ~50 times a second, more often than
                    // a film plays, so OBS game capture could lock onto the pill.
                    property real shownProgress: veyra.progress
                    // Where the last scrub seek was sent, so a release that lands on
                    // the same spot does not interrupt it with a duplicate.
                    property real lastSeekTarget: -1
                    Timer {
                        interval: 500; repeat: true; running: bar.visible
                        onTriggered: seekArea.shownProgress = veyra.progress
                    }
                    readonly property real hoverFrac: scrubbing ? scrubFrac
                                                      : seekMouse.containsMouse && seekArea.width > 0
                                                        ? Math.max(0, Math.min(1, seekMouse.mouseX / seekArea.width))
                                                        : frac
                    property int thumbnailBucket: -1
                    function fractionAt(x) {
                        return seekArea.width > 0 ? Math.max(0, Math.min(1, x / seekArea.width)) : 0
                    }
                    Timer {
                        id: scrubSeek
                        // Restarted on every pointer move (see the MouseArea below), so it
                        // fires only once the drag settles. Seeking mid-drag makes two
                        // seeks overlap and they interrupt each other: a network source
                        // re-opens its read on each one, which is what made a drag look
                        // like a freeze. newBV defers the same way (1 s there).
                        interval: 250
                        onTriggered: {
                            if (!seekArea.scrubbing) return
                            const target = veyra.timelineSeconds(seekArea.scrubFrac)
                            seekArea.lastSeekTarget = target
                            veyra.seekTo(target)
                        }
                    }
                    Timer {
                        id: thumbnailDelay
                        interval: 120
                        onTriggered: seekArea.thumbnailBucket = -1
                    }
                    Rectangle {
                        id: rail
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: seekMouse.containsMouse ? 6 : 3
                        radius: 9
                        color: Qt.rgba(1, 1, 1, 0.14)
                        Behavior on height { NumberAnimation { duration: Theme.d(300); easing.bezierCurve: Theme.spring } }
                        // White; the sunset gradient along the rail in the dusk palette.
                        Rectangle {
                            width: parent.width * seekArea.frac
                            height: parent.height
                            radius: 9
                            color: "#FFFFFF"
                            visible: !Theme.accentGradient
                        }
                        VAccentFill {
                            width: parent.width * seekArea.frac
                            height: parent.height
                            radius: 9
                            farEnd: true
                            span: parent.width
                            visible: Theme.accentGradient
                        }
                    }
                    // .seek .thumb: 11px dot, scale 0 -> 1 over .4s --spring on hover.
                    Rectangle {
                        width: 11; height: 11; radius: 5.5
                        color: "#FFFFFF"
                        x: seekArea.frac * seekArea.width - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        scale: seekMouse.containsMouse || seekArea.scrubbing ? 1 : 0
                        Behavior on scale { NumberAnimation { duration: Theme.d(400); easing.bezierCurve: Theme.spring } }
                    }
                    // .seek .peek: 144x104 above the rail, opacity .15s, scale .85 -> 1
                    // over .4s --spring from its bottom centre.
                    Rectangle {
                        visible: opacity > 0.01
                        width: veyra.liveTimeshift.available ? 84 : 144
                        height: veyra.liveTimeshift.available ? 26 : 104
                        radius: 8
                        color: "#000000"
                        border.width: 1
                        border.color: Theme.stroke2
                        x: Math.max(0, Math.min(parent.width - width,
                                                seekArea.hoverFrac * seekArea.width - width / 2))
                        y: -height - 18
                        opacity: seekMouse.containsMouse || seekArea.scrubbing ? 1 : 0
                        scale: seekMouse.containsMouse || seekArea.scrubbing ? 1 : 0.85
                        transformOrigin: Item.Bottom
                        Behavior on opacity { NumberAnimation { duration: Theme.d(150) } }
                        Behavior on scale { NumberAnimation { duration: Theme.d(400); easing.bezierCurve: Theme.spring } }
                        Image {
                            id: previewFrame
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            height: 81
                            asynchronous: true
                            cache: true
                            fillMode: Image.PreserveAspectFit
                            source: ""
                        }
                        Text {
                            anchors.centerIn: previewFrame
                            visible: previewFrame.status === Image.Loading || previewFrame.status === Image.Error
                            text: previewFrame.status === Image.Loading ? qsTr("加载中") : qsTr("预览不可用")
                            color: Theme.t3
                            font.family: Theme.fontUi
                            font.pixelSize: 11
                        }
                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            height: 23
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: veyra.liveTimeshift.enabled
                                  ? "−" + veyra.formatTime(veyra.liveTimeshift.end - veyra.timelineSeconds(seekArea.hoverFrac))
                                  : veyra.formatTime(veyra.timelineSeconds(seekArea.hoverFrac))
                            color: Theme.t1
                            font.family: Theme.fontMono
                            font.pixelSize: 11
                            font.weight: Font.Medium; font.variableAxes: Theme.axesMedium
                            Rectangle {
                                anchors.fill: parent
                                z: -1
                                color: "#111111"
                            }
                        }
                    }
                    MouseArea {
                        id: seekMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        preventStealing: true
                        enabled: veyra.timelineSeekable
                        onEnabledChanged: if (!enabled && seekArea.scrubbing) {
                            scrubSeek.stop()
                            seekArea.scrubbing = false
                        }
                        cursorShape: Qt.PointingHandCursor
                        onEntered: thumbnailDelay.restart()
                        onExited: {
                            thumbnailDelay.stop()
                            seekArea.thumbnailBucket = -1
                        }
                        onPressed: mouse => {
                            seekArea.lastSeekTarget = -1
                            seekArea.scrubFrac = seekArea.fractionAt(mouse.x)
                            seekArea.scrubbing = true
                        }
                        onPositionChanged: mouse => {
                            if (seekArea.scrubbing) {
                                seekArea.scrubFrac = seekArea.fractionAt(mouse.x)
                                // restart(), not start(): each move pushes the deadline
                                // back, so the seek waits for the pointer to settle.
                                scrubSeek.restart()
                            }
                            thumbnailDelay.restart()
                        }
                        onReleased: mouse => {
                            const target = veyra.timelineSeconds(seekArea.fractionAt(mouse.x))
                            scrubSeek.stop()
                            seekArea.shownProgress = seekArea.fractionAt(mouse.x)
                            seekArea.scrubbing = false
                            veyra.logUi("ui-seek", "targetSeconds=" + target.toFixed(3))
                            // The timer may have fired on the last move and already
                            // started a seek to (very nearly) this position. A second
                            // request would interrupt that one and cost another full
                            // re-position, so a near-identical target is dropped.
                            if (Math.abs(target - seekArea.lastSeekTarget) > 0.5) {
                                seekArea.lastSeekTarget = target
                                veyra.seekTo(target)
                            }
                        }
                        onCanceled: {
                            scrubSeek.stop()
                            seekArea.scrubbing = false
                        }
                    }
                }
                Text {
                    text: veyra.durationText
                    visible: !veyra.liveTimeshift.available
                    color: Theme.t3
                    font.family: Theme.fontMono
                    font.pixelSize: 10
                }
                VButton {
                    objectName: "cine-return-live"
                    visible: veyra.liveTimeshift.available
                    ghost: true
                    text: qsTr("回到直播")
                    onClicked: veyra.returnToLive()
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

            RowLayout {
                Layout.preferredHeight: 32
                spacing: 6
                VIcon { name: "vol"; color: Theme.t2 }
                VSlider {
                    id: volumeSlider
                    objectName: "cine-volume"
                    Layout.preferredWidth: bar.compact ? 48 : 68
                    Layout.fillHeight: true
                    from: 0; to: veyra.maximumVolume; value: veyra.volume; inputScale: 100
                    defaultValue: 1
                    valueFromModel: true
                    fullKnobHitArea: true
                    onMoved: moved => veyra.volume = moved
                }
                VSliderValue {
                    Layout.preferredWidth: 30
                    slider: volumeSlider
                    text: Math.round(veyra.volume * 100) + "%"
                    color: Theme.t2; pixelSize: 10
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

    PlayerAudioMenu {
        id: audioMenu
        objectName: "cine-audio-menu"
        backend: veyra
        aboveLimit: bar.menuBottomLimit
        onSettingsRequested: bar.requestDialog("audio")
    }
}
