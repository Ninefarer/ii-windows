#define NOMINMAX
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <shlobj.h>
#include <dwmapi.h>
#include <DispatcherQueue.h>
#include <winrt/base.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Numerics.h>
#include <winrt/Windows.System.h>
#include <winrt/Windows.UI.h>
#include <winrt/Windows.UI.Composition.h>
#include <winrt/Windows.UI.Composition.Desktop.h>
#include <windows.ui.composition.interop.h>
#include <cstdint>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <memory>
#include <sstream>
#include <string>
#include <vector>

namespace comp = winrt::Windows::UI::Composition;
namespace desktop = winrt::Windows::UI::Composition::Desktop;
using Interop = ABI::Windows::UI::Composition::Desktop::ICompositorDesktopInterop;
using TargetAbi = ABI::Windows::UI::Composition::Desktop::IDesktopWindowTarget;
constexpr wchar_t CARD_CLASS[] = L"IIDesktopCompositionProbeCard";
constexpr wchar_t CONTROL_CLASS[] = L"IIDesktopCompositionProbeControl";
constexpr int CARD_WIDTH = 280, CARD_HEIGHT = 180, GAP = 24;
HWND controller = nullptr, reportView = nullptr;
std::wstring report;
std::filesystem::path reportPath;
bool selfTest = false;

std::wstring hexValue(std::uintptr_t value) {
    std::wostringstream out;
    out << L"0x" << std::hex << value;
    return out.str();
}
void log(const std::wstring& line) {
    report += line + L"\r\n";
    // UTF-8 output, including a Unicode user profile path.
    const auto utf8 = winrt::to_string(report);
    std::ofstream stream(reportPath, std::ios::binary | std::ios::trunc);
    stream.write(utf8.data(), static_cast<std::streamsize>(utf8.size()));
    if (reportView != nullptr) {
        SetWindowTextW(reportView, report.c_str());
        SendMessageW(reportView, EM_SETSEL, static_cast<WPARAM>(-1), -1);
        SendMessageW(reportView, EM_SCROLLCARET, 0, 0);
    }
}
void logHr(const std::wstring& stage, HRESULT hr) {
    log(stage + L": " + hexValue(static_cast<std::uint32_t>(hr)) + (SUCCEEDED(hr) ? L" accepted" : L" rejected"));
}
std::wstring className(HWND hwnd) {
    wchar_t name[128] {};
    GetClassNameW(hwnd, name, 128);
    return name;
}
DWORD processOf(HWND hwnd) {
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    return pid;
}
HWND findIconsHost() {
    auto progman = FindWindowW(L"Progman", nullptr);
    if (progman == nullptr) return nullptr;
    auto view = FindWindowExW(progman, nullptr, L"SHELLDLL_DefView", nullptr);
    if (view != nullptr && IsWindowVisible(view)) return progman;
    struct Search { DWORD pid; HWND found; } search {processOf(progman), nullptr};
    EnumWindows([](HWND hwnd, LPARAM param) -> BOOL {
        auto& state = *reinterpret_cast<Search*>(param);
        if (className(hwnd) != L"WorkerW" || processOf(hwnd) != state.pid) return TRUE;
        auto child = FindWindowExW(hwnd, nullptr, L"SHELLDLL_DefView", nullptr);
        if (child == nullptr || !IsWindowVisible(child)) return TRUE;
        state.found = hwnd;
        return FALSE;
    }, reinterpret_cast<LPARAM>(&search));
    return search.found;
}
void logWallpaperWindows() {
    auto progman = FindWindowW(L"Progman", nullptr);
    if (progman == nullptr) return;
    EnumChildWindows(progman, [](HWND hwnd, LPARAM) -> BOOL {
        const auto name = className(hwnd);
        if (name.find(L"WPE") == std::wstring::npos) return TRUE;
        RECT r {};
        GetWindowRect(hwnd, &r);
        log(L"Wallpaper renderer " + name + L" hwnd=" + hexValue(reinterpret_cast<std::uintptr_t>(hwnd))
            + L" parent=" + hexValue(reinterpret_cast<std::uintptr_t>(GetParent(hwnd)))
            + L" pid=" + std::to_wstring(processOf(hwnd)) + L" visible=" + std::to_wstring(IsWindowVisible(hwnd))
            + L" size=" + std::to_wstring(r.right - r.left) + L"x" + std::to_wstring(r.bottom - r.top));
        return TRUE;
    }, 0);
}

struct Card {
    HWND hwnd = nullptr;
    desktop::DesktopWindowTarget target {nullptr};
    comp::ContainerVisual root {nullptr};
    std::wstring name;
    ~Card() { close(); }
    void close() {
        try {
            if (target != nullptr) { target.Root(nullptr); target.Close(); }
        } catch (const winrt::hresult_error&) {}
        root = nullptr;
        target = nullptr;
        if (hwnd != nullptr) DestroyWindow(hwnd);
    }
};
std::vector<std::unique_ptr<Card>> cards;
HWND currentHost = nullptr;
comp::Compositor compositor {nullptr};
winrt::com_ptr<ABI::Windows::System::IDispatcherQueueController> queue;

LRESULT CALLBACK cardProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    auto card = reinterpret_cast<Card*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        card = static_cast<Card*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
        card->hwnd = hwnd;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(card));
    }
    if (message == WM_NCDESTROY && card != nullptr) {
        card->hwnd = nullptr;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, 0);
    }
    if (message == WM_NCHITTEST) return HTTRANSPARENT;
    if (message == WM_ERASEBKGND) return 1;
    return DefWindowProcW(hwnd, message, wp, lp);
}

// This fallback is already used by ii's Windows backend. It is undocumented;
// acceptance and visible behavior are reported separately, never assumed.
struct AccentPolicy { DWORD state, flags, color, animation; };
struct CompositionData { DWORD attribute; void* data; SIZE_T size; };
using SetAttribute = BOOL(WINAPI*)(HWND, CompositionData*);
bool configureAccent(Card& card) {
#pragma warning(suppress: 4191)
    auto fn = reinterpret_cast<SetAttribute>(GetProcAddress(GetModuleHandleW(L"user32.dll"), "SetWindowCompositionAttribute"));
    if (fn == nullptr) { log(card.name + L": accent API unavailable"); return false; }
    AccentPolicy policy {3, 2, 0x35202020u, 0};
    CompositionData data {19, &policy, sizeof(policy)};
    SetLastError(0);
    const bool ok = fn(card.hwnd, &data) != FALSE;
    log(card.name + L": accent " + (ok ? std::wstring(L"accepted") : std::wstring(L"rejected"))
        + L", Win32 error=" + std::to_wstring(GetLastError()));
    return ok;
}
bool configureHostBackdrop(Card& card) {
    BOOL enabled = TRUE;
    // Failure is recorded, then target/brush creation is tested independently.
    logHr(card.name + L": DWMWA_USE_HOSTBACKDROPBRUSH",
        DwmSetWindowAttribute(card.hwnd, DWMWA_USE_HOSTBACKDROPBRUSH, &enabled, sizeof(enabled)));
    try {
        auto interop = compositor.as<Interop>();
        const HRESULT hr = interop->CreateDesktopWindowTarget(card.hwnd, TRUE,
            reinterpret_cast<TargetAbi**>(winrt::put_abi(card.target)));
        logHr(card.name + L": CreateDesktopWindowTarget", hr);
        winrt::check_hresult(hr);
        card.root = compositor.CreateContainerVisual();
        card.root.RelativeSizeAdjustment({1.0f, 1.0f});
        auto sprite = compositor.CreateSpriteVisual();
        sprite.RelativeSizeAdjustment({1.0f, 1.0f});
        sprite.Brush(compositor.CreateHostBackdropBrush());
        card.root.Children().InsertAtTop(sprite);
        auto tint = compositor.CreateSpriteVisual();
        tint.RelativeSizeAdjustment({1.0f, 1.0f});
        tint.Brush(compositor.CreateColorBrush(winrt::Windows::UI::Color {35, 24, 24, 32}));
        card.root.Children().InsertAtTop(tint);
        card.target.Root(card.root);
        log(card.name + L": host backdrop brush configured (visual result still requires observation)");
        return true;
    } catch (const winrt::hresult_error& error) {
        logHr(card.name + L": composition exception", error.code());
        return false;
    }
}
bool createCard(const wchar_t* name, HWND parent, int x, int y, bool accent, bool bottom = false) {
    auto card = std::make_unique<Card>();
    card->name = name;
    const DWORD style = parent != nullptr ? WS_CHILD : WS_POPUP;
    const DWORD ex = WS_EX_NOACTIVATE | WS_EX_TRANSPARENT | WS_EX_NOREDIRECTIONBITMAP
        | (parent == nullptr ? WS_EX_TOOLWINDOW : 0);
    auto hwnd = CreateWindowExW(ex, CARD_CLASS, name, style, x, y, CARD_WIDTH, CARD_HEIGHT,
        parent, nullptr, GetModuleHandleW(nullptr), card.get());
    if (hwnd == nullptr) { log(card->name + L": window creation failed " + std::to_wstring(GetLastError())); return false; }
    const auto region = CreateRoundRectRgn(0, 0, CARD_WIDTH + 1, CARD_HEIGHT + 1, 24, 24);
    if (SetWindowRgn(hwnd, region, FALSE) == 0 && region != nullptr) DeleteObject(region);
    log(card->name + L": hwnd=" + hexValue(reinterpret_cast<std::uintptr_t>(hwnd))
        + L" parent=" + hexValue(reinterpret_cast<std::uintptr_t>(GetParent(hwnd)))
        + L" DPI=" + std::to_wstring(GetDpiForWindow(hwnd)));
    if (accent) configureAccent(*card); else configureHostBackdrop(*card);
    SetWindowPos(hwnd, bottom ? HWND_BOTTOM : HWND_TOP, x, y, CARD_WIDTH, CARD_HEIGHT, SWP_NOACTIVATE | SWP_SHOWWINDOW);
    if (bottom) {
        log(card->name + L": bottom ordering requested; above=" + className(GetWindow(hwnd, GW_HWNDPREV))
            + L", below=" + className(GetWindow(hwnd, GW_HWNDNEXT)));
    }
    cards.push_back(std::move(card));
    return true;
}
void runCards(HWND host, const RECT& screen) {
    cards.clear();
    currentHost = host;
    log(L"--- Starting probes; API acceptance is NOT proof of live wallpaper blur ---");
    log(L"Desktop host=" + hexValue(reinterpret_cast<std::uintptr_t>(host)) + L" class=" + className(host));
    if (host == nullptr) { log(L"No supported Explorer icon host found. No desktop windows were created."); return; }
    const int left = screen.left + ((screen.right - screen.left) - (4 * CARD_WIDTH + 3 * GAP)) / 2;
    const int top = screen.bottom - CARD_HEIGHT - 85;
    POINT position {left, top};
    MapWindowPoints(HWND_DESKTOP, host, &position, 1);
    createCard(L"A: Explorer child / host backdrop", host, position.x, position.y, false);
    createCard(L"B: Explorer child / accent blur", host, position.x + CARD_WIDTH + GAP, position.y, true);
    createCard(L"C: top-level / host backdrop control", nullptr, left + 2 * (CARD_WIDTH + GAP), top, false);
    createCard(L"D: top-level / bottom ordered", nullptr, left + 3 * (CARD_WIDTH + GAP), top, false, true);
    log(L"Four rectangles near the bottom of the primary screen: A, B, C, D from left to right.");
    log(L"For D, also test an ordinary app over it and Win+D; no always-on-top flag is used.");
    log(L"Report whether each shows the MOVING wallpaper, static wallpaper, black, clear, or nothing.");
    log(L"No capture, wallpaper writes, duplicate renderer, Explorer restart, or foreign-window reparenting was used.");
}
void copyReport() {
    if (!OpenClipboard(controller)) return;
    const SIZE_T bytes = (report.size() + 1) * sizeof(wchar_t);
    auto memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (memory != nullptr) {
        auto ptr = GlobalLock(memory);
        if (ptr != nullptr) {
            memcpy(ptr, report.c_str(), bytes);
            GlobalUnlock(memory);
            EmptyClipboard();
            if (SetClipboardData(CF_UNICODETEXT, memory) != nullptr) memory = nullptr;
        }
        if (memory != nullptr) GlobalFree(memory);
    }
    CloseClipboard();
}
RECT primaryScreen() {
    MONITORINFO info {};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(MonitorFromPoint({0, 0}, MONITOR_DEFAULTTOPRIMARY), &info);
    return info.rcMonitor;
}
LRESULT CALLBACK controlProc(HWND hwnd, UINT message, WPARAM wp, LPARAM lp) {
    switch (message) {
    case WM_CREATE:
        controller = hwnd;
        CreateWindowW(L"STATIC", L"Wallpaper Engine desktop blur test (not an installer)\nA/B = child tests | C = top-level control | D = bottom-ordered top-level\nKeep Wallpaper Engine moving; observe the four rectangles near the bottom.\nClose this window to remove every probe rectangle.",
            WS_CHILD | WS_VISIBLE, 12, 10, 740, 76, hwnd, nullptr, nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Copy report", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            12, 92, 120, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(1)), nullptr, nullptr);
        CreateWindowW(L"BUTTON", L"Re-run probes", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
            144, 92, 120, 30, hwnd, reinterpret_cast<HMENU>(static_cast<INT_PTR>(2)), nullptr, nullptr);
        reportView = CreateWindowExW(WS_EX_CLIENTEDGE, L"EDIT", report.c_str(), WS_CHILD | WS_VISIBLE | WS_VSCROLL
            | ES_MULTILINE | ES_AUTOVSCROLL | ES_READONLY, 12, 134, 740, 260, hwnd, nullptr, nullptr, nullptr);
        SendMessageW(reportView, WM_SETFONT, reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
        SetTimer(hwnd, 1, 1000, nullptr);
        return 0;
    case WM_COMMAND:
        if (LOWORD(wp) == 1) copyReport();
        if (LOWORD(wp) == 2) { logWallpaperWindows(); runCards(findIconsHost(), primaryScreen()); }
        return 0;
    case WM_TIMER:
        if (currentHost != nullptr && !IsWindow(currentHost)) {
            cards.clear(); currentHost = nullptr;
            log(L"Desktop host disappeared. Probes removed. Re-run after Explorer is ready.");
        }
        return 0;
    case WM_DESTROY:
        KillTimer(hwnd, 1);
        cards.clear();
        reportView = nullptr;
        PostQuitMessage(0);
        return 0;
    default: return DefWindowProcW(hwnd, message, wp, lp);
    }
}
int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    int count = 0;
    auto arguments = CommandLineToArgvW(GetCommandLineW(), &count);
    for (int i = 1; i < count; ++i) {
        if (std::wstring(arguments[i]) == L"--self-test") selfTest = true;
        if (std::wstring(arguments[i]) == L"--log" && i + 1 < count) reportPath = arguments[++i];
    }
    LocalFree(arguments);
    if (reportPath.empty()) {
        PWSTR local = nullptr;
        if (FAILED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &local))) return 1;
        reportPath = std::filesystem::path(local) / L"ii-windows" / L"diagnostics" / L"desktop-composition-probe.txt";
        CoTaskMemFree(local);
    }
    std::error_code error;
    if (!reportPath.parent_path().empty()) std::filesystem::create_directories(reportPath.parent_path(), error);
    if (error) return 1;
    SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
    try {
        winrt::init_apartment(winrt::apartment_type::single_threaded);
        DispatcherQueueOptions options {sizeof(DispatcherQueueOptions), DQTYPE_THREAD_CURRENT, DQTAT_COM_STA};
        winrt::check_hresult(CreateDispatcherQueueController(options, queue.put()));
        compositor = comp::Compositor();
        log(L"ii desktop composition probe v1; compilation/lifecycle tests do not establish live Wallpaper Engine support.");
        log(L"Report path: " + reportPath.wstring());
        using RtlVersion = LONG(WINAPI*)(OSVERSIONINFOW*);
#pragma warning(suppress: 4191)
        auto versionFn = reinterpret_cast<RtlVersion>(GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "RtlGetVersion"));
        OSVERSIONINFOW version {};
        version.dwOSVersionInfoSize = sizeof(version);
        if (versionFn != nullptr && versionFn(&version) == 0) {
            log(L"Windows " + std::to_wstring(version.dwMajorVersion) + L"." + std::to_wstring(version.dwMinorVersion)
                + L" build " + std::to_wstring(version.dwBuildNumber));
        }
        BOOL enabled = FALSE;
        logHr(L"DwmIsCompositionEnabled", DwmIsCompositionEnabled(&enabled));
        log(L"DWM enabled=" + std::to_wstring(enabled));
        WNDCLASSW cardClass {};
        cardClass.lpfnWndProc = cardProc; cardClass.hInstance = instance; cardClass.lpszClassName = CARD_CLASS;
        winrt::check_bool(RegisterClassW(&cardClass));
        WNDCLASSW controlClass {};
        controlClass.lpfnWndProc = controlProc; controlClass.hInstance = instance;
        controlClass.lpszClassName = CONTROL_CLASS;
        controlClass.hbrBackground = reinterpret_cast<HBRUSH>(static_cast<INT_PTR>(COLOR_WINDOW + 1));
        controlClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        winrt::check_bool(RegisterClassW(&controlClass));
        if (selfTest) {
            // Own host only: CI must never attach to Explorer or require WPE.
            auto host = CreateWindowW(CONTROL_CLASS, L"probe self-test", WS_OVERLAPPEDWINDOW,
                0, 0, 1000, 800, nullptr, nullptr, instance, nullptr);
            winrt::check_bool(host != nullptr);
            RECT screen {0, 0, 1400, 800};
            runCards(host, screen);
            if (cards.size() != 4) winrt::throw_hresult(E_FAIL);
            std::vector<HWND> handles;
            for (const auto& card : cards) {
                winrt::check_bool(card->hwnd != nullptr);
                handles.push_back(card->hwnd);
            }
            cards.clear();
            for (auto hwnd : handles) winrt::check_bool(!IsWindow(hwnd));
            DestroyWindow(host);
            log(L"SELFTEST PASS: four own windows created and destroyed; no foreign desktop windows modified.");
        } else {
            auto window = CreateWindowW(CONTROL_CLASS, L"ii / Wallpaper Engine desktop composition probe",
                WS_OVERLAPPEDWINDOW & ~WS_MAXIMIZEBOX & ~WS_THICKFRAME, 60, 60, 790, 450,
                nullptr, nullptr, instance, nullptr);
            winrt::check_bool(window != nullptr);
            ShowWindow(window, SW_SHOW);
            logWallpaperWindows();
            runCards(findIconsHost(), primaryScreen());
            MSG message {};
            while (GetMessageW(&message, nullptr, 0, 0) > 0) {
                TranslateMessage(&message); DispatchMessageW(&message);
            }
        }
        cards.clear(); compositor = nullptr; queue = nullptr;
        return 0;
    } catch (const winrt::hresult_error& exception) {
        logHr(L"Probe stopped", exception.code());
        cards.clear(); compositor = nullptr; queue = nullptr;
        if (!selfTest) MessageBoxW(nullptr, report.c_str(), L"Desktop composition probe could not start", MB_OK | MB_ICONERROR);
        return 1;
    }
}
