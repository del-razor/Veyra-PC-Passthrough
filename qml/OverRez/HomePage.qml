// The capture page: where OverRez opens. The logo and tagline on top, then the
// screen capture settings and the button that starts the capture.
//
// Game mode is always on (QmlPlayerBridge::screenOptions): the picture covers the
// game 1:1 and the game keeps the keyboard, mouse and controller. So there is no
// game mode switch, no pointer option and no crop here.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

VPage {
    id: root
    signal requestPage(string page)
    signal startCapture()
    readonly property alias sourceViewport: homeScroll
    readonly property bool compact: height < 560
    readonly property var o: veyra.screenOptions
    readonly property var target: {
        const targets = veyra.screenTargets, id = veyra.screenTargetId
        for (let i = 0; i < targets.length; ++i)
            if (targets[i].id === id) return targets[i]
        return null
    }

    onCurrentChanged: if (current) veyra.refreshCaptureTargets()
    Component.onCompleted: veyra.refreshCaptureTargets()

    Flickable {
        id: homeScroll
        objectName: "source-card-scroll"
        anchors.fill: parent
        anchors.bottomMargin: 8
        contentWidth: width
        contentHeight: Math.max(height, content.implicitHeight + 48)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: VScrollBar { }

        ColumnLayout {
            id: content
            width: Math.min(640, homeScroll.width - 48)
            x: Math.round((homeScroll.width - width) / 2)
            y: Math.max(root.compact ? 56 : 72, Math.round((homeScroll.height - implicitHeight) / 2))
            spacing: root.compact ? 10 : 16

            // Logo and tagline.
            ColumnLayout {
                id: brand
                Layout.alignment: Qt.AlignHCenter
                spacing: 4
                Image {
                    id: logo
                    objectName: "home-logo"
                    Layout.alignment: Qt.AlignHCenter
                    source: Theme.logoImage
                    sourceSize.width: root.compact ? 72 : 108
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "OverRez"
                    color: Theme.t1
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsH1
                    font.weight: Font.DemiBold; font.variableAxes: Theme.axesDemiBold
                }
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "Beyond Ultra."
                    color: Theme.t2
                    font.family: Theme.fontUi
                    font.pixelSize: Theme.fsBody
                }
            }

            Rectangle {
                id: card
                radius: Theme.rCard
                color: Theme.card
                border.width: 1
                border.color: Theme.stroke
                Layout.fillWidth: true
                Layout.topMargin: root.compact ? 4 : 12
                implicitHeight: settings.implicitHeight + 36

                ColumnLayout {
                    id: settings
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 18
                    spacing: 4

                    VH2 { text: "Screen Capture Settings" }

                    DialogSection { text: "Target" }
                    DialogGroup {
                        VRow {
                            label: "Capture"
                            VSeg {
                                objectName: "screen-kind"
                                options: [{ id: "0", label: "Window" }, { id: "1", label: "Display" }]
                                current: String(root.o.kind)
                                onPicked: id => veyra.setScreenOption("kind", Number(id))
                            }
                        }
                        VRow {
                            label: root.o.kind === 1 ? "Display" : "Window"
                            hint: {
                                if (veyra.screenTargets.length === 0)
                                    return root.o.kind === 1 ? "No display found." : "No window found. Start the game first, then press Refresh."
                                const lines = []
                                if (root.target && root.target.otherDesktop === true)
                                    lines.push("This window is on another Windows virtual desktop. Move it to this desktop before you start.")
                                if (root.target && root.target.otherGpu === true)
                                    lines.push("This display is connected to %1 but OverRez processes on %2, so Windows copies every frame between them and adds latency. Connect the display to the processing GPU if you can."
                                               .arg(root.target.displayGpu).arg(root.target.processingGpu))
                                return lines.join("\n")
                            }
                            RowLayout {
                                spacing: 6
                                VSelect {
                                    objectName: "screen-target"
                                    implicitWidth: 300
                                    value: veyra.screenTargetLabel
                                    options: veyra.screenTargets
                                    onPicked: id => veyra.screenTargetId = id
                                }
                                VButton { text: "Refresh"; ghost: true; onClicked: veyra.refreshCaptureTargets() }
                            }
                        }
                    }

                    DialogSection { text: "Capture" }
                    DialogGroup {
                        VRow {
                            label: "Method"
                            hint: root.o.kind === 1
                                  ? "DXGI is the compatibility method for displays. It shows no yellow border."
                                  : "Windows can only be captured with Windows Graphics Capture."
                            VSeg {
                                enabled: root.o.kind === 1
                                opacity: enabled ? 1 : 0.5
                                options: [{ id: "0", label: "WGC" }, { id: "1", label: "DXGI" }]
                                current: String(root.o.method)
                                onPicked: id => veyra.setScreenOption("method", Number(id))
                            }
                        }
                        VRow {
                            label: "Frame rate limit"
                            hint: "With NR on, a 60 fps limit halves the frames NR has to process and keeps the load down."
                            hintBelow: true
                            VSeg {
                                options: [{ id: "0", label: "Follow" }, { id: "1", label: "30" }, { id: "2", label: "60" },
                                          { id: "3", label: "120" }, { id: "4", label: "144" }, { id: "5", label: "240" }]
                                current: String(root.o.fps)
                                onPicked: id => veyra.setScreenOption("fps", Number(id))
                            }
                        }
                        VRow {
                            label: "Picture"
                            hint: root.o.fill
                                  ? "Fills the screen. Keyboard and controller go to the game; mouse clicks are blocked so they can't land in the wrong place."
                                  : "Sits exactly over the game window, so the mouse works in the game too."
                            hintBelow: true
                            VSeg {
                                options: [{ id: "fit", label: "Match window" }, { id: "fill", label: "Fill screen" }]
                                current: root.o.fill ? "fill" : "fit"
                                onPicked: id => veyra.setScreenOption("fill", id === "fill")
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        Layout.topMargin: 12
                        wrapMode: Text.WordWrap
                        color: Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSmall
                        text: "OverRez covers the game with the enhanced picture while the game keeps your keyboard, mouse and controller. "
                              + "Press %1 to adjust the picture and %2 to stop. Run the game in borderless windowed mode; exclusive fullscreen can't be covered."
                                .arg(veyra.shortcuts.gamePanel || "Home").arg(veyra.shortcuts.gameExit || "End")
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 14
                        Item { Layout.fillWidth: true }
                        VButton {
                            objectName: "screen-start"
                            text: "Start capture"
                            iconName: "play"
                            primary: true
                            enabled: veyra.screenTargetId.length > 0 && !veyra.openingSource
                            onClicked: {
                                veyra.logUi("ui-source", "capture page start")
                                if (veyra.startScreenCapture()) root.startCapture()
                            }
                        }
                    }
                }
            }
        }
    }

    VRise { target: brand; d: 0 }
    VRise { target: card; d: 1 }
}
