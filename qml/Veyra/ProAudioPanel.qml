// Professional-view audioCol controls; settings remain in the shared bridge.
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes
import QtQuick.Effects

ColumnLayout {
    id: audioCol
    Layout.fillWidth: true
    spacing: 6
    VGroup {
        VRow {
            label: qsTr("音量")
            value: Math.round(veyra.volume * 100) + "%"
            VSlider {
                implicitWidth: 150
                from: 0; to: veyra.maximumVolume; value: veyra.volume; inputScale: 100
                defaultValue: 1
                onMoved: value => veyra.volume = value
            }
        }
        VRow {
            label: qsTr("静音")
            VSwitch {
                checked: veyra.muted
                onToggled: checked => veyra.muted = checked
            }
        }
        VRow {
            label: qsTr("声音同步")
            hint: veyra.audioSyncMode === 0 ? (veyra.audioSyncLive ? qsTr("软件估算补偿 ") + veyra.audioCompensationMs.toFixed(0) + " ms" : qsTr("自动估算 · 采集卡 / PS5 实时输入时生效"))
                  : veyra.audioSyncMode === 1 ? qsTr("手动偏移 · 实时输入时生效") : qsTr("关闭补偿")
            VSeg {
                options: [{ id: "0", label: qsTr("自动估算") }, { id: "1", label: qsTr("手动") }, { id: "2", label: qsTr("关闭", "off") }]
                current: String(veyra.audioSyncMode)
                onPicked: id => veyra.audioSyncMode = Number(id)
            }
        }
        VRow {
            label: qsTr("音频偏移")
            hint: qsTr("正值延后音频")
            value: veyra.audioOffsetMs + " ms"
            VSlider {
                implicitWidth: 150
                center: true
                from: -250; to: 250; value: veyra.audioOffsetMs; enabledControl: veyra.audioSyncMode === 1
                onMoved: value => veyra.audioOffsetMs = Math.round(value)
            }
        }
    }
}
