import QtQuick

VMenu {
    id: menu
    required property var backend
    signal settingsRequested()

    readonly property bool captureSource: backend.sourceKind === "capture"
    readonly property bool monitorOff: captureSource && backend.preferences.captureAudioMonitor === false
    readonly property string buttonLabel: captureSource
        ? (monitorOff ? qsTr("本机音频监听") + " · " + qsTr("已关闭") : qsTr("本机音频监听"))
        : qsTr("音轨")

    title: captureSource ? qsTr("声音") : qsTr("音轨")
    items: {
        const settings = { label: qsTr("音频设置…"), note: qsTr("输出设备、音画同步、偏移"), icon: "music", act: "settings" }
        if (captureSource) {
            return [
                { label: qsTr("本机音频监听"), tag: monitorOff ? qsTr("已关闭") : "", icon: "vol",
                  checked: !monitorOff, gold: monitorOff, act: "monitor", enabledValue: monitorOff },
                { sep: true }, settings
            ]
        }
        return [settings]
    }

    onPicked: (index, item) => {
        if (!item) return
        if (item.act === "settings") {
            settingsRequested()
        } else if (item.act === "monitor") {
            if (captureSource) backend.setPreference("captureAudioMonitor", item.enabledValue)
        }
    }
}
