// 首页, rebuilt from the design (pages-a.js PAGES.home + pages.css .home).
//
// OverRez: the logo, the title, the screen capture card and the
// "continue last capture" row.
// The logo in the dock returns here; there is no other home affordance.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects

VPage {
    id: root
    signal requestPage(string page)
    readonly property alias sourceViewport: homeScroll
    readonly property bool compact: height < 500
    // Main.qml keeps the dusk wordmark hidden while the startup intro (DuskIntro.qml) flies a
    // copy of it in, and aims that copy at this item.
    property bool introHold: false
    readonly property Item wordmarkItem: wordmark

    Flickable {
        id: homeScroll
        objectName: "source-card-scroll"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        contentWidth: width
        contentHeight: Math.max(height, homeContent.implicitHeight + 24)
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: VScrollBar { }
    }

    ColumnLayout {
        id: homeContent
        parent: homeScroll.contentItem
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(root.compact ? 8 : 12, Math.round((homeScroll.height - height) / 2))
        spacing: root.compact ? 8 : 24

        // .home .mark: 128px wide, drop-shadow(0 0 20px rgba(255,255,255,.35)) and the
        // 4.5s "breathe" loop: at 50% the glow is 30px at .55 and the mark scales 1.02.
        // MultiEffect blur is 0..1 of blurMax (32px): 20px = .625, 30px = .94.
        // The layer is padded 40px on every side so the glow has room (a layer on the
        // bare image clips the shadow to the image's own bounds). Negative margins
        // keep the layout the same as a plain 128px image.
        Item {
            id: mark
            visible: !Theme.dusk
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: -40
            Layout.bottomMargin: -40
            implicitWidth: logoImg.implicitWidth + 80
            implicitHeight: logoImg.implicitHeight + 80
            property real breath: 0
            scale: 1 + 0.02 * breath
            // Only while the home page shows: running behind other pages it redrew the whole
            // window every vsync during playback (~300 presents/s on a 320 Hz screen), which
            // cost GPU time and kept OBS game capture on the UI instead of the video.
            SequentialAnimation on breath {
                running: !Theme.reduced && mark.visible
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: Theme.d(2250); easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: Theme.d(2250); easing.type: Easing.InOutSine }
            }
            Image {
                id: logoImg
                anchors.centerIn: parent
                source: Theme.logoImage
                sourceSize.width: root.compact ? 42 : 128
                fillMode: Image.PreserveAspectFit
            }
            // A sibling MultiEffect, not layer.effect: Qt recreates a layer's effect item on
            // a screen DPI change while it walks the parent's children, and the walk then touched
            // the deleted item (crash moving the window to a 200 % monitor, field 2026-10-01).
            MultiEffect {
                source: logoImg
                anchors.fill: logoImg
                shadowEnabled: true
                // The dusk logo carries its own neon glow; the breath adds a pink one to it.
                shadowColor: Theme.dusk ? "#F396CE" : "#FFFFFF"
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0
                blurMax: 64
                shadowBlur: 0.625 + 0.3125 * mark.breath
                shadowOpacity: (Theme.dusk ? 0.22 : 0.35) + 0.2 * mark.breath
            }
        }

        // 日落: the user's wordmark (tools/qt_probe/make-wordmark-dusk.py) in place of the gamepad
        // and the title, a baked glow breathing behind it (the software scene graph draws no
        // MultiEffect). 0.24 of the page height, 130..210 px, so short windows keep the cards.
        Item {
            id: duskMark
            visible: Theme.dusk
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: wordmark.width
            implicitHeight: wordmark.height
            property real breath: 0
            // Only while it shows, as the gamepad's breath (see above).
            SequentialAnimation on breath {
                running: !Theme.reduced && duskMark.visible && !root.introHold
                loops: Animation.Infinite
                NumberAnimation { to: 1; duration: Theme.d(2250); easing.type: Easing.InOutSine }
                NumberAnimation { to: 0; duration: Theme.d(2250); easing.type: Easing.InOutSine }
            }
            Image {
                // wordmark-dusk-glow.png is the wordmark's box grown by 186/1164 of its width.
                readonly property real pad: wordmark.width * 186 / 1164
                x: -pad
                y: -pad
                width: wordmark.width + 2 * pad
                height: wordmark.height + 2 * pad
                source: "wordmark-dusk-glow.png"
                opacity: root.introHold ? 0 : 0.16 + 0.14 * duskMark.breath
            }
            Image {
                id: wordmark
                objectName: "home-wordmark"
                height: Math.round(root.compact ? Math.min(90, root.height * 0.15)
                                               : Math.max(130, Math.min(210, root.height * 0.24)))
                width: Math.round(height * 1164 / 969)
                source: "wordmark-dusk.png"
                sourceSize: Qt.size(width, height)
                opacity: root.introHold ? 0 : 1
            }
        }

        // .hello: the title.
        ColumnLayout {
            id: hello
            Layout.alignment: Qt.AlignHCenter
            spacing: 6
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: !Theme.dusk                    // the dusk wordmark says it
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

        // .srcgrid: the one source, a 164x124 card.
        Flow {
            id: srcGrid
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: cardWidth
            spacing: root.compact ? 8 : 12
            readonly property int cardWidth: 164
            readonly property int cardHeight: root.compact ? 80 : 124
            function cardSub(act) { return qsTr("窗口或显示器") }
            Repeater {
                id: sourceCards
                model: [
                    { glyph: "monitor", title: qsTr("屏幕捕获"), act: "screen" }
                ]
                // The layout owns the slot's position, so the card inside it is free to
                // move its own y for the hover lift (a y set on a layout child is
                // overwritten); the entrance rise goes on the slot.
                delegate: Item {
                    id: slot
                    required property var modelData
                    required property int index
                    readonly property alias card: srcCard
                    implicitWidth: srcGrid.cardWidth
                    implicitHeight: srcGrid.cardHeight
                    VRise { page: root; target: slot; d: 2 + slot.index }
                  Rectangle {
                    id: srcCard
                    readonly property var modelData: slot.modelData
                    // .srccard: 164x124, radius 14, content pinned top and bottom.
                    width: slot.width
                    height: slot.height
                    radius: Theme.rCard
                    color: cardHover.hovered ? Theme.card2 : Theme.card
                    border.width: 1
                    border.color: cardHover.hovered ? Theme.stroke2 : Theme.stroke
                    // .srccard:hover { transform: translateY(-4px) }
                    y: cardHover.hovered ? -4 : 0
                    Behavior on y { NumberAnimation { duration: Theme.d(500); easing.bezierCurve: Theme.spring } }
                    scale: cardTap.pressed ? 0.97 : 1.0
                    Behavior on scale { NumberAnimation { duration: Theme.d(500); easing.bezierCurve: Theme.spring } }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: root.compact ? 8 : 14
                        spacing: 0
                        Rectangle {
                            // .srccard .ico: 34x34, radius 10, translucent plate.
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 10
                            color: Qt.rgba(1, 1, 1, 0.06)
                            VIcon {
                                anchors.centerIn: parent
                                name: modelData.glyph
                            }
                        }
                        Item { Layout.fillHeight: true }
                        ColumnLayout {
                            spacing: 3
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                id: sourceTitle
                                text: modelData.title
                                color: Theme.t1
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsBody
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                elide: Text.ElideRight
                                id: sourceSubtitle
                                text: srcGrid.cardSub(modelData.act)
                                color: Theme.t3
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSmall
                            }
                        }
                    }
                    HoverHandler { id: cardHover; cursorShape: Qt.PointingHandCursor }
                    ToolTip.visible: cardHover.hovered && (sourceTitle.truncated || sourceSubtitle.truncated)
                    ToolTip.text: sourceTitle.text + " · " + sourceSubtitle.text
                    TapHandler {
                        id: cardTap
                        onTapped: {
                            veyra.logUi("ui-source", "home card act=" + modelData.act)
                            veyra.openScreenCaptureDialog()
                        }
                    }
                  }
                }
            }
        }

        // .resume: an accent-tinted gradient plate, shown only when a screen
        // capture session was actually used before. Nothing invented: the text is
        // the recorded session, and the row is absent when there is none.
        Rectangle {
            id: resume
            objectName: "home-resume"
            Layout.alignment: Qt.AlignHCenter
            // The last screen capture actually used.
            readonly property var last: veyra.lastSource
            visible: last.kind === "screen"
            implicitWidth: Math.min(520, root.width - 48)
            implicitHeight: 54
            radius: 14
            border.width: 1
            border.color: Theme.stroke
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.accentSoft }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.03) }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 10
                spacing: 14
                Rectangle {
                    implicitWidth: 34; implicitHeight: 34; radius: 10
                    color: Theme.accentSoft
                    VIcon {
                        anchors.centerIn: parent
                        name: "monitor"
                        color: Theme.accent
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        text: qsTr("继续上次")
                        color: Theme.t1
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        font.weight: Font.DemiBold; font.variableAxes: Theme.axesDemiBold
                    }
                    Text {
                        Layout.fillWidth: true
                        text: resume.last.summary || ""
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                }
                VButton {
                    text: qsTr("开始")
                    iconName: "play"
                    primary: true
                    onClicked: veyra.resumeLastSource()
                }
            }
        }

    }

    // [data-in] entrance order from pages-a.js (the source cards rise from their delegate, --d 2-5).
    VRise { target: mark; d: 0 }
    VRise { target: hello; d: 1 }
    VRise { target: resume; d: 6 }
}
