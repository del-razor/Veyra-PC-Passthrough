// QML bridge: Playback responsibilities.
#include "../QmlPlayerBridge_p.h"
#include "../LiveTranslation.h"

#include <regex>
#include "veyra/pipeline/NrReuse.h"

namespace veyra::ui {
// --- playback ---------------------------------------------------------------
QString QmlPlayerBridge::statusText() const {
    const auto& snapshot = impl_->snapshot;
    if (snapshot.captureDriverWaitMs) {
        return tr("采集卡驱动响应缓慢（已等待 %1 秒）。若频繁出现，请重新插拔采集卡并检查 USB 连接。")
            .arg(snapshot.captureDriverWaitMs / 1000);
    }
    return uiText(snapshot.status);
}
bool QmlPlayerBridge::running() const { return impl_->snapshot.running; }
bool QmlPlayerBridge::paused() const { return impl_->snapshot.transport == engine::TransportState::Paused; }
bool QmlPlayerBridge::failed() const { return impl_->snapshot.failed; }
bool QmlPlayerBridge::isImage() const { return impl_->snapshot.image; }
bool QmlPlayerBridge::isCapture() const { return impl_->snapshot.capture; }
bool QmlPlayerBridge::hasSource() const { return impl_->snapshot.running || impl_->snapshot.image; }
bool QmlPlayerBridge::openingSource() const { return impl_->openingSource; }
bool QmlPlayerBridge::captureEnhancementLoading() const { return impl_->snapshot.captureEnhancementLoading && !impl_->snapshot.failed; }
double QmlPlayerBridge::position() const { return impl_->snapshot.position; }
double QmlPlayerBridge::duration() const { return impl_->snapshot.duration; }
double QmlPlayerBridge::progress() const {
    const auto& n=impl_->snapshot.network;
    if (n.timeshiftEnabled&&n.timeshiftEndSeconds>n.timeshiftStartSeconds) {
        const double span=n.timeshiftEndSeconds-n.timeshiftStartSeconds;
        return std::clamp((position()-n.timeshiftStartSeconds)/span,0.0,1.0);
    }
    const double d = impl_->snapshot.duration;
    return d > 0.01 ? std::clamp(impl_->snapshot.position / d, 0.0, 1.0) : 0.0;
}
QString QmlPlayerBridge::positionText() const {
    const auto& n=impl_->snapshot.network;
    if(n.timeshiftEnabled&&n.timeshiftEndSeconds>n.timeshiftStartSeconds) {
        const double behind=std::max(0.0,n.timeshiftEndSeconds-position());
        return behind<1 ? tr("直播") : QStringLiteral("−")+mmss(behind);
    }
    return mmss(impl_->snapshot.position);
}
QString QmlPlayerBridge::durationText() const {
    return impl_->snapshot.network.live ? tr("直播") : mmss(impl_->snapshot.duration);
}
bool QmlPlayerBridge::timelineSeekable() const {
    const auto& n=impl_->snapshot.network;
    return n.live ? n.timeshiftEnabled&&n.timeshiftEndSeconds>n.timeshiftStartSeconds : duration()>0&&!isCapture();
}
QVariantMap QmlPlayerBridge::liveTimeshift() const {
    const auto& n=impl_->snapshot.network;
    return {{"enabled",n.timeshiftEnabled},{"available",n.live&&timelineSeekable()},
            {"start",n.timeshiftStartSeconds},{"end",n.timeshiftEndSeconds}};
}
double QmlPlayerBridge::timelineSeconds(double fraction) const {
    const auto& n=impl_->snapshot.network;
    fraction=std::clamp(fraction,0.0,1.0);
    if(n.timeshiftEnabled)return n.timeshiftStartSeconds+fraction*(n.timeshiftEndSeconds-n.timeshiftStartSeconds);
    return fraction*duration();
}
void QmlPlayerBridge::returnToLive() {
    if(!impl_->snapshot.network.timeshiftEnabled||!timelineSeekable()) return;
    seekTo(impl_->snapshot.network.timeshiftEndSeconds);
    if(paused())togglePlayPause();
}

// --- source -----------------------------------------------------------------
QString QmlPlayerBridge::sourceName() const {
    if (impl_->sourceLabel.empty()) return QString();
    if(impl_->liveKind==QLatin1String("url"))return tr("网络视频 · %1").arg(impl_->liveLabel);
    return QFileInfo(utf8Of(impl_->sourceLabel)).fileName();
}
QString QmlPlayerBridge::sourceSummary() const {
    const auto& s = impl_->snapshot;
    if (!s.sourceWidth) return QString();
    // Reported values only: no upscaling claim, no invented bit depth.
    return QStringLiteral("%1x%2").arg(s.sourceWidth).arg(s.sourceHeight);
}

int QmlPlayerBridge::sourceWidth() const { return int(impl_->snapshot.sourceWidth); }
int QmlPlayerBridge::sourceHeight() const { return int(impl_->snapshot.sourceHeight); }
double QmlPlayerBridge::sourceFps() const { return impl_->snapshot.nominalSourceFps; }
int QmlPlayerBridge::sourceRotation() const { return impl_->snapshot.sourceRotationDegrees; }
int QmlPlayerBridge::previewRotation() const { return int(impl_->engine.previewView().userQuarterTurns)*90; }
void QmlPlayerBridge::rotatePictureClockwise() {
    if(impl_->screenCropPreview||!hasSource()||!impl_->engine.rotatePreviewClockwise(impl_->snapshot.sessionId))return;
    // An in-progress protection selection uses the previous coordinate system.
    beginProtectionDraw(QString());
    tickSubtitles();
    if(gameMode()){updateGameGeometry();updateGameMode();emit gameModeChanged();}
    veyra::log::info("ui-rotation",std::format("session={} clockwise={}",impl_->snapshot.sessionId,previewRotation()));
    emit compareChanged();
}
double QmlPlayerBridge::sourceAspect() const {
    const auto& s = impl_->snapshot;
    // A known DAR already includes SAR/rotation. With no DAR, rotate the coded
    // extent as the presenter does; phone files can omit SAR yet carry a matrix.
    engine::PreviewView view;
    view.displayAspect=s.sourceDisplayAspect;
    view.rotationDegrees=s.sourceRotationDegrees;
    return view.aspect(float(s.sourceWidth),float(s.sourceHeight));
}

// --- live performance -------------------------------------------------------
// XeSS generates inside the provider: the engine only submits source frames,
// so its own rate would read 60 while the SDK presents 120. Show the provider's
// reported submissions for XeSS (AppShell: "SDK提交（非屏幕实测）").
static bool xessPresenting(const engine::PlayerSnapshot& s) {
    return s.fgActive && s.applied.frameGenerationBackend == engine::FrameGenerationBackend::XeSS &&
        s.metrics.flow.xessSdkSubmitFps > 0;
}
double QmlPlayerBridge::submitFps() const {
    const auto& s = impl_->snapshot;
    return xessPresenting(s) ? s.metrics.flow.xessSdkSubmitFps : s.submissionFps.value_or(0.0);
}
bool QmlPlayerBridge::submitFpsKnown() const { return xessPresenting(impl_->snapshot) || impl_->snapshot.submissionFps.has_value(); }
// Our own presents only: while the XeSS SDK presents its frames itself the
// intervals between them are not observed here, so there is no 1% low.
double QmlPlayerBridge::submitLowFps() const { return submitLowFpsKnown() ? *impl_->snapshot.submissionLow1Fps : 0.0; }
bool QmlPlayerBridge::submitLowFpsKnown() const { return !xessPresenting(impl_->snapshot) && impl_->snapshot.submissionLow1Fps.has_value(); }
QString QmlPlayerBridge::submitFpsLabel() const { return xessPresenting(impl_->snapshot) ? tr("SDK 提交") : tr("提交"); }
double QmlPlayerBridge::lateMs() const { return impl_->snapshot.lateMs; }
double QmlPlayerBridge::lateP95Ms() const { return impl_->snapshot.lateP95Ms; }
QString QmlPlayerBridge::metricsSummary() const {
    const auto& s = impl_->snapshot;
    // Submit FPS, named as such: it is what we handed to the presenter, not what
    // the panel scanned out. There is no "display FPS" because we cannot measure
    // one, and a number we did not measure must not be shown as if we had.
    if (!s.submissionFps) return tr("未测量");
    return tr("提交 %1").arg(*s.submissionFps, 0, 'f', 1);
}
bool QmlPlayerBridge::nrActive() const { return impl_->snapshot.nrActive; }
bool QmlPlayerBridge::nrAutoActive() const {return impl_->snapshot.nrAutoActive;}
int QmlPlayerBridge::nrAutoPercent() const {return int(impl_->snapshot.nrAutoPercent);}
QString QmlPlayerBridge::nrAutoStatus() const {
    const auto& s=impl_->snapshot;
    if(s.nrAutoActive)return tr("NR 自动 %1% · %2×%3").arg(s.nrAutoPercent).arg(s.nrAutoWidth).arg(s.nrAutoHeight);
    if(s.nrAutoStatus==L"自动NR实例池不可用，保留1080p NR")return tr("自动 NR 实例池不可用，保留固定 1080p 档");
    if(!s.nrAutoStatus.empty())return tr("当前配置未启用自动 NR，保留固定 1080p 档");
    return {};
}
// NR inference reuse: what the running preview graph actually does. Nothing
// while the mode is off or nothing plays; a reason when the mode is on but
// this chain cannot reuse (EnhanceGraph::nrReuseIneligibility, ASCII).
bool QmlPlayerBridge::nrReuseActive() const { return impl_->snapshot.nrReuseActive; }
QString QmlPlayerBridge::nrReuseStatus() const {
    const auto& s=impl_->snapshot;
    if(settings().nrReuse==engine::NrReuseMode::Off)return {};
    if(s.nrReuseActive){
        const unsigned every=pipeline::NrReuseScheduler::framesPerReuse(s.nrReuseLevel);
        const QString state=every==0?tr("跟得上，每帧都推理"):tr("每 %1 帧复用 1 帧").arg(every);
        // No running count: hours of play reach millions of frames.
        return s.nrReuseAutomatic?tr("自动 · ")+state:state;
    }
    const auto& why=s.nrReuseUnavailable;
    if(why.empty())return {};
    QString reason;
    if(why=="not a realtime preview graph"||why=="still image")reason=tr("只在实时预览生效");
    else if(why=="NR not created")reason=tr("NR 未运行");
    else if(why=="NVIDIA NGX NR only")reason=tr("仅支持英伟达 NR");
    else if(why=="SDR only")reason=tr("HDR 处理时不复用");
    else if(why=="NR motion must use optical flow")reason=tr("NR 运动来源需为光流");
    else if(why=="NR split across SR")reason=tr("NR 分在超分前后时不复用");
    else if(why=="protection between NR stages")reason=tr("NR 层之间有保护区域时不复用");
    else if(why=="node mode")reason=tr("节点模式暂不支持");
    else if(why=="automatic NR size pool")reason=tr("自动 NR 尺寸开启时不复用");
    else reason=tr("资源不足");
    return tr("未生效：")+reason;
}
bool QmlPlayerBridge::srActive() const { return impl_->snapshot.srActive; }
bool QmlPlayerBridge::fgActive() const { return impl_->snapshot.fgActive; }
bool QmlPlayerBridge::captureRecovering() const { return impl_->snapshot.captureRecovering; }
double QmlPlayerBridge::captureFps() const { return impl_->snapshot.captureFps; }
double QmlPlayerBridge::captureDropped() const { return double(impl_->snapshot.captureDropped); }
QString QmlPlayerBridge::backendWarning() const {
    const auto& snapshot=impl_->snapshot;
    if(snapshot.running&&snapshot.nrPreparing&&snapshot.backendWarning.empty())
        return tr("正在准备 RX 7000 NR，当前显示未应用 NR 的画面。");
    return uiText(snapshot.backendWarning);
}





void QmlPlayerBridge::bringToFront() {
    // Windows 只允许前台进程直接 SetForegroundWindow。点击发生在浏览器里，
    // Veyra 是后台进程，所以第一次调用会被拒绝（任务栏闪烁）。
    // 依次尝试：直接调用 -> 挂到前台线程 -> TOPMOST 切换强制改 Z 序。
    for (QWindow* w : QGuiApplication::topLevelWindows()) {
        if (!w->isVisible() || w->flags().testFlag(Qt::Tool)) continue;
        const auto hwnd = reinterpret_cast<HWND>(w->winId());
        if (hwnd == nullptr) continue;

        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        w->show();
        w->raise();
        w->requestActivate();
        if (SetForegroundWindow(hwnd)) {
            log::info("playback-server", "window brought to front");
            break;
        }

        const HWND fg = GetForegroundWindow();
        const DWORD fgThread = fg ? GetWindowThreadProcessId(fg, nullptr) : 0;
        const DWORD selfThread = GetCurrentThreadId();
        if (fgThread != 0 && fgThread != selfThread) {
            AttachThreadInput(selfThread, fgThread, TRUE);
            SetForegroundWindow(hwnd);
            AttachThreadInput(selfThread, fgThread, FALSE);
        }
        if (GetForegroundWindow() == hwnd) {
            log::info("playback-server", "window brought to front");
            break;
        }

        // 系统仍拒绝：短暂置顶再取消，强制改变 Z 序后再抢一次前台。
        SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetWindowPos(hwnd, HWND_NOTOPMOST, 0, 0, 0, 0,
                     SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
        SetForegroundWindow(hwnd);
        if (GetForegroundWindow() == hwnd) {
            log::info("playback-server", "window brought to front (topmost)");
        } else {
            log::warn("playback-server", "window could not be activated; flashing instead");
            FlashWindow(hwnd, TRUE);
        }
        break;
    }
}

void QmlPlayerBridge::togglePlayPause() {
    // AppShell's Play button: a paused session is still "running" (the worker
    // stays alive), so the decision must come from the transport state.
    const auto& s = impl_->snapshot;
    using T = engine::TransportState;
    if (s.image || s.transport == T::Opening || s.transport == T::Stopping) return;
    // Capture cards and streams pause too (field request 2026-10-02): the engine stops
    // reading and enhancing, keeps the last picture and resets the source's queue, so
    // play resumes with the newest frame rather than a backlog. The connection stays up.
    if (s.capture && s.running) {
        const bool pause = s.transport == T::Playing;
        impl_->engine.pause(pause);
        veyra::log::info("ui-transport", pause ? "live pause" : "live resume");
        emit notice(pause ? tr("已暂停：画面停在当前帧，不再处理新画面；点播放继续") : tr("已继续"), false);
        return;
    }
    if (!s.running || s.transport == T::Ended) return;
    const bool pause = s.transport == T::Playing;
    impl_->engine.pause(pause);
    veyra::log::info("ui-transport", pause ? "pause" : "resume");
}
void QmlPlayerBridge::stopPlayback() {
    impl_->screenCropPreview = false;
    flushHdrMemory();
    rememberPosition(true);
    ++impl_->liveOpenGen; impl_->pendingLiveText.clear();
    impl_->openingSource = false;
    impl_->openingSessionId = 0;
    impl_->engine.stop();
}
void QmlPlayerBridge::seekTo(double seconds) {
    if(!timelineSeekable())return;
    liveTranslation_->setPlayback(impl_->snapshot.sessionId, false, true);
    impl_->engine.seek(seconds);
}
void QmlPlayerBridge::seekBy(double seconds) {
    seekTo(std::max(0.0, impl_->snapshot.position + seconds));
}
void QmlPlayerBridge::logUi(const QString& channel, const QString& text) {
    const std::string c = channel.toStdString();
    veyra::log::info(c.c_str(), text.toStdString());
}
void QmlPlayerBridge::setWindowMask(QObject* window, const QRectF& rect) {
    auto* w = qobject_cast<QWindow*>(window);
    if (!w) return;
    w->setMask(QRegion(rect.toAlignedRect()));
}
void QmlPlayerBridge::holdOriginal(bool held) {
    // Releasing the key returns to whatever the 显示 page chose (off or split).
    if (held) impl_->engine.comparison(1, false);
    else impl_->engine.comparison(impl_->compareMode, impl_->compareBase, float(impl_->compareSplit));
    veyra::log::info("ui-compare", held ? "hold original on" : "hold original off");
}
void QmlPlayerBridge::stepFrame(int direction) {
    // A frame step is a small seek. The engine owns the real frame duration, so
    // this is honest about being approximate rather than pretending to be exact.
    if (!direction) return;
    impl_->engine.seek(std::max(0.0, impl_->snapshot.position + (direction > 0 ? 1.0 / 60.0 : -1.0 / 60.0)));
}

void QmlPlayerBridge::takeScreenshot() {
    if (!hasSource()) { emit notice(tr("没有正在播放的画面，无法截图"), true); return; }
    if(!impl_->pendingScreenshot.isEmpty()){emit notice(tr("请等待当前图片导出完成"),true);return;}
    const QString folder = screenshotDirectory();
    if (!QDir().mkpath(folder)) { emit notice(tr("截图目录不可用：%1").arg(folder), true); return; }
    const QString name = QStringLiteral("veyra-%1.png")
                             .arg(QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd-HHmmss-zzz")));
    const QString path = QDir(folder).filePath(name);
    impl_->engine.saveFrame(wideOf(QDir::toNativeSeparators(path)));
    impl_->pendingScreenshot=path;
    impl_->pendingScreenshotDeadline=QDateTime::currentMSecsSinceEpoch()+30000;
    impl_->lastScreenshot.clear();
    veyra::log::info("ui-screenshot", "requested path=" + path.toStdString());
    emit preferencesChanged();
}



} // namespace veyra::ui
