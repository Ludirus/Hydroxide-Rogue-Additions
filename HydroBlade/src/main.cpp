#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <commctrl.h>
#include <objidl.h>
#include <propidl.h>
#include <gdiplus.h>
#include <shellapi.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <winhttp.h>
#include <windowsx.h>
#include <bcrypt.h>

#include <algorithm>
#include <atomic>
#include <cctype>
#include <cstdio>
#include <cstdint>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <memory>
#include <mutex>
#include <optional>
#include <sstream>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace {

constexpr wchar_t kAppClassName[] = L"HydroBladeWindow";
constexpr wchar_t kAppTitle[] = L"HydroBlade";
constexpr long long kRogueLoaderPlaceId = 3016661674LL;
constexpr long long kRogueGaiaPlaceId = 5208655184LL;
constexpr UINT kRefreshUiMessage = WM_APP + 1;
constexpr UINT kStartSigilsMessage = WM_APP + 2;
constexpr UINT_PTR kActiveListSubclass = 41;
constexpr UINT_PTR kInactiveListSubclass = 42;
constexpr int kContextInsertRotAlt = 5001;
constexpr int kContextRemoveAccount = 5002;
constexpr int kContextToggleSigil = 5003;
constexpr int kSettingsBrowseFolder = 6101;

enum ControlId {
    IdAccountName = 1001,
    IdCookie,
    IdRole,
    IdUsername,
    IdUserId,
    IdJobId,
    IdAddAccount,
    IdAuthenticate,
    IdJoinGaia,
    IdStartSigils,
    IdAlias,
    IdSetAlias,
    IdSetActive,
    IdSetInactive,
    IdActiveList,
    IdInactiveList,
    IdStatus,
    IdStats,
    IdWsStatus,
    IdHint,
    IdDragBadge,
    IdSettings,
    IdClearCookie,
};

enum class Role {
    SigilAlt,
    RotAlt,
    SilverAlt,
    VerdienAccount,
};

struct Account {
    std::wstring id;
    std::wstring parentId;
    std::wstring label;
    std::wstring alias;
    std::wstring silver = L"unset";
    std::wstring cookie;
    Role role = Role::SigilAlt;
    std::wstring username;
    std::wstring userId;
    std::wstring gaiaJobId;
    bool active = false;
    bool authenticated = false;
};

struct HttpResponse {
    DWORD status = 0;
    std::wstring body;
    std::vector<std::pair<std::wstring, std::wstring>> headers;
};

struct AuthResult {
    bool ok = false;
    std::wstring username;
    std::wstring userId;
    std::wstring message;
};

struct LaunchResult {
    bool ok = false;
    std::wstring message;
};

struct TicketResult {
    bool ok = false;
    std::wstring ticket;
    std::wstring message;
};

HINSTANCE g_instance = nullptr;
HWND g_main = nullptr;
HWND g_name = nullptr;
HWND g_cookie = nullptr;
HWND g_role = nullptr;
HWND g_username = nullptr;
HWND g_userId = nullptr;
HWND g_jobId = nullptr;
HWND g_alias = nullptr;
HWND g_activeList = nullptr;
HWND g_inactiveList = nullptr;
HWND g_status = nullptr;
HWND g_stats = nullptr;
HWND g_wsStatus = nullptr;
HWND g_hint = nullptr;
HWND g_dragBadge = nullptr;
HFONT g_font = nullptr;
HFONT g_titleFont = nullptr;
HFONT g_smallFont = nullptr;
HBRUSH g_bgBrush = nullptr;
HBRUSH g_fieldBrush = nullptr;
HBRUSH g_panelBrush = nullptr;
ULONG_PTR g_gdiplusToken = 0;
std::unique_ptr<Gdiplus::Bitmap> g_logo;
HICON g_appIcon = nullptr;
std::vector<Account> g_accounts;
std::recursive_mutex g_accountsMutex;
std::atomic_uint64_t g_idCounter{1};
std::wstring g_autoExecuteFolder;
std::wstring g_failureWebhook;
bool g_failureWebhookEnabled = false;
bool g_sigilsRunning = false;
uint64_t g_sigilsRunId = 0;
std::unordered_set<std::wstring> g_collapsedSigils;
std::wstring g_statusLog;
std::optional<std::string> g_koroOriginalContent;
std::filesystem::path g_koroBackupPath;
std::unordered_set<std::wstring> g_generatedAutoExecuteFiles;

struct RuntimeAccount {
    std::wstring accountId;
    std::wstring parentId;
    std::wstring role;
    std::wstring username;
    std::wstring userId;
    std::wstring placeId;
    std::wstring jobId;
    std::wstring status;
    std::wstring statusDetail;
    uint64_t lastSeen = 0;
};

std::recursive_mutex g_runtimeMutex;
std::unordered_map<std::wstring, RuntimeAccount> g_runtimeAccounts;
std::unordered_set<std::wstring> g_failedGroups;
std::unordered_map<std::wstring, std::vector<Account>> g_pendingRotLaunches;
std::unordered_set<std::wstring> g_requestedRotGroups;

struct DragState {
    HWND source = nullptr;
    size_t index = static_cast<size_t>(-1);
    bool active = false;
};

DragState g_drag;

void SyncAutoExecuteFiles();
void RestoreAutoExecuteFiles();
std::wstring AccountShortName(const Account& account);
size_t RotChildCountFor(size_t index);
void SetStatus(const std::wstring& message);
void HideDragBadge();
void EnsureDragBadgeClass();

std::wstring Trim(std::wstring text) {
    auto isSpace = [](wchar_t c) { return c == L' ' || c == L'\t' || c == L'\r' || c == L'\n'; };
    while (!text.empty() && isSpace(text.front())) {
        text.erase(text.begin());
    }
    while (!text.empty() && isSpace(text.back())) {
        text.pop_back();
    }
    return text;
}

std::wstring ToLower(std::wstring text) {
    std::transform(text.begin(), text.end(), text.begin(), [](wchar_t c) {
        return static_cast<wchar_t>(std::towlower(c));
    });
    return text;
}

std::wstring NormalizeRobloxCookie(std::wstring cookie) {
    cookie = Trim(std::move(cookie));
    if (cookie.empty()) {
        return {};
    }

    const std::wstring lower = ToLower(cookie);
    const std::wstring dottedKey = L".roblosecurity=";
    const std::wstring plainKey = L"roblosecurity=";
    size_t start = std::wstring::npos;

    const size_t dotted = lower.find(dottedKey);
    if (dotted != std::wstring::npos) {
        start = dotted + dottedKey.size();
    } else {
        const size_t plain = lower.find(plainKey);
        if (plain != std::wstring::npos) {
            start = plain + plainKey.size();
        }
    }

    if (start != std::wstring::npos) {
        const size_t end = cookie.find_first_of(L";\r\n", start);
        cookie = cookie.substr(start, end == std::wstring::npos ? std::wstring::npos : end - start);
    } else {
        const size_t end = cookie.find_first_of(L";\r\n");
        if (end != std::wstring::npos) {
            cookie = cookie.substr(0, end);
        }
    }

    cookie = Trim(std::move(cookie));
    while (cookie.size() >= 2 &&
           ((cookie.front() == L'"' && cookie.back() == L'"') ||
            (cookie.front() == L'\'' && cookie.back() == L'\''))) {
        cookie = Trim(cookie.substr(1, cookie.size() - 2));
    }
    return cookie;
}

std::wstring GetWindowString(HWND hwnd) {
    const int length = GetWindowTextLengthW(hwnd);
    std::wstring value(static_cast<size_t>(length + 1), L'\0');
    if (length > 0) {
        GetWindowTextW(hwnd, value.data(), static_cast<int>(value.size()));
    }
    value.resize(static_cast<size_t>(length));
    return Trim(value);
}

void SetWindowString(HWND hwnd, const std::wstring& value) {
    SetWindowTextW(hwnd, value.c_str());
}

std::string Narrow(const std::wstring& value) {
    if (value.empty()) {
        return {};
    }
    const int size = WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        nullptr,
        0,
        nullptr,
        nullptr);
    std::string out(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(
        CP_UTF8,
        0,
        value.data(),
        static_cast<int>(value.size()),
        out.data(),
        size,
        nullptr,
        nullptr);
    return out;
}

std::wstring Widen(const std::string& value) {
    if (value.empty()) {
        return {};
    }
    const int size = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
    std::wstring out(static_cast<size_t>(size), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), out.data(), size);
    return out;
}

std::string EscapeJson(const std::wstring& value) {
    std::ostringstream out;
    for (const unsigned char ch : Narrow(value)) {
        switch (ch) {
            case '\\': out << "\\\\"; break;
            case '"': out << "\\\""; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (ch < 0x20) {
                    out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(ch);
                } else {
                    out << ch;
                }
                break;
        }
    }
    return out.str();
}

std::wstring RoleName(Role role) {
    switch (role) {
        case Role::SigilAlt: return L"Sigil Alt";
        case Role::RotAlt: return L"Sigil Alt / Rot Alt";
        case Role::SilverAlt: return L"Silver Bank";
        case Role::VerdienAccount: return L"Verdien Account";
    }
    return L"Sigil Alt";
}

std::string RoleKey(Role role) {
    switch (role) {
        case Role::SigilAlt: return "sigil_alt";
        case Role::RotAlt: return "rot_alt";
        case Role::SilverAlt: return "silver_alt";
        case Role::VerdienAccount: return "verdien_account";
    }
    return "sigil_alt";
}

Role RoleFromIndex(int index) {
    switch (index) {
        case 1: return Role::RotAlt;
        case 2: return Role::SilverAlt;
        case 3: return Role::VerdienAccount;
        default: return Role::SigilAlt;
    }
}

Role RoleFromKey(const std::string& key) {
    if (key == "rot_alt") return Role::RotAlt;
    if (key == "silver_alt") return Role::SilverAlt;
    if (key == "verdien_account") return Role::VerdienAccount;
    return Role::SigilAlt;
}

std::wstring ExeDirectory() {
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    PathRemoveFileSpecW(path);
    return path;
}

std::wstring StorePath() {
    return ExeDirectory() + L"\\hydroblade_accounts.json";
}

std::wstring SettingsPath() {
    return ExeDirectory() + L"\\hydroblade_settings.json";
}

std::wstring LogoPath() {
    const std::filesystem::path exeDir = ExeDirectory();
    const std::filesystem::path besideExe = exeDir / L"assets" / L"hydroblade-logo.png";
    if (std::filesystem::exists(besideExe)) {
        return besideExe.wstring();
    }
    const std::filesystem::path repoLayout = exeDir.parent_path() / L"assets" / L"hydroblade-logo.png";
    return repoLayout.wstring();
}

std::wstring GenerateAccountId() {
    const uint64_t tick = static_cast<uint64_t>(GetTickCount64());
    const uint64_t next = g_idCounter.fetch_add(1);
    std::wstringstream stream;
    stream << L"hb-" << std::hex << tick << L"-" << next;
    return stream.str();
}

size_t FindAccountIndexById(const std::wstring& id) {
    if (id.empty()) {
        return static_cast<size_t>(-1);
    }
    for (size_t i = 0; i < g_accounts.size(); ++i) {
        if (g_accounts[i].id == id) {
            return i;
        }
    }
    return static_cast<size_t>(-1);
}

std::wstring WorkflowForAccount(const Account& account) {
    if (!g_sigilsRunning || !account.active) {
        return {};
    }
    if (account.role == Role::SigilAlt) {
        return L"sigil_idle";
    }
    if (account.role == Role::RotAlt) {
        return L"rot_alchemy";
    }
    return {};
}

std::wstring WorkflowForAccountId(const std::wstring& id) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    const size_t index = FindAccountIndexById(id);
    if (index == static_cast<size_t>(-1)) {
        return {};
    }
    return WorkflowForAccount(g_accounts[index]);
}

bool IsGaiaPlaceId(const std::wstring& placeId) {
    return placeId == std::to_wstring(kRogueGaiaPlaceId);
}

std::wstring ParentJobForAccount(const std::wstring& accountId, const std::wstring& parentId) {
    {
        std::lock_guard<std::recursive_mutex> runtimeLock(g_runtimeMutex);
        if (!parentId.empty()) {
            const auto runtime = g_runtimeAccounts.find(parentId);
            if (runtime != g_runtimeAccounts.end() && IsGaiaPlaceId(runtime->second.placeId) && !runtime->second.jobId.empty()) {
                return runtime->second.jobId;
            }
            return {};
        }
    }

    std::lock_guard<std::recursive_mutex> accountLock(g_accountsMutex);
    const size_t index = FindAccountIndexById(parentId.empty() ? accountId : parentId);
    if (index != static_cast<size_t>(-1)) {
        return g_accounts[index].gaiaJobId;
    }
    return {};
}

std::wstring GroupIdForRuntime(const std::wstring& accountId, const std::wstring& parentId, const std::wstring& role) {
    if (role == L"rot_alt" && !parentId.empty()) {
        return parentId;
    }
    return accountId;
}

std::wstring ParentLabel(const Account& account) {
    const size_t parent = FindAccountIndexById(account.parentId);
    if (parent == static_cast<size_t>(-1)) {
        return {};
    }
    return g_accounts[parent].label.empty() ? g_accounts[parent].username : g_accounts[parent].label;
}

struct PromptState {
    std::wstring label;
    std::wstring value;
    std::wstring initialValue;
    bool password = false;
    bool accepted = false;
    bool done = false;
    HWND edit = nullptr;
};

void ClearCookieInput() {
    SetWindowString(g_cookie, L"");
    SetWindowString(g_username, L"");
    SetWindowString(g_userId, L"");
}

LRESULT CALLBACK PromptProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    PromptState* state = reinterpret_cast<PromptState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (message) {
        case WM_CREATE: {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
            state = reinterpret_cast<PromptState*>(create->lpCreateParams);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
            CreateWindowExW(0, L"STATIC", state->label.c_str(), WS_CHILD | WS_VISIBLE | SS_LEFT, 18, 16, 320, 22, hwnd, nullptr, g_instance, nullptr);
            DWORD editStyle = WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL;
            if (state->password) {
                editStyle |= ES_PASSWORD;
            }
            state->edit = CreateWindowExW(0, L"EDIT", state->initialValue.c_str(), editStyle, 18, 44, 340, 30, hwnd, reinterpret_cast<HMENU>(9001), g_instance, nullptr);
            CreateWindowExW(0, L"BUTTON", L"Insert", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON, 184, 88, 82, 30, hwnd, reinterpret_cast<HMENU>(IDOK), g_instance, nullptr);
            CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE, 276, 88, 82, 30, hwnd, reinterpret_cast<HMENU>(IDCANCEL), g_instance, nullptr);
            SendMessageW(state->edit, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
            SetFocus(state->edit);
            return 0;
        }
        case WM_COMMAND:
            if (LOWORD(wParam) == IDOK && HIWORD(wParam) == BN_CLICKED && state) {
                state->value = GetWindowString(state->edit);
                state->accepted = true;
                state->done = true;
                DestroyWindow(hwnd);
                return 0;
            }
            if (LOWORD(wParam) == IDCANCEL && HIWORD(wParam) == BN_CLICKED && state) {
                state->done = true;
                DestroyWindow(hwnd);
                return 0;
            }
            break;
        case WM_CLOSE:
            if (state) {
                state->done = true;
            }
            DestroyWindow(hwnd);
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

LRESULT CALLBACK DragBadgeProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_NCHITTEST:
            return HTTRANSPARENT;
        case WM_ERASEBKGND:
            return 1;
        case WM_PAINT: {
            PAINTSTRUCT ps = {};
            HDC hdc = BeginPaint(hwnd, &ps);
            RECT rect = {};
            GetClientRect(hwnd, &rect);

            HBRUSH fill = CreateSolidBrush(RGB(18, 19, 25));
            FillRect(hdc, &rect, fill);
            DeleteObject(fill);

            HBRUSH border = CreateSolidBrush(RGB(0, 194, 255));
            FrameRect(hdc, &rect, border);
            DeleteObject(border);

            RECT textRect = rect;
            textRect.left += 10;
            textRect.right -= 10;
            wchar_t text[256] = {};
            GetWindowTextW(hwnd, text, 256);
            SetBkMode(hdc, TRANSPARENT);
            SetTextColor(hdc, RGB(240, 242, 248));
            if (g_font) {
                SelectObject(hdc, g_font);
            }
            DrawTextW(hdc, text, -1, &textRect, DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
            EndPaint(hwnd, &ps);
            return 0;
        }
        default:
            break;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

void EnsureDragBadgeClass() {
    static bool registered = false;
    if (registered) {
        return;
    }
    WNDCLASSW wc = {};
    wc.lpfnWndProc = DragBadgeProc;
    wc.hInstance = g_instance;
    wc.lpszClassName = L"HydroBladeDragBadge";
    wc.hCursor = LoadCursor(nullptr, IDC_HAND);
    RegisterClassW(&wc);
    registered = true;
}

std::optional<std::wstring> PromptForText(const std::wstring& title, const std::wstring& label, bool password = false, const std::wstring& initialValue = L"", bool allowEmpty = false) {
    static bool registered = false;
    if (!registered) {
        WNDCLASSW wc = {};
        wc.lpfnWndProc = PromptProc;
        wc.hInstance = g_instance;
        wc.lpszClassName = L"HydroBladePrompt";
        wc.hCursor = LoadCursor(nullptr, IDC_IBEAM);
        wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        RegisterClassW(&wc);
        registered = true;
    }

    PromptState state;
    state.label = label;
    state.password = password;
    state.initialValue = initialValue;
    RECT parentRect = {};
    GetWindowRect(g_main, &parentRect);
    const int width = 390;
    const int height = 160;
    HWND dialog = CreateWindowExW(
        WS_EX_DLGMODALFRAME,
        L"HydroBladePrompt",
        title.c_str(),
        WS_CAPTION | WS_POPUP | WS_SYSMENU,
        parentRect.left + ((parentRect.right - parentRect.left) - width) / 2,
        parentRect.top + ((parentRect.bottom - parentRect.top) - height) / 2,
        width,
        height,
        g_main,
        nullptr,
        g_instance,
        &state);
    if (!dialog) {
        return std::nullopt;
    }

    EnableWindow(g_main, FALSE);
    ShowWindow(dialog, SW_SHOW);
    UpdateWindow(dialog);
    SetForegroundWindow(dialog);
    BringWindowToTop(dialog);

    MSG msg = {};
    while (!state.done && GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(dialog, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    EnableWindow(g_main, TRUE);
    SetForegroundWindow(g_main);
    if (state.accepted && (allowEmpty || !state.value.empty())) {
        return state.value;
    }
    return std::nullopt;
}

std::string ReadWholeFile(const std::wstring& path) {
    std::ifstream in(std::filesystem::path(path), std::ios::binary);
    if (!in) {
        return {};
    }
    std::ostringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

void SaveAccounts() {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    std::ofstream out(std::filesystem::path(StorePath()), std::ios::binary | std::ios::trunc);
    if (!out) {
        return;
    }

    out << "{\n  \"accounts\": [\n";
    for (size_t i = 0; i < g_accounts.size(); ++i) {
        const Account& account = g_accounts[i];
        out << "    {\n";
        out << "      \"id\": \"" << EscapeJson(account.id) << "\",\n";
        out << "      \"parentId\": \"" << EscapeJson(account.parentId) << "\",\n";
        out << "      \"label\": \"" << EscapeJson(account.label) << "\",\n";
        out << "      \"alias\": \"" << EscapeJson(account.alias) << "\",\n";
        out << "      \"silver\": \"" << EscapeJson(account.silver.empty() ? L"unset" : account.silver) << "\",\n";
        out << "      \"cookie\": \"" << EscapeJson(account.cookie) << "\",\n";
        out << "      \"role\": \"" << RoleKey(account.role) << "\",\n";
        out << "      \"username\": \"" << EscapeJson(account.username) << "\",\n";
        out << "      \"userId\": \"" << EscapeJson(account.userId) << "\",\n";
        out << "      \"gaiaJobId\": \"" << EscapeJson(account.gaiaJobId) << "\",\n";
        out << "      \"active\": " << (account.active ? "true" : "false") << ",\n";
        out << "      \"authenticated\": " << (account.authenticated ? "true" : "false") << "\n";
        out << "    }" << (i + 1 == g_accounts.size() ? "\n" : ",\n");
    }
    out << "  ]\n}\n";
    SyncAutoExecuteFiles();
}

std::optional<std::string> ExtractJsonString(const std::string& object, const std::string& key) {
    const std::string token = "\"" + key + "\"";
    size_t pos = object.find(token);
    if (pos == std::string::npos) {
        return std::nullopt;
    }
    pos = object.find(':', pos + token.size());
    if (pos == std::string::npos) {
        return std::nullopt;
    }
    pos = object.find('"', pos + 1);
    if (pos == std::string::npos) {
        return std::nullopt;
    }
    std::string out;
    bool escaped = false;
    for (++pos; pos < object.size(); ++pos) {
        const char ch = object[pos];
        if (escaped) {
            switch (ch) {
                case 'n': out.push_back('\n'); break;
                case 'r': out.push_back('\r'); break;
                case 't': out.push_back('\t'); break;
                default: out.push_back(ch); break;
            }
            escaped = false;
        } else if (ch == '\\') {
            escaped = true;
        } else if (ch == '"') {
            return out;
        } else {
            out.push_back(ch);
        }
    }
    return std::nullopt;
}

bool ExtractJsonBool(const std::string& object, const std::string& key) {
    const std::string token = "\"" + key + "\"";
    size_t pos = object.find(token);
    if (pos == std::string::npos) {
        return false;
    }
    pos = object.find(':', pos + token.size());
    if (pos == std::string::npos) {
        return false;
    }
    while (pos + 1 < object.size() && std::isspace(static_cast<unsigned char>(object[pos + 1]))) {
        ++pos;
    }
    return object.compare(pos + 1, 4, "true") == 0;
}

void SaveSettings() {
    std::ofstream out(std::filesystem::path(SettingsPath()), std::ios::binary | std::ios::trunc);
    if (!out) {
        return;
    }
    out << "{\n";
    out << "  \"autoExecuteFolder\": \"" << EscapeJson(g_autoExecuteFolder) << "\",\n";
    out << "  \"failureWebhook\": \"" << EscapeJson(g_failureWebhook) << "\",\n";
    out << "  \"failureWebhookEnabled\": " << (g_failureWebhookEnabled ? "true" : "false") << "\n";
    out << "}\n";
}

void LoadSettings() {
    const std::string text = ReadWholeFile(SettingsPath());
    g_autoExecuteFolder = Widen(ExtractJsonString(text, "autoExecuteFolder").value_or(""));
    g_failureWebhook = Widen(ExtractJsonString(text, "failureWebhook").value_or(""));
    if (text.find("\"failureWebhookEnabled\"") != std::string::npos) {
        g_failureWebhookEnabled = ExtractJsonBool(text, "failureWebhookEnabled");
    } else {
        g_failureWebhookEnabled = !g_failureWebhook.empty();
    }
}

std::wstring EffectiveFailureWebhook() {
    return g_failureWebhookEnabled ? g_failureWebhook : L"";
}

std::optional<std::wstring> BrowseForFolder(const std::wstring& title, HWND owner = nullptr) {
    BROWSEINFOW browse = {};
    browse.hwndOwner = owner ? owner : g_main;
    browse.lpszTitle = title.c_str();
    browse.ulFlags = BIF_RETURNONLYFSDIRS | BIF_NEWDIALOGSTYLE | BIF_USENEWUI;
    PIDLIST_ABSOLUTE pidl = SHBrowseForFolderW(&browse);
    if (!pidl) {
        return std::nullopt;
    }

    wchar_t path[MAX_PATH] = {};
    const bool ok = SHGetPathFromIDListW(pidl, path) != FALSE;
    CoTaskMemFree(pidl);
    if (!ok || path[0] == L'\0') {
        return std::nullopt;
    }
    return std::wstring(path);
}

bool IsDiscordWebhookUrl(const std::wstring& value) {
    std::wstring url = Trim(value);
    std::transform(url.begin(), url.end(), url.begin(), [](wchar_t ch) { return static_cast<wchar_t>(std::towlower(ch)); });
    return url.rfind(L"https://discord.com/api/webhooks/", 0) == 0 ||
           url.rfind(L"https://discordapp.com/api/webhooks/", 0) == 0 ||
           url.rfind(L"https://canary.discord.com/api/webhooks/", 0) == 0 ||
           url.rfind(L"https://ptb.discord.com/api/webhooks/", 0) == 0;
}

struct SettingsDialogState {
    std::wstring autoExecuteFolder;
    std::wstring failureWebhook;
    bool failureWebhookEnabled = false;
    bool accepted = false;
    bool done = false;
    HWND folderEdit = nullptr;
    HWND webhookEdit = nullptr;
    HWND webhookCheck = nullptr;
};

void SetChildFont(HWND hwnd, HFONT font) {
    if (hwnd && font) {
        SendMessageW(hwnd, WM_SETFONT, reinterpret_cast<WPARAM>(font), TRUE);
    }
}

LRESULT CALLBACK SettingsProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    SettingsDialogState* state = reinterpret_cast<SettingsDialogState*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    switch (message) {
        case WM_CREATE: {
            auto* create = reinterpret_cast<CREATESTRUCTW*>(lParam);
            state = reinterpret_cast<SettingsDialogState*>(create->lpCreateParams);
            SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(state));
            SetChildFont(CreateWindowExW(0, L"STATIC", L"Executor auto execute folder", WS_CHILD | WS_VISIBLE | SS_LEFT, 18, 18, 260, 22, hwnd, nullptr, g_instance, nullptr), g_font);
            state->folderEdit = CreateWindowExW(0, L"EDIT", state->autoExecuteFolder.c_str(), WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL | ES_READONLY, 18, 44, 438, 30, hwnd, nullptr, g_instance, nullptr);
            SetChildFont(state->folderEdit, g_font);
            SetChildFont(CreateWindowExW(0, L"BUTTON", L"Browse", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON, 466, 44, 100, 30, hwnd, reinterpret_cast<HMENU>(kSettingsBrowseFolder), g_instance, nullptr), g_font);
            SetChildFont(CreateWindowExW(0, L"STATIC", L"Discord webhook URL", WS_CHILD | WS_VISIBLE | SS_LEFT, 18, 88, 220, 22, hwnd, nullptr, g_instance, nullptr), g_font);
            state->webhookEdit = CreateWindowExW(0, L"EDIT", state->failureWebhook.c_str(), WS_CHILD | WS_VISIBLE | WS_BORDER | ES_AUTOHSCROLL, 18, 114, 548, 30, hwnd, nullptr, g_instance, nullptr);
            SetChildFont(state->webhookEdit, g_font);
            state->webhookCheck = CreateWindowExW(0, L"BUTTON", L"Enable Discord screenshot webhook", WS_CHILD | WS_VISIBLE | BS_AUTOCHECKBOX, 18, 154, 340, 26, hwnd, nullptr, g_instance, nullptr);
            SetChildFont(state->webhookCheck, g_font);
            SendMessageW(state->webhookCheck, BM_SETCHECK, state->failureWebhookEnabled ? BST_CHECKED : BST_UNCHECKED, 0);
            SetChildFont(CreateWindowExW(0, L"BUTTON", L"Save", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON, 374, 194, 90, 32, hwnd, reinterpret_cast<HMENU>(IDOK), g_instance, nullptr), g_font);
            SetChildFont(CreateWindowExW(0, L"BUTTON", L"Cancel", WS_CHILD | WS_VISIBLE, 476, 194, 90, 32, hwnd, reinterpret_cast<HMENU>(IDCANCEL), g_instance, nullptr), g_font);
            SetFocus(state->folderEdit);
            return 0;
        }
        case WM_COMMAND:
            if (LOWORD(wParam) == kSettingsBrowseFolder && state) {
                const auto folder = BrowseForFolder(L"Select executor auto execute folder", hwnd);
                if (folder.has_value()) {
                    SetWindowString(state->folderEdit, folder.value());
                }
                return 0;
            }
            if (LOWORD(wParam) == IDOK && state) {
                const bool webhookEnabled = SendMessageW(state->webhookCheck, BM_GETCHECK, 0, 0) == BST_CHECKED;
                const std::wstring webhook = Trim(GetWindowString(state->webhookEdit));
                if (webhookEnabled && !IsDiscordWebhookUrl(webhook)) {
                    MessageBoxW(hwnd, L"Enter a valid Discord webhook URL or disable webhook sending.", L"HydroBlade Settings", MB_OK | MB_ICONWARNING);
                    return 0;
                }
                state->autoExecuteFolder = Trim(GetWindowString(state->folderEdit));
                state->failureWebhook = webhook;
                state->failureWebhookEnabled = webhookEnabled;
                state->accepted = true;
                state->done = true;
                DestroyWindow(hwnd);
                return 0;
            }
            if (LOWORD(wParam) == IDCANCEL && state) {
                state->done = true;
                DestroyWindow(hwnd);
                return 0;
            }
            break;
        case WM_CLOSE:
            if (state) {
                state->done = true;
            }
            DestroyWindow(hwnd);
            return 0;
        default:
            break;
    }
    return DefWindowProcW(hwnd, message, wParam, lParam);
}

std::optional<SettingsDialogState> ShowSettingsDialog() {
    static bool registered = false;
    if (!registered) {
        WNDCLASSW wc = {};
        wc.lpfnWndProc = SettingsProc;
        wc.hInstance = g_instance;
        wc.lpszClassName = L"HydroBladeSettings";
        wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
        wc.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        RegisterClassW(&wc);
        registered = true;
    }

    SettingsDialogState state;
    state.autoExecuteFolder = g_autoExecuteFolder;
    state.failureWebhook = g_failureWebhook;
    state.failureWebhookEnabled = g_failureWebhookEnabled;
    RECT parentRect = {};
    GetWindowRect(g_main, &parentRect);
    const int width = 600;
    const int height = 276;
    HWND dialog = CreateWindowExW(
        WS_EX_DLGMODALFRAME,
        L"HydroBladeSettings",
        L"HydroBlade Settings",
        WS_CAPTION | WS_POPUP | WS_SYSMENU,
        parentRect.left + ((parentRect.right - parentRect.left) - width) / 2,
        parentRect.top + ((parentRect.bottom - parentRect.top) - height) / 2,
        width,
        height,
        g_main,
        nullptr,
        g_instance,
        &state);
    if (!dialog) {
        return std::nullopt;
    }

    EnableWindow(g_main, FALSE);
    ShowWindow(dialog, SW_SHOW);
    UpdateWindow(dialog);
    SetForegroundWindow(dialog);

    MSG msg = {};
    while (!state.done && GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(dialog, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }
    EnableWindow(g_main, TRUE);
    SetForegroundWindow(g_main);
    if (state.accepted) {
        return state;
    }
    return std::nullopt;
}

void EnsureAutoExecuteFolder() {
    LoadSettings();
    if (!g_autoExecuteFolder.empty() && std::filesystem::exists(std::filesystem::path(g_autoExecuteFolder))) {
        return;
    }

    MessageBoxW(
        g_main,
        L"Select your executor's auto execute folder. HydroBlade will write clean per-account Lua boot files there. Cookies are never written to those files.",
        L"HydroBlade Setup",
        MB_OK | MB_ICONINFORMATION);

    const auto folder = BrowseForFolder(L"Select executor auto execute folder");
    if (folder.has_value()) {
        g_autoExecuteFolder = folder.value();
        SaveSettings();
    }
}

void OpenSettings() {
    LoadSettings();
    const std::wstring previousAutoExecuteFolder = g_autoExecuteFolder;
    const auto settings = ShowSettingsDialog();
    if (!settings.has_value()) {
        SetStatus(L"Settings unchanged.");
        return;
    }

    const std::wstring nextAutoExecuteFolder = Trim(settings->autoExecuteFolder);
    if (!previousAutoExecuteFolder.empty() && previousAutoExecuteFolder != nextAutoExecuteFolder) {
        RestoreAutoExecuteFiles();
    }
    g_autoExecuteFolder = nextAutoExecuteFolder;
    g_failureWebhook = Trim(settings->failureWebhook);
    g_failureWebhookEnabled = settings->failureWebhookEnabled;
    SaveSettings();
    SyncAutoExecuteFiles();
    std::wstring status = L"Settings saved.";
    if (!g_autoExecuteFolder.empty()) {
        status += L" Auto execute folder: " + g_autoExecuteFolder;
    }
    if (!g_failureWebhookEnabled) {
        status += L" Discord screenshot webhook disabled.";
    } else if (g_failureWebhook.empty()) {
        status += L" Discord screenshot webhook cleared.";
    } else {
        status += L" Discord screenshot webhook enabled.";
    }
    SetStatus(status);
}

void LoadAccounts() {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    g_accounts.clear();
    const std::string text = ReadWholeFile(StorePath());
    size_t pos = 0;
    while ((pos = text.find('{', pos)) != std::string::npos) {
        size_t end = text.find('}', pos + 1);
        if (end == std::string::npos) {
            break;
        }

        const std::string object = text.substr(pos, end - pos + 1);
        const auto role = ExtractJsonString(object, "role");
        if (role.has_value()) {
            Account account;
            account.id = Widen(ExtractJsonString(object, "id").value_or(""));
            if (account.id.empty()) {
                account.id = GenerateAccountId();
            }
            account.parentId = Widen(ExtractJsonString(object, "parentId").value_or(""));
            account.label = Widen(ExtractJsonString(object, "label").value_or(""));
            account.alias = Widen(ExtractJsonString(object, "alias").value_or(""));
            account.silver = Widen(ExtractJsonString(object, "silver").value_or("unset"));
            if (account.silver.empty()) {
                account.silver = L"unset";
            }
            account.cookie = Widen(ExtractJsonString(object, "cookie").value_or(""));
            account.role = RoleFromKey(role.value());
            account.username = Widen(ExtractJsonString(object, "username").value_or(""));
            account.userId = Widen(ExtractJsonString(object, "userId").value_or(""));
            account.gaiaJobId = Widen(ExtractJsonString(object, "gaiaJobId").value_or(""));
            account.active = ExtractJsonBool(object, "active");
            account.authenticated = ExtractJsonBool(object, "authenticated");
            g_accounts.push_back(std::move(account));
        }
        pos = end + 1;
    }
}

std::wstring SafeFilePart(std::wstring value) {
    if (value.empty()) {
        value = GenerateAccountId();
    }
    for (wchar_t& ch : value) {
        if (ch == L'\\' || ch == L'/' || ch == L':' || ch == L'*' || ch == L'?' ||
            ch == L'"' || ch == L'<' || ch == L'>' || ch == L'|' || iswspace(ch)) {
            ch = L'_';
        }
    }
    return value;
}

std::string EscapeLua(const std::wstring& value) {
    std::ostringstream out;
    for (const unsigned char ch : Narrow(value)) {
        switch (ch) {
            case '\\': out << "\\\\"; break;
            case '"': out << "\\\""; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default: out << ch; break;
        }
    }
    return out.str();
}

std::filesystem::path ClientLuaSourcePath() {
    const std::filesystem::path exeDir = ExeDirectory();
    const std::filesystem::path besideExe = exeDir / L"hydroblade_client.lua";
    if (std::filesystem::exists(besideExe)) {
        return besideExe;
    }
    return exeDir.parent_path() / L"hydroblade_client.lua";
}

void WriteAccountAutoExecuteFile(const Account& account) {
    if (g_autoExecuteFolder.empty() || account.userId.empty()) {
        return;
    }

    const std::filesystem::path folder = g_autoExecuteFolder;
    std::filesystem::create_directories(folder);

    const std::filesystem::path file = folder / (L"HydroBlade_" + SafeFilePart(account.userId) + L".lua");
    g_generatedAutoExecuteFiles.insert(file.wstring());
    std::ofstream out(file, std::ios::binary | std::ios::trunc);
    if (!out) {
        return;
    }

    out << "repeat task.wait() until game:IsLoaded() and game:FindService(\"Players\") and game.Players.LocalPlayer\n";
    out << "local player = game.Players.LocalPlayer\n";
    out << "if tostring(player.UserId) ~= \"" << EscapeLua(account.userId) << "\" then return end\n";
    out << "getgenv().HYDROBLADE_ACCOUNT_ID = \"" << EscapeLua(account.id) << "\"\n";
    out << "getgenv().HYDROBLADE_PARENT_ID = \"" << EscapeLua(account.parentId) << "\"\n";
    out << "getgenv().HYDROBLADE_USERNAME = \"" << EscapeLua(account.username) << "\"\n";
    out << "getgenv().HYDROBLADE_USER_ID = \"" << EscapeLua(account.userId) << "\"\n";
    out << "getgenv().HYDROBLADE_ALIAS = \"" << EscapeLua(account.alias) << "\"\n";
    out << "getgenv().HYDROBLADE_ROLE = \"" << RoleKey(account.role) << "\"\n";
    out << "getgenv().HYDROBLADE_ACTIVE = " << (account.active ? "true" : "false") << "\n";
    out << "getgenv().HYDROBLADE_GAIA_JOB_ID = \"" << EscapeLua(account.gaiaJobId) << "\"\n";
    out << "getgenv().HYDROBLADE_WORKFLOW = \"" << EscapeLua(WorkflowForAccount(account)) << "\"\n";
    out << "getgenv().HYDROBLADE_FAILURE_WEBHOOK = \"" << EscapeLua(EffectiveFailureWebhook()) << "\"\n";
    out << "getgenv().HYDROBLADE_FAILURE_WEBHOOK_ENABLED = " << (g_failureWebhookEnabled ? "true" : "false") << "\n";
    out << "getgenv().HYDROBLADE_CLIENT = true\n";
    out << "getgenv().HYDROBLADE_BOOT_MODE = \"account\"\n";
    out << "getgenv().HYDROBLADE_DIST_ENTRYPOINT = \"dist/hydroblade_client.lua\"\n";
    out << "getgenv().HYDROBLADE_WS_URL = getgenv().HYDROBLADE_WS_URL or \"ws://127.0.0.1:8765\"\n";
    out << "getgenv().HYDROXIDE_REPO = getgenv().HYDROXIDE_REPO or \"https://raw.githubusercontent.com/Ludirus/Hydroxide-Rogue-Additions/main/\"\n";
    out << "local ok, err = pcall(function()\n";
    out << "    local repo = tostring(getgenv().HYDROXIDE_REPO)\n";
    out << "    if repo:sub(-1) ~= \"/\" then\n";
    out << "        repo = repo .. \"/\"\n";
    out << "    end\n";
    out << "    return loadstring(game:HttpGet(repo .. \"loader.lua\", true))()\n";
    out << "end)\n";
    out << "if not ok and warn then warn(\"[HydroBlade] loader failed\", err) end\n";
}

bool ContainsLuaQuotedString(const std::string& text, const std::string& value) {
    return text.find("\"" + value + "\"") != std::string::npos || text.find("'" + value + "'") != std::string::npos;
}

size_t FindLuaTableClose(const std::string& text, size_t open) {
    int depth = 0;
    bool inString = false;
    char quote = '\0';
    bool escaped = false;
    for (size_t i = open; i < text.size(); ++i) {
        const char ch = text[i];
        if (inString) {
            if (escaped) {
                escaped = false;
            } else if (ch == '\\') {
                escaped = true;
            } else if (ch == quote) {
                inString = false;
            }
            continue;
        }
        if (ch == '"' || ch == '\'') {
            inString = true;
            quote = ch;
            continue;
        }
        if (ch == '{') {
            ++depth;
        } else if (ch == '}') {
            --depth;
            if (depth == 0) {
                return i;
            }
        }
    }
    return std::string::npos;
}

std::optional<size_t> FindBlockedUsersTableOpen(const std::string& text) {
    for (const std::string& name : { std::string("blockedUsers"), std::string("BlockUsers") }) {
        const size_t namePos = text.find(name);
        if (namePos == std::string::npos) {
            continue;
        }
        const size_t open = text.find('{', namePos + name.size());
        if (open != std::string::npos) {
            return open;
        }
    }
    return std::nullopt;
}

std::vector<Account> AccountsForSigilLaunch(const std::vector<Account>& accounts) {
    std::vector<Account> launchAccounts;
    for (const Account& sigil : accounts) {
        if (!sigil.active || sigil.role != Role::SigilAlt) {
            continue;
        }
        launchAccounts.push_back(sigil);
        for (const Account& rot : accounts) {
            if (rot.role == Role::RotAlt && rot.parentId == sigil.id) {
                launchAccounts.push_back(rot);
            }
        }
    }
    return launchAccounts;
}

bool UpdateKoroBlockedUsers(const std::vector<Account>& launchAccounts) {
    if (g_autoExecuteFolder.empty() || launchAccounts.empty()) {
        return false;
    }

    const std::filesystem::path koroPath = std::filesystem::path(g_autoExecuteFolder) / L"koro.luau";
    if (!std::filesystem::exists(koroPath)) {
        return false;
    }

    std::string text = ReadWholeFile(koroPath.wstring());
    std::string insertion;
    std::unordered_set<std::string> seen;
    for (const Account& account : launchAccounts) {
        if (account.username.empty()) {
            continue;
        }
        const std::string username = EscapeLua(account.username);
        if (username.empty() || seen.find(username) != seen.end() || ContainsLuaQuotedString(text, username)) {
            continue;
        }
        seen.insert(username);
        insertion += "\n    \"" + username + "\",";
    }
    if (insertion.empty()) {
        return false;
    }

    const auto open = FindBlockedUsersTableOpen(text);
    if (open.has_value()) {
        const size_t close = FindLuaTableClose(text, *open);
        if (close != std::string::npos) {
            const std::string body = text.substr(*open + 1, close - *open - 1);
            const size_t last = body.find_last_not_of(" \t\r\n");
            std::string tableInsertion = insertion + "\n";
            if (last != std::string::npos && body[last] != ',') {
                tableInsertion = "," + tableInsertion;
            }
            text.insert(close, tableInsertion);
        } else {
            text += "\nlocal blockedUsers = {" + insertion + "\n}\n";
        }
    } else {
        text += "\nlocal blockedUsers = {" + insertion + "\n}\n";
    }

    if (!g_koroOriginalContent.has_value() || g_koroBackupPath != koroPath) {
        g_koroOriginalContent = ReadWholeFile(koroPath.wstring());
        g_koroBackupPath = koroPath;
    }

    std::ofstream out(koroPath, std::ios::binary | std::ios::trunc);
    if (!out) {
        return false;
    }
    out << text;
    return true;
}

void SyncAutoExecuteFiles() {
    if (g_autoExecuteFolder.empty()) {
        return;
    }

    try {
        const std::filesystem::path folder = g_autoExecuteFolder;
        std::filesystem::create_directories(folder);

        for (const Account& account : g_accounts) {
            WriteAccountAutoExecuteFile(account);
        }
    } catch (...) {
        // Auto-execute sync is best-effort; account storage must not fail because the folder is locked.
    }
}

void RestoreAutoExecuteFiles() {
    bool restored = false;
    try {
        if (!g_autoExecuteFolder.empty()) {
            const std::filesystem::path folder = g_autoExecuteFolder;
            if (std::filesystem::exists(folder)) {
                for (const auto& entry : std::filesystem::directory_iterator(folder)) {
                    if (!entry.is_regular_file()) {
                        continue;
                    }
                    const std::wstring name = entry.path().filename().wstring();
                    if (name.rfind(L"HydroBlade_", 0) == 0 && entry.path().extension() == L".lua") {
                        std::filesystem::remove(entry.path());
                        restored = true;
                    }
                }
            }
        }

        for (const std::wstring& file : g_generatedAutoExecuteFiles) {
            const std::filesystem::path path = file;
            if (std::filesystem::exists(path)) {
                std::filesystem::remove(path);
                restored = true;
            }
        }
        g_generatedAutoExecuteFiles.clear();

        if (g_koroOriginalContent.has_value() && !g_koroBackupPath.empty()) {
            std::ofstream out(g_koroBackupPath, std::ios::binary | std::ios::trunc);
            if (out) {
                out << g_koroOriginalContent.value();
                restored = true;
            }
        }
        g_koroOriginalContent.reset();
        g_koroBackupPath.clear();
    } catch (...) {
        SetStatus(L"Auto execute restore failed. Check folder permissions.");
        return;
    }

    if (restored) {
        SetStatus(L"Auto execute folder restored.");
    }
}

std::wstring UrlEncode(const std::wstring& value) {
    std::ostringstream out;
    for (const unsigned char ch : Narrow(value)) {
        if ((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') ||
            ch == '-' || ch == '_' || ch == '.' || ch == '~') {
            out << ch;
        } else {
            out << '%' << std::uppercase << std::hex << std::setw(2) << std::setfill('0') << static_cast<int>(ch);
        }
    }
    return Widen(out.str());
}

std::wstring HeaderValue(const HttpResponse& response, const std::wstring& key) {
    for (const auto& [name, value] : response.headers) {
        if (_wcsicmp(name.c_str(), key.c_str()) == 0) {
            return value;
        }
    }
    return {};
}

std::optional<std::wstring> JsonValueAfterKey(const std::wstring& body, const std::wstring& key) {
    const std::wstring token = L"\"" + key + L"\"";
    size_t pos = body.find(token);
    if (pos == std::wstring::npos) {
        return std::nullopt;
    }
    pos = body.find(L':', pos + token.size());
    if (pos == std::wstring::npos) {
        return std::nullopt;
    }
    while (pos + 1 < body.size() && iswspace(body[pos + 1])) {
        ++pos;
    }
    ++pos;
    if (pos >= body.size()) {
        return std::nullopt;
    }
    if (body[pos] == L'"') {
        std::wstring out;
        bool escaped = false;
        for (++pos; pos < body.size(); ++pos) {
            const wchar_t ch = body[pos];
            if (escaped) {
                out.push_back(ch);
                escaped = false;
            } else if (ch == L'\\') {
                escaped = true;
            } else if (ch == L'"') {
                return out;
            } else {
                out.push_back(ch);
            }
        }
        return std::nullopt;
    }

    size_t end = pos;
    while (end < body.size() && (iswdigit(body[end]) || body[end] == L'-')) {
        ++end;
    }
    if (end > pos) {
        return body.substr(pos, end - pos);
    }
    return std::nullopt;
}

class RobloxClient {
public:
    AuthResult AuthenticateCookie(const std::wstring& cookie) {
        const std::wstring normalizedCookie = NormalizeRobloxCookie(cookie);
        if (normalizedCookie.empty()) {
            return {false, L"", L"", L"Missing account cookie."};
        }
        const std::wstring header = L"Cookie: .ROBLOSECURITY=" + normalizedCookie + L"\r\n";
        const HttpResponse response = Request(L"GET", L"users.roblox.com", L"/v1/users/authenticated", header, L"");
        if (response.status != 200) {
            return {false, L"", L"", L"Authentication failed. HTTP " + std::to_wstring(response.status)};
        }

        const auto id = JsonValueAfterKey(response.body, L"id");
        const auto name = JsonValueAfterKey(response.body, L"name");
        if (!id.has_value() || !name.has_value()) {
            return {false, L"", L"", L"Authenticated, but Roblox response did not include id/name."};
        }

        return {true, name.value(), id.value(), L"Authenticated as " + name.value() + L" (" + id.value() + L")"};
    }

    LaunchResult JoinRogueGaiaJob(const Account& account, const std::wstring& jobOverride = L"") {
        const std::wstring normalizedCookie = NormalizeRobloxCookie(account.cookie);
        if (normalizedCookie.empty()) {
            return {false, L"Missing account cookie."};
        }

        const TicketResult ticket = GetAuthenticationTicket(normalizedCookie);
        if (!ticket.ok) {
            return {false, ticket.message.empty() ? L"Could not obtain Roblox authentication ticket." : ticket.message};
        }

        const std::wstring tracker = std::to_wstring(GetTickCount64());
        std::wstring launcher =
            std::wstring(L"https://assetgame.roblox.com/game/PlaceLauncher.ashx?request=RequestGame") +
            L"&browserTrackerId=" + tracker +
            L"&placeId=" + std::to_wstring(kRogueLoaderPlaceId) +
            L"&isPlayTogetherGame=false";

        const std::wstring protocol =
            L"roblox-player:1+launchmode:play+gameinfo:" + UrlEncode(ticket.ticket) +
            L"+placelauncherurl:" + UrlEncode(launcher) +
            L"+browsertrackerid:" + tracker +
            L"+robloxLocale:en_us+gameLocale:en_us";

        HINSTANCE result = ShellExecuteW(nullptr, L"open", protocol.c_str(), nullptr, nullptr, SW_SHOWNORMAL);
        if (reinterpret_cast<intptr_t>(result) <= 32) {
            return {false, L"Roblox player protocol launch failed."};
        }
        return {true, L"Launch requested for " + DisplayName(account) + L" into loader place " + std::to_wstring(kRogueLoaderPlaceId) + L"."};
    }

private:
    static std::wstring DisplayName(const Account& account) {
        if (!account.username.empty()) return account.username;
        if (!account.label.empty()) return account.label;
        return L"account";
    }

    TicketResult GetAuthenticationTicket(const std::wstring& cookie) {
        const std::wstring baseHeaders = RobloxRequestHeaders(cookie, L"");
        HttpResponse csrfProbe = Request(
            L"POST",
            L"auth.roblox.com",
            L"/v2/logout",
            baseHeaders,
            L"{}");

        std::wstring csrf = HeaderValue(csrfProbe, L"x-csrf-token");
        if (csrf.empty()) {
            HttpResponse ticketProbe = Request(
                L"POST",
                L"auth.roblox.com",
                L"/v1/authentication-ticket",
                baseHeaders,
                L"{}");
            const std::wstring ticket = HeaderValue(ticketProbe, L"rbx-authentication-ticket");
            if (!ticket.empty()) {
                return {true, ticket, L""};
            }
            csrf = HeaderValue(ticketProbe, L"x-csrf-token");
            if (csrf.empty()) {
                return {false, L"", L"Could not obtain Roblox authentication ticket. CSRF unavailable. logout HTTP " + std::to_wstring(csrfProbe.status) + L", ticket HTTP " + std::to_wstring(ticketProbe.status)};
            }
        }

        HttpResponse response = Request(
            L"POST",
            L"auth.roblox.com",
            L"/v1/authentication-ticket",
            RobloxRequestHeaders(cookie, csrf),
            L"{}");

        const std::wstring ticket = HeaderValue(response, L"rbx-authentication-ticket");
        if (!ticket.empty()) {
            return {true, ticket, L""};
        }

        std::wstring retryCsrf = HeaderValue(response, L"x-csrf-token");
        if (!retryCsrf.empty() && retryCsrf != csrf) {
            HttpResponse retry = Request(
                L"POST",
                L"auth.roblox.com",
                L"/v1/authentication-ticket",
                RobloxRequestHeaders(cookie, retryCsrf),
                L"{}");
            const std::wstring retryTicket = HeaderValue(retry, L"rbx-authentication-ticket");
            if (!retryTicket.empty()) {
                return {true, retryTicket, L""};
            }
            return {false, L"", L"Could not obtain Roblox authentication ticket. HTTP " + std::to_wstring(retry.status)};
        }

        return {false, L"", L"Could not obtain Roblox authentication ticket. HTTP " + std::to_wstring(response.status)};
    }

    static std::wstring RobloxRequestHeaders(const std::wstring& cookie, const std::wstring& csrf) {
        std::wstring headers =
            L"Cookie: .ROBLOSECURITY=" + cookie + L"\r\n"
            L"Content-Type: application/json\r\n"
            L"Accept: application/json, text/plain, */*\r\n"
            L"Origin: https://www.roblox.com\r\n"
            L"Referer: https://www.roblox.com/\r\n";
        if (!csrf.empty()) {
            headers += L"X-CSRF-TOKEN: " + csrf + L"\r\n";
        }
        return headers;
    }

    HttpResponse Request(
        const std::wstring& method,
        const std::wstring& host,
        const std::wstring& path,
        const std::wstring& headers,
        const std::wstring& body) {
        HttpResponse response;
        HINTERNET session = WinHttpOpen(
            L"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36",
            WINHTTP_ACCESS_TYPE_DEFAULT_PROXY,
            WINHTTP_NO_PROXY_NAME,
            WINHTTP_NO_PROXY_BYPASS,
            0);
        if (!session) {
            return response;
        }

        HINTERNET connect = WinHttpConnect(session, host.c_str(), INTERNET_DEFAULT_HTTPS_PORT, 0);
        if (!connect) {
            WinHttpCloseHandle(session);
            return response;
        }

        HINTERNET request = WinHttpOpenRequest(
            connect,
            method.c_str(),
            path.c_str(),
            nullptr,
            WINHTTP_NO_REFERER,
            WINHTTP_DEFAULT_ACCEPT_TYPES,
            WINHTTP_FLAG_SECURE);
        if (!request) {
            WinHttpCloseHandle(connect);
            WinHttpCloseHandle(session);
            return response;
        }

        std::string bodyUtf8 = Narrow(body);
        BOOL sent = WinHttpSendRequest(
            request,
            headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str(),
            headers.empty() ? 0 : static_cast<DWORD>(headers.size()),
            bodyUtf8.empty() ? WINHTTP_NO_REQUEST_DATA : bodyUtf8.data(),
            static_cast<DWORD>(bodyUtf8.size()),
            static_cast<DWORD>(bodyUtf8.size()),
            0);

        if (sent && WinHttpReceiveResponse(request, nullptr)) {
            DWORD statusSize = sizeof(response.status);
            WinHttpQueryHeaders(
                request,
                WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                WINHTTP_HEADER_NAME_BY_INDEX,
                &response.status,
                &statusSize,
                WINHTTP_NO_HEADER_INDEX);

            DWORD rawSize = 0;
            WinHttpQueryHeaders(
                request,
                WINHTTP_QUERY_RAW_HEADERS_CRLF,
                WINHTTP_HEADER_NAME_BY_INDEX,
                WINHTTP_NO_OUTPUT_BUFFER,
                &rawSize,
                WINHTTP_NO_HEADER_INDEX);
            if (GetLastError() == ERROR_INSUFFICIENT_BUFFER && rawSize > 0) {
                std::wstring raw(rawSize / sizeof(wchar_t), L'\0');
                if (WinHttpQueryHeaders(
                        request,
                        WINHTTP_QUERY_RAW_HEADERS_CRLF,
                        WINHTTP_HEADER_NAME_BY_INDEX,
                        raw.data(),
                        &rawSize,
                        WINHTTP_NO_HEADER_INDEX)) {
                    ParseHeaders(raw, response.headers);
                }
            }

            std::string data;
            DWORD available = 0;
            do {
                available = 0;
                if (!WinHttpQueryDataAvailable(request, &available) || available == 0) {
                    break;
                }
                std::string buffer(available, '\0');
                DWORD read = 0;
                if (!WinHttpReadData(request, buffer.data(), available, &read) || read == 0) {
                    break;
                }
                buffer.resize(read);
                data += buffer;
            } while (available > 0);
            response.body = Widen(data);
        }

        WinHttpCloseHandle(request);
        WinHttpCloseHandle(connect);
        WinHttpCloseHandle(session);
        return response;
    }

    static void ParseHeaders(const std::wstring& raw, std::vector<std::pair<std::wstring, std::wstring>>& headers) {
        std::wstringstream stream(raw);
        std::wstring line;
        while (std::getline(stream, line)) {
            if (!line.empty() && line.back() == L'\r') {
                line.pop_back();
            }
            const size_t colon = line.find(L':');
            if (colon == std::wstring::npos) {
                continue;
            }
            std::wstring name = Trim(line.substr(0, colon));
            std::wstring value = Trim(line.substr(colon + 1));
            if (!name.empty()) {
                headers.emplace_back(std::move(name), std::move(value));
            }
        }
    }
};

std::string EscapeJsonUtf8(const std::string& value) {
    std::ostringstream out;
    for (const unsigned char ch : value) {
        switch (ch) {
            case '\\': out << "\\\\"; break;
            case '"': out << "\\\""; break;
            case '\n': out << "\\n"; break;
            case '\r': out << "\\r"; break;
            case '\t': out << "\\t"; break;
            default:
                if (ch < 0x20) {
                    out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << static_cast<int>(ch);
                } else {
                    out << ch;
                }
                break;
        }
    }
    return out.str();
}

std::string JsonPair(const char* key, const std::wstring& value) {
    return std::string("\"") + key + "\":\"" + EscapeJsonUtf8(Narrow(value)) + "\"";
}

std::string AccountListJson() {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    std::ostringstream out;
    out << "{\"type\":\"accounts\",\"accounts\":[";
    for (size_t i = 0; i < g_accounts.size(); ++i) {
        const Account& account = g_accounts[i];
        if (i > 0) {
            out << ",";
        }
        out << "{"
            << JsonPair("id", account.id) << ","
            << JsonPair("parentId", account.parentId) << ","
            << JsonPair("label", account.label) << ","
            << JsonPair("alias", account.alias) << ","
            << JsonPair("silver", account.silver.empty() ? L"unset" : account.silver) << ","
            << "\"role\":\"" << RoleKey(account.role) << "\","
            << JsonPair("username", account.username) << ","
            << JsonPair("userId", account.userId) << ","
            << JsonPair("gaiaJobId", account.gaiaJobId) << ","
            << "\"active\":" << (account.active ? "true" : "false") << ","
            << "\"authenticated\":" << (account.authenticated ? "true" : "false")
            << "}";
    }
    out << "]}";
    return out.str();
}

bool SetAccountActiveById(const std::wstring& id, bool active) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    const size_t index = FindAccountIndexById(id);
    if (index == static_cast<size_t>(-1)) {
        return false;
    }
    g_accounts[index].active = active;
    SaveAccounts();
    PostMessageW(g_main, kRefreshUiMessage, 0, 0);
    return true;
}

std::string Base64Encode(const std::vector<unsigned char>& bytes) {
    static constexpr char table[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    std::string out;
    int value = 0;
    int bits = -6;
    for (const unsigned char byte : bytes) {
        value = (value << 8) + byte;
        bits += 8;
        while (bits >= 0) {
            out.push_back(table[(value >> bits) & 0x3F]);
            bits -= 6;
        }
    }
    if (bits > -6) {
        out.push_back(table[((value << 8) >> (bits + 8)) & 0x3F]);
    }
    while (out.size() % 4) {
        out.push_back('=');
    }
    return out;
}

std::string WebSocketAcceptKey(const std::string& clientKey) {
    static constexpr char guid[] = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    const std::string input = clientKey + guid;

    BCRYPT_ALG_HANDLE algorithm = nullptr;
    BCRYPT_HASH_HANDLE hash = nullptr;
    DWORD objectLength = 0;
    DWORD dataLength = 0;
    DWORD hashLength = 0;
    std::vector<unsigned char> hashObject;
    std::vector<unsigned char> digest;

    if (BCryptOpenAlgorithmProvider(&algorithm, BCRYPT_SHA1_ALGORITHM, nullptr, 0) != 0) {
        return {};
    }
    BCryptGetProperty(algorithm, BCRYPT_OBJECT_LENGTH, reinterpret_cast<PUCHAR>(&objectLength), sizeof(objectLength), &dataLength, 0);
    BCryptGetProperty(algorithm, BCRYPT_HASH_LENGTH, reinterpret_cast<PUCHAR>(&hashLength), sizeof(hashLength), &dataLength, 0);
    hashObject.resize(objectLength);
    digest.resize(hashLength);

    if (BCryptCreateHash(algorithm, &hash, hashObject.data(), objectLength, nullptr, 0, 0) == 0 &&
        BCryptHashData(hash, reinterpret_cast<PUCHAR>(const_cast<char*>(input.data())), static_cast<ULONG>(input.size()), 0) == 0 &&
        BCryptFinishHash(hash, digest.data(), hashLength, 0) == 0) {
        if (hash) BCryptDestroyHash(hash);
        BCryptCloseAlgorithmProvider(algorithm, 0);
        return Base64Encode(digest);
    }

    if (hash) BCryptDestroyHash(hash);
    BCryptCloseAlgorithmProvider(algorithm, 0);
    return {};
}

std::string HeaderLineValue(const std::string& request, const std::string& key) {
    std::istringstream stream(request);
    std::string line;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') {
            line.pop_back();
        }
        const size_t colon = line.find(':');
        if (colon == std::string::npos) {
            continue;
        }
        std::string name = line.substr(0, colon);
        std::string value = line.substr(colon + 1);
        std::transform(name.begin(), name.end(), name.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        std::string loweredKey = key;
        std::transform(loweredKey.begin(), loweredKey.end(), loweredKey.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (name == loweredKey) {
            while (!value.empty() && std::isspace(static_cast<unsigned char>(value.front()))) {
                value.erase(value.begin());
            }
            return value;
        }
    }
    return {};
}

bool SendAll(SOCKET socket, const char* data, int length) {
    int sent = 0;
    while (sent < length) {
        const int count = send(socket, data + sent, length - sent, 0);
        if (count <= 0) {
            return false;
        }
        sent += count;
    }
    return true;
}

bool RecvExact(SOCKET socket, unsigned char* data, int length) {
    int received = 0;
    while (received < length) {
        const int count = recv(socket, reinterpret_cast<char*>(data + received), length - received, 0);
        if (count <= 0) {
            return false;
        }
        received += count;
    }
    return true;
}

bool SendWebSocketText(SOCKET socket, const std::string& text) {
    std::vector<unsigned char> frame;
    frame.push_back(0x81);
    if (text.size() <= 125) {
        frame.push_back(static_cast<unsigned char>(text.size()));
    } else if (text.size() <= 65535) {
        frame.push_back(126);
        frame.push_back(static_cast<unsigned char>((text.size() >> 8) & 0xFF));
        frame.push_back(static_cast<unsigned char>(text.size() & 0xFF));
    } else {
        frame.push_back(127);
        for (int i = 7; i >= 0; --i) {
            frame.push_back(static_cast<unsigned char>((text.size() >> (i * 8)) & 0xFF));
        }
    }
    frame.insert(frame.end(), text.begin(), text.end());
    return SendAll(socket, reinterpret_cast<const char*>(frame.data()), static_cast<int>(frame.size()));
}

std::optional<std::string> ReceiveWebSocketText(SOCKET socket) {
    unsigned char header[2] = {};
    if (!RecvExact(socket, header, 2)) {
        return std::nullopt;
    }
    const unsigned char opcode = header[0] & 0x0F;
    if (opcode == 0x8) {
        return std::nullopt;
    }
    if (opcode != 0x1) {
        return std::string{};
    }

    const bool masked = (header[1] & 0x80) != 0;
    uint64_t length = header[1] & 0x7F;
    if (length == 126) {
        unsigned char extended[2] = {};
        if (!RecvExact(socket, extended, 2)) return std::nullopt;
        length = (static_cast<uint64_t>(extended[0]) << 8) | extended[1];
    } else if (length == 127) {
        unsigned char extended[8] = {};
        if (!RecvExact(socket, extended, 8)) return std::nullopt;
        length = 0;
        for (unsigned char byte : extended) {
            length = (length << 8) | byte;
        }
    }

    unsigned char mask[4] = {};
    if (masked && !RecvExact(socket, mask, 4)) {
        return std::nullopt;
    }
    if (length > 1024 * 1024) {
        return std::nullopt;
    }

    std::string payload(static_cast<size_t>(length), '\0');
    if (length > 0 && !RecvExact(socket, reinterpret_cast<unsigned char*>(payload.data()), static_cast<int>(length))) {
        return std::nullopt;
    }
    if (masked) {
        for (size_t i = 0; i < payload.size(); ++i) {
            payload[i] = static_cast<char>(payload[i] ^ mask[i % 4]);
        }
    }
    return payload;
}

size_t LaunchPendingRotForParent(const std::wstring& parentId, const std::wstring& placeId, const std::wstring& jobId, const std::wstring& role) {
    if (parentId.empty() || jobId.empty() || role != L"sigil_alt" || !IsGaiaPlaceId(placeId)) {
        return 0;
    }

    std::vector<Account> pending;
    {
        std::lock_guard<std::recursive_mutex> lock(g_runtimeMutex);
        const auto found = g_pendingRotLaunches.find(parentId);
        if (found == g_pendingRotLaunches.end()) {
            return 0;
        }
        pending = std::move(found->second);
        g_pendingRotLaunches.erase(found);
    }

    size_t launched = 0;
    RobloxClient client;
    for (const Account& account : pending) {
        const LaunchResult result = client.JoinRogueGaiaJob(account, jobId);
        if (result.ok) {
            ++launched;
            Sleep(750);
        }
    }
    if (launched > 0) {
        SetStatus(L"Launched " + std::to_wstring(launched) + L" pending Rot account(s) after Sigil reached Gaia job " + jobId + L".");
    }
    return launched;
}

RuntimeAccount RuntimeFromMessage(const std::string& message) {
    RuntimeAccount account;
    account.accountId = Widen(ExtractJsonString(message, "account_id").value_or(""));
    account.parentId = Widen(ExtractJsonString(message, "parent_id").value_or(""));
    account.role = Widen(ExtractJsonString(message, "role").value_or(""));
    account.username = Widen(ExtractJsonString(message, "username").value_or(""));
    account.userId = Widen(ExtractJsonString(message, "user_id").value_or(""));
    account.placeId = Widen(ExtractJsonString(message, "place_id").value_or(""));
    account.jobId = Widen(ExtractJsonString(message, "job_id").value_or(""));
    account.status = Widen(ExtractJsonString(message, "status").value_or(""));
    if (const auto error = ExtractJsonString(message, "error")) {
        account.statusDetail = Widen(*error);
    } else if (const auto detail = ExtractJsonString(message, "detail")) {
        account.statusDetail = Widen(*detail);
    }
    account.lastSeen = GetTickCount64();
    return account;
}

bool IsGroupFailed(const RuntimeAccount& account) {
    const std::wstring groupId = GroupIdForRuntime(account.accountId, account.parentId, account.role);
    std::lock_guard<std::recursive_mutex> lock(g_runtimeMutex);
    return !groupId.empty() && g_failedGroups.find(groupId) != g_failedGroups.end();
}

bool IsRotRequested(const RuntimeAccount& account) {
    const std::wstring groupId = GroupIdForRuntime(account.accountId, account.parentId, account.role);
    std::lock_guard<std::recursive_mutex> lock(g_runtimeMutex);
    return !groupId.empty() && g_requestedRotGroups.find(groupId) != g_requestedRotGroups.end();
}

std::wstring RuntimeStatusText(const std::wstring& status) {
    if (status == L"waiting_for_gaia_from_loader") return L"waiting for Gaia from loader";
    if (status == L"waiting_for_gaia_menu") return L"waiting for Gaia StartMenu";
    if (status == L"clicking_gaia_play") return L"clicking Gaia Play";
    if (status == L"gaia_play_clicked") return L"clicked Gaia Play";
    if (status == L"spawned") return L"spawned into Gaia";
    if (status == L"spawn_wait_failed") return L"spawn wait failed";
    return L"";
}

void UpsertRuntimeAccount(const RuntimeAccount& account) {
    if (account.accountId.empty()) {
        return;
    }
    std::wstring oldPlaceId;
    std::wstring oldJobId;
    std::wstring oldStatus;
    std::wstring oldStatusDetail;
    std::wstring displayName;
    std::lock_guard<std::recursive_mutex> lock(g_runtimeMutex);
    RuntimeAccount& stored = g_runtimeAccounts[account.accountId];
    oldPlaceId = stored.placeId;
    oldJobId = stored.jobId;
    oldStatus = stored.status;
    oldStatusDetail = stored.statusDetail;
    if (!account.accountId.empty()) stored.accountId = account.accountId;
    if (!account.parentId.empty()) stored.parentId = account.parentId;
    if (!account.role.empty()) stored.role = account.role;
    if (!account.username.empty()) stored.username = account.username;
    if (!account.userId.empty()) stored.userId = account.userId;
    if (!account.placeId.empty()) stored.placeId = account.placeId;
    if (!account.jobId.empty()) stored.jobId = account.jobId;
    if (!account.status.empty()) {
        stored.status = account.status;
        stored.statusDetail = account.statusDetail;
    }
    stored.lastSeen = account.lastSeen;
    displayName = !stored.username.empty() ? stored.username : (!stored.userId.empty() ? L"User " + stored.userId : stored.accountId);
    const bool placeChanged = !stored.placeId.empty() && stored.placeId != oldPlaceId;
    const bool jobChanged = !stored.jobId.empty() && stored.jobId != oldJobId;
    const bool statusChanged = !stored.status.empty() && (stored.status != oldStatus || stored.statusDetail != oldStatusDetail);
    const bool reachedGaia = placeChanged && IsGaiaPlaceId(stored.placeId);
    const std::wstring placeId = stored.placeId;
    const std::wstring jobId = stored.jobId;
    if (placeChanged || jobChanged) {
        SetStatus(L"Monitoring " + displayName + L": place " + (placeId.empty() ? L"unknown" : placeId) + L", job " + (jobId.empty() ? L"unknown" : jobId));
    }
    if (reachedGaia && !jobId.empty()) {
        SetStatus(displayName + L" reached Gaia place " + std::to_wstring(kRogueGaiaPlaceId) + L" with job " + jobId + L".");
    }
    const std::wstring statusText = RuntimeStatusText(stored.status);
    if (statusChanged && !statusText.empty()) {
        std::wstring line = displayName + L": " + statusText + L".";
        if (!stored.statusDetail.empty()) {
            line += L" " + stored.statusDetail;
        }
        SetStatus(line);
    }
}

std::string ClientRuntimeReply(const RuntimeAccount& account, const std::string& type) {
    const bool kick = IsGroupFailed(account);
    const bool rotRequested = IsRotRequested(account);
    const std::wstring parentJob = ParentJobForAccount(account.accountId, account.parentId);
    const bool gaiaReady = IsGaiaPlaceId(account.placeId) && !account.jobId.empty();
    std::ostringstream out;
    out << "{\"type\":\"" << type << "\","
        << "\"workflow\":\"" << EscapeJsonUtf8(Narrow(WorkflowForAccountId(account.accountId))) << "\","
        << "\"failure_webhook\":\"" << EscapeJsonUtf8(Narrow(EffectiveFailureWebhook())) << "\","
        << "\"failure_webhook_enabled\":" << (g_failureWebhookEnabled ? "true" : "false") << ","
        << "\"place_id\":\"" << EscapeJsonUtf8(Narrow(account.placeId)) << "\","
        << "\"job_id\":\"" << EscapeJsonUtf8(Narrow(account.jobId)) << "\","
        << "\"gaia_ready\":" << (gaiaReady ? "true" : "false") << ","
        << "\"parent_job\":\"" << EscapeJsonUtf8(Narrow(parentJob)) << "\","
        << "\"rot_requested\":" << (rotRequested ? "true" : "false") << ","
        << "\"kick\":" << (kick ? "true" : "false") << ","
        << "\"reason\":\"" << (kick ? "HydroBlade group failure" : "") << "\"}";
    return out.str();
}

std::string MarkRotFailure(const std::string& message) {
    RuntimeAccount account = RuntimeFromMessage(message);
    UpsertRuntimeAccount(account);
    const bool groupFailure = ExtractJsonBool(message, "group_failure");
    const bool kickSelf = message.find("\"kick_self\"") == std::string::npos || ExtractJsonBool(message, "kick_self");
    const std::wstring groupId = GroupIdForRuntime(account.accountId, account.parentId, account.role);
    if (groupFailure && !groupId.empty()) {
        std::lock_guard<std::recursive_mutex> lock(g_runtimeMutex);
        g_failedGroups.insert(groupId);
    }
    const std::string reason = ExtractJsonString(message, "reason").value_or("rot failure");
    SetStatus(std::wstring(groupFailure ? L"Group-fatal Rot failure: " : L"Rot local failure: ") + Widen(reason));
    return std::string("{\"type\":\"rot_failure_ack\",\"kick\":") + (kickSelf ? "true" : "false") + ",\"group_failure\":" + (groupFailure ? "true" : "false") + ",\"reason\":\"" + EscapeJsonUtf8(reason) + "\"}";
}

std::string MarkRotRequest(const std::string& message) {
    RuntimeAccount account = RuntimeFromMessage(message);
    UpsertRuntimeAccount(account);
    std::wstring groupId = GroupIdForRuntime(account.accountId, account.parentId, account.role);
    if (groupId.empty()) {
        groupId = account.parentId.empty() ? account.accountId : account.parentId;
    }
    if (!groupId.empty()) {
        std::lock_guard<std::recursive_mutex> lock(g_runtimeMutex);
        g_requestedRotGroups.insert(groupId);
    }
    return std::string("{\"type\":\"request_rots_ack\",\"rot_requested\":") + (!groupId.empty() ? "true" : "false") + "}";
}

std::string ExecuteWsCommand(const std::string& message) {
    const std::string method = ExtractJsonString(message, "method").value_or(message);
    if (method == "ping") {
        return "{\"type\":\"pong\",\"server\":\"HydroBlade\"}";
    }
    if (method == "help") {
        return "{\"type\":\"help\",\"methods\":[\"ping\",\"help\",\"listen\",\"repeat\",\"list_accounts\",\"set_active\",\"set_inactive\",\"start_sigils\",\"client_status\",\"parent_job\",\"request_rots\",\"rot_failure\"]}";
    }
    if (method == "listen") {
        RuntimeAccount account = RuntimeFromMessage(message);
        UpsertRuntimeAccount(account);
        LaunchPendingRotForParent(account.accountId, account.placeId, account.jobId, account.role);
        std::string reply = ClientRuntimeReply(account, "listening");
        reply.pop_back();
        return reply + ",\"events\":[\"accounts\",\"status\",\"workflow\"],\"snapshot\":" + AccountListJson() + "}";
    }
    if (method == "repeat") {
        const std::string data = ExtractJsonString(message, "data").value_or(message);
        return std::string("{\"type\":\"repeat\",\"data\":\"") + EscapeJsonUtf8(data) + "\"}";
    }
    if (method == "list_accounts") {
        return AccountListJson();
    }
    if (method == "set_active" || method == "set_inactive") {
        const std::string id = ExtractJsonString(message, "id").value_or("");
        const bool ok = SetAccountActiveById(Widen(id), method == "set_active");
        if (ok) {
            return std::string("{\"type\":\"updated\",\"method\":\"") + method + "\",\"id\":\"" + EscapeJsonUtf8(id) + "\"}";
        }
        return std::string("{\"type\":\"error\",\"message\":\"Account id not found: ") + EscapeJsonUtf8(id) + "\"}";
    }
    if (method == "start_sigils") {
        PostMessageW(g_main, kStartSigilsMessage, 0, 0);
        return "{\"type\":\"queued\",\"method\":\"start_sigils\"}";
    }
    if (method == "client_status") {
        RuntimeAccount account = RuntimeFromMessage(message);
        UpsertRuntimeAccount(account);
        LaunchPendingRotForParent(account.accountId, account.placeId, account.jobId, account.role);
        return ClientRuntimeReply(account, "client_status");
    }
    if (method == "parent_job") {
        RuntimeAccount account = RuntimeFromMessage(message);
        UpsertRuntimeAccount(account);
        const std::wstring job = ParentJobForAccount(account.accountId, account.parentId);
        return std::string("{\"type\":\"parent_job\",\"job_id\":\"") + EscapeJsonUtf8(Narrow(job)) + "\"}";
    }
    if (method == "request_rots") {
        return MarkRotRequest(message);
    }
    if (method == "rot_failure") {
        return MarkRotFailure(message);
    }
    return std::string("{\"type\":\"error\",\"message\":\"Unknown method: ") + EscapeJsonUtf8(method) + "\"}";
}

class WsServer {
public:
    ~WsServer() {
        Stop();
    }

    void Start(HWND hwnd) {
        owner_ = hwnd;
        running_ = true;
        worker_ = std::thread([this]() { Run(); });
    }

    void Stop() {
        running_ = false;
        if (listenSocket_ != INVALID_SOCKET) {
            closesocket(listenSocket_);
            listenSocket_ = INVALID_SOCKET;
        }
        if (worker_.joinable()) {
            worker_.join();
        }
        WSACleanup();
    }

    uint16_t Port() const {
        return port_;
    }

    bool Listening() const {
        return listening_.load();
    }

private:
    void Run() {
        WSADATA data = {};
        if (WSAStartup(MAKEWORD(2, 2), &data) != 0) {
            PostStatus(L"WebSocket server failed to initialize Winsock.");
            return;
        }

        listenSocket_ = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
        if (listenSocket_ == INVALID_SOCKET) {
            PostStatus(L"WebSocket server could not create a socket.");
            return;
        }

        sockaddr_in address = {};
        address.sin_family = AF_INET;
        inet_pton(AF_INET, "127.0.0.1", &address.sin_addr);

        bool bound = false;
        for (uint16_t port = 8765; port <= 8775; ++port) {
            address.sin_port = htons(port);
            if (bind(listenSocket_, reinterpret_cast<sockaddr*>(&address), sizeof(address)) == 0) {
                port_ = port;
                bound = true;
                break;
            }
        }
        if (!bound) {
            PostStatus(L"WebSocket server could not bind ports 8765-8775.");
            closesocket(listenSocket_);
            listenSocket_ = INVALID_SOCKET;
            return;
        }

        if (listen(listenSocket_, SOMAXCONN) != 0) {
            PostStatus(L"WebSocket server could not listen.");
            closesocket(listenSocket_);
            listenSocket_ = INVALID_SOCKET;
            return;
        }

        listening_ = true;
        PostStatus(std::wstring(L"WS listening on ws://127.0.0.1:") + std::to_wstring(port_));

        while (running_) {
            SOCKET client = accept(listenSocket_, nullptr, nullptr);
            if (client == INVALID_SOCKET) {
                if (running_) {
                    Sleep(50);
                }
                continue;
            }
            std::thread([this, client]() { HandleClient(client); }).detach();
        }
    }

    void HandleClient(SOCKET client) {
        std::string request;
        char buffer[1024] = {};
        while (request.find("\r\n\r\n") == std::string::npos && request.size() < 16384) {
            const int received = recv(client, buffer, sizeof(buffer), 0);
            if (received <= 0) {
                closesocket(client);
                return;
            }
            request.append(buffer, buffer + received);
        }

        const std::string key = HeaderLineValue(request, "Sec-WebSocket-Key");
        const std::string acceptKey = WebSocketAcceptKey(key);
        if (acceptKey.empty()) {
            closesocket(client);
            return;
        }

        const std::string response =
            "HTTP/1.1 101 Switching Protocols\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Accept: " + acceptKey + "\r\n\r\n";
        if (!SendAll(client, response.c_str(), static_cast<int>(response.size()))) {
            closesocket(client);
            return;
        }

        SendWebSocketText(client, "{\"type\":\"hello\",\"server\":\"HydroBlade\",\"methods\":[\"ping\",\"help\",\"listen\",\"repeat\",\"list_accounts\",\"set_active\",\"set_inactive\",\"start_sigils\",\"client_status\",\"parent_job\",\"request_rots\",\"rot_failure\"]}");
        while (running_) {
            const auto message = ReceiveWebSocketText(client);
            if (!message.has_value()) {
                break;
            }
            const std::string reply = ExecuteWsCommand(message.value());
            if (!SendWebSocketText(client, reply)) {
                break;
            }
        }
        closesocket(client);
    }

    void PostStatus(const std::wstring& status) {
        SetWindowString(g_wsStatus, L"  " + status);
    }

    HWND owner_ = nullptr;
    SOCKET listenSocket_ = INVALID_SOCKET;
    std::thread worker_;
    std::atomic_bool running_{false};
    std::atomic_bool listening_{false};
    uint16_t port_ = 0;
};

std::unique_ptr<WsServer> g_wsServer;

void SetStatus(const std::wstring& message) {
    SYSTEMTIME now = {};
    GetLocalTime(&now);
    wchar_t stamp[32] = {};
    swprintf_s(stamp, L"[%02u:%02u:%02u] ", now.wHour, now.wMinute, now.wSecond);
    g_statusLog += stamp;
    g_statusLog += message;
    g_statusLog += L"\r\n";
    constexpr size_t kMaxStatusChars = 24000;
    if (g_statusLog.size() > kMaxStatusChars) {
        const size_t trimTo = g_statusLog.size() - kMaxStatusChars;
        const size_t nextLine = g_statusLog.find(L"\r\n", trimTo);
        g_statusLog.erase(0, nextLine == std::wstring::npos ? trimTo : nextLine + 2);
    }
    if (!g_status || !IsWindow(g_status)) {
        return;
    }
    SetWindowTextW(g_status, g_statusLog.c_str());
    const int length = GetWindowTextLengthW(g_status);
    SendMessageW(g_status, EM_SETSEL, static_cast<WPARAM>(length), static_cast<LPARAM>(length));
    SendMessageW(g_status, EM_SCROLLCARET, 0, 0);
}

void UpdateStats() {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    size_t active = 0;
    size_t inactive = 0;
    size_t sigils = 0;
    size_t rot = 0;
    size_t silver = 0;
    size_t verdien = 0;
    for (const Account& account : g_accounts) {
        account.active ? ++active : ++inactive;
        if (account.role == Role::SigilAlt) ++sigils;
        if (account.role == Role::RotAlt) ++rot;
        if (account.role == Role::SilverAlt) ++silver;
        if (account.role == Role::VerdienAccount) ++verdien;
    }

    std::wstringstream stream;
    stream << L"Active " << active << L"    Inactive " << inactive
           << L"    Sigils " << sigils << L"    Rot " << rot
           << L"    Silver Banks " << silver << L"    Verdien " << verdien;
    SetWindowString(g_stats, stream.str());
}

std::wstring AccountTitle(const Account& account) {
    std::wstring title;
    if (!account.alias.empty()) {
        title = account.alias;
    } else if (!account.username.empty()) {
        title = account.username;
    } else if (!account.label.empty()) {
        title = account.label;
    } else if (!account.userId.empty()) {
        title = L"User " + account.userId;
    } else {
        title = L"Unnamed";
    }
    if (account.role == Role::RotAlt) {
        title = L"  > " + title;
    }
    if (!account.username.empty() && account.username != title && (account.role != Role::RotAlt || title.find(account.username) == std::wstring::npos)) {
        title += L"  @" + account.username;
    }
    if (!account.userId.empty()) {
        title += L"  ID: " + account.userId;
    }
    title += L"  [" + RoleName(account.role) + L"]";
    if (account.role == Role::SilverAlt) {
        title += L"  Silver: " + (account.silver.empty() ? L"unset" : account.silver);
    }
    if (account.role == Role::RotAlt) {
        const std::wstring parent = ParentLabel(account);
        if (!parent.empty()) {
            title += L"  under " + parent;
        }
    }
    if (account.authenticated) {
        title += L"  Auth";
    } else if (account.cookie.empty()) {
        title += L"  Needs cookie";
    }
    return title;
}

void RefreshLists() {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    SendMessageW(g_activeList, LB_RESETCONTENT, 0, 0);
    SendMessageW(g_inactiveList, LB_RESETCONTENT, 0, 0);

    auto addRow = [](HWND list, size_t index, const std::wstring& title) {
        const LRESULT row = SendMessageW(list, LB_ADDSTRING, 0, reinterpret_cast<LPARAM>(title.c_str()));
        SendMessageW(list, LB_SETITEMDATA, static_cast<WPARAM>(row), static_cast<LPARAM>(index));
    };

    auto renderList = [&](HWND list, bool active) {
        for (size_t i = 0; i < g_accounts.size(); ++i) {
            const Account& account = g_accounts[i];
            if (account.active != active || account.role == Role::RotAlt) {
                continue;
            }

            std::wstring title = AccountTitle(account);
            if (account.role == Role::SigilAlt) {
                const size_t children = RotChildCountFor(i);
                if (children > 0) {
                    const bool expanded = g_collapsedSigils.find(account.id) == g_collapsedSigils.end();
                    title = (expanded ? L"[-] " : L"[+] ") + title + L"  Rot: " + std::to_wstring(children);
                } else {
                    title = L"    " + title;
                }
            } else {
                title = L"    " + title;
            }
            addRow(list, i, title);

            if (account.role == Role::SigilAlt && g_collapsedSigils.find(account.id) == g_collapsedSigils.end()) {
                for (size_t childIndex = 0; childIndex < g_accounts.size(); ++childIndex) {
                    const Account& child = g_accounts[childIndex];
                    if (child.active == active && child.role == Role::RotAlt && child.parentId == account.id) {
                        addRow(list, childIndex, AccountTitle(child));
                    }
                }
            }
        }

        for (size_t i = 0; i < g_accounts.size(); ++i) {
            const Account& account = g_accounts[i];
            if (account.active != active || account.role != Role::RotAlt) {
                continue;
            }
            const size_t parent = FindAccountIndexById(account.parentId);
            if (parent == static_cast<size_t>(-1) || g_accounts[parent].active != active || g_accounts[parent].role != Role::SigilAlt) {
                addRow(list, i, AccountTitle(account));
            }
        }
    };

    renderList(g_activeList, true);
    renderList(g_inactiveList, false);
    for (auto it = g_collapsedSigils.begin(); it != g_collapsedSigils.end();) {
        if (FindAccountIndexById(*it) == static_cast<size_t>(-1)) {
            it = g_collapsedSigils.erase(it);
        } else {
            ++it;
        }
    }
    UpdateStats();
}

std::optional<size_t> SelectedAccountIndex() {
    const int activeSel = static_cast<int>(SendMessageW(g_activeList, LB_GETCURSEL, 0, 0));
    if (activeSel != LB_ERR) {
        return static_cast<size_t>(SendMessageW(g_activeList, LB_GETITEMDATA, activeSel, 0));
    }
    const int inactiveSel = static_cast<int>(SendMessageW(g_inactiveList, LB_GETCURSEL, 0, 0));
    if (inactiveSel != LB_ERR) {
        return static_cast<size_t>(SendMessageW(g_inactiveList, LB_GETITEMDATA, inactiveSel, 0));
    }
    return std::nullopt;
}

void LoadSelectedIntoForm(size_t index) {
    if (index >= g_accounts.size()) {
        return;
    }
    const Account& account = g_accounts[index];
    SetWindowString(g_name, account.label);
    SetWindowString(g_alias, account.alias);
    SetWindowString(g_cookie, account.cookie);
    SetWindowString(g_username, account.username);
    SetWindowString(g_userId, account.userId);
    SetWindowString(g_jobId, account.gaiaJobId);
    int roleIndex = 0;
    if (account.role == Role::RotAlt) roleIndex = 1;
    if (account.role == Role::SilverAlt) roleIndex = 2;
    if (account.role == Role::VerdienAccount) roleIndex = 3;
    SendMessageW(g_role, CB_SETCURSEL, roleIndex, 0);
}

void ApplyAliasToSelected() {
    const auto selected = SelectedAccountIndex();
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (!selected.has_value() || *selected >= g_accounts.size()) {
        SetStatus(L"Select an account before setting an alias.");
        return;
    }
    g_accounts[*selected].alias = GetWindowString(g_alias);
    SaveAccounts();
    RefreshLists();
    SetStatus(g_accounts[*selected].alias.empty() ? L"Alias cleared." : L"Alias updated.");
}

size_t ApplyActiveToAccountGroup(size_t index, bool active) {
    if (index >= g_accounts.size()) {
        return 0;
    }

    size_t moved = 1;
    const bool moveChildren = g_accounts[index].role == Role::SigilAlt;
    const std::wstring parentId = g_accounts[index].id;
    g_accounts[index].active = active;
    if (moveChildren) {
        for (Account& account : g_accounts) {
            if (account.role == Role::RotAlt && account.parentId == parentId) {
                account.active = active;
                ++moved;
            }
        }
    }
    return moved;
}

void UpsertAccount(bool active) {
    const auto selected = SelectedAccountIndex();
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    Account account;
    account.label = GetWindowString(g_name);
    account.alias = GetWindowString(g_alias);
    account.cookie = GetWindowString(g_cookie);
    account.username = GetWindowString(g_username);
    account.userId = GetWindowString(g_userId);
    account.gaiaJobId = GetWindowString(g_jobId);
    account.role = RoleFromIndex(static_cast<int>(SendMessageW(g_role, CB_GETCURSEL, 0, 0)));
    account.id = GenerateAccountId();
    account.active = (selected.has_value() && *selected < g_accounts.size()) ? g_accounts[*selected].active : active;

    if (account.label.empty()) {
        account.label = account.username.empty() ? L"Roblox Account" : account.username;
    }
    const bool updatingExisting = selected.has_value() && *selected < g_accounts.size();
    if (account.cookie.empty() && !updatingExisting) {
        SetStatus(L"Cookie is required before adding an account.");
        return;
    }

    if (updatingExisting) {
        account.id = g_accounts[*selected].id.empty() ? GenerateAccountId() : g_accounts[*selected].id;
        account.parentId = g_accounts[*selected].parentId;
        account.silver = g_accounts[*selected].silver.empty() ? L"unset" : g_accounts[*selected].silver;
        account.authenticated = g_accounts[*selected].authenticated;
        g_accounts[*selected] = std::move(account);
        SetStatus(L"Updated selected account.");
    } else {
        g_accounts.push_back(std::move(account));
        SetStatus(L"Added account.");
    }
    SaveAccounts();
    RefreshLists();
}

void MoveSelected(bool active) {
    const auto selected = SelectedAccountIndex();
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (!selected.has_value() || *selected >= g_accounts.size()) {
        SetStatus(L"Select an account first.");
        return;
    }
    const size_t moved = ApplyActiveToAccountGroup(*selected, active);
    SaveAccounts();
    RefreshLists();
    SetStatus((active ? L"Moved to Active Accounts." : L"Moved to Inactive Accounts.") + std::wstring(L" Accounts moved: ") + std::to_wstring(moved));
}

void MoveAccountByIndex(size_t index, bool active) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (index >= g_accounts.size()) {
        SetStatus(L"Drag target was no longer valid.");
        return;
    }
    const size_t moved = ApplyActiveToAccountGroup(index, active);
    SaveAccounts();
    RefreshLists();
    SetStatus((active ? L"Dragged to Active Accounts." : L"Dragged to Inactive Accounts.") + std::wstring(L" Accounts moved: ") + std::to_wstring(moved));
}

void ReparentRotAlt(size_t rotIndex, size_t parentIndex) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (rotIndex >= g_accounts.size() || parentIndex >= g_accounts.size()) {
        SetStatus(L"Drag target was no longer valid.");
        return;
    }
    if (g_accounts[rotIndex].role != Role::RotAlt || g_accounts[parentIndex].role != Role::SigilAlt) {
        return;
    }
    if (g_accounts[rotIndex].id == g_accounts[parentIndex].id) {
        return;
    }

    g_accounts[rotIndex].parentId = g_accounts[parentIndex].id;
    g_accounts[rotIndex].active = g_accounts[parentIndex].active;
    g_accounts[rotIndex].gaiaJobId = g_accounts[parentIndex].gaiaJobId;
    const std::wstring rotName = AccountShortName(g_accounts[rotIndex]);
    const std::wstring parentName = AccountShortName(g_accounts[parentIndex]);
    SaveAccounts();
    RefreshLists();
    SetStatus(L"Moved " + rotName + L" under " + parentName + L".");
}

void RemoveAccount(size_t index) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (index >= g_accounts.size()) {
        SetStatus(L"Select an account before removing.");
        return;
    }

    const bool removeChildren = g_accounts[index].role == Role::SigilAlt;
    const std::wstring id = g_accounts[index].id;
    const std::wstring name = AccountShortName(g_accounts[index]);
    const int confirm = MessageBoxW(
        g_main,
        removeChildren ? L"Remove this Sigil account and all linked Rot Alts?" : L"Remove this account?",
        L"Remove Account",
        MB_YESNO | MB_ICONWARNING | MB_DEFBUTTON2);
    if (confirm != IDYES) {
        SetStatus(L"Remove cancelled.");
        return;
    }

    size_t removed = 0;
    for (size_t i = 0; i < g_accounts.size();) {
        const bool isTarget = i == index;
        const bool isChild = removeChildren && g_accounts[i].role == Role::RotAlt && g_accounts[i].parentId == id;
        if (isTarget || isChild) {
            g_accounts.erase(g_accounts.begin() + static_cast<std::ptrdiff_t>(i));
            ++removed;
            continue;
        }
        ++i;
    }
    SaveAccounts();
    RefreshLists();
    SetStatus(L"Removed " + name + L". Accounts removed: " + std::to_wstring(removed));
}

void InsertRotAlt(size_t parentIndex) {
    if (GetCapture()) {
        ReleaseCapture();
    }
    HideDragBadge();
    g_drag = {};

    Account parent;
    {
        std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
        if (parentIndex >= g_accounts.size()) {
            SetStatus(L"Select a Sigil Alt before inserting a Rot Alt.");
            return;
        }
        parent = g_accounts[parentIndex];
    }
    if (parent.role != Role::SigilAlt) {
        SetStatus(L"Insert Rot Alt is available on Sigil Alt accounts.");
        return;
    }

    const auto cookie = PromptForText(L"Insert Rot Alt", L"Paste the Rot Alt .ROBLOSECURITY cookie", true, L"", true);
    if (!cookie.has_value()) {
        SetStatus(L"Rot Alt insert cancelled.");
        return;
    }

    const std::wstring normalizedCookie = NormalizeRobloxCookie(cookie.value());
    if (normalizedCookie.empty()) {
        SetStatus(L"Paste a Rot Alt .ROBLOSECURITY cookie first.");
        return;
    }

    SetStatus(L"Authenticating Rot Alt cookie...");
    RobloxClient client;
    AuthResult result = client.AuthenticateCookie(normalizedCookie);
    if (!result.ok) {
        SetStatus(L"Insert Rot Alt failed: " + result.message);
        return;
    }

    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    size_t target = static_cast<size_t>(-1);
    for (size_t i = 0; i < g_accounts.size(); ++i) {
        if (!result.userId.empty() && g_accounts[i].userId == result.userId) {
            target = i;
            break;
        }
    }

    Account child;
    if (target != static_cast<size_t>(-1)) {
        child = g_accounts[target];
    } else {
        child.id = GenerateAccountId();
        child.silver = L"unset";
    }
    child.parentId = parent.id;
    child.role = Role::RotAlt;
    child.active = parent.active;
    child.gaiaJobId = parent.gaiaJobId;
    child.cookie = normalizedCookie;
    child.username = result.username;
    child.userId = result.userId;
    child.label = result.username;
    child.authenticated = true;
    if (child.silver.empty()) {
        child.silver = L"unset";
    }

    if (target != static_cast<size_t>(-1)) {
        g_accounts[target] = std::move(child);
    } else {
        g_accounts.push_back(std::move(child));
    }
    g_collapsedSigils.erase(parent.id);
    SaveAccounts();
    RefreshLists();
    SetStatus(L"Inserted Rot Alt: " + result.username + L" (" + result.userId + L")");
}

void AddCookieToAccount(bool active) {
    const auto selected = SelectedAccountIndex();
    const std::wstring cookie = NormalizeRobloxCookie(GetWindowString(g_cookie));
    if (cookie.empty()) {
        SetStatus(L"Paste a .ROBLOSECURITY cookie first.");
        return;
    }

    SetStatus(active ? L"Authenticating and adding active account..." : L"Authenticating and adding inactive account...");
    RobloxClient client;
    AuthResult result = client.AuthenticateCookie(cookie);
    if (!result.ok) {
        SetStatus(result.message);
        return;
    }

    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    size_t target = static_cast<size_t>(-1);
    if (selected.has_value() && *selected < g_accounts.size() && g_accounts[*selected].cookie.empty()) {
        target = *selected;
    } else {
        for (size_t i = 0; i < g_accounts.size(); ++i) {
            if (!result.userId.empty() && g_accounts[i].userId == result.userId) {
                target = i;
                break;
            }
        }
    }

    Account account;
    if (target != static_cast<size_t>(-1)) {
        account = g_accounts[target];
    } else {
        account.id = GenerateAccountId();
        account.silver = L"unset";
    }

    account.cookie = cookie;
    account.username = result.username;
    account.userId = result.userId;
    account.authenticated = true;
    account.active = active;
    if (!(account.role == Role::RotAlt && !account.parentId.empty())) {
        account.role = RoleFromIndex(static_cast<int>(SendMessageW(g_role, CB_GETCURSEL, 0, 0)));
    }
    account.label = result.username;
    account.alias = GetWindowString(g_alias);
    account.gaiaJobId = GetWindowString(g_jobId);
    if (account.silver.empty()) {
        account.silver = L"unset";
    }

    if (target != static_cast<size_t>(-1)) {
        g_accounts[target] = std::move(account);
        LoadSelectedIntoForm(target);
    } else {
        g_accounts.push_back(std::move(account));
    }

    SetWindowString(g_name, result.username);
    ClearCookieInput();
    SaveAccounts();
    RefreshLists();
    SetStatus(std::wstring(active ? L"Added active account: " : L"Added inactive account: ") + result.username + L" (" + result.userId + L")");
}

void AddCookieToActive() {
    AddCookieToAccount(true);
}

void AuthenticateSelected() {
    AddCookieToAccount(false);
}

void JoinSelectedGaia() {
    const auto selected = SelectedAccountIndex();
    if (!selected.has_value() || *selected >= g_accounts.size()) {
        SetStatus(L"Select an account first.");
        return;
    }
    SetStatus(L"Launching Roblox player...");
    RobloxClient client;
    const LaunchResult result = client.JoinRogueGaiaJob(g_accounts[*selected]);
    SetStatus(result.message);
}

void StartSigils() {
    std::vector<Account> accounts;
    {
        std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
        g_sigilsRunning = true;
        ++g_sigilsRunId;
        for (Account& parent : g_accounts) {
            if (parent.role != Role::SigilAlt || !parent.active) {
                continue;
            }
            for (Account& child : g_accounts) {
                if (child.role == Role::RotAlt && child.parentId == parent.id) {
                    child.active = true;
                    child.gaiaJobId = parent.gaiaJobId;
                }
            }
        }
        {
            std::lock_guard<std::recursive_mutex> runtimeLock(g_runtimeMutex);
            g_failedGroups.clear();
            g_pendingRotLaunches.clear();
            g_requestedRotGroups.clear();
        }
        SaveAccounts();
        SyncAutoExecuteFiles();
        accounts = g_accounts;
    }

    const bool koroUpdated = UpdateKoroBlockedUsers(AccountsForSigilLaunch(accounts));
    size_t launchedSigils = 0;
    size_t launchedRots = 0;
    size_t failedLaunches = 0;
    size_t groups = 0;
    std::wstring firstFailure;
    RobloxClient client;
    for (const Account& sigil : accounts) {
        if (!sigil.active || sigil.role != Role::SigilAlt) {
            continue;
        }
        ++groups;
        SetStatus(L"Launching Sigil: " + AccountShortName(sigil));
        const LaunchResult sigilResult = client.JoinRogueGaiaJob(sigil);
        if (sigilResult.ok) {
            ++launchedSigils;
            SetStatus(L"Launched Sigil: " + AccountShortName(sigil));
            Sleep(750);
        } else {
            ++failedLaunches;
            SetStatus(L"Sigil launch failed: " + AccountShortName(sigil) + L" - " + sigilResult.message);
            if (firstFailure.empty()) {
                firstFailure = AccountShortName(sigil) + L": " + sigilResult.message;
            }
        }
        std::vector<Account> rotChildren;
        for (const Account& rot : accounts) {
            if (rot.role != Role::RotAlt || rot.parentId != sigil.id) {
                continue;
            }
            rotChildren.push_back(rot);
        }
        for (const Account& rot : rotChildren) {
            SetStatus(L"Launching Rot Alt: " + AccountShortName(rot));
            const LaunchResult rotResult = client.JoinRogueGaiaJob(rot, sigil.gaiaJobId);
            if (rotResult.ok) {
                ++launchedRots;
                SetStatus(L"Launched Rot Alt: " + AccountShortName(rot));
                Sleep(750);
            } else {
                ++failedLaunches;
                SetStatus(L"Rot Alt launch failed: " + AccountShortName(rot) + L" - " + rotResult.message);
                if (firstFailure.empty()) {
                    firstFailure = AccountShortName(rot) + L": " + rotResult.message;
                }
            }
        }
    }
    RefreshLists();
    std::wstring status = L"Start Sigils launched " + std::to_wstring(launchedSigils) + L" Sigil(s) and " + std::to_wstring(launchedRots) + L" Rot Alt(s) across " + std::to_wstring(groups) + L" Sigil group(s).";
    if (groups == 0) {
        status += L" No active Sigil Alt accounts were found.";
    }
    if (failedLaunches > 0) {
        status += L" Failed launch(es): " + std::to_wstring(failedLaunches) + L".";
        if (!firstFailure.empty()) {
            status += L" First failure: " + firstFailure;
        }
    }
    if (koroUpdated) {
        status += L" Updated koro.luau blocked users.";
    }
    SetStatus(status);
}

int ListIndexFromPoint(HWND hwnd, LPARAM lParam) {
    const POINT point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
    const DWORD result = static_cast<DWORD>(SendMessageW(hwnd, LB_ITEMFROMPOINT, 0, MAKELPARAM(point.x, point.y)));
    if (HIWORD(result)) {
        return LB_ERR;
    }
    return LOWORD(result);
}

void SelectListRow(HWND hwnd, int row) {
    if (row == LB_ERR) {
        return;
    }
    SendMessageW(hwnd, LB_SETCURSEL, static_cast<WPARAM>(row), 0);
    if (hwnd == g_activeList) {
        SendMessageW(g_inactiveList, LB_SETCURSEL, static_cast<WPARAM>(-1), 0);
    } else {
        SendMessageW(g_activeList, LB_SETCURSEL, static_cast<WPARAM>(-1), 0);
    }
    if (const auto selected = SelectedAccountIndex()) {
        LoadSelectedIntoForm(*selected);
    }
}

std::wstring AccountShortName(const Account& account) {
    if (!account.alias.empty()) return account.alias;
    if (!account.username.empty()) return account.username;
    if (!account.label.empty()) return account.label;
    if (!account.userId.empty()) return L"User " + account.userId;
    return L"Unnamed";
}

size_t RotChildCountFor(size_t index) {
    if (index >= g_accounts.size() || g_accounts[index].role != Role::SigilAlt) {
        return 0;
    }
    const std::wstring parentId = g_accounts[index].id;
    size_t count = 0;
    for (const Account& account : g_accounts) {
        if (account.role == Role::RotAlt && account.parentId == parentId) {
            ++count;
        }
    }
    return count;
}

void ToggleSigilExpanded(size_t index) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (index >= g_accounts.size() || g_accounts[index].role != Role::SigilAlt) {
        return;
    }
    if (RotChildCountFor(index) == 0) {
        SetStatus(L"This Sigil has no Rot Alts.");
        return;
    }
    const std::wstring id = g_accounts[index].id;
    if (g_collapsedSigils.find(id) == g_collapsedSigils.end()) {
        g_collapsedSigils.insert(id);
        SetStatus(L"Collapsed " + AccountShortName(g_accounts[index]) + L".");
    } else {
        g_collapsedSigils.erase(id);
        SetStatus(L"Expanded " + AccountShortName(g_accounts[index]) + L".");
    }
    RefreshLists();
}

std::wstring DragBadgeText(size_t index) {
    std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
    if (index >= g_accounts.size()) {
        return L"Moving account";
    }
    const size_t rotChildren = RotChildCountFor(index);
    std::wstring text = L"Moving: " + AccountShortName(g_accounts[index]);
    if (rotChildren > 0) {
        text += L" + " + std::to_wstring(rotChildren) + L" Rot";
    } else if (g_accounts[index].role == Role::RotAlt) {
        text += L" -> drop on Sigil to reassign";
    }
    return text;
}

void UpdateDragBadge(POINT screenPoint) {
    if (!g_drag.source || !g_dragBadge) {
        return;
    }
    SetWindowString(g_dragBadge, DragBadgeText(g_drag.index));
    SetWindowPos(
        g_dragBadge,
        HWND_TOPMOST,
        screenPoint.x + 16,
        screenPoint.y + 16,
        320,
        30,
        SWP_SHOWWINDOW | SWP_NOACTIVATE);
    InvalidateRect(g_dragBadge, nullptr, TRUE);
    UpdateWindow(g_dragBadge);
}

void HideDragBadge() {
    if (g_dragBadge) {
        ShowWindow(g_dragBadge, SW_HIDE);
    }
}

void ShowAccountContextMenu(HWND hwnd, int row, POINT screenPoint) {
    if (GetCapture()) {
        ReleaseCapture();
    }
    HideDragBadge();
    g_drag = {};

    SelectListRow(hwnd, row);
    const auto selected = SelectedAccountIndex();
    const bool canInsert =
        selected.has_value() &&
        *selected < g_accounts.size() &&
        g_accounts[*selected].role == Role::SigilAlt;
    const bool canToggle =
        canInsert &&
        RotChildCountFor(*selected) > 0;

    HMENU menu = CreatePopupMenu();
    if (canToggle && selected.has_value()) {
        const bool expanded = g_collapsedSigils.find(g_accounts[*selected].id) == g_collapsedSigils.end();
        AppendMenuW(menu, MF_STRING, kContextToggleSigil, expanded ? L"Collapse Rot Alts" : L"Expand Rot Alts");
    }
    AppendMenuW(
        menu,
        MF_STRING | (canInsert ? MF_ENABLED : MF_GRAYED),
        kContextInsertRotAlt,
        L"Insert Rot Alt");
    AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
    AppendMenuW(menu, MF_STRING, kContextRemoveAccount, L"Remove Account");
    const int command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_RIGHTBUTTON, screenPoint.x, screenPoint.y, 0, g_main, nullptr);
    DestroyMenu(menu);
    if (command == kContextToggleSigil && canToggle && selected.has_value()) {
        ToggleSigilExpanded(*selected);
    }
    if (command == kContextInsertRotAlt && canInsert && selected.has_value()) {
        InsertRotAlt(*selected);
    }
    if (command == kContextRemoveAccount && selected.has_value()) {
        RemoveAccount(*selected);
    }
}

std::optional<size_t> AccountIndexAtScreenPoint(HWND list, POINT screenPoint) {
    if (list != g_activeList && list != g_inactiveList) {
        return std::nullopt;
    }
    POINT clientPoint = screenPoint;
    ScreenToClient(list, &clientPoint);
    const DWORD result = static_cast<DWORD>(SendMessageW(list, LB_ITEMFROMPOINT, 0, MAKELPARAM(clientPoint.x, clientPoint.y)));
    if (HIWORD(result)) {
        return std::nullopt;
    }
    const LRESULT itemData = SendMessageW(list, LB_GETITEMDATA, LOWORD(result), 0);
    if (itemData == LB_ERR) {
        return std::nullopt;
    }
    return static_cast<size_t>(itemData);
}

HWND AccountListAtScreenPoint(POINT screenPoint) {
    RECT activeRect = {};
    RECT inactiveRect = {};
    GetWindowRect(g_activeList, &activeRect);
    GetWindowRect(g_inactiveList, &inactiveRect);
    if (PtInRect(&activeRect, screenPoint)) {
        return g_activeList;
    }
    if (PtInRect(&inactiveRect, screenPoint)) {
        return g_inactiveList;
    }
    return nullptr;
}

LRESULT CALLBACK AccountListSubclass(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam, UINT_PTR subclassId, DWORD_PTR) {
    const bool sourceActive = subclassId == kActiveListSubclass;
    switch (message) {
        case WM_LBUTTONDOWN: {
            const int row = ListIndexFromPoint(hwnd, lParam);
            if (row != LB_ERR) {
                SelectListRow(hwnd, row);
                const auto selected = SelectedAccountIndex();
                if (selected.has_value()) {
                    g_drag.source = hwnd;
                    g_drag.index = *selected;
                    g_drag.active = sourceActive;
                    SetCapture(hwnd);
                    POINT point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
                    ClientToScreen(hwnd, &point);
                    UpdateDragBadge(point);
                    SetStatus(L"Dragging account. Parent Sigils include linked Rot Alts.");
                }
            }
            break;
        }
        case WM_MOUSEMOVE: {
            if (g_drag.source) {
                POINT point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
                ClientToScreen(hwnd, &point);
                UpdateDragBadge(point);
                SetCursor(LoadCursor(nullptr, IDC_HAND));
                return 0;
            }
            break;
        }
        case WM_LBUTTONUP: {
            if (GetCapture() == hwnd) {
                ReleaseCapture();
            }
            if (g_drag.source) {
                POINT point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
                ClientToScreen(hwnd, &point);
                HideDragBadge();
                HWND target = AccountListAtScreenPoint(point);
                if (target == g_activeList || target == g_inactiveList) {
                    const auto targetIndex = AccountIndexAtScreenPoint(target, point);
                    bool reparented = false;
                    if (targetIndex.has_value() && *targetIndex != g_drag.index) {
                        std::lock_guard<std::recursive_mutex> lock(g_accountsMutex);
                        if (g_drag.index < g_accounts.size() &&
                            *targetIndex < g_accounts.size() &&
                            g_accounts[g_drag.index].role == Role::RotAlt &&
                            g_accounts[*targetIndex].role == Role::SigilAlt) {
                            reparented = true;
                        }
                    }
                    if (reparented && targetIndex.has_value()) {
                        ReparentRotAlt(g_drag.index, *targetIndex);
                    } else if (target != g_drag.source) {
                        MoveAccountByIndex(g_drag.index, target == g_activeList);
                    } else {
                        SetStatus(L"Drag cancelled.");
                    }
                } else {
                    SetStatus(L"Drag cancelled.");
                }
                g_drag = {};
                return 0;
            }
            break;
        }
        case WM_CONTEXTMENU: {
            POINT point{GET_X_LPARAM(lParam), GET_Y_LPARAM(lParam)};
            if (point.x == -1 && point.y == -1) {
                RECT rect = {};
                GetWindowRect(hwnd, &rect);
                point = {rect.left + 24, rect.top + 24};
            }
            POINT clientPoint = point;
            ScreenToClient(hwnd, &clientPoint);
            const DWORD result = static_cast<DWORD>(SendMessageW(hwnd, LB_ITEMFROMPOINT, 0, MAKELPARAM(clientPoint.x, clientPoint.y)));
            if (!HIWORD(result)) {
                ShowAccountContextMenu(hwnd, LOWORD(result), point);
                return 0;
            }
            break;
        }
        default:
            break;
    }
    return DefSubclassProc(hwnd, message, wParam, lParam);
}

HWND CreateControl(
    const wchar_t* className,
    const wchar_t* text,
    DWORD style,
    int x,
    int y,
    int w,
    int h,
    int id) {
    HWND hwnd = CreateWindowExW(
        0,
        className,
        text,
        WS_CHILD | WS_VISIBLE | style,
        x,
        y,
        w,
        h,
        g_main,
        reinterpret_cast<HMENU>(static_cast<intptr_t>(id)),
        g_instance,
        nullptr);
    SendMessageW(hwnd, WM_SETFONT, reinterpret_cast<WPARAM>(g_font), TRUE);
    return hwnd;
}

HWND CreatePanelLabel(const wchar_t* text, int x, int y, int w, int h) {
    HWND hwnd = CreateControl(L"STATIC", text, SS_LEFT, x, y, w, h, 0);
    if (g_smallFont) {
        SendMessageW(hwnd, WM_SETFONT, reinterpret_cast<WPARAM>(g_smallFont), TRUE);
    }
    return hwnd;
}

HWND CreateButton(const wchar_t* text, int x, int y, int w, int h, int id) {
    return CreateControl(L"BUTTON", text, BS_PUSHBUTTON | BS_OWNERDRAW, x, y, w, h, id);
}

void BuildUi() {
    INITCOMMONCONTROLSEX icc = {sizeof(icc), ICC_STANDARD_CLASSES | ICC_LISTVIEW_CLASSES};
    InitCommonControlsEx(&icc);

    g_font = CreateFontW(
        -16,
        0,
        0,
        0,
        FW_NORMAL,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_SWISS,
        L"Segoe UI");
    g_titleFont = CreateFontW(
        -30,
        0,
        0,
        0,
        FW_SEMIBOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_SWISS,
        L"Segoe UI");
    g_smallFont = CreateFontW(
        -13,
        0,
        0,
        0,
        FW_SEMIBOLD,
        FALSE,
        FALSE,
        FALSE,
        DEFAULT_CHARSET,
        OUT_DEFAULT_PRECIS,
        CLIP_DEFAULT_PRECIS,
        CLEARTYPE_QUALITY,
        DEFAULT_PITCH | FF_SWISS,
        L"Segoe UI");
    g_bgBrush = CreateSolidBrush(RGB(24, 26, 33));
    g_fieldBrush = CreateSolidBrush(RGB(18, 19, 25));
    g_panelBrush = CreateSolidBrush(RGB(19, 22, 31));

    g_logo.reset(Gdiplus::Bitmap::FromFile(LogoPath().c_str()));
    if (!g_logo || g_logo->GetLastStatus() != Gdiplus::Ok) {
        g_logo.reset();
    } else {
        g_logo->GetHICON(&g_appIcon);
        if (g_appIcon) {
            SendMessageW(g_main, WM_SETICON, ICON_BIG, reinterpret_cast<LPARAM>(g_appIcon));
            SendMessageW(g_main, WM_SETICON, ICON_SMALL, reinterpret_cast<LPARAM>(g_appIcon));
        }
    }

    HWND title = CreateControl(L"STATIC", L"LudSploit Auto Sigil", SS_LEFT, 34, 30, 430, 42, 0);
    SendMessageW(title, WM_SETFONT, reinterpret_cast<WPARAM>(g_titleFont), TRUE);
    g_stats = CreateControl(L"STATIC", L"Active 0    Inactive 0    Sigils 0    Rot 0    Silver Banks 0    Verdien 0", SS_LEFT, 38, 88, 620, 24, IdStats);
    CreateButton(L"Settings", 656, 28, 94, 32, IdSettings);
    g_wsStatus = CreateControl(L"STATIC", L"  WS starting...", WS_BORDER | SS_LEFT, 772, 28, 336, 32, IdWsStatus);
    g_hint = CreateControl(L"STATIC", L"Paste cookie, add active. Drag rows between lists. Right-click Sigils for Rot Alts.", SS_LEFT, 772, 78, 350, 40, IdHint);

    CreatePanelLabel(L"ACCOUNT INTAKE", 34, 174, 160, 22);
    g_name = CreateControl(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL, 34, 178, 1, 1, IdAccountName);
    ShowWindow(g_name, SW_HIDE);

    CreatePanelLabel(L".ROBLOSECURITY Cookie", 34, 210, 210, 22);
    g_cookie = CreateControl(L"EDIT", L"", WS_BORDER | ES_PASSWORD | ES_AUTOHSCROLL, 34, 236, 408, 34, IdCookie);
    CreateButton(L"Clear", 454, 236, 78, 34, IdClearCookie);

    CreatePanelLabel(L"Role", 34, 304, 90, 22);
    g_role = CreateControl(L"COMBOBOX", L"", CBS_DROPDOWNLIST | WS_VSCROLL, 34, 330, 236, 150, IdRole);
    SendMessageW(g_role, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Sigil Alt"));
    SendMessageW(g_role, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Sigil Alt > Rot Alt"));
    SendMessageW(g_role, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Silver Bank"));
    SendMessageW(g_role, CB_ADDSTRING, 0, reinterpret_cast<LPARAM>(L"Verdien Account"));
    SendMessageW(g_role, CB_SETCURSEL, 0, 0);

    CreatePanelLabel(L"Rogue Gaia Job ID", 296, 304, 160, 22);
    g_jobId = CreateControl(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL, 296, 330, 236, 30, IdJobId);

    g_username = CreateControl(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL | ES_READONLY, 36, 180, 1, 1, IdUsername);
    g_userId = CreateControl(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL | ES_READONLY, 38, 180, 1, 1, IdUserId);
    ShowWindow(g_username, SW_HIDE);
    ShowWindow(g_userId, SW_HIDE);

    CreateButton(L"Add Account", 34, 390, 236, 34, IdAddAccount);
    CreateButton(L"Auth Only", 296, 390, 112, 34, IdAuthenticate);
    CreateButton(L"Start Sigils", 420, 390, 112, 34, IdStartSigils);

    CreatePanelLabel(L"OPERATIONS", 34, 462, 140, 22);
    CreatePanelLabel(L"Alias", 34, 496, 90, 20);
    g_alias = CreateControl(L"EDIT", L"", WS_BORDER | ES_AUTOHSCROLL, 34, 520, 210, 30, IdAlias);
    CreateButton(L"Set Alias", 260, 520, 118, 30, IdSetAlias);
    CreateButton(L"Join Gaia", 394, 520, 138, 30, IdJoinGaia);
    CreateButton(L"Set Active", 34, 566, 140, 34, IdSetActive);
    CreateButton(L"Set Inactive", 190, 566, 140, 34, IdSetInactive);
    g_status = CreateControl(L"EDIT", L"", WS_BORDER | ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL | WS_VSCROLL, 34, 610, 498, 44, IdStatus);
    SetStatus(L"Ready.");
    EnsureDragBadgeClass();
    g_dragBadge = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE,
        L"HydroBladeDragBadge",
        L"",
        WS_POPUP,
        0,
        0,
        320,
        30,
        g_main,
        reinterpret_cast<HMENU>(IdDragBadge),
        g_instance,
        nullptr);
    ShowWindow(g_dragBadge, SW_HIDE);

    CreatePanelLabel(L"ACTIVE ACCOUNTS", 594, 174, 180, 22);
    g_activeList = CreateControl(L"LISTBOX", L"", WS_BORDER | LBS_NOTIFY | WS_VSCROLL, 594, 204, 514, 184, IdActiveList);

    CreatePanelLabel(L"INACTIVE ACCOUNTS", 594, 426, 190, 22);
    g_inactiveList = CreateControl(L"LISTBOX", L"", WS_BORDER | LBS_NOTIFY | WS_VSCROLL, 594, 456, 514, 190, IdInactiveList);

    SetWindowSubclass(g_activeList, AccountListSubclass, kActiveListSubclass, 0);
    SetWindowSubclass(g_inactiveList, AccountListSubclass, kInactiveListSubclass, 0);
}

void DrawRoundedPanel(Gdiplus::Graphics& graphics, int x, int y, int width, int height) {
    Gdiplus::SolidBrush fill(Gdiplus::Color(255, 19, 22, 31));
    Gdiplus::Pen border(Gdiplus::Color(255, 48, 58, 76), 1.0f);
    Gdiplus::Pen accent(Gdiplus::Color(255, 0, 194, 255), 2.0f);
    graphics.FillRectangle(&fill, x, y, width, height);
    graphics.DrawRectangle(&border, x, y, width, height);
    graphics.DrawLine(&accent, x + 1, y + 1, x + width - 2, y + 1);
}

void PaintUi(HWND hwnd) {
    PAINTSTRUCT ps = {};
    HDC hdc = BeginPaint(hwnd, &ps);
    Gdiplus::Graphics graphics(hdc);
    graphics.SetSmoothingMode(Gdiplus::SmoothingModeAntiAlias);

    Gdiplus::LinearGradientBrush bg(
        Gdiplus::Rect(0, 0, 1160, 720),
        Gdiplus::Color(255, 10, 12, 18),
        Gdiplus::Color(255, 20, 24, 36),
        Gdiplus::LinearGradientModeVertical);
    graphics.FillRectangle(&bg, 0, 0, 1160, 720);

    DrawRoundedPanel(graphics, 18, 18, 1116, 126);
    DrawRoundedPanel(graphics, 18, 160, 532, 282);
    DrawRoundedPanel(graphics, 18, 452, 532, 214);
    DrawRoundedPanel(graphics, 578, 160, 548, 246);
    DrawRoundedPanel(graphics, 578, 412, 548, 248);

    Gdiplus::Pen redAccent(Gdiplus::Color(255, 240, 45, 80), 2.0f);
    graphics.DrawLine(&redAccent, 578, 412, 1126, 412);

    EndPaint(hwnd, &ps);
}

void DrawButton(const DRAWITEMSTRUCT* item) {
    if (!item || item->CtlType != ODT_BUTTON) {
        return;
    }

    wchar_t text[128] = {};
    GetWindowTextW(item->hwndItem, text, 128);
    const bool pressed = (item->itemState & ODS_SELECTED) != 0;
    const bool disabled = (item->itemState & ODS_DISABLED) != 0;

    COLORREF fill = pressed ? RGB(22, 84, 102) : RGB(22, 27, 38);
    COLORREF border = pressed ? RGB(240, 45, 80) : RGB(0, 194, 255);
    COLORREF textColor = disabled ? RGB(105, 112, 124) : RGB(238, 244, 250);

    HBRUSH fillBrush = CreateSolidBrush(fill);
    FillRect(item->hDC, &item->rcItem, fillBrush);
    DeleteObject(fillBrush);

    HBRUSH borderBrush = CreateSolidBrush(border);
    FrameRect(item->hDC, &item->rcItem, borderBrush);
    DeleteObject(borderBrush);

    RECT inner = item->rcItem;
    InflateRect(&inner, -1, -1);
    HBRUSH innerBorderBrush = CreateSolidBrush(RGB(42, 50, 66));
    FrameRect(item->hDC, &inner, innerBorderBrush);
    DeleteObject(innerBorderBrush);

    SetBkMode(item->hDC, TRANSPARENT);
    SetTextColor(item->hDC, textColor);
    SelectObject(item->hDC, g_font);
    DrawTextW(item->hDC, text, -1, &inner, DT_CENTER | DT_VCENTER | DT_SINGLELINE | DT_END_ELLIPSIS);
}

LRESULT CALLBACK WindowProc(HWND hwnd, UINT message, WPARAM wParam, LPARAM lParam) {
    switch (message) {
        case WM_CREATE:
            g_main = hwnd;
            EnsureAutoExecuteFolder();
            BuildUi();
            LoadAccounts();
            RefreshLists();
            SyncAutoExecuteFiles();
            g_wsServer = std::make_unique<WsServer>();
            g_wsServer->Start(hwnd);
            return 0;
        case kRefreshUiMessage:
            RefreshLists();
            return 0;
        case kStartSigilsMessage:
            StartSigils();
            return 0;
        case WM_ERASEBKGND:
            return 1;
        case WM_PAINT:
            PaintUi(hwnd);
            return 0;
        case WM_DRAWITEM:
            DrawButton(reinterpret_cast<DRAWITEMSTRUCT*>(lParam));
            return TRUE;
        case WM_COMMAND: {
            const int id = LOWORD(wParam);
            const int notify = HIWORD(wParam);
            if ((id == IdActiveList || id == IdInactiveList) && notify == LBN_DBLCLK) {
                if (const auto selected = SelectedAccountIndex()) {
                    ToggleSigilExpanded(*selected);
                }
                return 0;
            }
            if ((id == IdActiveList || id == IdInactiveList) && notify == LBN_SELCHANGE) {
                if (id == IdActiveList) {
                    SendMessageW(g_inactiveList, LB_SETCURSEL, static_cast<WPARAM>(-1), 0);
                } else {
                    SendMessageW(g_activeList, LB_SETCURSEL, static_cast<WPARAM>(-1), 0);
                }
                if (const auto selected = SelectedAccountIndex()) {
                    LoadSelectedIntoForm(*selected);
                }
                return 0;
            }
            if (notify != BN_CLICKED) {
                return 0;
            }
            switch (id) {
                case IdAddAccount: AddCookieToActive(); return 0;
                case IdAuthenticate: AuthenticateSelected(); return 0;
                case IdJoinGaia: JoinSelectedGaia(); return 0;
                case IdStartSigils: StartSigils(); return 0;
                case IdSettings: OpenSettings(); return 0;
                case IdClearCookie: ClearCookieInput(); SetStatus(L"Cookie input cleared."); return 0;
                case IdSetAlias: ApplyAliasToSelected(); return 0;
                case IdSetActive: MoveSelected(true); return 0;
                case IdSetInactive: MoveSelected(false); return 0;
                default: return 0;
            }
        }
        case WM_CTLCOLORSTATIC: {
            HDC hdc = reinterpret_cast<HDC>(wParam);
            SetTextColor(hdc, RGB(230, 232, 238));
            HWND control = reinterpret_cast<HWND>(lParam);
            if (control == g_wsStatus || control == g_status || control == g_dragBadge) {
                SetBkColor(hdc, RGB(18, 19, 25));
                return reinterpret_cast<LRESULT>(g_fieldBrush);
            }
            SetBkMode(hdc, TRANSPARENT);
            return reinterpret_cast<LRESULT>(GetStockObject(HOLLOW_BRUSH));
        }
        case WM_CTLCOLOREDIT:
        case WM_CTLCOLORLISTBOX: {
            HDC hdc = reinterpret_cast<HDC>(wParam);
            SetTextColor(hdc, RGB(240, 242, 248));
            SetBkColor(hdc, RGB(18, 19, 25));
            return reinterpret_cast<LRESULT>(g_fieldBrush);
        }
        case WM_DESTROY:
            if (g_wsServer) {
                g_wsServer->Stop();
                g_wsServer.reset();
            }
            g_sigilsRunning = false;
            RestoreAutoExecuteFiles();
            SaveAccounts();
            RemoveWindowSubclass(g_activeList, AccountListSubclass, kActiveListSubclass);
            RemoveWindowSubclass(g_inactiveList, AccountListSubclass, kInactiveListSubclass);
            if (g_dragBadge) {
                DestroyWindow(g_dragBadge);
                g_dragBadge = nullptr;
            }
            g_logo.reset();
            if (g_appIcon) {
                DestroyIcon(g_appIcon);
            }
            if (g_font) {
                DeleteObject(g_font);
            }
            if (g_titleFont) {
                DeleteObject(g_titleFont);
            }
            if (g_smallFont) {
                DeleteObject(g_smallFont);
            }
            if (g_bgBrush) {
                DeleteObject(g_bgBrush);
            }
            if (g_fieldBrush) {
                DeleteObject(g_fieldBrush);
            }
            if (g_panelBrush) {
                DeleteObject(g_panelBrush);
            }
            PostQuitMessage(0);
            return 0;
        default:
            return DefWindowProcW(hwnd, message, wParam, lParam);
    }
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int showCommand) {
    g_instance = instance;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);
    Gdiplus::GdiplusStartupInput gdiplusInput;
    Gdiplus::GdiplusStartup(&g_gdiplusToken, &gdiplusInput, nullptr);

    WNDCLASSW wc = {};
    wc.lpfnWndProc = WindowProc;
    wc.hInstance = instance;
    wc.lpszClassName = kAppClassName;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    HBRUSH classBrush = CreateSolidBrush(RGB(24, 26, 33));
    wc.hbrBackground = classBrush;

    RegisterClassW(&wc);

    HWND hwnd = CreateWindowExW(
        0,
        kAppClassName,
        kAppTitle,
        WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
        CW_USEDEFAULT,
        CW_USEDEFAULT,
        1160,
        720,
        nullptr,
        nullptr,
        instance,
        nullptr);

    if (!hwnd) {
        return 1;
    }

    ShowWindow(hwnd, showCommand);
    UpdateWindow(hwnd);

    MSG msg = {};
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
    DeleteObject(classBrush);
    if (g_gdiplusToken) {
        Gdiplus::GdiplusShutdown(g_gdiplusToken);
    }
    CoUninitialize();
    return static_cast<int>(msg.wParam);
}
