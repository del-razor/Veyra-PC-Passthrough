// QML bridge: Export responsibilities.
#include "../QmlPlayerBridge_p.h"

namespace veyra::ui {










QString QmlPlayerBridge::srTargetLabel() const {
    // The label follows the SR target, because that is what sets the output size.
    switch (srTargetIndex()) {
    case 1: return QStringLiteral("2K");
    case 2: return QStringLiteral("4K");
    case 3: return QStringLiteral("8K");
    case 4: return QStringLiteral("5K");
    case 5: return QStringLiteral("6K");
    case 6: return QStringLiteral("7K");
    default: return tr("源尺寸");
    }
}

int QmlPlayerBridge::srTargetIndex() const {
    // UI IDs 1/2/3 remain 2K/4K/8K; append 4/5/6 for 5K/6K/7K.
    switch (settings().srTarget) {
    case pipeline::SrTarget::Qhd: return 1;
    case pipeline::SrTarget::Uhd4K: return 2;
    case pipeline::SrTarget::Uhd8K: return 3;
    case pipeline::SrTarget::Uhd5K: return 4;
    case pipeline::SrTarget::Uhd6K: return 5;
    case pipeline::SrTarget::Uhd7K: return 6;
    }
    return 0;
}
void QmlPlayerBridge::setSrTargetIndex(int index) {
    if(index<1||index>6)return;
    auto s = settings();
    pipeline::SrTarget want = pipeline::SrTarget::Uhd4K;
    switch (index) {
    case 1: want = pipeline::SrTarget::Qhd; break;
    case 2: want = pipeline::SrTarget::Uhd4K; break;
    case 3: want = pipeline::SrTarget::Uhd8K; break;
    case 4: want = pipeline::SrTarget::Uhd5K; break;
    case 5: want = pipeline::SrTarget::Uhd6K; break;
    case 6: want = pipeline::SrTarget::Uhd7K; break;
    default: break;
    }
    if (s.srTarget == want) return;
    s.srTarget = want;
    impl_->commit(std::move(s));
    emit settingsChanged();
}

QVariantList QmlPlayerBridge::presetChoices() const {
    // One list for both kinds; the label carries the distinction so the export page
    // can offer "any preset" without a second control.
    QVariantList out;
    out << QVariantMap{{"id", QStringLiteral("-1")}, {"label", tr("当前播放设置")}};
    const auto& entries = impl_->facade.presets().entries();
    for (size_t i = 0; i < entries.size(); ++i) {
        QVariantMap item;
        item["id"] = QString::number(i);
        item["label"] = utf8Of(entries[i].name)
                        + (entries[i].kind == engine::ChainMode::Node ? tr(" · 节点") : QString());
        item["disabled"] = entries[i].kind == engine::ChainMode::Node;
        out << item;
    }
    return out;
}


QString QmlPlayerBridge::formatTime(double seconds) const { return mmss(seconds); }

QString QmlPlayerBridge::diagnosticsReport() const {
    // Engine-reported values only. A diagnostic that guesses is worse than none.
    const auto& s = impl_->snapshot;
    QStringList lines;
    lines << tr("状态: %1").arg(uiText(s.status));
    lines << tr("源: %1x%2 旋转 %3° 标称 %4 fps")
                 .arg(s.sourceWidth).arg(s.sourceHeight).arg(s.sourceRotationDegrees)
                 .arg(s.nominalSourceFps, 0, 'f', 2);
    lines << tr("提交 FPS: %1").arg(s.submissionFps ? QString::number(*s.submissionFps, 'f', 2) : tr("未测量"));
    lines << tr("晚点: 当前 %1 ms / P95 %2 ms").arg(s.lateMs, 0, 'f', 2).arg(s.lateP95Ms, 0, 'f', 2);
    lines << tr("调度等待 P95: %1 ms").arg(s.schedulingWaitP95Ms, 0, 'f', 2);
    lines << tr("处理 CPU P95: %1 ms").arg(s.processCpuP95Ms, 0, 'f', 2);
    lines << tr("呈现 CPU P95: %1 ms").arg(s.presentCpuP95Ms, 0, 'f', 2);
    lines << tr("帧: 已处理 %1 生成 %2").arg(s.frames).arg(s.generated);
    lines << tr("NR 求值 %1 / NVOF %2").arg(s.nrEvaluated).arg(s.nvofExecuted);
    if (s.capture) {
        lines << tr("采集: 接收 %1 丢弃 %2 速率 %3 fps")
                     .arg(s.captureReceived).arg(s.captureDropped).arg(s.captureFps, 0, 'f', 2);
    }
    if (!s.backendWarning.empty()) lines << tr("后端告警: %1").arg(uiText(s.backendWarning));
    if (!s.colorStatus.empty()) lines << tr("色彩: %1").arg(uiText(s.colorStatus));
    if (!s.videoHdrStatus.empty()) lines << tr("Video HDR: %1").arg(uiText(s.videoHdrStatus));
    return lines.join(QLatin1Char('\n'));
}


} // namespace veyra::ui
