// CivCityFix - d3d9.dll proxy for CivCity: Rome (2006)
//
// Sits between the game and DXVK (renamed to dxvk_d3d9.dll):
//  * forwards everything to DXVK, which avoids the startup crash on modern drivers
//  * turns the game's exclusive fullscreen request into a centered borderless window
//    on a black backdrop, so a 4:3 resolution fills the screen height without stretching
//  * offers extra resolutions the monitor does not list itself ("auto" = 4:3 at the
//    monitor's full height, e.g. 1920x1440 on a 1440p screen)
//
// Settings: CivCityFix.ini next to the game exe. Log: CivCityFix.log.

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d9.h>
#include <stdio.h>
#include <stdarg.h>
#include <vector>
#include "version.h"

// Also lets the installer recognise its own d3d9.dll.
static const char kVersion[] = "CivCityFix " CCF_VERSION_STR;

#pragma comment(linker, "/EXPORT:Direct3DCreate9=_Proxy_Direct3DCreate9@4")
#pragma comment(linker, "/EXPORT:Direct3DCreate9Ex=_Proxy_Direct3DCreate9Ex@8")
#pragma comment(linker, "/EXPORT:D3DPERF_BeginEvent=dxvk_d3d9.D3DPERF_BeginEvent")
#pragma comment(linker, "/EXPORT:D3DPERF_EndEvent=dxvk_d3d9.D3DPERF_EndEvent")
#pragma comment(linker, "/EXPORT:D3DPERF_GetStatus=dxvk_d3d9.D3DPERF_GetStatus")
#pragma comment(linker, "/EXPORT:D3DPERF_QueryRepeatFrame=dxvk_d3d9.D3DPERF_QueryRepeatFrame")
#pragma comment(linker, "/EXPORT:D3DPERF_SetMarker=dxvk_d3d9.D3DPERF_SetMarker")
#pragma comment(linker, "/EXPORT:D3DPERF_SetOptions=dxvk_d3d9.D3DPERF_SetOptions")
#pragma comment(linker, "/EXPORT:D3DPERF_SetRegion=dxvk_d3d9.D3DPERF_SetRegion")
#pragma comment(linker, "/EXPORT:DebugSetLevel=dxvk_d3d9.DebugSetLevel")
#pragma comment(linker, "/EXPORT:DebugSetMute=dxvk_d3d9.DebugSetMute")
#pragma comment(linker, "/EXPORT:Direct3D9EnableMaximizedWindowedModeShim=dxvk_d3d9.Direct3D9EnableMaximizedWindowedModeShim")
#pragma comment(linker, "/EXPORT:Direct3DShaderValidatorCreate9=dxvk_d3d9.Direct3DShaderValidatorCreate9")
#pragma comment(linker, "/EXPORT:PSGPError=dxvk_d3d9.PSGPError")
#pragma comment(linker, "/EXPORT:PSGPSampleTexture=dxvk_d3d9.PSGPSampleTexture")

// ---------------------------------------------------------------------------
// Globals, logging, config

static HMODULE g_self;
static HMODULE g_real;
static wchar_t g_dir[MAX_PATH];          // folder of this dll, with trailing backslash
static CRITICAL_SECTION g_lock;

struct ExtraMode { UINT w, h; };
static std::vector<ExtraMode> g_extraModes;
static bool g_borderless = true;

static HWND g_gameWnd;
static HWND g_backdrop;
static HWINEVENTHOOK g_minHook;

static void Log(const char* fmt, ...)
{
    wchar_t path[MAX_PATH];
    swprintf(path, MAX_PATH, L"%sCivCityFix.log", g_dir);
    FILE* f = _wfopen(path, L"a");
    if (!f)
        return;
    SYSTEMTIME t;
    GetLocalTime(&t);
    fprintf(f, "%02d:%02d:%02d.%03d  ", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds);
    va_list ap;
    va_start(ap, fmt);
    vfprintf(f, fmt, ap);
    va_end(ap);
    fputc('\n', f);
    fclose(f);
}

// 4:3 mode that fills the primary monitor's height (or its width on narrow screens).
// install.ps1 computes the same mode, so keep the two in sync.
static ExtraMode AutoMode()
{
    UINT mw = 1920, mh = 1080;
    DEVMODEW dm = {};
    dm.dmSize = sizeof(dm);
    if (EnumDisplaySettingsW(nullptr, ENUM_CURRENT_SETTINGS, &dm))
    {
        mw = dm.dmPelsWidth;
        mh = dm.dmPelsHeight;
    }
    UINT h = mh;
    UINT w = (h * 4 / 3) & ~7u;
    if (w > mw)
    {
        w = mw & ~7u;
        h = (w * 3 / 4) & ~7u;
    }
    return { w, h };
}

static void LoadConfig()
{
    wchar_t ini[MAX_PATH];
    swprintf(ini, MAX_PATH, L"%sCivCityFix.ini", g_dir);

    g_borderless = GetPrivateProfileIntW(L"Display", L"Borderless", 1, ini) != 0;

    wchar_t buf[512];
    GetPrivateProfileStringW(L"Display", L"ExtraModes", L"auto,1600x1200", buf, 512, ini);
    g_extraModes.clear();
    wchar_t* ctx = nullptr;
    for (wchar_t* tok = wcstok(buf, L", ;", &ctx); tok; tok = wcstok(nullptr, L", ;", &ctx))
    {
        UINT w = 0, h = 0;
        if (_wcsicmp(tok, L"auto") == 0)
        {
            ExtraMode m = AutoMode();
            g_extraModes.push_back(m);
            Log("auto mode: %ux%u", m.w, m.h);
        }
        else if (swscanf(tok, L"%ux%u", &w, &h) == 2 && w >= 640 && h >= 480)
        {
            g_extraModes.push_back({ w, h });
        }
    }

    Log("%s  config: Borderless=%d ExtraModes=%u", kVersion, g_borderless ? 1 : 0, (unsigned)g_extraModes.size());
}

// Window placement and monitor sizes must be in physical pixels, also with Windows
// display scaling above 100%. DXVK does the same; whichever runs first wins.
static void MakeDpiAware()
{
    typedef BOOL(WINAPI * SetDpiCtx_t)(HANDLE);
    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    SetDpiCtx_t setCtx = user32 ? (SetDpiCtx_t)GetProcAddress(user32, "SetProcessDpiAwarenessContext") : nullptr;
    if (!setCtx || !setCtx((HANDLE)-4)) // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2
        SetProcessDPIAware();
}

static bool LoadReal()
{
    if (g_real)
        return true;
    wchar_t path[MAX_PATH];
    swprintf(path, MAX_PATH, L"%sdxvk_d3d9.dll", g_dir);
    g_real = LoadLibraryW(path);
    if (g_real)
    {
        Log("loaded DXVK: dxvk_d3d9.dll");
        return true;
    }
    // No DXVK next to us: fall back to the system runtime so the game still starts.
    wchar_t sys[MAX_PATH];
    GetSystemDirectoryW(sys, MAX_PATH);
    swprintf(path, MAX_PATH, L"%s\\d3d9.dll", sys);
    g_real = LoadLibraryW(path);
    Log("dxvk_d3d9.dll missing (err %lu), fell back to system d3d9: %s", GetLastError(), g_real ? "ok" : "FAILED");
    return g_real != nullptr;
}

// ---------------------------------------------------------------------------
// Backdrop and window placement

static LRESULT CALLBACK BackdropProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg)
    {
    case WM_MOUSEACTIVATE:
        if (g_gameWnd)
            SetForegroundWindow(g_gameWnd);
        return MA_NOACTIVATE;
    case WM_ERASEBKGND:
    {
        RECT r;
        GetClientRect(hwnd, &r);
        FillRect((HDC)wp, &r, (HBRUSH)GetStockObject(BLACK_BRUSH));
        return 1;
    }
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static void CALLBACK MinimizeEvent(HWINEVENTHOOK, DWORD event, HWND hwnd, LONG idObject, LONG, DWORD, DWORD)
{
    if (hwnd != g_gameWnd || idObject != OBJID_WINDOW || !g_backdrop)
        return;
    ShowWindow(g_backdrop, event == EVENT_SYSTEM_MINIMIZESTART ? SW_HIDE : SW_SHOWNOACTIVATE);
}

static void EnsureBackdrop(HWND game, const RECT& mon)
{
    if (!g_backdrop)
    {
        WNDCLASSW wc = {};
        wc.lpfnWndProc = BackdropProc;
        wc.hInstance = g_self;
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = (HBRUSH)GetStockObject(BLACK_BRUSH);
        wc.lpszClassName = L"CivCityFixBackdrop";
        RegisterClassW(&wc);

        g_backdrop = CreateWindowExW(WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, wc.lpszClassName, L"",
                                     WS_POPUP, mon.left, mon.top, mon.right - mon.left, mon.bottom - mon.top,
                                     nullptr, nullptr, g_self, nullptr);
        Log("backdrop created: %p", (void*)g_backdrop);
    }
    else
    {
        SetWindowPos(g_backdrop, nullptr, mon.left, mon.top, mon.right - mon.left, mon.bottom - mon.top,
                     SWP_NOZORDER | SWP_NOACTIVATE);
    }

    // An owned window always stays above its owner, so making the backdrop the game
    // window's owner keeps the black bars directly behind the game in every z-order change.
    if ((HWND)GetWindowLongPtrW(game, GWLP_HWNDPARENT) != g_backdrop)
        SetWindowLongPtrW(game, GWLP_HWNDPARENT, (LONG_PTR)g_backdrop);

    ShowWindow(g_backdrop, SW_SHOWNOACTIVATE);

    if (!g_minHook)
    {
        DWORD pid = GetCurrentProcessId();
        g_minHook = SetWinEventHook(EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND, nullptr,
                                    MinimizeEvent, pid, 0, WINEVENT_OUTOFCONTEXT);
    }
}

static void PlaceWindow(HWND hwnd, UINT w, UINT h)
{
    if (!hwnd)
        return;
    g_gameWnd = hwnd;

    MONITORINFO mi = { sizeof(mi) };
    GetMonitorInfoW(MonitorFromWindow(hwnd, MONITOR_DEFAULTTOPRIMARY), &mi);
    const RECT mon = mi.rcMonitor;
    const int mw = mon.right - mon.left;
    const int mh = mon.bottom - mon.top;
    int x = mon.left + ((int)mw - (int)w) / 2;
    int y = mon.top + ((int)mh - (int)h) / 2;
    if (x < mon.left) x = mon.left;
    if (y < mon.top) y = mon.top;

    LONG style = GetWindowLongW(hwnd, GWL_STYLE);
    style &= ~(WS_CAPTION | WS_THICKFRAME | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_BORDER | WS_DLGFRAME);
    style |= WS_POPUP | WS_VISIBLE;
    SetWindowLongW(hwnd, GWL_STYLE, style);

    LONG ex = GetWindowLongW(hwnd, GWL_EXSTYLE);
    ex &= ~(WS_EX_TOPMOST | WS_EX_WINDOWEDGE | WS_EX_CLIENTEDGE | WS_EX_DLGMODALFRAME | WS_EX_STATICEDGE);
    ex |= WS_EX_APPWINDOW;
    SetWindowLongW(hwnd, GWL_EXSTYLE, ex);

    EnsureBackdrop(hwnd, mon);

    SetWindowPos(hwnd, HWND_NOTOPMOST, x, y, (int)w, (int)h, SWP_FRAMECHANGED | SWP_SHOWWINDOW);
    SetWindowPos(hwnd, HWND_TOP, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW);
    SetForegroundWindow(hwnd);

    Log("window %p placed at %d,%d size %ux%u on monitor %dx%d", (void*)hwnd, x, y, w, h, mw, mh);
}

// ---------------------------------------------------------------------------
// Vtable hooks on the DXVK objects

typedef UINT    (STDMETHODCALLTYPE* GetAdapterModeCount_t)(IDirect3D9*, UINT, D3DFORMAT);
typedef HRESULT (STDMETHODCALLTYPE* EnumAdapterModes_t)(IDirect3D9*, UINT, D3DFORMAT, UINT, D3DDISPLAYMODE*);
typedef HRESULT (STDMETHODCALLTYPE* CreateDevice_t)(IDirect3D9*, UINT, D3DDEVTYPE, HWND, DWORD, D3DPRESENT_PARAMETERS*, IDirect3DDevice9**);
typedef HRESULT (STDMETHODCALLTYPE* Reset_t)(IDirect3DDevice9*, D3DPRESENT_PARAMETERS*);

static GetAdapterModeCount_t o_GetAdapterModeCount;
static EnumAdapterModes_t    o_EnumAdapterModes;
static CreateDevice_t        o_CreateDevice;
static Reset_t               o_Reset;

enum { VT_D3D9_GetAdapterModeCount = 6, VT_D3D9_EnumAdapterModes = 7, VT_D3D9_CreateDevice = 16, VT_DEV_Reset = 16 };

static void* HookVtbl(void* obj, int index, void* hook)
{
    void** vt = *(void***)obj;
    void* orig = vt[index];
    if (orig == hook)
        return nullptr;
    DWORD old;
    VirtualProtect(&vt[index], sizeof(void*), PAGE_EXECUTE_READWRITE, &old);
    vt[index] = hook;
    VirtualProtect(&vt[index], sizeof(void*), old, &old);
    return orig;
}

// Extra modes the adapter does not list for this format.
static std::vector<D3DDISPLAYMODE> MissingModes(IDirect3D9* d3d, UINT adapter, D3DFORMAT fmt, UINT realCount)
{
    std::vector<D3DDISPLAYMODE> out;
    if (realCount == 0 || g_extraModes.empty())
        return out;

    UINT hz = 60;
    D3DDISPLAYMODE m;
    for (const ExtraMode& e : g_extraModes)
    {
        bool found = false;
        for (UINT i = 0; i < realCount && !found; ++i)
            if (SUCCEEDED(o_EnumAdapterModes(d3d, adapter, fmt, i, &m)) && m.Width == e.w && m.Height == e.h)
                found = true;
        if (!found)
            out.push_back({ e.w, e.h, hz, fmt });
    }
    return out;
}

static UINT STDMETHODCALLTYPE hk_GetAdapterModeCount(IDirect3D9* self, UINT adapter, D3DFORMAT fmt)
{
    UINT n = o_GetAdapterModeCount(self, adapter, fmt);
    return n + (UINT)MissingModes(self, adapter, fmt, n).size();
}

static HRESULT STDMETHODCALLTYPE hk_EnumAdapterModes(IDirect3D9* self, UINT adapter, D3DFORMAT fmt, UINT mode, D3DDISPLAYMODE* out)
{
    UINT n = o_GetAdapterModeCount(self, adapter, fmt);
    if (mode < n)
        return o_EnumAdapterModes(self, adapter, fmt, mode, out);
    std::vector<D3DDISPLAYMODE> extra = MissingModes(self, adapter, fmt, n);
    if (mode - n >= extra.size() || !out)
        return D3DERR_INVALIDCALL;
    *out = extra[mode - n];
    return D3D_OK;
}

// Rewrites a fullscreen request to windowed. Returns true if it did.
static bool MakeWindowed(D3DPRESENT_PARAMETERS& pp)
{
    if (!g_borderless || pp.Windowed)
        return false;
    pp.Windowed = TRUE;
    pp.FullScreen_RefreshRateInHz = 0;
    return true;
}

static HRESULT STDMETHODCALLTYPE hk_Reset(IDirect3DDevice9* self, D3DPRESENT_PARAMETERS* pp)
{
    if (!pp)
        return o_Reset(self, pp);
    D3DPRESENT_PARAMETERS mod = *pp;
    bool conv = MakeWindowed(mod);
    if (conv)
        PlaceWindow(mod.hDeviceWindow ? mod.hDeviceWindow : g_gameWnd, mod.BackBufferWidth, mod.BackBufferHeight);
    HRESULT hr = o_Reset(self, &mod);
    Log("Reset %ux%u windowed=%d (converted=%d) -> 0x%08lx", mod.BackBufferWidth, mod.BackBufferHeight, pp->Windowed, conv, hr);
    if (conv && SUCCEEDED(hr))
        PlaceWindow(mod.hDeviceWindow ? mod.hDeviceWindow : g_gameWnd, mod.BackBufferWidth, mod.BackBufferHeight);
    BOOL askedWindowed = pp->Windowed;
    UINT askedHz = pp->FullScreen_RefreshRateInHz;
    *pp = mod;
    pp->Windowed = askedWindowed;
    pp->FullScreen_RefreshRateInHz = askedHz;
    return hr;
}

static HRESULT STDMETHODCALLTYPE hk_CreateDevice(IDirect3D9* self, UINT adapter, D3DDEVTYPE type, HWND focus, DWORD flags,
                                                 D3DPRESENT_PARAMETERS* pp, IDirect3DDevice9** dev)
{
    if (!pp)
        return o_CreateDevice(self, adapter, type, focus, flags, pp, dev);

    D3DPRESENT_PARAMETERS mod = *pp;
    HWND wnd = mod.hDeviceWindow ? mod.hDeviceWindow : focus;
    bool conv = MakeWindowed(mod);
    if (conv)
        PlaceWindow(wnd, mod.BackBufferWidth, mod.BackBufferHeight);

    HRESULT hr = o_CreateDevice(self, adapter, type, focus, flags, &mod, dev);
    Log("CreateDevice %ux%u fmt=%d requested windowed=%d hz=%u (converted=%d) -> 0x%08lx",
        mod.BackBufferWidth, mod.BackBufferHeight, (int)mod.BackBufferFormat, pp->Windowed, pp->FullScreen_RefreshRateInHz, conv, hr);

    if (SUCCEEDED(hr) && dev && *dev)
    {
        EnterCriticalSection(&g_lock);
        void* orig = HookVtbl(*dev, VT_DEV_Reset, (void*)hk_Reset);
        if (orig && !o_Reset)
            o_Reset = (Reset_t)orig;
        LeaveCriticalSection(&g_lock);
        if (conv)
            PlaceWindow(wnd, mod.BackBufferWidth, mod.BackBufferHeight);
    }

    // Hand back what the runtime filled in, but keep the game's view of fullscreen.
    BOOL askedWindowed = pp->Windowed;
    UINT askedHz = pp->FullScreen_RefreshRateInHz;
    *pp = mod;
    pp->Windowed = askedWindowed;
    pp->FullScreen_RefreshRateInHz = askedHz;
    return hr;
}

static void HookInterface(IDirect3D9* d3d)
{
    if (!d3d)
        return;
    EnterCriticalSection(&g_lock);
    void* p;
    if ((p = HookVtbl(d3d, VT_D3D9_GetAdapterModeCount, (void*)hk_GetAdapterModeCount)) && !o_GetAdapterModeCount)
        o_GetAdapterModeCount = (GetAdapterModeCount_t)p;
    if ((p = HookVtbl(d3d, VT_D3D9_EnumAdapterModes, (void*)hk_EnumAdapterModes)) && !o_EnumAdapterModes)
        o_EnumAdapterModes = (EnumAdapterModes_t)p;
    if ((p = HookVtbl(d3d, VT_D3D9_CreateDevice, (void*)hk_CreateDevice)) && !o_CreateDevice)
        o_CreateDevice = (CreateDevice_t)p;
    LeaveCriticalSection(&g_lock);
}

// ---------------------------------------------------------------------------
// Exports

extern "C" IDirect3D9* WINAPI Proxy_Direct3DCreate9(UINT sdk)
{
    static bool configured = false;
    if (!configured)
    {
        configured = true;
        MakeDpiAware();
        LoadConfig();
    }
    if (!LoadReal())
        return nullptr;
    typedef IDirect3D9*(WINAPI * Create_t)(UINT);
    Create_t create = (Create_t)GetProcAddress(g_real, "Direct3DCreate9");
    IDirect3D9* d3d = create ? create(sdk) : nullptr;
    Log("Direct3DCreate9(%u) -> %p", sdk, (void*)d3d);
    HookInterface(d3d);
    return d3d;
}

extern "C" HRESULT WINAPI Proxy_Direct3DCreate9Ex(UINT sdk, IDirect3D9Ex** out)
{
    if (!LoadReal())
        return E_FAIL;
    typedef HRESULT(WINAPI * CreateEx_t)(UINT, IDirect3D9Ex**);
    CreateEx_t create = (CreateEx_t)GetProcAddress(g_real, "Direct3DCreate9Ex");
    if (!create)
        return E_FAIL;
    HRESULT hr = create(sdk, out);
    if (SUCCEEDED(hr) && out)
        HookInterface(*out);
    return hr;
}

BOOL WINAPI DllMain(HINSTANCE inst, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_self = inst;
        DisableThreadLibraryCalls(inst);
        InitializeCriticalSection(&g_lock);
        GetModuleFileNameW(inst, g_dir, MAX_PATH);
        wchar_t* slash = wcsrchr(g_dir, L'\\');
        if (slash)
            slash[1] = 0;
    }
    return TRUE;
}
