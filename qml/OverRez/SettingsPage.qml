// 设置, rebuilt from the design (pages-b.js PAGES.set + pages.css .set).
//
// Design: a 220px nav column (外观 / 启动与窗口 / 播放 / 音频 / 性能 / 兼容 /
// PS5 串流 / 快捷键 / 组件与许可 / 关于 / 赞助作者; split 2026-10-05 because one page held
// almost every setting) and a large body. The design deliberately has NO
// capture-card section here: capture settings live in the capture dialog.
//
// Rows that would need engine support this build does not have say so, rather than
// being drawn as switches that would do nothing.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

VPage {
    id: root
    signal requestPage(string page)

    property string section: "look"
    property bool hdrAdvancedExpanded: false
    // The shortcut row waiting for a new key ("" = none).
    property string capturingKey: ""
    onSectionChanged: {
        capturingKey = ""
        if (settingsBodyScroll) settingsBodyScroll.contentY = settingsBodyScroll.originY
        // M32: the section's groups redraw one after another (pages-b.js
        // render(true): 480 ms, i*40 ms, y 12).
        Qt.callLater(() => stagger(sectionColumns[section] || null))
    }
    readonly property var sectionColumns: ({ look: secLook, window: secWindow, play: secPlay, perf: secPerf, compat: secCompat, keys: secKeys, comp: secComp, about: secAbout })
    Component { id: staggerComp; VRise.Stagger {} }
    function stagger(col) {
        if (Theme.reduced || !col) return
        let i = 0
        for (let k = 0; k < col.children.length; ++k) {
            const c = col.children[k]
            if (!c.visible || c.motionDy === undefined) continue
            staggerComp.createObject(root, { target: c, delay: i * 40, span: 480, dy: 12 }).start()
            ++i
        }
    }

    readonly property var sections: [
        { id: "look",   label: "Appearance", icon: "palette" },
        { id: "window", label: "Startup & Window", icon: "appwin" },
        { id: "play",   label: "Video", icon: "play" },
        { id: "perf",   label: "Performance", icon: "gauge" },
        { id: "compat", label: "Compatibility", icon: "monitor" },
        { id: "keys",  label: "Shortcuts", icon: "zap" },
        { id: "comp",  label: "Components & Licenses", icon: "box" },
        { id: "about", label: "About", icon: "info" }
    ]

    // --- nav ---------------------------------------------------------------
    Rectangle {
        id: navCard
        anchors.left: parent.left
        anchors.leftMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        width: 220
        radius: Theme.rCard
        color: Theme.card
        border.width: 1
        border.color: Theme.stroke

        Flickable {
            id: navScroll
            objectName: "settings-navigation"
            anchors.fill: parent
            anchors.margins: 10
            contentWidth: width
            contentHeight: navColumn.implicitHeight
            flickableDirection: Flickable.VerticalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true
            ScrollBar.vertical: VScrollBar { }
        }
        ColumnLayout {
            id: navColumn
            parent: navScroll.contentItem
            width: navScroll.width - (navScroll.contentHeight > navScroll.height ? 8 : 0)
            spacing: 2
            VH2 { text: qsTr("设置"); Layout.margins: 8 }
            Item { implicitHeight: 6 }
            Repeater {
                model: root.sections
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 36
                    radius: 9
                    color: root.section === modelData.id ? Theme.card3
                         : navHover.hovered ? Qt.rgba(1, 1, 1, 0.04) : "transparent"
                    Behavior on color { ColorAnimation { duration: Theme.d(200) } }
                    // .setnav button: icon, 10px, label.
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 10
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10
                        VIcon {
                            name: modelData.icon
                            size: 15
                            color: modelData.tint !== undefined ? modelData.tint : navLabel.color
                        }
                        Text {
                            id: navLabel
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            elide: Text.ElideRight
                            text: modelData.label
                            color: root.section === modelData.id ? Theme.t1 : Theme.t2
                            font.family: Theme.fontUi
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }
                    ToolTip.visible: navHover.hovered && navLabel.truncated
                    ToolTip.text: navLabel.text
                    ToolTip.delay: 500
                    HoverHandler { id: navHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: root.section = modelData.id }
                }
            }
        }
    }

    // --- body --------------------------------------------------------------
    Rectangle {
        id: bodyCard
        anchors.left: parent.left
        anchors.leftMargin: 14 + 220 + 10
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.top: parent.top
        anchors.topMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14
        radius: Theme.rCard
        color: Theme.card
        border.width: 1
        border.color: Theme.stroke
        clip: true

        Flickable {
            id: settingsBodyScroll
            anchors.fill: parent
            contentHeight: body.implicitHeight + 44
            clip: true
            ScrollBar.vertical: VScrollBar { }

            ColumnLayout {
                id: body
                x: 26
                y: 22
                // .setbody section { max-width: 720px }
                width: Math.min(parent.width - 52, 720)
                spacing: 12

                // --- 外观 ---
                ColumnLayout {
                    id: secLook
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "look"
                    VH1 { text: "Appearance" }
                    Text {
                        text: qsTr("界面随时可调，不影响播放和增强设置。")
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    VGroup {
                        // Veyra PLUS: classic palette only, no startup intro or music.
                        VRow {
                            label: qsTr("页面切换栏")
                            hint: qsTr("平时隐藏；鼠标碰到窗口顶部时弹下来")
                            VSeg {
                                objectName: "set-dock"
                                options: [{ id: "auto", label: qsTr("自动隐藏") }, { id: "always", label: qsTr("始终显示") }]
                                current: veyra.preferences.dockPinned === true ? "always" : "auto"
                                onPicked: id => veyra.setPreference("dockPinned", id === "always")
                            }
                        }
                        VRow {
                            label: qsTr("强调色")
                            hint: qsTr("开关、进度、选中状态")
                            // .swatch: two colour dots, the chosen one ringed and 1.12x.
                            Row {
                                objectName: "set-accent"
                                spacing: 10
                                Repeater {
                                    model: [{ id: "orange", c: "#FF8A3D", tip: qsTr("橙色"), duskTip: qsTr("日落渐变") },
                                            { id: "white", c: "#F3F3F5", tip: qsTr("白色光晕"), duskTip: qsTr("白色光晕") }]
                                    delegate: Rectangle {
                                        id: swatch
                                        required property var modelData
                                        readonly property bool on: (veyra.preferences.accent || "orange") === modelData.id
                                        objectName: "set-accent-" + modelData.id
                                        width: 24; height: 24; radius: 12
                                        // The dusk palette shows what each choice paints: the sunset
                                        // gradient, or the neon white (the ring stays on top).
                                        color: Theme.dusk ? "#FFF6FB" : modelData.c
                                        gradient: Theme.dusk && modelData.id === "orange" ? sunset : undefined
                                        Gradient {
                                            id: sunset
                                            orientation: Gradient.Horizontal
                                            GradientStop { position: 0.0; color: Theme.accentFrom }
                                            GradientStop { position: 1.0; color: Theme.accentTo }
                                        }
                                        border.width: 2
                                        border.color: on ? "#FFFFFF" : "transparent"
                                        scale: on ? 1.12 : 1
                                        Behavior on scale { NumberAnimation { duration: Theme.d(400); easing.bezierCurve: Theme.spring } }
                                        HoverHandler { id: swHover; cursorShape: Qt.PointingHandCursor }
                                        TapHandler { onTapped: veyra.setPreference("accent", modelData.id) }
                                        ToolTip.visible: swHover.hovered
                                        ToolTip.text: Theme.dusk ? modelData.duskTip : modelData.tip
                                    }
                                }
                            }
                        }
                        VRow {
                            label: qsTr("减少动画")
                            hint: qsTr("关闭弹性与转场")
                            VSwitch {
                                checked: veyra.reducedMotion
                                onToggled: checked => veyra.reducedMotion = checked
                            }
                        }
                        VRow {
                            label: qsTr("滑块键盘微调")
                            hint: "Click a slider, then use the ← and → keys to adjust it by this step. Esc leaves the slider."
                            VSeg {
                                objectName: "set-slider-step"
                                options: [{ id: "1", label: "1" }, { id: "0.1", label: "0.1" }, { id: "0.01", label: "0.01" }]
                                current: String(veyra.preferences.sliderKeyStep !== undefined ? veyra.preferences.sliderKeyStep : 0.1)
                                onPicked: id => veyra.setPreference("sliderKeyStep", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("背景渐变强度")
                            hint: Theme.dusk ? qsTr("日落天空的渐变强度，带抖动防色带") : qsTr("深黑底上的极轻渐变与抖动（防色带）")
                            VSeg {
                                objectName: "set-backdrop"
                                options: [{ id: "0", label: qsTr("无") }, { id: "1", label: qsTr("轻") }, { id: "2", label: qsTr("中") }]
                                current: String(veyra.preferences.backdrop !== undefined ? veyra.preferences.backdrop : 1)
                                onPicked: id => veyra.setPreference("backdrop", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("界面缩放")
                            hint: (veyra.preferences.uiScale || 0) !== veyra.uiScaleActive ? qsTr("重启后生效") : qsTr("自动 = 跟随 Windows 显示缩放")
                            VSeg {
                                objectName: "set-scale"
                                options: [{ id: "0", label: qsTr("自动") }, { id: "100", label: "100%" }, { id: "125", label: "125%" }, { id: "150", label: "150%" }]
                                current: String(veyra.preferences.uiScale || 0)
                                onPicked: id => veyra.setPreference("uiScale", Number(id))
                            }
                        }
                    }
                }

                // --- 启动与窗口 ---
                ColumnLayout {
                    id: secWindow
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "window"
                    VH1 { text: "Startup & Window" }
                    Text {
                        text: qsTr("程序启动时的页面、窗口和恢复行为。")
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    VGroup {
                        VRow {
                            label: qsTr("打开时的默认页面")
                            hint: "Capture Source is the screen capture page. The logo at the top also returns there."
                            VSeg {
                                objectName: "set-default-page"
                                options: [
                                    { id: "home", label: "Capture Source" },
                                    { id: "min", label: qsTr("极简模式") },
                                    { id: "pro", label: qsTr("专业模式") },
                                    { id: "last", label: qsTr("上次") }
                                ]
                                current: veyra.defaultPage
                                onPicked: id => veyra.defaultPage = id
                            }
                        }
                        VRow {
                            label: qsTr("启动窗口大小")
                            hint: qsTr("下次启动生效；超过屏幕时按屏幕缩小并居中")
                            VSelect {
                                objectName: "set-window-size"
                                readonly property var sizes: [
                                    { id: "1280x800", label: "1280 × 800" },
                                    { id: "1600x1000", label: "1600 × 1000" },
                                    { id: "1920x1200", label: "1920 × 1200" },
                                    { id: "last", label: qsTr("记住上次大小") }
                                ]
                                options: sizes
                                value: (sizes.find(o => o.id === (veyra.preferences.windowSize || "1280x800")) || sizes[0]).label
                                onPicked: id => veyra.setPreference("windowSize", id)
                            }
                        }
                        VRow {
                            label: qsTr("启动后自动继续上次内容")
                            hint: "Starts the last screen capture again when OverRez opens."
                            VSwitch {
                                objectName: "set-auto-resume"
                                checked: !!veyra.preferences.autoResume
                                onToggled: v => veyra.setPreference("autoResume", v)
                            }
                        }
                    }
                }

                // --- 播放 ---
                ColumnLayout {
                    id: secPlay
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "play"
                    VH1 { text: "Video" }
                    Text {
                        text: "HDR output, live translation, screenshots, recording, streaming apps and Instant Replay."
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    VGroup {
                        VRow {
                            label: qsTr("HDR 输出格式")
                            hint: qsTr("HDR10 默认；补帧固定 HDR10，需要 Windows HDR 开启")
                            VSeg { options: [{id:"0",label:"HDR10"},{id:"1",label:qsTr("scRGB 浮点")}]; current: String(veyra.hdrOutputMode); onPicked: id => veyra.hdrOutputMode = Number(id) }
                        }
                        VRow {
                            label: qsTr("HDR 亮度曲线") + " / " + qsTr("HDR 元数据")
                            VButton {
                                objectName: "set-hdr-advanced-toggle"
                                text: root.hdrAdvancedExpanded ? qsTr("收起") : qsTr("展开")
                                trailingIcon: root.hdrAdvancedExpanded ? "up" : "down"
                                onClicked: root.hdrAdvancedExpanded = !root.hdrAdvancedExpanded
                            }
                        }
                        ColumnLayout {
                            objectName: "set-hdr-advanced-body"
                            Layout.fillWidth: true
                            spacing: 0
                            visible: root.hdrAdvancedExpanded
                            // HDR 亮度曲线: static, so the highlights are protected.
                            // One-click presets (same ids as the list page).
                            Flow {
                                Layout.fillWidth: true
                                Layout.preferredHeight: implicitHeight
                                spacing: 6
                                Repeater {
                                    model: [{id:"standard",label:qsTr("标准")},
                                            {id:"darkLift",label:qsTr("暗场提亮")},
                                            {id:"highlightGuard",label:qsTr("高光保护")},
                                            {id:"darkAndBright",label:qsTr("暗亮双修")},
                                            {id:"brightRoom",label:qsTr("明亮环境")},
                                            {id:"darkRoom",label:qsTr("暗室观影")},
                                            {id:"punch",label:qsTr("强化冲击")}]
                                    delegate: VButton {
                                        required property var modelData
                                        text: modelData.label
                                        ghost: true
                                        primary: veyra.hdrTuningPreset === modelData.id
                                        onClicked: veyra.applyHdrTuningPreset(modelData.id)
                                    }
                                }
                            }
                            VRow {
                                label: qsTr("HDR 亮度曲线")
                                hint: qsTr("静态曲线：抬暗部、定中灰、压高光")
                                value: veyra.hdrCurve ? qsTr("已开启") : qsTr("已关闭")
                                VSwitch {
                                    objectName: "hdrcurve-enabled"
                                    checked: veyra.hdrCurve
                                    onToggled: checked => veyra.hdrCurve = checked
                                }
                            }
                            VRow {
                                label: qsTr("强度")
                                hint: qsTr("0% 关闭曲线；峰值保护与元数据独立")
                                value: veyra.hdrCurveStrength + "%"
                                VSlider {
                                    objectName: "hdrcurve-strength"
                                    implicitWidth: 120
                                    valueFromModel: true
                                    resettable: true; defaultValue: 100
                                    from: 0; to: 200
                                    value: veyra.hdrCurveStrength
                                    onMoved: value => veyra.hdrCurveStrength = Math.round(value)
                                }
                            }
                            VRow {
                                label: qsTr("显示设备峰值 (nit)")
                                hint: veyra.hdrDisplayInfo.valid
                                    ? qsTr("系统报告：峰值 %1、全屏 %2、黑位 %3 nit")
                                        .arg(veyra.hdrDisplayInfo.peakNits)
                                        .arg(veyra.hdrDisplayInfo.fullFrameNits)
                                        .arg(Number(veyra.hdrDisplayInfo.minNits).toFixed(3))
                                    : qsTr("0 = 自动使用系统报告值")
                                value: veyra.hdrDisplayPeakNits > 0
                                    ? (veyra.hdrDisplayPeakNits + " nit") : qsTr("自动")
                                VSlider {
                                    objectName: "hdrcurve-displaypeak"
                                    implicitWidth: 120
                                    valueFromModel: true
                                    resettable: true; defaultValue: 0
                                    from: 0; to: 4000
                                    value: veyra.hdrDisplayPeakNits
                                    onMoved: value => veyra.hdrDisplayPeakNits = Math.round(value)
                                }
                            }
                            Repeater {
                                model: [{key:"shadowLiftEv100",label:qsTr("暗部抬升 (0.01 EV)"),from:-200,to:200,def:0},
                                        {key:"shadowRangeNits",label:qsTr("抬升范围 (nit)"),from:1,to:100,def:10,hint:qsTr("只在这个亮度以下的暗部生效")},
                                        {key:"midGrayNits",label:qsTr("中灰 (nit)"),from:100,to:500,def:203,hint:qsTr("203 = 中性；调高整体变亮，峰值不变")},
                                        {key:"highlightStartNits",label:qsTr("高光起点 (nit)"),from:0,to:2000,def:0,hint:qsTr("0 = 不做高光滚降")},
                                        {key:"rollOffPercent",label:qsTr("滚降强度 (%)"),from:10,to:200,def:100},
                                        {key:"peakCapNits",label:qsTr("峰值上限 (nit)"),from:0,to:4000,def:0,hint:qsTr("0 = 不限制")}]
                                delegate: VRow {
                                    required property var modelData
                                    label: modelData.label
                                    hint: modelData.hint || ""
                                    value: String(veyra.hdrCurveParams[modelData.key] ?? "—")
                                    VSlider {
                                        objectName: "hdrcurve-" + modelData.key
                                        implicitWidth: 150
                                        valueFromModel: true
                                        resettable: true; defaultValue: modelData.def
                                        from: modelData.from; to: modelData.to
                                        value: veyra.hdrCurveParams[modelData.key] ?? modelData.def
                                        onMoved: value => veyra.setHdrCurveParameter(modelData.key, Math.round(value))
                                    }
                                }
                            }
                            // HDR 元数据: what the display's own tone mapping works from.
                            VRow {
                                label: qsTr("HDR 元数据")
                                hint: qsTr("HDR10 提示；系统或显示器可能忽略")
                                value: veyra.hdrMetadataEnabled ? qsTr("已启用（HDR10）") : qsTr("已关闭")
                                VSwitch {
                                    objectName: "hdrmeta-enabled"
                                    checked: veyra.hdrMetadataEnabled
                                    onToggled: checked => veyra.hdrMetadataEnabled = checked
                                }
                            }
                            Repeater {
                                model: [{key:"masteringPeakNits",label:qsTr("母版峰值 (nit)"),from:0,to:4000,def:0,hint:qsTr("0 = 跟随片源；实际效果取决于显示设备")},
                                        {key:"maxCllNits",label:qsTr("MaxCLL (nit)"),from:0,to:4000,def:0,hint:qsTr("0 = 跟随片源")},
                                        {key:"maxFallNits",label:qsTr("MaxFALL (nit)"),from:0,to:4000,def:0,hint:qsTr("0 = 跟随片源")}]
                                delegate: VRow {
                                    required property var modelData
                                    label: modelData.label
                                    hint: modelData.hint || ""
                                    value: String(veyra.hdrMetadataParams[modelData.key] ?? "—")
                                    VSlider {
                                        objectName: "hdrmeta-" + modelData.key
                                        implicitWidth: 150
                                        valueFromModel: true
                                        resettable: true; defaultValue: modelData.def
                                        from: modelData.from; to: modelData.to
                                        value: veyra.hdrMetadataParams[modelData.key] ?? modelData.def
                                        onMoved: value => veyra.setHdrMetadataParameter(modelData.key, Math.round(value))
                                    }
                                }
                            }

                        }
                        VRow {
                            visible: (veyra.liveTranslation || null) !== null
                            label: qsTr("实时翻译")
                            VButton {
                                objectName: "set-live-translation"
                                text: qsTr("实时翻译设置…")
                                onClicked: root.requestPage("translation")
                            }
                        }
                        VRow {
                            label: qsTr("截图保存位置")
                            hint: veyra.screenshotDirectory + qsTr("（SDR 存 PNG，HDR 存 JPEG XR）")
                            RowLayout {
                                spacing: 6
                                VButton { text: qsTr("打开"); ghost: true; onClicked: veyra.openScreenshotDirectory() }
                                VButton { objectName: "set-shotdir"; text: qsTr("更改…"); onClicked: veyra.chooseScreenshotDirectory() }
                            }
                        }
                    VGroup {
                        objectName: "set-recording"
                        VRow {
                            label: qsTr("录制保存位置")
                            hint: veyra.recordingDirectory + " (MP4: the enhanced picture and your PC's sound)"
                            RowLayout {
                                spacing: 6
                                VButton { text: qsTr("打开"); ghost: true; onClicked: veyra.openRecordingDirectory() }
                                VButton { objectName: "set-recdir"; text: qsTr("更改…"); onClicked: veyra.chooseRecordingDirectory() }
                            }
                        }
                        VRow {
                            label: qsTr("录制码率")
                            hint: qsTr("自动按画面尺寸和帧率选择；数字为 Mbps，越高越清晰、文件也越大")
                            VSeg {
                                objectName: "set-recbitrate"
                                options: [{ id: "0", label: qsTr("自动") }, { id: "8", label: "8" }, { id: "16", label: "16" }, { id: "20", label: "20" }, { id: "40", label: "40" }, { id: "80", label: "80" }]
                                current: String(veyra.recordingBitrateMbps)
                                onPicked: id => veyra.setPreference("recordBitrateMbps", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("录制帧率")
                            hint: qsTr("跟随显示可录到补帧后的画面；限速则按该帧率抽帧")
                            VSeg {
                                objectName: "set-recfps"
                                options: [{ id: "0", label: qsTr("跟随") }, { id: "30", label: "30" }, { id: "60", label: "60" }, { id: "120", label: "120" }]
                                current: String(veyra.recordingFpsLimit)
                                onPicked: id => veyra.setPreference("recordFps", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("录制分段")
                            hint: qsTr("达到任一限制后，在下一关键帧分段。0 表示关闭，设置在下次录制时生效。")
                            RowLayout {
                                DialogHost.VTextField {
                                    objectName: "record-split-seconds"
                                    implicitWidth: 74
                                    text: String(veyra.preferences.recordSplitSeconds || 0)
                                    validator: IntValidator { bottom: 0; top: 86400 }
                                    onEdited: veyra.setPreference("recordSplitSeconds", Number(text))
                                }
                                Text { text: qsTr("秒"); color: Theme.t3; font.pixelSize: Theme.fsSmall }
                                DialogHost.VTextField {
                                    objectName: "record-split-mib"
                                    implicitWidth: 88
                                    text: String(veyra.preferences.recordSplitMiB || 0)
                                    validator: IntValidator { bottom: 0; top: 1048576 }
                                    onEdited: veyra.setPreference("recordSplitMiB", Number(text))
                                }
                                Text { text: "MiB"; color: Theme.t3; font.pixelSize: Theme.fsSmall }
                            }
                        }
                        VRow {
                            label: qsTr("录制编码")
                            hint: qsTr("HDR 画面固定使用 HEVC 10bit；宽或高超过 4096 时自动使用 HEVC")
                            VSeg {
                                objectName: "set-rechevc"
                                options: [{ id: "0", label: "H.264" }, { id: "1", label: "HEVC" }]
                                current: veyra.recordingHevc ? "1" : "0"
                                onPicked: id => veyra.setPreference("recordHevc", id === "1")
                            }
                        }
                        VRow {
                            label: qsTr("二次编码")
                            hint: qsTr("编码器先快速分析一遍画面再分配码率，同样码率下快速运动和复杂画面更清晰；仅 NVIDIA（NVENC），四分之一分辨率首遍更轻，完整分辨率最好但更重 · 默认关闭")
                            VSeg {
                                objectName: "set-recmultipass"
                                options: [{ id: "0", label: qsTr("关闭") }, { id: "1", label: qsTr("四分之一") }, { id: "2", label: qsTr("完整") }]
                                current: String(veyra.preferences.recordMultipass !== undefined ? veyra.preferences.recordMultipass : 0)
                                onPicked: id => veyra.setPreference("recordMultipass", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("心理视觉调优")
                            hint: qsTr("自适应量化：把码率挪到眼睛更敏感的地方（平坦天空、暗部、静止细节），减少色块；仅 NVIDIA（NVENC），显卡支持时再加时间自适应量化 · 默认关闭")
                            VSwitch {
                                objectName: "set-recpsychoaq"
                                checked: veyra.preferences.recordPsychoAq === true
                                onToggled: v => veyra.setPreference("recordPsychoAq", v)
                            }
                        }
                        VRow {
                            label: qsTr("录制声音")
                            hint: "Records what Windows plays on the default output device: the game and anything else you hear."
                            VSwitch {
                                objectName: "set-recaudio"
                                checked: veyra.recordingAudio
                                onToggled: v => veyra.setPreference("recordAudio", v)
                            }
                        }
                        // Microphone (#101): mixed into the sound, or a track of its own.
                        VRow {
                            label: qsTr("录制麦克风")
                            hint: qsTr("同时录入麦克风；默认混进录制声音，也可以放在单独的音轨")
                            VSwitch {
                                objectName: "set-recmic"
                                checked: veyra.recordingMicrophone
                                onToggled: v => { veyra.setPreference("recordMic", v); if (v) veyra.refreshMicrophones() }
                            }
                        }
                        VRow {
                            visible: veyra.recordingMicrophone
                            onVisibleChanged: if (visible) veyra.refreshMicrophones()
                            label: qsTr("麦克风设备")
                            hint: qsTr("需要在 Windows 设置 → 隐私和安全性 → 麦克风 中允许桌面应用访问")
                            VSelect {
                                objectName: "set-recmic-device"
                                implicitWidth: 230
                                options: [{ id: "", label: qsTr("系统默认麦克风") }].concat(veyra.microphoneDevices)
                                value: (options.find(o => o.id === veyra.recordingMicrophoneId)
                                        || { label: qsTr("已选设备（未连接）") }).label
                                onPicked: id => veyra.setPreference("recordMicDevice", id)
                            }
                        }
                        VRow {
                            visible: veyra.recordingMicrophone
                            label: qsTr("麦克风单独音轨")
                            hint: qsTr("开启后麦克风在第 2 条音轨，剪辑时可单独调整；普通播放器通常只播放第 1 条")
                            VSwitch {
                                objectName: "set-recmic-track"
                                checked: veyra.recordingMicrophoneTrack
                                onToggled: v => veyra.setPreference("recordMicTrack", v)
                            }
                        }
                    }
                    VGroup {
                        objectName: "set-virtual-camera-group"
                        VRow {
                            label: qsTr("直播软件兼容组件")
                            hint: {
                                const c = veyra.virtualCameraState || {}
                                if(c.installing) return qsTr("正在安装或卸载，请完成 Windows 管理员确认")
                                if(c.setupError) return c.setupError
                                if(c.systemOutdated) return qsTr("系统级组件是旧版本，管理员运行的 OBS 等直播软件会看不到画面；请点击“更新组件”")
                                return c.systemInstalled ? qsTr("已安装系统级组件，支持管理员运行的直播软件")
                                                         : qsTr("当前仅注册到本用户；管理员运行的 OBS 等直播软件需要安装系统级组件")
                            }
                            VButton {
                                objectName: "set-virtual-camera-install"
                                primary: !!(veyra.virtualCameraState || {}).systemOutdated
                                text: (veyra.virtualCameraState || {}).systemOutdated ? qsTr("更新组件")
                                    : (veyra.virtualCameraState || {}).systemInstalled ? qsTr("修复组件") : qsTr("安装组件")
                                enabled: !(veyra.virtualCameraState || {}).installing
                                onClicked: veyra.installVirtualCamera()
                            }
                        }
                        VRow {
                            label: qsTr("虚拟摄像机")
                            hint: qsTr("在直播软件的视频采集设备中选择 Veyra Virtual Camera；输出处理后的完整画面，不需要全屏")
                            VSwitch {
                                objectName: "set-virtual-camera-toggle"
                                checked: veyra.virtualCameraEnabled
                                onToggled: enabled => veyra.setVirtualCameraEnabled(enabled)
                            }
                        }
                        VRow {
                            label: qsTr("摄像机输出帧率")
                            hint: qsTr("自动：跟随直播软件为摄像机选的帧率（如 OBS 设 60 或 120），补帧 3X、4X 时按均匀时间挑帧；固定值为上限。SDR 视频输出，声音请单独采集；XeSS 显示端生成的帧不包含在内")
                            VSeg {
                                objectName: "set-virtual-camera-fps"
                                options: [{id: "0", label: qsTr("自动")}, {id: "30", label: "30"}, {id: "60", label: "60"}, {id: "120", label: "120"}]
                                current: String(veyra.virtualCameraFps)
                                onPicked: id => veyra.setPreference("virtualCameraFps", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("摄像机状态")
                            hint: {
                                const c = veyra.virtualCameraState || {}
                                if (c.error) return c.error
                                if (!c.active) return qsTr("已关闭；每次启动软件后需手动启用")
                                if (!(c.width > 0)) return qsTr("已启用，等待处理后的画面")
                                const size = qsTr("%1 × %2 · 已输出 %3 帧 · 跳过 %4 帧").arg(c.width).arg(c.height).arg(c.frames).arg(c.dropped)
                                           + (c.consumerFps > 0 ? qsTr(" · 直播软件请求 %1 帧/秒").arg(c.consumerFps) : "")
                                return c.processingWidth !== c.width || c.processingHeight !== c.height
                                     ? size + qsTr("（处理尺寸 %1 × %2）").arg(c.processingWidth).arg(c.processingHeight) : size
                            }
                            VButton { objectName: "set-virtual-camera-uninstall"; text: qsTr("卸载摄像机"); ghost: true; enabled: !(veyra.virtualCameraState || {}).installing; onClicked: veyra.uninstallVirtualCamera() }
                        }
                        // The consumer takes evenly spaced pictures: from a rate that is not a whole
                        // multiple of its own (90 against 60: 3X on a 30 fps game) they cannot be even.
                        VRow {
                            objectName: "set-virtual-camera-rhythm"
                            readonly property var cam: veyra.virtualCameraState || {}
                            readonly property real ratio: cam.presentedFps > 0 && cam.consumerFps > 0
                                ? Math.max(cam.presentedFps, cam.consumerFps) / Math.min(cam.presentedFps, cam.consumerFps) : 1
                            visible: !!cam.active && Math.abs(ratio - Math.round(ratio)) > 0.1
                            label: qsTr("直播画面节奏")
                            hintColor: Theme.warn
                            hint: qsTr("画面 %1 帧/秒不是直播软件 %2 帧/秒的整数倍，直播画面会一快一慢交替。请换成整数倍的补帧倍数，例如 30 帧游戏直播 60 帧时用 2X 或 4X")
                                  .arg(cam.presentedFps).arg(cam.consumerFps)
                        }
                    }
                    // Instant replay (#103): the last few seconds or minutes in memory.
                    VGroup {
                        objectName: "set-replay-group"
                        VRow {
                            label: qsTr("即时回放")
                            hint: qsTr("在内存中保留最近一段画面和声音，按 %1 保存到录制保存位置；会多占用一路硬件编码").arg(veyra.shortcuts.replay || qsTr("快捷键"))
                            VSwitch {
                                objectName: "set-replay"
                                checked: veyra.replayEnabled
                                onToggled: v => veyra.setPreference("replayEnabled", v)
                            }
                        }
                        VRow {
                            visible: veyra.replayEnabled
                            label: qsTr("回放长度")
                            hint: {
                                const s = veyra.replayState || {}
                                if (!s.active || !(s.seconds > 0)) return qsTr("播放时开始缓存；录制码率越高，占用内存越多")
                                if (s.memoryLimited) return qsTr("内存上限只够保留 %1 秒（约 %2 MB），可降低录制码率").arg(s.seconds).arg(s.megabytes)
                                return qsTr("已缓存 %1 秒，占用内存约 %2 MB").arg(s.seconds).arg(s.megabytes)
                            }
                            VSeg {
                                objectName: "set-replay-seconds"
                                options: [{ id: "15", label: qsTr("15 秒") }, { id: "30", label: qsTr("30 秒") }, { id: "60", label: qsTr("1 分钟") },
                                          { id: "120", label: qsTr("2 分钟") }, { id: "300", label: qsTr("5 分钟") }, { id: "600", label: qsTr("10 分钟") }]
                                current: String(veyra.replaySeconds)
                                onPicked: id => veyra.setPreference("replaySeconds", Number(id))
                            }
                        }
                    }
                    }
                    VGroup {
                        objectName: "set-smooth-motion"
                        VRow {
                            label: qsTr("Smooth Motion 开启方法")
                            hint: qsTr("NVIDIA 驱动级 AI 插帧，与软件内补帧二选一")
                            VButton {
                                text: smoothHelp.visible ? qsTr("收起") : qsTr("查看")
                                ghost: true
                                onClicked: smoothHelp.visible = !smoothHelp.visible
                            }
                        }
                        Text {
                            id: smoothHelp
                            visible: false
                            Layout.fillWidth: true
                            Layout.leftMargin: 12; Layout.rightMargin: 12; Layout.bottomMargin: 10
                            text: qsTr("只用驱动补帧时：在专业模式的补帧页关闭补帧，再到 NVIDIA App 打开 Smooth Motion（AI 插帧）。") + "\n"
                                  + qsTr("只用 DLSS / XeSS 补帧时：到 NVIDIA App 关闭 Smooth Motion。") + "\n"
                                  + qsTr("软件不检测、不拦截两者叠加，也不修改驱动配置；AMD FSR 补帧暂不提供。")
                            color: Theme.t2
                            font.family: Theme.fontUi
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                            lineHeight: 1.3
                        }
                    }
                }

                // --- 性能 ---
                ColumnLayout {
                    id: secPerf
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "perf"
                    VH1 { text: "Performance" }
                    Text {
                        text: qsTr("显卡调度、预热与资源监控。默认设置适合大多数机器。")
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    VGroup {
                        VRow {
                            label: qsTr("GPU 优先级")
                            hint: veyra.gpuPriorityStatus + qsTr("；默认“高”，同时运行游戏或其他重负载程序变慢时可改为“普通”")
                            VSeg {
                                objectName: "set-gpu-priority"
                                options: [{ id: "normal", label: qsTr("普通") }, { id: "high", label: qsTr("高") }, { id: "realtime", label: qsTr("实时") }]
                                current: veyra.preferences.gpuPriority || "high"
                                onPicked: id => veyra.setPreference("gpuPriority", id)
                            }
                        }
                        VRow {
                            label: qsTr("启动时预热增强组件")
                            hint: !veyra.enhancementPrewarmAvailable
                                  ? qsTr("当前显卡不支持预热")
                                  : qsTr("默认关闭。开启后首页空闲时预先准备已启用的单层 NR 或超分，首次打开约快 2 秒；准备好后会一直占用约 0.8–1.8 GB 显存，直到打开视频")
                            VSwitch {
                                objectName: "set-prewarm-enhancement"
                                enabled: veyra.enhancementPrewarmAvailable
                                checked: veyra.preferences.prewarmEnhancement === true
                                onToggled: v => veyra.setPreference("prewarmEnhancement", v)
                            }
                        }
                        VRow {
                            label: qsTr("GPU 占用监控")
                            hint: qsTr("专业页「GPU 占用」只统计这一块显卡") + (veyra.gpuMonitorName ? qsTr("；当前：") + veyra.gpuMonitorName : "")
                            VSelect {
                                objectName: "set-monitor-gpu"
                                implicitWidth: 230
                                options: veyra.gpuMonitorChoices
                                value: (options.find(o => o.id === (veyra.preferences.monitorGpu || "")) || options[0] || { label: "—" }).label
                                onPicked: id => veyra.setPreference("monitorGpu", id)
                            }
                        }
                        VRow {
                            label: qsTr("同时用这块显卡运算")
                            hint: veyra.computeGpuHint
                            VSwitch {
                                objectName: "set-compute-gpu"
                                checked: veyra.preferences.computeOnMonitorGpu === true
                                onToggled: v => veyra.setPreference("computeOnMonitorGpu", v)
                            }
                        }
                        VRow {
                            label: qsTr("全屏帧率")
                            hint: qsTr("在视频上显示提交 FPS 和 1% Low。全屏时按 %1 切换。").arg(veyra.shortcuts.fullscreenStats || qsTr("快捷键"))
                            VSwitch {
                                objectName: "fullscreen-frame-stats"
                                checked: !!veyra.preferences.fullscreenFrameStats
                                onToggled: v => veyra.setPreference("fullscreenFrameStats", v)
                            }
                        }
                        VRow {
                            label: qsTr("帧率显示位置")
                            visible: !!veyra.preferences.fullscreenFrameStats
                            VSelect {
                                objectName: "fullscreen-frame-stats-corner"
                                options: [{id:"0",label:qsTr("左上")},{id:"1",label:qsTr("右上")},
                                          {id:"2",label:qsTr("左下")},{id:"3",label:qsTr("右下")}]
                                value: options[veyra.preferences.fullscreenFrameStatsCorner ?? 1].label
                                onPicked: id => veyra.setPreference("fullscreenFrameStatsCorner", Number(id))
                            }
                        }
                        VRow {
                            label: qsTr("全屏显存增长保护")
                            hint: qsTr("检测异常增长时自动退出全屏；默认关闭")
                            VSwitch {
                                objectName: "set-fullscreen-memory-protection"
                                checked: !!veyra.preferences.fullscreenMemoryProtection
                                onToggled: v => veyra.setPreference("fullscreenMemoryProtection", v)
                            }
                        }
                    }
                }

                // --- 兼容 ---
                ColumnLayout {
                    id: secCompat
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "compat"
                    VH1 { text: "Compatibility" }
                    Text {
                        text: qsTr("界面绘制、OBS、监控软件兼容需重启；HDR 补帧兼容可在播放中切换。")
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                    }
                    VGroup {
                        VRow {
                            // 界面绘制 (veyra/ui/InterfaceRenderer.h, read by main.cpp at start).
                            // Software by default: no swapchain or D3D12 device of its own for
                            // overlays to hook, and no video memory. OBS 游戏采集兼容 and
                            // 监控软件兼容 still draw in software when GPU is chosen.
                            readonly property bool gpuChosen: veyra.preferences.uiRenderer === "gpu"
                            label: qsTr("界面绘制")
                            hint: gpuChosen
                                  ? (!veyra.softwareUiActive
                                     ? qsTr("显卡绘制：动画更顺，带阴影与模糊；占用显存和 GPU，可能与小飞机等监控软件冲突")
                                     : veyra.obsGameCaptureActive
                                       ? qsTr("OBS 游戏采集兼容开启时，界面始终软件绘制")
                                       : veyra.overlayCompatActive
                                         ? qsTr("本次检测到监控软件，仍用软件绘制（监控软件兼容：自动）")
                                         : qsTr("重启后生效"))
                                  : (veyra.softwareUiActive
                                     ? qsTr("软件绘制：兼容性最好，不占显存，不和视频抢 GPU；部分阴影与模糊简化")
                                     : qsTr("重启后生效"))
                            VSeg {
                                objectName: "set-ui-renderer"
                                options: [{ id: "software", label: qsTr("软件") }, { id: "gpu", label: "GPU" }]
                                current: veyra.preferences.uiRenderer === "gpu" ? "gpu" : "software"
                                onPicked: id => {
                                    // A restart changes the renderer unless a compatibility rule
                                    // keeps the interface in software anyway.
                                    const changes = id === "gpu"
                                        ? veyra.softwareUiActive && !veyra.obsGameCaptureActive
                                          && !((veyra.preferences.overlayCompat || "auto") === "auto" && veyra.presentationOverlayRunning())
                                        : !veyra.softwareUiActive
                                    if (veyra.setPreference("uiRenderer", id) && changes)
                                        obsRestart.open()
                                }
                            }
                        }
                        VRow {
                            label: qsTr("HDR 补帧闪黑兼容")
                            hint: qsTr("默认关闭。仅 NVIDIA HDR10 补帧时生效；4K 额外约 32 MiB 显存，可能增加 GPU 开销。切换时画面可能短暂停顿。")
                            VSwitch {
                                objectName: "set-hdr-fg-compatibility"
                                checked: !!veyra.preferences.hdrFgCompatibility
                                onToggled: v => veyra.setPreference("hdrFgCompatibility", v)
                            }
                        }
                        VRow {
                            label: qsTr("OBS 游戏采集兼容")
                            hint: (!!veyra.preferences.obsGameCapture !== veyra.obsGameCaptureActive)
                                  ? qsTr("重启后生效")
                                  : qsTr("仅采集视频；界面软件绘制，部分阴影与模糊简化")
                            VSwitch {
                                objectName: "set-obs-game-capture"
                                checked: !!veyra.preferences.obsGameCapture
                                onToggled: v => {
                                    if (veyra.setPreference("obsGameCapture", v)
                                            && v !== veyra.obsGameCaptureActive)
                                        obsRestart.open()
                                }
                            }
                        }
                        DialogNote {
                            text: qsTr("直播建议开启 Veyra 虚拟摄像机，在 OBS 中添加「视频采集设备」，选择 Veyra Virtual Camera。")
                        }
                        VRow {
                            // RivaTuner (MSI Afterburner's OSD), NVIDIA's in-game overlay and GamePP: see
                            // main.cpp. Auto draws the interface in software when one runs at start, so
                            // they only hook the video. With 界面绘制 = 软件 (the default) the interface
                            // is drawn in software anyway, and this choice changes nothing.
                            id: overlayCompatRow
                            readonly property bool automatic: (veyra.preferences.overlayCompat || "auto") === "auto"
                            readonly property bool gpuChosen: veyra.preferences.uiRenderer === "gpu"
                            label: qsTr("监控软件兼容")
                            hint: veyra.obsGameCaptureActive
                                  ? qsTr("OBS 游戏采集兼容已让界面软件绘制，小飞机 OSD 只显示在视频上")
                                  : !gpuChosen
                                  ? qsTr("只在“界面绘制”选 GPU 时起作用；软件绘制时小飞机 OSD 只显示在视频上")
                                  : (automatic !== veyra.overlayCompatActive && (veyra.overlayCompatActive || veyra.presentationOverlayRunning()))
                                    ? qsTr("重启后生效")
                                    : veyra.overlayCompatActive
                                      ? qsTr("监控兼容绘制已启用：OSD 只显示在视频上；部分阴影与模糊简化")
                                      : automatic
                                        ? qsTr("启动时检测到小飞机（RTSS）、NVIDIA 信息浮窗或游戏加加就改用软件绘制界面，它们只显示在视频上")
                                        : qsTr("界面始终用显卡绘制；小飞机 OSD 不在 Veyra 里显示；开着 NVIDIA 信息浮窗或游戏加加时可能卡死")
                            VSeg {
                                objectName: "set-overlay-compat"
                                options: [{ id: "auto", label: qsTr("自动") }, { id: "off", label: qsTr("关闭") }]
                                current: veyra.preferences.overlayCompat || "auto"
                                onPicked: id => {
                                    if (veyra.setPreference("overlayCompat", id) && !veyra.obsGameCaptureActive
                                            && overlayCompatRow.gpuChosen
                                            && (id === "auto") !== veyra.overlayCompatActive
                                            && (veyra.overlayCompatActive || veyra.presentationOverlayRunning()))
                                        obsRestart.open()
                                }
                            }
                        }
                    }
                }

                // --- 快捷键 ----------------------------------------------
                ColumnLayout {
                    id: secKeys
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "keys"
                    VH1 { text: "Shortcuts" }
                    Text {
                        text: "Click a key on the right, then press the new key combination. Esc cancels."
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                    }
                    VGroup {
                        Repeater {
                            model: [
                                { id: "gamePanel", a: "Adjust picture", note: "Opens the adjust panel over the game. Ctrl, Alt and Shift combinations work." },
                                { id: "gameExit", a: "Stop capture", note: "Emergency exit: leaves full screen and gives the screen back, even if the panel can't open." },
                                { id: "fullscreen", a: "Full screen", note: "F11 or Alt+Enter also work." },
                                { id: "hold", a: "Hold to see the original picture" },
                                { id: "screenshot", a: "Screenshot", note: "Works while you play." },
                                { id: "record", a: "Start / stop recording", note: "Works while you play." },
                                { id: "replay", a: "Save Instant Replay", note: "Turn on Instant Replay in Settings > Video first. Works while you play." },
                                { id: "fullscreenStats", a: "Show / hide the frame rate in full screen" },
                                { id: "toggleMode", a: "Switch Minimal / Pro" }
                            ]
                            delegate: VRow {
                                id: keyRow
                                required property var modelData
                                label: modelData.a
                                hint: modelData.note || ""
                                Rectangle {
                                    objectName: "key-" + keyRow.modelData.id
                                    readonly property bool capturing: root.capturingKey === keyRow.modelData.id
                                    implicitWidth: Math.max(64, keyText.implicitWidth + 20)
                                    implicitHeight: 26
                                    radius: 7
                                    color: capturing ? Theme.accentSoft : Qt.rgba(1, 1, 1, 0.06)
                                    border.width: 1
                                    border.color: capturing ? Theme.accent : Theme.stroke
                                    Text {
                                        id: keyText
                                        anchors.centerIn: parent
                                        text: parent.capturing ? "Press the new key…" : (veyra.shortcuts[keyRow.modelData.id] || "Not set")
                                        color: Theme.t1
                                        font.family: Theme.fontMono
                                        font.pixelSize: Theme.fsSmall
                                    }
                                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: { root.capturingKey = keyRow.modelData.id; keyCatcher.forceActiveFocus() } }
                                }
                            }
                        }
                        VRow {
                            label: qsTr("恢复默认")
                            VButton { text: qsTr("全部还原"); ghost: true; onClicked: veyra.resetShortcuts() }
                        }
                    }
                    // Captures the next key combination for the row being rebound.
                    Item {
                        id: keyCatcher
                        focus: false
                        Keys.onPressed: event => {
                            if (root.capturingKey === "") return
                            event.accepted = true
                            if (event.key === Qt.Key_Escape) { root.capturingKey = ""; return }
                            const modifierOnly = [Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_Meta].indexOf(event.key) >= 0
                            if (modifierOnly) return
                            const parts = []
                            if (event.modifiers & Qt.MetaModifier) parts.push("Meta")
                            if (event.modifiers & Qt.ControlModifier) parts.push("Ctrl")
                            if (event.modifiers & Qt.AltModifier) parts.push("Alt")
                            if (event.modifiers & Qt.ShiftModifier) parts.push("Shift")
                            const names = { [Qt.Key_Space]: "Space", [Qt.Key_Tab]: "Tab", [Qt.Key_Return]: "Return", [Qt.Key_Enter]: "Enter",
                                            [Qt.Key_Backspace]: "Backspace", [Qt.Key_Delete]: "Del", [Qt.Key_Home]: "Home", [Qt.Key_End]: "End",
                                            [Qt.Key_PageUp]: "PgUp", [Qt.Key_PageDown]: "PgDown", [Qt.Key_Insert]: "Ins" }
                            let name = names[event.key]
                            if (!name && event.key >= Qt.Key_F1 && event.key <= Qt.Key_F24) name = "F" + (event.key - Qt.Key_F1 + 1)
                            if (!name && event.text && event.text.trim().length === 1) name = event.text.toUpperCase()
                            if (!name && event.key >= 0x20 && event.key < 0x7F) name = String.fromCharCode(event.key)
                            if (!name) return
                            parts.push(name)
                            if (veyra.setShortcut(root.capturingKey, parts.join("+"))) root.capturingKey = ""
                        }
                    }
                }

                // --- 组件与许可 ------------------------------------------
                ColumnLayout {
                    id: secComp
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "comp"
                    onVisibleChanged: if (visible) veyra.refreshComponentList()
                    VH1 { text: "Components & Licenses" }
                    Text {
                        Layout.fillWidth: true
                        text: "The GPU runtimes OverRez uses for frame generation, super resolution and neural rendering. They are not an official NVIDIA, AMD or Intel partnership or certification. File hashes are in release-runtime-manifest.json, and the licenses are in the licenses folder."
                        color: Theme.t2
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsBody
                        wrapMode: Text.WordWrap
                    }
                    VGroup {
                        // Reported by the engine's component state rather than a
                        // hand-written list that could drift from the package.
                        Repeater {
                            model: veyra.componentList
                            delegate: VRow {
                                id: componentRow
                                required property var modelData
                                readonly property bool anr: modelData.id === "anr"
                                readonly property var download: veyra.anrDownload || ({})
                                readonly property bool downloading: anr && !!download.active
                                readonly property bool downloadable: anr
                                    && !!((veyra.effectCapabilities || {}).anr || {}).downloadable
                                label: modelData.name
                                hint: downloading ? download.status : modelData.detail
                                value: downloading ? download.percent + "%" : ""
                                VButton {
                                    visible: componentRow.downloading || componentRow.downloadable
                                    text: componentRow.downloading ? qsTr("取消") : qsTr("下载并启用")
                                    onClicked: {
                                        if (componentRow.downloading) veyra.cancelAnrDownload()
                                        else veyra.downloadAnr()
                                    }
                                }
                                VTag {
                                    visible: !componentRow.downloading && !componentRow.downloadable
                                    text: modelData.experimental ? qsTr("实验") : (modelData.loaded ? qsTr("已加载") : qsTr("未加载"))
                                    kind: modelData.experimental ? "exp" : (modelData.loaded ? "ok" : "")
                                }
                            }
                        }
                    }
                }

                // --- 关于 ------------------------------------------------
                ColumnLayout {
                    id: secAbout
                    Layout.fillWidth: true
                    spacing: 12
                    visible: root.section === "about"
                    RowLayout {
                        spacing: 18
                        Image {
                            source: Theme.logoImage
                            sourceSize.width: 88
                            fillMode: Image.PreserveAspectFit
                        }
                        ColumnLayout {
                            spacing: 4
                            VH1 { text: "OverRez" }
                            Text {
                                objectName: "about-version"
                                text: "Version " + veyra.version
                                color: Theme.t2
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsBody
                            }
                            Text {
                                text: "Beyond Ultra."
                                color: Theme.t3
                                font.family: Theme.fontUi
                                font.pixelSize: Theme.fsSmall
                            }
                        }
                    }
                    VGroup {
                        VRow {
                            label: "Log"
                            hint: veyra.logFile
                            VButton { text: "Open folder"; ghost: true; onClicked: veyra.openLogFolder() }
                        }
                        VRow {
                            label: "User data"
                            hint: veyra.dataDirectory
                            VButton { text: "Open folder"; ghost: true; onClicked: veyra.openDataFolder() }
                        }
                    }
                    // The diagnostics the engine actually reports, shown verbatim.
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 220
                        radius: 9
                        color: Theme.card2
                        clip: true
                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 10
                            contentHeight: diagText.implicitHeight
                            clip: true
                            ScrollBar.vertical: VScrollBar { }
                            Text {
                                id: diagText
                                width: parent.width
                                text: veyra.diagnosticsReport()
                                color: Theme.t2
                                font.family: Theme.fontMono
                                font.pixelSize: Theme.fsSmall
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                    Text {
                        objectName: "about-credit"
                        Layout.fillWidth: true
                        text: "Based on Veyra by Likely7. Licensed under GPL-3.0."
                        color: Theme.t3
                        font.family: Theme.fontUi
                        font.pixelSize: Theme.fsSmall
                        wrapMode: Text.WordWrap
                    }
                }

                Item { Layout.preferredHeight: 12 }
            }
        }
    }

    VConfirm {
        id: obsRestart
        objectName: "obs-restart-confirm"
        title: qsTr("需要重启软件")
        text: "Settings saved. They take effect after a restart. Restart now? The current capture will stop."
        acceptText: qsTr("是")
        rejectText: qsTr("否")
        onAccepted: veyra.restartApplication()
    }

    // [data-in] entrance order from pages-b.js PAGES.set.
    VRise { target: navCard; d: 0 }
    VRise { target: bodyCard; d: 1 }
}
