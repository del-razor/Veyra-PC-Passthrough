// QML bridge: Capture responsibilities.
#include "../QmlPlayerBridge_p.h"
#include "veyra/source/VirtualDesktop.h"
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <map>

namespace veyra::ui {
void QmlPlayerBridge::openSourceUri(const std::wstring& uri, const std::wstring& label, bool screenFill) {
    impl_->screenCropPreview = false;
    rememberPosition(true);
    emit mediaOpenRequested();
    impl_->openingSource = true;
    impl_->openingSessionId = 0;
    impl_->sourceLabel = label;
    impl_->screenFillActive = screenFill;
    // Honor the dialog's initial viewport before input can be taken over.
    // Later explicit aspect choices still replace this session preset.
    if (!impl_->gameModeUri.empty() && uri == impl_->gameModeUri) impl_->aspectMode = 0;
    const bool screen = uri.starts_with(L"screen:");
    veyra::log::info("capture-ui", "open uri " + QString::fromStdWString(uri).toStdString());
    openAfterLivePage(screen ? tr("正在开始屏幕捕获…") : tr("正在打开采集设备 · %1").arg(utf8Of(label)), [this, uri] {
        if (impl_->preOpen) impl_->preOpen();
        impl_->engine.previewView({});
        impl_->engine.open(impl_->videoWindow, uri, impl_->options);
        impl_->openingSessionId = impl_->engine.snapshot().sessionId;
        // Only the exact capture startScreenCapture opened in 游戏模式 is one.
        impl_->gameModeSessionId = !impl_->gameModeUri.empty() && uri == impl_->gameModeUri ? impl_->openingSessionId : 0;
        impl_->gameModeLive = false;
        impl_->gameModeUri.clear();
        updateGameMode();
        refreshSubtitles({});
    }, screen ? QStringLiteral("min") : QStringLiteral("pro"));
}

void QmlPlayerBridge::openAfterLivePage(const QString& pending, std::function<void()> open, const QString& homeTarget) {
    const int gen = ++impl_->liveOpenGen;
    const bool fromHome = impl_->currentPage.isEmpty() || impl_->currentPage == QLatin1String("home");
    if (fromHome) emit navigate(homeTarget);
    if (!fromHome || !impl_->gameModeUri.empty()) {
        // Game mode does not wait for the cinema animation or feature startup.
        impl_->pendingLiveText.clear(); open(); return;
    }
    // Open after the destination has laid out its video viewport. Cinema also
    // needs this delay for its window-height animation.
    impl_->pendingLiveText = pending;
    emit snapshotChanged();
    const int delay = reducedMotion() ? 0 : 820;
    veyra::log::info("ui-live-open", std::format("deferred ms={} gen={}", delay, gen));
    QTimer::singleShot(delay, this, [this, gen, open = std::move(open)] {
        if (gen != impl_->liveOpenGen) { veyra::log::info("ui-live-open", std::format("superseded gen={}", gen)); return; }
        impl_->pendingLiveText.clear();
        veyra::log::info("ui-live-open", std::format("open gen={}", gen));
        open();
        emit snapshotChanged();
    });
}

// Force-SDR and vertical flip are real settings the engine already carries, so
// these are genuine controls rather than placeholders.
bool QmlPlayerBridge::captureForceSdr() const { return settings().forceSdrPreview; }
void QmlPlayerBridge::setCaptureForceSdr(bool value) {
    auto s = settings();
    if (s.forceSdrPreview == value) return;
    s.forceSdrPreview = value;
    if(impl_->commit(std::move(s))){impl_->prefs["captureForceSdr"]=value;if(!impl_->savePrefs())emit notice(tr("采集设置保存失败，请检查配置目录是否可写"),true);}
    emit settingsChanged();
}

// --- screen capture ----------------------------------------------------------
namespace {
// An adapter's name by LUID (DXGI). Cached: neither changes while the program runs.
QString adapterName(uint64_t luid) {
    static std::map<uint64_t, QString> names;
    if (const auto it = names.find(luid); it != names.end()) return it->second;
    QString name;
    Microsoft::WRL::ComPtr<IDXGIFactory4> factory;
    Microsoft::WRL::ComPtr<IDXGIAdapter1> adapter;
    DXGI_ADAPTER_DESC1 d{};
    if (SUCCEEDED(CreateDXGIFactory1(IID_PPV_ARGS(&factory))) &&
        SUCCEEDED(factory->EnumAdapterByLuid(LUID{DWORD(luid & 0xFFFFFFFFu), LONG(luid >> 32)}, IID_PPV_ARGS(&adapter))) &&
        SUCCEEDED(adapter->GetDesc1(&d)))
        name = QString::fromWCharArray(d.Description);
    return names[luid] = name;
}
}

QVariantList QmlPlayerBridge::screenTargets() const {
    // Enumerated from the source for the chosen kind; cached until refreshed so a
    // binding re-evaluation does not walk every window again.
    QVariantList out;
    // Issue #107: a target whose display another GPU drives is copied between the
    // GPUs by Windows on every frame; the dialog names both adapters.
    const auto* engine = engineAdapterDesc();
    const uint64_t processing = engine ? uint64_t(uint32_t(engine->AdapterLuid.HighPart)) << 32 | engine->AdapterLuid.LowPart : 0;
    for (const auto& target : impl_->screenList) {
        QVariantMap item;
        item["id"] = QString::number(target.handle);
        QString label = QString::fromWCharArray(target.name.c_str());
        // A window on another virtual desktop (Win+Ctrl+D) is captured without
        // switching to it; the label names that desktop as Task View shows it.
        if (target.otherDesktop) {
            const QString name = QString::fromStdWString(target.desktopName);
            const QString desktop = !target.desktopNumber ? tr("其他桌面")
                : name.isEmpty() ? tr("桌面 %1").arg(target.desktopNumber)
                : tr("桌面 %1 · %2").arg(target.desktopNumber).arg(name);
            label = QStringLiteral("[%1] %2").arg(desktop, label);
        }
        if (target.width > 0)
            label += QStringLiteral(" · %1x%2").arg(target.width).arg(target.height);
        if (target.refresh > 0) label += QStringLiteral(" · %1Hz").arg(target.refresh);
        item["label"] = label;
        item["width"] = int(target.width);
        item["height"] = int(target.height);
        item["otherDesktop"] = target.otherDesktop;
        item["desktop"] = int(target.desktopNumber);
        if (processing && target.displayAdapter && target.displayAdapter != processing) {
            item["otherGpu"] = true;
            item["displayGpu"] = adapterName(target.displayAdapter);
            item["processingGpu"] = QString::fromWCharArray(engine->Description);
        }
        out << item;
    }
    return out;
}
QVariantMap QmlPlayerBridge::screenOptions() const {
    QVariantMap d{{"kind", 0}, {"method", 0}, {"fps", 0}, {"cursor", true}, {"fill", false},
                  {"left", 0}, {"top", 0}, {"right", 0}, {"bottom", 0}, {"passthrough", false}};
    const auto saved = impl_->prefs.value("screen").toMap();
    for (auto it = saved.begin(); it != saved.end(); ++it) if (d.contains(it.key())) d[it.key()] = it.value();
    if (d.value("kind").toInt() == 0) d["method"] = 0;           // DXGI is monitors only
    // OverRez: game mode is always on. The real pointer stays on top of the picture,
    // so the picture carries none, and it maps 1:1 to the screen, so it is never cropped.
    d["passthrough"] = true;
    d["cursor"] = false;
    d["left"] = d["top"] = d["right"] = d["bottom"] = 0;
    return d;
}
bool QmlPlayerBridge::setScreenOption(const QString& key, const QVariant& value) {
    static const QHash<QString, std::pair<int, int>> ranges{{"kind", {0, 1}}, {"method", {0, 1}}, {"fps", {0, 5}},
        {"left", {0, 16384}}, {"top", {0, 16384}}, {"right", {0, 16384}}, {"bottom", {0, 16384}}};
    auto saved = impl_->prefs.value("screen").toMap();
    if (ranges.contains(key)) {
        bool ok = false; const int n = value.toInt(&ok);
        const auto [low, high] = ranges.value(key);
        if (!ok || n < low || n > high) { emit notice(tr("数值超出范围"), true); return false; }
        saved[key] = n;
    } else if (key == QLatin1String("cursor") || key == QLatin1String("passthrough")) {
        return true;                                             // fixed by game mode, see screenOptions()
    } else if (key == QLatin1String("fill")) {
        saved[key] = value.toBool();
    } else return false;
    impl_->prefs["screen"] = saved;
    impl_->savePrefs();
    if (key == QLatin1String("kind")) { impl_->screenTarget.clear(); refreshCaptureTargets(); }
    emit captureChanged();
    return true;
}
bool QmlPlayerBridge::startScreenCapture(bool cropPreview) {
    const auto o = screenOptions();
    source::ScreenCaptureOptions value;
    bool found = false;
    for (const auto& t : impl_->screenList)
        if (QString::number(t.handle) == impl_->screenTarget) { value.kind = t.kind; value.target = t.handle; found = true; }
    if (!found) { emit notice(tr("先选择一个捕获目标"), true); return false; }
    constexpr unsigned rates[] = {0, 30, 60, 120, 144, 240};
    value.method = source::ScreenCaptureMethod(o.value("method").toInt());
    value.fps = rates[std::clamp(o.value("fps").toInt(), 0, 5)];
    value.cursor = o.value("cursor").toBool();
    value.left = o.value("left").toUInt(); value.top = o.value("top").toUInt();
    value.right = o.value("right").toUInt(); value.bottom = o.value("bottom").toUInt();
    // 游戏模式: the real pointer is drawn on top, so the picture carries none (a
    // second, late pointer otherwise), the picture must match the screen 1:1 for
    // clicks to land where they are seen (no crop), and the yellow border goes.
    const bool game = o.value("passthrough").toBool();
    if (cropPreview && game) return false;
    // 游戏模式 hands the foreground to the captured window, and activating a window
    // on another virtual desktop makes Windows switch to that desktop, away from
    // the picture. Checked live: the window may have moved since the list was read.
    if (game && value.kind == source::ScreenTargetKind::Window) {
        source::vdesk::Placement desktop;
        if (source::vdesk::Lookup{}.otherDesktop(reinterpret_cast<void*>(value.target), desktop)) {
            emit notice(QStringLiteral("This window is on another Windows virtual desktop. Move it to this desktop, then start the capture."), true);
            return false;
        }
    }
    if (game) {
        value.cursor = false; value.borderless = true;
        value.left = value.top = value.right = value.bottom = 0;
        const HWND window = value.kind == source::ScreenTargetKind::Window ? reinterpret_cast<HWND>(value.target) : nullptr;
        impl_->gameMonitor = window ? MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST) : reinterpret_cast<HMONITOR>(value.target);
        impl_->game.setTarget(window, impl_->gameMonitor, !window);
        impl_->gameModeUri = value.uri();
        // Exclusive fullscreen still cannot be covered by another process.
        QUERY_USER_NOTIFICATION_STATE state{};
        if (SUCCEEDED(SHQueryUserNotificationState(&state)) && state == QUNS_RUNNING_D3D_FULL_SCREEN)
            emit notice(QStringLiteral("The game is in exclusive fullscreen, which Windows lets nothing cover. Switch the game to borderless windowed or windowed mode."), true);
    } else impl_->gameModeUri.clear();
    if (cropPreview) value.left = value.top = value.right = value.bottom = 0;
    bool otherDesktop = false;
    for (const auto& t : impl_->screenList) if (t.handle == value.target) otherDesktop = t.otherDesktop;
    veyra::log::info("screen-ui", std::format("start kind={} method={} fps={} cursor={} crop={},{},{},{} fill={} gameMode={} otherVirtualDesktop={}", int(value.kind), int(value.method),
        value.fps, value.cursor, value.left, value.top, value.right, value.bottom, o.value("fill").toBool(), game, otherDesktop));
    openSourceUri(value.uri(), wideOf(screenTargetLabel()), !cropPreview && o.value("fill").toBool());
    impl_->screenCropPreview = cropPreview;
    impl_->liveKind = QStringLiteral("screen");
    impl_->liveLabel = screenTargetLabel();
    impl_->screenFitClient = impl_->screenFitImage = QSize();
    if(cropPreview) applyAspect(true);
    if (gameMode()) { updateGameGeometry(); updateGameMode(); emit gameModeChanged(); }
    emit compareChanged();
    if(!cropPreview) rememberSource(QStringLiteral("screen"), screenTargetLabel());
    return true;
}
bool QmlPlayerBridge::applyScreenCrop(int left,int top,int right,int bottom) {
    if (!impl_->screenCropPreview || impl_->openingSource || sourceKind() != QLatin1String("screen") ||
        std::min({left,top,right,bottom}) < 0 ||
        int64_t(left)+right+16 > sourceWidth() || int64_t(top)+bottom+16 > sourceHeight()) {
        emit notice(tr("裁剪范围超出画面"),true);
        return false;
    }
    const auto previous=impl_->prefs.value("screen");
    auto crop=previous.toMap();
    crop["left"]=left; crop["top"]=top; crop["right"]=right; crop["bottom"]=bottom;
    impl_->prefs["screen"]=crop;
    if (!startScreenCapture()) { impl_->prefs["screen"]=previous; return false; }
    impl_->savePrefs();
    emit captureChanged();
    return true;
}
bool QmlPlayerBridge::gameMode() const { return impl_->gameModeSessionId != 0; }
bool QmlPlayerBridge::passthroughActive() const { return impl_->passthroughShown; }
bool QmlPlayerBridge::gameInputActive() const { return impl_->gameInputShown; }
bool QmlPlayerBridge::gameScaledPreview() const {
    return gameMode() && (ui::gameViewportScaled(impl_->screenFillActive, impl_->aspectMode) || previewRotation()!=0);
}
QRectF QmlPlayerBridge::gameVideoRect() const { return impl_->gameVideoRect; }
void QmlPlayerBridge::attachMainWindow(qulonglong nativeHandle) {
    impl_->game.attach(reinterpret_cast<HWND>(nativeHandle));
    for (auto* window:QGuiApplication::allWindows())
        if (qulonglong(window->winId())==nativeHandle) { impl_->gameWindow=window; break; }
}
void QmlPlayerBridge::updateGameGeometry() {
    if (!gameMode() || !impl_->presentation.fullscreen || !impl_->gameWindow) return;
    RECT r=impl_->game.pictureBounds();
    if (gameScaledPreview()) {
        const HWND main = reinterpret_cast<HWND>(impl_->gameWindow->winId());
        POINT origin{};
        MONITORINFO info{sizeof(info)};
        if (!GetMonitorInfoW(impl_->gameMonitor, &info) || !ClientToScreen(main, &origin)) return;
        r=info.rcMonitor; OffsetRect(&r,-origin.x,-origin.y);
    }
    const qreal scale=impl_->gameWindow->devicePixelRatio();
    if (scale<=0) return;
    const QRectF rect(r.left/scale,r.top/scale,(r.right-r.left)/scale,(r.bottom-r.top)/scale);
    if (!rect.isEmpty() && rect!=impl_->gameVideoRect) {
        impl_->gameVideoRect=rect; emit gameModeChanged();
    }
}
void QmlPlayerBridge::setGamePanelOpen(bool open) {
    if (impl_->gamePanelOpen == open) return;
    impl_->gamePanelOpen = open;
    updateGameMode();
}
int QmlPlayerBridge::gameModeScreenIndex() const {
    if (!impl_->gameMonitor) return -1;
    const auto screens = QGuiApplication::screens();
    for (int i = 0; i < screens.size(); ++i) {
        const auto* native = screens[i]->nativeInterface<QNativeInterface::QWindowsScreen>();
        if (native && native->handle() == impl_->gameMonitor) return i;
    }
    return -1;
}
void QmlPlayerBridge::testBlockUi(int ms) {
    if (GetEnvironmentVariableW(L"VEYRA_TEST_UI_BLOCK", nullptr, 0) == 0) return;
    veyra::log::warn("game-mode", std::format("test: GUI thread blocked for {} ms", ms));
    Sleep(DWORD(std::clamp(ms, 0, 20000)));
}
// 游戏模式 state: click-through while the game-mode capture is live and the picture
// is fullscreen, the panel while the Home panel is open, otherwise a normal window.
void QmlPlayerBridge::updateGameMode() {
    using Mode = ui::GamePassthrough::Mode;
    auto& i = *impl_;
    const auto& s = i.snapshot;
    if (i.gameModeSessionId) {
        const bool same = s.sessionId == i.gameModeSessionId;
        if (same && s.running && !s.failed) i.gameModeLive = true;
        const bool ended = (same && (s.failed || s.transport == engine::TransportState::Stopping ||
            s.transport == engine::TransportState::Empty || (i.gameModeLive && !s.running))) || s.sessionId > i.gameModeSessionId;
        if (ended) {
            const bool shown = i.game.mode() != Mode::Off;
            veyra::log::info("game-mode", std::format("capture session {} ended failed={} pictureInFront={}", i.gameModeSessionId, s.failed, shown));
            i.gameModeSessionId = 0; i.gameModeLive = false;
            if (shown) {
                i.gameInputShown = i.passthroughShown = false;
                emit gameModeChanged();
                i.game.apply(Mode::Off);
                const QString why = s.failed ? uiText(s.status) : QString();
                emit gameModeStopped(why.isEmpty() ? tr("捕获已结束，已退出游戏模式") : why);
            }
        }
    }
    if (!i.presentation.fullscreen) i.gameRefused = false;
    Mode want = ui::gameInputMode(i.gameModeSessionId != 0, i.presentation.fullscreen,
                                  i.gameRefused, i.gamePanelOpen, gameScaledPreview());
    if (want!=Mode::Off && i.gameVideoRect.isEmpty()) updateGameGeometry();
    // A listener failure holds until fullscreen is left.
    if (want != Mode::Off && i.game.mode() == Mode::Off && !i.game.arm()) { i.gameRefused = true; want = Mode::Off; }
    if (want != i.game.mode()) {
        // QML binds the window's click-through flags to passthroughActive: publish
        // first, so Qt has changed the window before the foreground moves.
        const bool through = want == Mode::Through;
        const bool input = through || want == Mode::Scaled;
        if (through != i.passthroughShown || input != i.gameInputShown) {
            i.passthroughShown = through; i.gameInputShown = input; emit gameModeChanged();
        }
        if (want == Mode::Scaled && i.game.mode() != Mode::Panel)
            emit notice(tr("全屏缩放已启用：键盘和手柄控制源窗口，鼠标点击已拦截以免错位；需要鼠标穿透时切回贴合原窗口"), false);
        i.game.apply(want);
    }
    const bool mode = i.gameModeSessionId != 0;
    if ((!mode || !i.presentation.fullscreen) && !i.gameVideoRect.isEmpty()) {
        i.gameVideoRect={}; emit gameModeChanged();
    }
    if (mode != i.gameModeShown) { i.gameModeShown = mode; emit gameModeChanged(); }
}
QString QmlPlayerBridge::screenTargetId() const { return impl_->screenTarget; }
void QmlPlayerBridge::setScreenTargetId(const QString& value) {
    impl_->screenTarget = value;
    emit captureChanged();
}
QString QmlPlayerBridge::screenTargetLabel() const {
    const QString id = screenTargetId();
    if (id.isEmpty()) return tr("未选择目标");
    for (const auto& item : screenTargets()) {
        if (item.toMap().value(QStringLiteral("id")).toString() == id)
            return item.toMap().value(QStringLiteral("label")).toString();
    }
    return tr("目标已失效");
}
void QmlPlayerBridge::refreshCaptureTargets() {
    const int kind = screenOptions().value("kind").toInt();
    impl_->screenList = source::ScreenCaptureSource::targets(kind == 1 ? source::ScreenTargetKind::Monitor : source::ScreenTargetKind::Window);
    bool stillThere = false;
    for (const auto& t : impl_->screenList) stillThere = stillThere || QString::number(t.handle) == impl_->screenTarget;
    if (!stillThere) impl_->screenTarget = impl_->screenList.empty() ? QString() : QString::number(impl_->screenList.front().handle);
    emit captureChanged();
}


} // namespace veyra::ui
