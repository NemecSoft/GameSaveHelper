// ============================================================================
//  GameSaveHelper.exe - 通用游戏存档备份助手
//
//  用法（命令行，严格检查，不做推断）：
//      GameSaveHelper.exe 大富翁11 "D:\games\Z\Richman 11\2074800\*.*" "更多路径\*.*"
//          第一个参数是游戏名，其余参数必须是引号包裹的完整路径
//      GameSaveHelper.exe 大富翁11
//          到 当前目录(或exe目录) 的 config.json 里读取该游戏的存档路径配置
//
//  界面（极简，模仿 GameSaveHelper_old.bat 的文字输出）：
//      - 启动即自动开始备份，窗口里只有文字和两个按钮
//      - 备份中：蓝底白字，逐行显示进度
//      - 成功：绿底白字，显示备份包完整路径和使用方法
//      - 失败：红底白字，显示失败原因
//      - 「显示备份后的文件」：打开备份所在目录并定位到文件（不自动打开）
//      - 「关闭」：关闭窗口
//      - 无参数 / 参数错误：红底显示「备份失败，参数错误，请联系管理员...」
//
//  产物：桌面上的「游戏名_年月日_时分秒.exe」，双击一步还原
//
//  实现约定：
//      - 纯 Win32 / Unicode，静态链接 CRT，单文件交付，无运行时依赖
//      - 高 DPI 感知，字体 Microsoft YaHei UI
// ============================================================================

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <shlobj.h>
#include <shlwapi.h>
#include <shellapi.h>
#include <objbase.h>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>
#include <thread>
#include <functional>
#include <algorithm>

#pragma comment(lib, "user32.lib")
#pragma comment(lib, "gdi32.lib")
#pragma comment(lib, "comctl32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "shlwapi.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "advapi32.lib")

#pragma comment(linker, "/manifestdependency:\"type='win32' name='Microsoft.Windows.Common-Controls' version='6.0.0.0' processorArchitecture='*' publicKeyToken='6595b64144ccf1df' language='*'\"")

#ifndef IDR_TEMPLATE
#define IDR_TEMPLATE 101
#endif
#include "resource.h"

// ---------------------------------------------------------------------------
// 控件 ID
// ---------------------------------------------------------------------------
enum {
    IDC_TEXT = 1001,
    IDC_OPEN,
    IDC_CLOSE,
    IDC_PROGRESS,
    IDC_STATUS
};

// ---------------------------------------------------------------------------
// 配色（现代浅色风格）：状态标题蓝/绿/红，正文区浅灰卡片
// ---------------------------------------------------------------------------
static const COLORREF CLR_RUN  = RGB(0, 103, 192);   // 备份进行中
static const COLORREF CLR_OK   = RGB(16, 124, 16);   // 备份成功
static const COLORREF CLR_BAD  = RGB(196, 43, 28);   // 备份失败
static const COLORREF CLR_CARD = RGB(246, 246, 246); // 正文区底色
static const COLORREF CLR_INK  = RGB(27, 27, 27);    // 正文文字色

// ---------------------------------------------------------------------------
// 全局
// ---------------------------------------------------------------------------
static int      g_dpi = 96;
static HFONT    g_fontUI = nullptr;          // 9pt
static HFONT    g_fontStatus = nullptr;      // 13pt bold（顶部状态标题）
static HINSTANCE g_inst = nullptr;

static HBRUSH   g_brushCard = nullptr;       // 正文区浅灰底刷子
static COLORREF g_statusColor = CLR_RUN;     // 当前状态标题颜色

static bool     g_busy = false;
static std::wstring g_text;                  // 窗口里显示的全部文字
static std::wstring g_lastExe;               // 成功生成的备份包完整路径
static std::wstring g_openLabel;             // 「显示备份后的文件」按钮上的文字

static int S(int px) { return MulDiv(px, g_dpi, 96); }

// ---------------------------------------------------------------------------
// 小工具
// ---------------------------------------------------------------------------
static std::string W2U8(const std::wstring& w)
{
    if (w.empty()) return std::string();
    int n = WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), nullptr, 0, nullptr, nullptr);
    std::string s((size_t)n, '\0');
    WideCharToMultiByte(CP_UTF8, 0, w.c_str(), (int)w.size(), &s[0], n, nullptr, nullptr);
    return s;
}

static std::wstring U82W(const std::string& s)
{
    if (s.empty()) return std::wstring();
    int n = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), nullptr, 0);
    std::wstring w((size_t)n, L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), (int)s.size(), &w[0], n);
    return w;
}

// NSIS 字符串转义：$ " ` 三个字符有特殊含义
static std::wstring NsisEsc(const std::wstring& s)
{
    std::wstring r;
    r.reserve(s.size() + 8);
    for (wchar_t c : s) {
        if (c == L'$') r += L"$$";
        else if (c == L'"') r += L"$\"";
        else if (c == L'`') r += L"$`";
        else r += c;
    }
    return r;
}

static std::wstring FormatSize(ULONGLONG b)
{
    wchar_t buf[64];
    if (b < 1024)              swprintf_s(buf, L"%llu B", b);
    else if (b < 1024 * 1024)  swprintf_s(buf, L"%.1f KB", b / 1024.0);
    else if (b < 1024ULL * 1024 * 1024) swprintf_s(buf, L"%.1f MB", b / 1048576.0);
    else                       swprintf_s(buf, L"%.2f GB", b / 1073741824.0);
    return buf;
}

static std::wstring SanitizeFileName(const std::wstring& s)
{
    static const std::wstring bad = L"\\/:*?\"<>|";
    std::wstring r;
    for (wchar_t c : s) r += (bad.find(c) != std::wstring::npos) ? L'_' : c;
    while (!r.empty() && (r.back() == L'.' || r.back() == L' ')) r.pop_back();
    return r.empty() ? L"GameSave" : r;
}

static std::wstring GetExeDir()
{
    wchar_t buf[MAX_PATH];
    GetModuleFileNameW(nullptr, buf, MAX_PATH);
    PathRemoveFileSpecW(buf);
    return buf;
}

static std::wstring JoinPath(const std::wstring& a, const std::wstring& b)
{
    if (a.empty()) return b;
    if (a.back() == L'\\') return a + b;
    return a + L"\\" + b;
}

static bool FileExistsW(const std::wstring& p)
{
    return GetFileAttributesW(p.c_str()) != INVALID_FILE_ATTRIBUTES;
}

// 系统桌面（需求：备份包默认放在桌面）
static std::wstring GetDesktopDir()
{
    wchar_t buf[MAX_PATH] = { 0 };
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_DESKTOPDIRECTORY, nullptr, 0, buf)))
        return buf;
    return JoinPath(GetExeDir(), L"out");
}

// 注意：绝不以任何方式打开用户的存档文件（不能用 CreateFile 探测占用——
// 那本身就是锁文件）。存在性检查只用 GetFileAttributesW / FindFirstFile，
// 若个别文件真被占用，makensis 读取失败时会自然报错。

// ---------------------------------------------------------------------------
// config.json：{ "游戏名": ["路径1", "路径2"], ... }
// 只做针对性的查找解析（游戏名 -> 路径数组），够用且零依赖
// ---------------------------------------------------------------------------
static bool ParseJsonString(const std::string& s, size_t& i, std::string& out)
{
    if (i >= s.size() || s[i] != '"') return false;
    i++;
    out.clear();
    while (i < s.size()) {
        char c = s[i];
        if (c == '"') { i++; return true; }
        if (c == '\\') {
            i++;
            if (i >= s.size()) return false;
            char e = s[i++];
            switch (e) {
            case '"':  out += '"';  break;
            case '\\': out += '\\'; break;
            case '/':  out += '/';  break;
            case 'n':  out += '\n'; break;
            case 'r':  out += '\r'; break;
            case 't':  out += '\t'; break;
            case 'b':  out += '\b'; break;
            case 'f':  out += '\f'; break;
            case 'u': {
                if (i + 4 > s.size()) return false;
                unsigned int wc = 0;
                for (int k = 0; k < 4; k++) {
                    char h = s[i++];
                    wc <<= 4;
                    if      (h >= '0' && h <= '9') wc += (unsigned)(h - '0');
                    else if (h >= 'a' && h <= 'f') wc += (unsigned)(h - 'a' + 10);
                    else if (h >= 'A' && h <= 'F') wc += (unsigned)(h - 'A' + 10);
                    else return false;
                }
                // 代理对（\uD83D\uDE00 之类）合成一个字符
                if (wc >= 0xD800 && wc <= 0xDBFF && i + 6 <= s.size() &&
                    s[i] == '\\' && s[i + 1] == 'u') {
                    size_t save = i; i += 2;
                    unsigned int lo = 0; bool ok = true;
                    for (int k = 0; k < 4; k++) {
                        char h = s[i++];
                        lo <<= 4;
                        if      (h >= '0' && h <= '9') lo += (wchar_t)(h - '0');
                        else if (h >= 'a' && h <= 'f') lo += (wchar_t)(h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') lo += (wchar_t)(h - 'A' + 10);
                        else { ok = false; break; }
                    }
                    if (ok && lo >= 0xDC00 && lo <= 0xDFFF)
                        wc = 0x10000 + ((wc - 0xD800) << 10) + (lo - 0xDC00);
                    else i = save;
                }
                // UTF-8 编码写回
                if (wc < 0x80) out += (char)wc;
                else if (wc < 0x800) {
                    out += (char)(0xC0 | (wc >> 6));
                    out += (char)(0x80 | (wc & 0x3F));
                } else if (wc < 0x10000) {
                    out += (char)(0xE0 | (wc >> 12));
                    out += (char)(0x80 | ((wc >> 6) & 0x3F));
                    out += (char)(0x80 | (wc & 0x3F));
                } else {
                    out += (char)(0xF0 | (wc >> 18));
                    out += (char)(0x80 | ((wc >> 12) & 0x3F));
                    out += (char)(0x80 | ((wc >> 6) & 0x3F));
                    out += (char)(0x80 | (wc & 0x3F));
                }
                break;
            }
            default: return false;
            }
        } else {
            out += c; i++;
        }
    }
    return false;
}

// 宽容版 JSON 字符串读取：容忍 Playday 导出数据里的坏转义。
// 规则：\ 跳过下一个字符；遇到 " 时向后看，若跳过空白后是 , ] } 或另一个 " 之一
// 则视为字符串结束，否则当作内容继续（用于容忍 "...*.*\" 这类坏转义）。
// limit：可选扫描上界（如 savePaths 数组的 ']' 位置），超过视为未正常结束。
static bool ParseJsonStringLenient(const std::string& s, size_t& i, std::string& out,
                                   size_t limit = std::string::npos)
{
    if (i >= s.size() || s[i] != '"') return false;
    i++;
    out.clear();
    while (i < s.size() && i < limit) {
        char c = s[i];
        if (c == '\\') {
            if (i + 1 < s.size() && s[i + 1] == '"') {
                // \" ：若后面是分隔符，说明这是坏转义的收尾——反斜杠属于值本身
                size_t k = i + 2;
                while (k < s.size() && (s[k]==' '||s[k]=='\t'||s[k]=='\r'||s[k]=='\n')) k++;
                if (k >= s.size() || s[k] == ',' || s[k] == ']' || s[k] == '}') {
                    out += '\\';
                    i++;               // 停在结束引号上，由调用方越过
                    return true;
                }
            }
            i++;
            if (i >= s.size()) return false;
            char e = s[i++];
            switch (e) {
            case '"':  out += '"';  break;
            case '\\': out += '\\'; break;
            case '/':  out += '/';  break;
            case 'n':  out += '\n'; break;
            case 'r':  out += '\r'; break;
            case 't':  out += '\t'; break;
            case 'b':  out += '\b'; break;
            case 'f':  out += '\f'; break;
            default:   out += e;    break;   // \u 等：宽容处理，原样保留
            }
        } else if (c == '"') {
            size_t k = i + 1;
            while (k < s.size() && (s[k]==' '||s[k]=='\t'||s[k]=='\r'||s[k]=='\n')) k++;
            if (k >= s.size() || s[k] == ',' || s[k] == ']' || s[k] == '}' || s[k] == '"') {
                i++;
                return true;
            }
            out += c; i++;               // 多余的引号（坏数据），当内容
        } else {
            out += c; i++;
        }
    }
    return false;
}

// 清洗存档路径：去首尾空白、去末尾多余的反斜杠/引号（保留 X:\ 盘根）
static std::wstring CleanSavePath(std::wstring p)
{
    size_t b = p.find_first_not_of(L" \t\r\n");
    if (b == std::wstring::npos) return L"";
    p = p.substr(b, p.find_last_not_of(L" \t\r\n") - b + 1);
    while (p.size() > 3) {
        wchar_t c = p.back();
        if (c == L'\\' || c == L'/' || c == L'"') p.pop_back();
        else break;
    }
    return p;
}

// 从 config.json 内容里找指定游戏的路径数组
// 返回：0=没找到该游戏，1=找到但数组为空，2=找到且有路径
static int ParseGameConfig(const std::string& json, const std::wstring& game,
                           std::vector<std::wstring>& paths)
{
    std::string needle = "\"" + W2U8(game) + "\"";
    size_t k = json.find(needle);
    while (k != std::string::npos) {
        size_t e = k + needle.size();
        while (e < json.size() &&
               (json[e] == ' ' || json[e] == '\t' || json[e] == '\r' || json[e] == '\n')) e++;
        if (e < json.size() && json[e] == ':') break;
        k = json.find(needle, k + 1);
    }
    if (k == std::string::npos) return 0;

    size_t lb = json.find('[', k);
    size_t rb = (lb == std::string::npos) ? std::string::npos : json.find(']', lb);
    if (lb == std::string::npos || rb == std::string::npos) return 0;

    size_t i = lb + 1;
    while (i < rb) {
        if (json[i] == '"') {
            std::string val;
            if (!ParseJsonStringLenient(json, i, val)) return 0;
            paths.push_back(CleanSavePath(U82W(val)));
        } else {
            i++;
        }
    }
    return paths.empty() ? 1 : 2;
}

// 解析 Playday 导出的 games.json：顶层数组，每项形如
//   { "name": "游戏名", ... , "savePaths": ["X:\\...\\*.*", ...] }
// 该导出数据存在坏转义（如 "...*.*\" 把收尾引号转义掉），无法用标准 JSON
// 解析，也不能靠引号状态做结构扫描。所以用「缩进锚点」定位：
// 游戏级字段的缩进正好是 2 个 Tab（\n\t\t"name": "、\n\t\t"savePaths": ），
// 嵌套对象（actions 等）缩进更深，不会误命中。
// 返回：0=没找到该游戏，1=找到但 savePaths 为空，2=找到且有路径
static int ParseGamesJson(const std::string& json, const std::wstring& game,
                          std::vector<std::wstring>& paths)
{
    const std::string nameKey = "\n\t\t\"name\": \"";
    const std::string spKey  = "\n\t\t\"savePaths\"";

    size_t pos = 0;
    while (true) {
        size_t nk = json.find(nameKey, pos);
        if (nk == std::string::npos) return 0;

        // 宽容读取游戏名（值里可能有坏转义）
        size_t vq = nk + nameKey.size() - 1;      // 指向值的开引号
        std::string val;
        size_t i2 = vq;
        if (!ParseJsonStringLenient(json, i2, val)) { pos = nk + 1; continue; }
        pos = i2;
        if (U82W(val) != game) continue;

        // 本对象的 savePaths 必须出现在下一个游戏级 name 锚之前
        size_t limit = json.find(nameKey, i2);
        if (limit == std::string::npos) limit = json.size();
        size_t sk = json.find(spKey, i2);
        if (sk == std::string::npos || sk > limit) return 1;   // 没有该字段 = 空

        size_t lb = json.find('[', sk);
        size_t rb = (lb == std::string::npos) ? std::string::npos : json.find(']', lb);
        if (lb == std::string::npos || rb == std::string::npos) return 1;

        size_t i = lb + 1;
        while (i < rb) {
            while (i < rb && (json[i]==' '||json[i]=='\t'||json[i]=='\r'||json[i]=='\n'||json[i]==',')) i++;
            if (i >= rb || json[i] == ']') break;
            if (json[i] != '"') { i++; continue; }
            std::string v;
            // 限制在数组 ']' 之内扫描；解析不出正常结尾就当作数组到此为止
            if (!ParseJsonStringLenient(json, i, v, rb)) break;
            paths.push_back(CleanSavePath(U82W(v)));
        }
        return paths.empty() ? 1 : 2;
    }
}

// ---------------------------------------------------------------------------
// 程序自带设置（exe 目录下的 settings.json，release 部署时一起带上）：
//   gamesJson : games.json 配置文件路径（读取存档路径用，可配置位置）
//   nsis      : makensis.exe 路径（相对路径则相对本程序目录）
//   outDir    : 备份包默认输出目录（留空 = 桌面）
//   recurse   : 是否递归扫描子目录（"true" / "false"）
// ---------------------------------------------------------------------------
struct AppSettings {
    std::wstring gamesJson;
    std::wstring nsis;
    std::wstring outDir;
    bool recurse = true;
};
static AppSettings g_settings;

// 在 JSON 文本里读指定 key 的字符串值（找 "key" 后跟冒号）
static std::wstring ReadSettingString(const std::string& json, const char* key)
{
    std::string needle = std::string("\"") + key + "\"";
    size_t k = json.find(needle);
    while (k != std::string::npos) {
        size_t colon = json.find(':', k + needle.size());
        if (colon == std::string::npos) return L"";
        size_t e = colon + 1;
        while (e < json.size() && (json[e]==' '||json[e]=='\t'||json[e]=='\r'||json[e]=='\n')) e++;
        if (e < json.size() && json[e] == '"') {
            std::string val;
            size_t i = e;
            ParseJsonStringLenient(json, i, val);
            return U82W(val);
        }
        k = json.find(needle, k + 1);
    }
    return L"";
}

static void LoadAppSettings()
{
    std::wstring f = JoinPath(GetExeDir(), L"settings.json");
    HANDLE h = CreateFileW(f.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                           OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    DWORD sz = GetFileSize(h, nullptr);
    std::string raw((size_t)sz, '\0');
    DWORD rd = 0;
    ReadFile(h, &raw[0], sz, &rd, nullptr);
    CloseHandle(h);
    if (raw.size() >= 3 && (BYTE)raw[0] == 0xEF && (BYTE)raw[1] == 0xBB && (BYTE)raw[2] == 0xBF)
        raw.erase(0, 3);
    g_settings.gamesJson = ReadSettingString(raw, "gamesJson");
    g_settings.nsis      = ReadSettingString(raw, "nsis");
    g_settings.outDir    = ReadSettingString(raw, "outDir");
    std::wstring rec     = ReadSettingString(raw, "recurse");
    if (!rec.empty()) g_settings.recurse = (rec == L"true" || rec == L"1");
}

// 依次在配置候选里找：
//   1) /config: 明确指定的文件（优先，支持两种格式）
//   2) 当前目录\games.json → exe目录\games.json
//   3) 当前目录\config.json → exe目录\config.json
//   4) 内置兜底：Playday 导出的 games.json
// 格式按内容自动识别：'[' 开头 = games.json 数组格式，'{' 开头 = config.json 格式
// 返回：0=所有候选里都没找到该游戏，1=找到但配置为空，2=找到且有路径
static int LoadConfigPaths(const std::wstring& game,
                           std::vector<std::wstring>& paths, std::wstring& usedFile,
                           const std::wstring& explicitFile = L"")
{
    std::vector<std::wstring> cands;
    if (!explicitFile.empty()) {
        cands.push_back(explicitFile);
    } else {
        wchar_t cur[MAX_PATH] = { 0 };
        GetCurrentDirectoryW(MAX_PATH, cur);
        cands = {
            JoinPath(cur, L"games.json"),
            JoinPath(GetExeDir(), L"games.json"),
            JoinPath(cur, L"config.json"),
            JoinPath(GetExeDir(), L"config.json"),
        };
        // settings.json 里配置的 games.json 路径优先于内置兜底
        if (!g_settings.gamesJson.empty()) cands.push_back(g_settings.gamesJson);
        cands.push_back(L"D:\\AI\\Code\\Playnite\\Playday\\games.json");
    }
    for (auto& c : cands) {
        HANDLE h = CreateFileW(c.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h == INVALID_HANDLE_VALUE) continue;
        DWORD sz = GetFileSize(h, nullptr);
        std::string raw((size_t)sz, '\0');
        DWORD rd = 0;
        ReadFile(h, &raw[0], sz, &rd, nullptr);
        CloseHandle(h);
        if (raw.size() >= 3 && (BYTE)raw[0] == 0xEF && (BYTE)raw[1] == 0xBB && (BYTE)raw[2] == 0xBF)
            raw.erase(0, 3);
        // 跳过前导空白，按第一个字符判断格式
        size_t p = raw.find_first_not_of(" \t\r\n");
        int r = 0;
        if (p != std::string::npos && raw[p] == '[')
            r = ParseGamesJson(raw, game, paths);
        else
            r = ParseGameConfig(raw, game, paths);
        if (r == 2) { usedFile = c; return 2; }
        if (r == 1) { usedFile = c; return 1; }   // 找到但为空：不再往下找
        // 0 = 这个文件里没有该游戏，继续下一个候选
    }
    return 0;
}

// ---------------------------------------------------------------------------
// 数据模型
// ---------------------------------------------------------------------------
struct Part {
    std::wstring dir;       // 去掉通配符后的目录
    std::wstring pattern;   // 通配符
    std::wstring search;    // dir + "\" + pattern
    std::wstring subName;   // 导出到别处时用的子目录名
    int          count = 0;
    ULONGLONG    size = 0;
};

struct Job {
    std::wstring        gameName;
    std::vector<Part>   parts;
    std::wstring        outDir;
    bool                recurse = true;
};

struct Outcome {
    bool        ok = false;
    std::wstring header;    // 状态标题（顶部彩色大字，如「备份成功」）
    std::wstring text;      // 一句话结论
    std::wstring detail;    // 多行日志
    std::wstring exePath;
};

// ---------------------------------------------------------------------------
// 文件枚举（递归，支持通配符）
// ---------------------------------------------------------------------------
struct EnumResult {
    int        count = 0;
    ULONGLONG  size = 0;
};

static void EnumFiles(const std::wstring& dir, const std::wstring& pattern,
                      bool recurse, EnumResult& er)
{
    WIN32_FIND_DATAW fd{};
    HANDLE h = FindFirstFileW((dir + L"\\" + pattern).c_str(), &fd);
    if (h != INVALID_HANDLE_VALUE) {
        do {
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            er.size += ((ULONGLONG)fd.nFileSizeHigh << 32) | fd.nFileSizeLow;
            er.count++;
        } while (FindNextFileW(h, &fd));
        FindClose(h);
    }
    if (!recurse) return;

    HANDLE hd = FindFirstFileW((dir + L"\\*").c_str(), &fd);
    if (hd == INVALID_HANDLE_VALUE) return;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (fd.cFileName[0] == L'.' &&
            (fd.cFileName[1] == L'\0' || (fd.cFileName[1] == L'.' && fd.cFileName[2] == L'\0')))
            continue;
        EnumFiles(dir + L"\\" + fd.cFileName, pattern, true, er);
    } while (FindNextFileW(hd, &fd));
    FindClose(hd);
}

// 把 "D:\a\b\*.*" 拆成 dir="D:\a\b" pattern="*.*"；没有通配符就整体当目录
static void SplitPathSpec(const std::wstring& in, std::wstring& dir, std::wstring& pattern)
{
    size_t pos = in.find_last_of(L"\\/");
    std::wstring leaf = (pos != std::wstring::npos) ? in.substr(pos + 1) : in;
    dir = (pos != std::wstring::npos) ? in.substr(0, pos) : L".";
    if (leaf.find_first_of(L"*?") != std::wstring::npos) {
        pattern = leaf;
    } else {
        dir = in;                       // 整个参数就是目录
        pattern = L"*.*";
    }
    while (dir.size() > 3 && dir.back() == L'\\') dir.pop_back();
    if (dir.size() == 2 && dir[1] == L':') dir += L"\\";
}

// ---------------------------------------------------------------------------
// 找 makensis.exe
// ---------------------------------------------------------------------------
static bool FindMakeNsis(std::wstring& out)
{
    std::wstring exeDir = GetExeDir();
    std::vector<std::wstring> cands;
    // settings.json 里配置的 nsis 路径最优先（相对路径则相对本程序目录）
    if (!g_settings.nsis.empty()) {
        std::wstring n = g_settings.nsis;
        if (n.find(L':') == std::wstring::npos &&
            n.find_first_of(L"\\/") != 0)
            n = JoinPath(exeDir, n);
        cands.push_back(n);
    }
    cands.push_back(JoinPath(exeDir, L"nsis\\makensis.exe"));
    cands.push_back(JoinPath(exeDir, L"makensis.exe"));
    cands.push_back(L"C:\\Program Files (x86)\\NSIS\\makensis.exe");
    cands.push_back(L"C:\\Program Files\\NSIS\\makensis.exe");
    // 注册表里登记的 NSIS 安装路径
    HKEY hk = nullptr;
    if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, L"SOFTWARE\\NSIS", 0, KEY_READ | KEY_WOW64_32KEY, &hk) == ERROR_SUCCESS) {
        wchar_t buf[MAX_PATH] = { 0 };
        DWORD sz = sizeof(buf);
        if (RegQueryValueExW(hk, nullptr, nullptr, nullptr, (LPBYTE)buf, &sz) == ERROR_SUCCESS)
            cands.push_back(JoinPath(buf, L"makensis.exe"));
        RegCloseKey(hk);
    }
    for (auto& c : cands) {
        if (FileExistsW(c)) { out = c; return true; }
    }
    // PATH 里找
    wchar_t buf[MAX_PATH];
    if (SearchPathW(nullptr, L"makensis.exe", nullptr, MAX_PATH, buf, nullptr)) {
        out = buf; return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// 读模板：优先 exe 同目录的 template\GameSaveHelper.nsi，否则用内嵌资源
// ---------------------------------------------------------------------------
static bool LoadTemplate(std::string& out, std::wstring& usedPath)
{
    std::wstring ext = JoinPath(GetExeDir(), L"template\\GameSaveHelper.nsi");
    if (FileExistsW(ext)) {
        HANDLE h = CreateFileW(ext.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h != INVALID_HANDLE_VALUE) {
            DWORD sz = GetFileSize(h, nullptr);
            std::string raw((size_t)sz, '\0');
            DWORD read = 0;
            ReadFile(h, &raw[0], sz, &read, nullptr);
            CloseHandle(h);
            if (raw.size() >= 3 && (BYTE)raw[0] == 0xEF && (BYTE)raw[1] == 0xBB && (BYTE)raw[2] == 0xBF)
                raw.erase(0, 3);
            out = raw; usedPath = ext; return true;
        }
    }
    HRSRC hr = FindResourceW(g_inst, MAKEINTRESOURCEW(IDR_TEMPLATE), RT_RCDATA);
    if (!hr) return false;
    HGLOBAL hg = LoadResource(g_inst, hr);
    if (!hg) return false;
    DWORD sz = SizeofResource(g_inst, hr);
    const char* p = (const char*)LockResource(hg);
    if (!p) return false;
    std::string raw(p, (size_t)sz);
    if (raw.size() >= 3 && (BYTE)raw[0] == 0xEF && (BYTE)raw[1] == 0xBB && (BYTE)raw[2] == 0xBF)
        raw.erase(0, 3);
    out = raw; usedPath = L"(内置模板)";
    return true;
}

// ---------------------------------------------------------------------------
// 核心：生成 NSI + 调 makensis
// ---------------------------------------------------------------------------
static void ReplaceAll(std::string& s, const std::string& from, const std::string& to)
{
    size_t pos = 0;
    while ((pos = s.find(from, pos)) != std::string::npos) {
        s.replace(pos, from.size(), to);
        pos += to.size();
    }
}

typedef std::function<void(const std::wstring&)> ProgressFn;

static Outcome RunJob(const Job& job, const ProgressFn& progress = {})
{
    Outcome oc;

    if (job.gameName.empty()) { oc.header = L"备份失败"; oc.text = L"没有游戏名称。"; return oc; }
    if (job.parts.empty())    { oc.header = L"备份失败"; oc.text = L"没有要备份的位置。"; return oc; }

    std::wstring log;
    auto logLine = [&log](const std::wstring& s) { log += s; log += L"\r\n"; };

    // 1. 逐位置扫描：目录不存在 / 空目录的位置记为警告并跳过，
    //    只要有一个位置有文件就继续；全部位置都没文件才中止
    std::vector<Part> parts = job.parts;
    std::vector<Part> used;                  // 实际有文件、参与打包的位置
    std::vector<std::wstring> errs;          // 全部无效时的原因列表
    std::vector<std::wstring> warns;         // 跳过的位置（出现在结果详情里）
    ULONGLONG totalSize = 0; int totalFiles = 0;
    int nPos = (int)parts.size();
    for (int i = 0; i < nPos; i++) {
        auto& p = parts[i];
        if (progress)
            progress(L"正在扫描位置 " + std::to_wstring(i + 1) + L"/" +
                     std::to_wstring(nPos) + L"：" + p.search);
        if (GetFileAttributesW(p.dir.c_str()) == INVALID_FILE_ATTRIBUTES) {
            warns.push_back(L"[位置" + std::to_wstring(i + 1) + L"] 目录不存在：" + p.search);
            errs.push_back(L"[位置" + std::to_wstring(i + 1) + L"] 目录不存在：" + p.search);
            continue;
        }
        EnumResult er;
        EnumFiles(p.dir, p.pattern, job.recurse, er);
        p.size = er.size; p.count = er.count;
        logLine(L"  " + p.search + L"  ->  " + std::to_wstring(er.count) + L" 个文件, " + FormatSize(er.size));
        if (er.count == 0) {
            warns.push_back(L"[位置" + std::to_wstring(i + 1) + L"] 没有匹配到任何文件（空目录）：" + p.search);
            errs.push_back(L"[位置" + std::to_wstring(i + 1) + L"] 没有匹配到任何文件：" + p.search);
            continue;
        }
        used.push_back(p);
        totalSize += er.size; totalFiles += er.count;
    }

    parts = used;
    if (parts.empty()) {
        std::wstring all;
        for (auto& e : errs) { all += e; all += L"\n"; }
        oc.header = L"备份失败，没有存档或者存档被锁定了";
        oc.text = all;
        oc.detail = log;
        return oc;
    }

    if (progress)
        progress(L"共 " + std::to_wstring(totalFiles) + L" 个文件（" + FormatSize(totalSize) +
                 L"），正在生成安装脚本...");

    // 2. 输出文件名：存档备份【游戏名】_时间（精确到秒）；默认放系统桌面
    SYSTEMTIME st{}; GetLocalTime(&st);
    wchar_t stamp[64], human[64];
    swprintf_s(stamp, L"%04d%02d%02d_%02d%02d%02d", st.wYear, st.wMonth, st.wDay,
               st.wHour, st.wMinute, st.wSecond);
    swprintf_s(human, L"%04d-%02d-%02d %02d:%02d:%02d", st.wYear, st.wMonth, st.wDay,
               st.wHour, st.wMinute, st.wSecond);

    std::wstring outDir = !job.outDir.empty() ? job.outDir
                        : (!g_settings.outDir.empty() ? g_settings.outDir
                                                      : GetDesktopDir());
    DWORD mkAttr = GetFileAttributesW(outDir.c_str());
    if (mkAttr == INVALID_FILE_ATTRIBUTES) CreateDirectoryW(outDir.c_str(), nullptr);
    std::wstring exePath = JoinPath(outDir,
                             L"存档备份【" + SanitizeFileName(job.gameName) + L"】_" + stamp + L".exe");

    // 3. 找 makensis
    std::wstring makensis;
    if (!FindMakeNsis(makensis)) {
        oc.header = L"备份失败";
        oc.text = L"没找到 makensis.exe。请把 NSIS 放到本程序目录下的 nsis\\ 文件夹里。";
        oc.detail = log;
        return oc;
    }
    std::wstring nsisHome = makensis.substr(0, makensis.find_last_of(L"\\/"));

    // 4. 生成 NSI
    std::string tmpl; std::wstring tmplUsed;
    if (!LoadTemplate(tmpl, tmplUsed)) {
        oc.header = L"备份失败";
        oc.text = L"模板加载失败。";
        oc.detail = log;
        return oc;
    }

    std::string sVars, sInit, sCreate, sLeave, sOver, sRestore, sRaise;
    int n = (int)parts.size();
    for (int i = 0; i < n; i++) {
        const Part& p = parts[i];
        char idx[16]; sprintf_s(idx, "%d", i);
        std::string I(idx);
        int y = 112 + i * 16;
        char ys[16]; sprintf_s(ys, "%d", y);

        sVars    += "Var P" + I + "\r\nVar E" + I + "\r\nVar B" + I + "\r\n";
        sInit    += "  StrCpy $P" + I + " \"" + W2U8(NsisEsc(p.dir)) + "\"\r\n";

        sCreate  += "  ${NSD_CreateText} 4% " + std::string(ys) + "u 74% 13u \"$P" + I + "\"\r\n";
        sCreate  += "  Pop $E" + I + "\r\n";
        sCreate  += "  SetCtlColors $E" + I + " ${CLR_TEXT} ${CLR_EDITBG}\r\n";
        sCreate  += "  ${NSD_CreateBrowseButton} 80% " + std::string(ys) + "u 20% 13u \"浏览\"\r\n";
        sCreate  += "  Pop $B" + I + "\r\n";
        sCreate  += "  ${NSD_OnClick} $B" + I + " OnBrowse\r\n";

        sLeave   += "  ${NSD_GetText} $E" + I + " $P" + I + "\r\n";

        sOver    += "  IfFileExists \"$P" + I + "\\*.*\" 0 +2\r\n";
        sOver    += "  StrCpy $OVERLIST \"$OVERLIST  • $P" + I + "$\\r$\\n\"\r\n";

        std::string rec = job.recurse ? "/r " : "";
        sRestore += "  SetOutPath \"$PLUGINSDIR\\p" + I + "\"\r\n";
        sRestore += "  File " + rec + "\"" + W2U8(NsisEsc(p.search)) + "\"\r\n";
        sRestore += "  CreateDirectory \"$P" + I + "\"\r\n";
        sRestore += "  ClearErrors\r\n";
        sRestore += "  CopyFiles /SILENT \"$PLUGINSDIR\\p" + I + "\\*.*\" \"$P" + I + "\"\r\n";
        sRestore += "  ${If} ${Errors}\r\n";
        sRestore += "    IntOp $FAIL $FAIL + 1\r\n";
        sRestore += "    StrCpy $REPORT \"$REPORT[失败] $P" + I + "$\\r$\\n\"\r\n";
        sRestore += "  ${Else}\r\n";
        sRestore += "    IntOp $OK $OK + 1\r\n";
        sRestore += "    StrCpy $REPORT \"$REPORT[完成] $P" + I + "$\\r$\\n\"\r\n";
        sRestore += "  ${EndIf}\r\n";
        // 每个输入框/浏览按钮在铺底后要显式提回最上层（防止被整页底色盖住）
        sRaise   += "  System::Call \"user32::BringWindowToTop(p $E" + I + ")\"\r\n";
        sRaise   += "  System::Call \"user32::BringWindowToTop(p $B" + I + ")\"\r\n";
    }

    int tipY = 112 + n * 16 + 6;
    char bandY[16]; sprintf_s(bandY, "%d", tipY + 24);
    char btnY[16];  sprintf_s(btnY,  "%d", tipY + 30);
    char tipS[16]; sprintf_s(tipS, "%d", tipY);

    // 图标：优先 assets\icon.ico，其次 NSIS 自带（用 NSIS 原生 Icon 命令，
    // 模板没引 MUI2，写 !define MUI_ICON 是不生效的）
    std::string iconLine = "; (无图标)";
    std::wstring icon1 = JoinPath(GetExeDir(), L"assets\\icon.ico");
    std::wstring icon2 = JoinPath(nsisHome, L"Contrib\\Graphics\\Icons\\modern-install.ico");
    if (FileExistsW(icon1))      iconLine = "Icon \"" + W2U8(NsisEsc(icon1)) + "\"";
    else if (FileExistsW(icon2)) iconLine = "Icon \"" + W2U8(NsisEsc(icon2)) + "\"";

    ReplaceAll(tmpl, "@@BUILD_TIME@@",    W2U8(human));
    ReplaceAll(tmpl, "@@PRODUCT_NAME@@",  W2U8(NsisEsc(job.gameName)));
    ReplaceAll(tmpl, "@@BACKUP_TIME@@",   W2U8(human));
    ReplaceAll(tmpl, "@@BACKUP_STAMP@@",  W2U8(stamp));
    ReplaceAll(tmpl, "@@TOTAL_FILES@@",   W2U8(std::to_wstring(totalFiles)));
    ReplaceAll(tmpl, "@@TOTAL_SIZE@@",    W2U8(FormatSize(totalSize)));
    ReplaceAll(tmpl, "@@PART_COUNT@@",    W2U8(std::to_wstring(n)));
    ReplaceAll(tmpl, "@@OUT_FILE@@",      W2U8(NsisEsc(exePath)));
    ReplaceAll(tmpl, "@@ICON_LINE@@",     iconLine);
    ReplaceAll(tmpl, "@@PART_VARS@@",     sVars);
    ReplaceAll(tmpl, "@@PART_INIT@@",     sInit);
    ReplaceAll(tmpl, "@@PART_CREATE@@",   sCreate);
    ReplaceAll(tmpl, "@@PART_RAISE@@",    sRaise);
    ReplaceAll(tmpl, "@@PART_LEAVE@@",    sLeave);
    ReplaceAll(tmpl, "@@PART_OVERWRITE@@",sOver);
    ReplaceAll(tmpl, "@@PART_RESTORE@@",  sRestore);
    ReplaceAll(tmpl, "@@TIP_Y@@",         tipS);
    ReplaceAll(tmpl, "@@BAND_Y@@",        bandY);
    ReplaceAll(tmpl, "@@BTN_Y@@",         btnY);

    std::wstring buildDir = JoinPath(GetExeDir(), L"build");
    CreateDirectoryW(buildDir.c_str(), nullptr);
    std::wstring nsiPath = JoinPath(buildDir, SanitizeFileName(job.gameName) + L".nsi");

    {
        std::string bom = "\xEF\xBB\xBF";
        HANDLE h = CreateFileW(nsiPath.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS,
                               FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h == INVALID_HANDLE_VALUE) { oc.header = L"备份失败"; oc.text = L"无法写入脚本文件。"; return oc; }
        DWORD w = 0;
        WriteFile(h, bom.data(), 3, &w, nullptr);
        WriteFile(h, tmpl.data(), (DWORD)tmpl.size(), &w, nullptr);
        CloseHandle(h);
    }

    // 5. 编译
    DeleteFileW(exePath.c_str());
    if (progress) progress(L"正在编译备份包，可能需要几秒钟...");

    std::wstring logFile = JoinPath(buildDir, L"makensis.log");
    std::wstring cmd = L"\"" + makensis + L"\" /V2 \"" + nsiPath + L"\"";

    SECURITY_ATTRIBUTES sa{ sizeof(sa), nullptr, TRUE };
    HANDLE hLog = CreateFileW(logFile.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa,
                              CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    STARTUPINFOW si{ sizeof(si) };
    PROCESS_INFORMATION pi{};
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdOutput = hLog;
    si.hStdError = hLog;

    BOOL started = CreateProcessW(nullptr, &cmd[0], nullptr, nullptr, TRUE,
                                  CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                                  nullptr, nsisHome.c_str(), &si, &pi);
    DWORD code = 1;
    if (started) {
        WaitForSingleObject(pi.hProcess, INFINITE);
        GetExitCodeProcess(pi.hProcess, &code);
        CloseHandle(pi.hThread);
        CloseHandle(pi.hProcess);
    }
    CloseHandle(hLog);

    std::string compilerOut;
    {
        HANDLE h = CreateFileW(logFile.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr,
                               OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (h != INVALID_HANDLE_VALUE) {
            DWORD sz = GetFileSize(h, nullptr);
            std::string raw((size_t)sz, '\0');
            DWORD rd = 0; ReadFile(h, &raw[0], sz, &rd, nullptr);
            CloseHandle(h);
            compilerOut = raw;
        }
    }

    if (!started || code != 0 || !FileExistsW(exePath.c_str())) {
        logLine(L"编译失败（退出码 " + std::to_wstring(code) + L"），脚本保留在：");
        logLine(L"  " + nsiPath);
        oc.header = L"备份失败";
        oc.text = L"编译失败。";
        oc.detail = log + L"\r\n" + U82W(compilerOut);
        return oc;
    }

    // 6. 成功：显示备份文件信息 + 恢复路径 + 使用方法
    ULONGLONG exeSize = 0;
    {
        WIN32_FILE_ATTRIBUTE_DATA fad{};
        if (GetFileAttributesExW(exePath.c_str(), GetFileExInfoStandard, &fad))
            exeSize = ((ULONGLONG)fad.nFileSizeHigh << 32) | fad.nFileSizeLow;
    }

    logLine(L"");
    logLine(L"备份文件：" + exePath);
    logLine(L"文件大小：" + FormatSize(exeSize) + L" · 备份时间：" + human);
    logLine(L"");
    logLine(L"恢复路径（双击备份包可一键恢复到以下位置）：");
    for (const auto& p : parts)
        logLine(L"  · " + p.dir);
    if (!warns.empty()) {
        logLine(L"");
        logLine(L"以下位置没有文件，已跳过：");
        for (const auto& w : warns)
            logLine(L"  · " + w);
    }
    logLine(L"");
    logLine(L"使用方法：");
    logLine(L"  1. 把备份文件保存到网盘、U盘或微信/QQ，即可带走存档");
    logLine(L"  2. 把备份拷回电脑，双击后点「恢复存档」即可一键还原");
    logLine(L"  3. 微信传输会在文件末尾追加 .tmp，删除这 4 个字符即可使用");

    oc.ok = true;
    oc.exePath = exePath;
    oc.header = L"备份成功";
    oc.detail = log;
    return oc;
}

// ---------------------------------------------------------------------------
// 主窗口
// ---------------------------------------------------------------------------
static HWND g_hwnd = nullptr;
static HWND g_lblStatus = nullptr, g_textBox = nullptr;
static HWND g_btnOpen = nullptr, g_btnClose = nullptr, g_prog = nullptr;
static std::wstring g_lastLog;

// 日志文件：<exe目录>\logs\GameSaveHelper.log —— 详细信息都写这里
static std::wstring LogFilePath()
{
    std::wstring d = JoinPath(GetExeDir(), L"logs");
    CreateDirectoryW(d.c_str(), nullptr);
    return JoinPath(d, L"GameSaveHelper.log");
}

static void AppendLog(const std::wstring& title, const std::wstring& body)
{
    HANDLE h = CreateFileW(LogFilePath().c_str(), FILE_APPEND_DATA, FILE_SHARE_READ,
                           nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (h == INVALID_HANDLE_VALUE) return;
    // 首次创建时补 UTF-8 BOM，记事本才认得
    DWORD sz = GetFileSize(h, nullptr);
    std::wstring text;
    if (sz == 0) text += L"\xFEFF";
    SYSTEMTIME st{}; GetLocalTime(&st);
    wchar_t ts[64];
    swprintf_s(ts, L"[%04d-%02d-%02d %02d:%02d:%02d] ", st.wYear, st.wMonth, st.wDay,
               st.wHour, st.wMinute, st.wSecond);
    text += std::wstring(ts) + title + L"\r\n" + body + L"\r\n\r\n";
    std::string u8 = W2U8(text);
    DWORD w = 0;
    WriteFile(h, u8.data(), (DWORD)u8.size(), &w, nullptr);
    CloseHandle(h);
}

// 往窗口文字区追加一行，并自动滚到最下面
static void AppendLine(const std::wstring& s)
{
    g_text += s;
    g_text += L"\r\n";
    SetWindowTextW(g_textBox, g_text.c_str());
    int len = GetWindowTextLengthW(g_textBox);
    SendMessageW(g_textBox, EM_SETSEL, len, len);
    SendMessageW(g_textBox, EM_SCROLLCARET, 0, 0);
}

static std::wstring SepLine() { return std::wstring(75, L'='); }

// 设置顶部状态标题（文字 + 颜色）
static void SetStatusHeader(const std::wstring& s, COLORREF color)
{
    g_statusColor = color;
    SetWindowTextW(g_lblStatus, s.c_str());
    InvalidateRect(g_lblStatus, nullptr, TRUE);
}

// 成功/失败后统一的收尾：换状态标题、显示结果文字、启用按钮
static void FinishUI(bool ok, const std::wstring& header,
                     const std::wstring& resultText, const std::wstring& detail)
{
    SendMessageW(g_prog, PBM_SETMARQUEE, FALSE, 0);
    ShowWindow(g_prog, SW_HIDE);
    g_busy = false;
    EnableWindow(g_btnClose, TRUE);
    EnableWindow(g_btnOpen, ok ? TRUE : FALSE);
    SetWindowTextW(g_btnOpen, ok ? g_openLabel.c_str() : L"查看日志");

    SetStatusHeader(header, ok ? CLR_OK : CLR_BAD);

    if (ok) {
        // 成功：把备份文件信息、恢复路径、使用方法追加到详情区
        AppendLine(L"");
        AppendLine(detail);
    } else {
        // 失败原因逐行显示（text 里可能有多行）
        AppendLine(L"");
        size_t pos = 0;
        std::wstring t = resultText;
        while (pos < t.size()) {
            size_t nl = t.find(L'\n', pos);
            if (nl == std::wstring::npos) nl = t.size();
            std::wstring line = t.substr(pos, nl - pos);
            if (!line.empty() && line.back() == L'\r') line.pop_back();
            if (!line.empty()) AppendLine(line);
            pos = nl + 1;
        }
        AppendLine(L"详情日志：" + LogFilePath());
    }

    AppendLog(ok ? L"生成成功" : L"备份失败",
              header + L"\r\n" + resultText + (detail.empty() ? L"" : (L"\r\n" + detail)));
}

// 开始备份：锁按钮、显示进度条、后台线程跑
static void StartRun(HWND hwnd, const Job& job)
{
    g_busy = true;
    EnableWindow(g_btnClose, FALSE);
    EnableWindow(g_btnOpen, FALSE);
    ShowWindow(g_prog, SW_SHOW);
    SendMessageW(g_prog, PBM_SETMARQUEE, TRUE, 40);

    // 后台线程跑，界面不卡；进度实时回传
    std::thread([job, hwnd]() {
        ProgressFn progress = [hwnd](const std::wstring& s) {
            PostMessageW(hwnd, WM_APP + 2, 0, (LPARAM)(new std::wstring(s)));
        };
        Outcome oc = RunJob(job, progress);
        PostMessageW(hwnd, WM_APP + 1, 0, (LPARAM)new Outcome(oc));
    }).detach();
}

static LRESULT CALLBACK WndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE: {
        // 顶部状态标题（进行中蓝 / 成功绿 / 失败红）
        g_lblStatus = CreateWindowW(L"STATIC", L"",
                                WS_CHILD | WS_VISIBLE | SS_LEFT,
                                S(24), S(20), S(592), S(32), hwnd,
                                (HMENU)(INT_PTR)IDC_STATUS, g_inst, nullptr);
        SendMessageW(g_lblStatus, WM_SETFONT, (WPARAM)g_fontStatus, TRUE);

        // 正文区：只读多行编辑框，浅灰卡片、无边框
        g_textBox = CreateWindowExW(0, L"EDIT", L"",
                                WS_CHILD | WS_VISIBLE | WS_VSCROLL |
                                ES_MULTILINE | ES_READONLY | ES_AUTOVSCROLL,
                                S(24), S(62), S(592), S(268), hwnd,
                                (HMENU)(INT_PTR)IDC_TEXT, g_inst, nullptr);
        SendMessageW(g_textBox, WM_SETFONT, (WPARAM)g_fontUI, TRUE);

        // 进度条：备份进行中才显示
        g_prog = CreateWindowW(PROGRESS_CLASSW, L"",
                               WS_CHILD | PBS_MARQUEE | PBS_SMOOTH,
                               S(24), S(338), S(592), S(6), hwnd,
                               (HMENU)(INT_PTR)IDC_PROGRESS, g_inst, nullptr);
        ShowWindow(g_prog, SW_HIDE);

        // 按钮：「显示备份后的文件」+「关闭」
        g_btnOpen = CreateWindowW(L"BUTTON", g_openLabel.c_str(),
                                  WS_CHILD | WS_VISIBLE | WS_TABSTOP | WS_DISABLED,
                                  S(450), S(354), S(166), S(32), hwnd,
                                  (HMENU)(INT_PTR)IDC_OPEN, g_inst, nullptr);
        SendMessageW(g_btnOpen, WM_SETFONT, (WPARAM)g_fontUI, TRUE);

        g_btnClose = CreateWindowW(L"BUTTON", L"关闭",
                                   WS_CHILD | WS_VISIBLE | WS_TABSTOP,
                                   S(352), S(354), S(90), S(32), hwnd,
                                   (HMENU)(INT_PTR)IDC_CLOSE, g_inst, nullptr);
        SendMessageW(g_btnClose, WM_SETFONT, (WPARAM)g_fontUI, TRUE);
        return 0;
    }

    case WM_ERASEBKGND: {
        RECT rc; GetClientRect(hwnd, &rc);
        FillRect((HDC)wp, &rc, (HBRUSH)GetStockObject(WHITE_BRUSH));
        return 1;
    }

    // 颜色处理：正文编辑框浅灰底深字；状态标题用当前状态色；其余白底
    case WM_CTLCOLORSTATIC:
        if ((HWND)lp == g_textBox) {
            HDC hdc = (HDC)wp;
            SetBkColor(hdc, CLR_CARD);
            SetTextColor(hdc, CLR_INK);
            return (LRESULT)g_brushCard;
        }
        if ((HWND)lp == g_lblStatus) {
            HDC hdc = (HDC)wp;
            SetBkMode(hdc, TRANSPARENT);
            SetTextColor(hdc, g_statusColor);
            return (LRESULT)GetStockObject(WHITE_BRUSH);
        }
        SetBkMode((HDC)wp, TRANSPARENT);
        SetTextColor((HDC)wp, CLR_INK);
        return (LRESULT)GetStockObject(WHITE_BRUSH);

    case WM_COMMAND:
        switch (LOWORD(wp)) {
        case IDC_CLOSE:
            if (!g_busy) PostMessageW(hwnd, WM_CLOSE, 0, 0);
            return 0;
        case IDC_OPEN: {
            if (!g_lastExe.empty()) {
                // 打开备份所在目录并定位（选中）到备份包文件
                std::wstring param = L"/select,\"" + g_lastExe + L"\"";
                ShellExecuteW(hwnd, L"open", L"explorer.exe", param.c_str(), nullptr, SW_SHOW);
            } else {
                // 失败后点这里 = 用记事本打开日志
                ShellExecuteW(hwnd, L"open", LogFilePath().c_str(), nullptr, nullptr, SW_SHOW);
            }
            return 0;
        }
        }
        break;

    case WM_CLOSE:
        if (g_busy) return 0;   // 备份进行中不允许关闭（避免 makensis 被中断）
        DestroyWindow(hwnd);
        return 0;

    case WM_APP + 1:
        // 后台线程完成
        {
            Outcome* oc = (Outcome*)lp;
            g_lastExe = oc->exePath;
            g_lastLog = oc->detail;
            FinishUI(oc->ok,
                     oc->header.empty() ? (oc->ok ? L"备份成功" : L"备份失败") : oc->header,
                     oc->text, oc->detail);
            delete oc;
        }
        return 0;

    case WM_APP + 2: {   // 进度文本（后台线程 PostMessage 回传）
        std::wstring* s = (std::wstring*)lp;
        AppendLine(*s);
        delete s;
        return 0;
    }

    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

// ---------------------------------------------------------------------------
// 入口
// ---------------------------------------------------------------------------
int WINAPI wWinMain(HINSTANCE hInst, HINSTANCE, PWSTR, int)
{
    g_inst = hInst;
    CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE);

    // 高 DPI（PER_MONITOR_AWARE_V2 = (HANDLE)-4）
    if (HMODULE u = LoadLibraryW(L"user32.dll")) {
        typedef BOOL(WINAPI* PFN)(HANDLE);
        auto pfn = (PFN)GetProcAddress(u, "SetProcessDpiAwarenessContext");
        if (pfn) pfn((HANDLE)(INT_PTR)-4);
        FreeLibrary(u);
    }
    HDC hdc = GetDC(nullptr);
    g_dpi = GetDeviceCaps(hdc, LOGPIXELSY);
    ReleaseDC(nullptr, hdc);
    if (g_dpi < 96) g_dpi = 96;

    INITCOMMONCONTROLSEX icc{ sizeof(icc), ICC_STANDARD_CLASSES | ICC_PROGRESS_CLASS };
    InitCommonControlsEx(&icc);

    // 读取程序设置（exe 目录下的 settings.json；没有就用默认值）
    LoadAppSettings();

    g_fontUI = CreateFontW(-MulDiv(9, g_dpi, 72), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
                           DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                           CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
    g_fontStatus = CreateFontW(-MulDiv(13, g_dpi, 72), 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                               DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                               CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Microsoft YaHei UI");
    g_brushCard = CreateSolidBrush(CLR_CARD);

    // ======================= 命令行解析（严格模式，不做推断） =======================
    // 规则（需求明确）：
    //   无参数                     -> 红底报错「备份失败，参数错误，请联系管理员...」
    //   GameSaveHelper.exe 游戏名   -> 到 当前目录(或exe目录) 的 config.json 里找存档路径配置
    //   GameSaveHelper.exe 游戏名 "路径1" ["路径2"...] -> 用命令行路径打包
    // 第一个参数必须是游戏名（不能是路径、不能是选项），其余非选项参数必须是完整路径
    int argc = 0;
    LPWSTR* argv = CommandLineToArgvW(GetCommandLineW(), &argc);

    std::wstring cliName;
    std::vector<std::wstring> cliPaths;
    bool autoStart = false;
    bool quiet = false;
    bool noRecurse = false;
    std::wstring cliOut;
    std::wstring cliConfig;
    std::wstring argError;
    std::wstring configFileUsed;

    // 预扫描 -q/-quiet：这样连参数校验的错误都能走 stderr，脚本才能捕获
    for (int i = 1; i < argc; i++) {
        std::wstring a = argv[i];
        if (a.size() > 1 && (a[0] == L'-' || a[0] == L'/')) {
            std::wstring o = a.substr(1);
            std::transform(o.begin(), o.end(), o.begin(), ::towlower);
            if (o == L"q" || o == L"quiet") quiet = true;
        }
    }

    // 错误报告：写 stderr（脚本可捕获）+ 写日志文件，不弹窗
    auto SayError = [](const std::wstring& msg) {
        std::string u8 = W2U8(msg);
        HANDLE h = GetStdHandle(STD_ERROR_HANDLE);
        if (h && h != INVALID_HANDLE_VALUE) {
            DWORD w = 0;
            WriteFile(h, u8.data(), (DWORD)u8.size(), &w, nullptr);
            WriteFile(h, "\r\n", 2, &w, nullptr);
        }
        AppendLog(L"命令行错误", msg);
    };

    if (argc >= 2) {
        std::wstring first = argv[1];
        // 严格：第一个参数必须是游戏名
        if (first.empty() || first[0] == L'-' || first[0] == L'/' ||
            first.find_first_of(L":\\/") != std::wstring::npos) {
            argError = L"收到的第一个参数不是游戏名称。";
        } else {
            cliName = first;
            for (int i = 2; i < argc; i++) {
                std::wstring a = argv[i];
                bool isOption = a.size() > 1 && (a[0] == L'-' || a[0] == L'/');
                // "/X:盘符..." 形式更像路径（几乎不会这么写选项），当路径处理
                if (isOption && a[0] == L'/' && a.size() > 2 &&
                    iswalpha(a[1]) && a[2] == L':') isOption = false;
                if (isOption) {
                    std::wstring opt = a.substr(1);
                    std::transform(opt.begin(), opt.end(), opt.begin(), ::towlower);
                    if (opt == L"q" || opt == L"quiet")           { quiet = true; continue; }
                    if (opt == L"nr" || opt == L"norecurse")      { noRecurse = true; continue; }
                    if (opt.compare(0, 4, L"out:") == 0)          { cliOut = a.substr(5); continue; }
                    if (opt.compare(0, 7, L"config:") == 0)       { cliConfig = a.substr(8); continue; }
                    argError = L"未知选项：" + a;
                    break;
                }
                // 严格：必须是完整路径（含盘符或分隔符）
                if (a.find_first_of(L":\\/") == std::wstring::npos) {
                    argError = L"路径参数必须是引号包裹的完整路径（收到的是：「" + a + L"」）";
                    break;
                }
                cliPaths.push_back(a);
            }
        }
    }

    // 只有游戏名 -> 从配置文件读取存档路径（games.json / config.json）
    if (argError.empty() && !cliName.empty() && cliPaths.empty()) {
        int cr = LoadConfigPaths(cliName, cliPaths, configFileUsed, cliConfig);
        if (cr == 0) {
            argError = L"在配置文件里找不到游戏「" + cliName + L"」的存档路径配置。"
                       L"\n\n查找顺序：/config: 指定文件 → 当前目录\\games.json → 本程序目录\\games.json"
                       L" → 当前目录\\config.json → 本程序目录\\config.json"
                       L" → D:\\AI\\Code\\Playnite\\Playday\\games.json";
        } else if (cr == 1) {
            argError = L"游戏「" + cliName + L"」的存档配置为空，请联系管理员。";
        }
    }

    autoStart = argError.empty() && !cliName.empty() && !cliPaths.empty();

    // 静默模式下参数错误：错误写 stderr 后直接退出（不弹窗口），返回码 2
    if (quiet && !argError.empty()) {
        SayError(argError);
        LocalFree(argv);
        CoUninitialize();
        return 2;
    }

    // 静默模式：不出窗口，直接干完就退出（方便脚本调用）；
    // 仅在参数完全合法时进入，参数错误仍会弹红底窗口提示
    if (quiet && autoStart) {
        Job job;
        job.gameName = cliName;
        job.recurse = g_settings.recurse && !noRecurse;
        job.outDir = cliOut;      // 空 = 默认放系统桌面
        for (auto& s : cliPaths) {
            Part p;
            SplitPathSpec(s, p.dir, p.pattern);
            p.search = p.dir + L"\\" + p.pattern;
            size_t sp = p.dir.find_last_of(L"\\");
            p.subName = (sp != std::wstring::npos) ? p.dir.substr(sp + 1) : p.dir;
            job.parts.push_back(p);
        }
        Outcome oc = RunJob(job);
        if (!oc.ok) {
            SayError(oc.text + (oc.detail.empty() ? L"" : L"\n\n" + oc.detail));
            LocalFree(argv);
            CoUninitialize();
            return 1;
        }
        AppendLog(L"生成成功（命令行）", oc.text + (oc.detail.empty() ? L"" : L"\r\n" + oc.detail));
        LocalFree(argv);
        CoUninitialize();
        return 0;
    }

    // ---------------- 组装要显示的初始内容 ----------------
    Job g_job{};
    bool hasJob = false;
    std::wstring initHeader;
    COLORREF initColor = CLR_RUN;

    if (!argError.empty()) {
        // 参数错误：红色状态标题 + 用法说明
        initHeader = L"备份失败，参数错误，请联系管理员...";
        initColor = CLR_BAD;
        g_text = argError + L"\r\n\r\n";
        g_text += L"用法：\r\n";
        g_text += L"  GameSaveHelper.exe 游戏名\r\n";
        g_text += L"      从配置文件读取该游戏的存档路径（games.json 优先，可 /config: 指定）\r\n";
        g_text += L"  GameSaveHelper.exe 游戏名 \"D:\\存档目录\\*.*\" [\"更多路径\\*.*\"]\r\n";
        g_text += L"      用命令行指定的路径备份\r\n";
        g_text += L"选项：\r\n";
        g_text += L"  /config:文件路径   指定配置文件（games.json 或 config.json 格式）\r\n";
        g_text += L"  /out:目录          指定备份输出目录（默认桌面）\r\n";
        g_text += L"  /q                 静默模式（脚本调用，不出窗口）\r\n";
        g_text += L"示例：\r\n";
        g_text += L"  GameSaveHelper.exe 大富翁11 \"D:\\games\\Z\\Richman 11\\2074800\\*.*\"\r\n";
        SayError(argError);
    } else if (autoStart) {
        // 参数合法：组装任务，窗口打开后自动开始备份
        g_job.gameName = cliName;
        g_job.recurse = g_settings.recurse && !noRecurse;
        g_job.outDir = cliOut;
        for (auto& s : cliPaths) {
            Part p;
            SplitPathSpec(s, p.dir, p.pattern);
            p.search = p.dir + L"\\" + p.pattern;
            size_t sp = p.dir.find_last_of(L"\\");
            p.subName = (sp != std::wstring::npos) ? p.dir.substr(sp + 1) : p.dir;
            g_job.parts.push_back(p);
        }
        hasJob = true;
        initHeader = L"正在生成备份......";
        initColor = CLR_RUN;
    }

    // 「显示备份后的文件」按钮文字（显示文件名，更直观）
    g_openLabel = L"显示备份后的文件";

    // 窗口标题：像老 bat 一样用「游戏名+存档备份」
    std::wstring caption = cliName.empty() ? L"GameSaveHelper" : (cliName + L"存档备份");

    WNDCLASSEXW wc{ sizeof(wc) };
    wc.lpfnWndProc = WndProc;
    wc.hInstance = hInst;
    wc.hCursor = LoadCursor(nullptr, IDC_ARROW);
    wc.hbrBackground = nullptr;
    wc.lpszClassName = L"GameSaveHelperWnd";
    wc.hIcon = LoadIconW(hInst, MAKEINTRESOURCEW(IDI_APPICON));
    RegisterClassExW(&wc);

    // 按客户区 640 x 400 精确算窗口大小
    RECT rc{ 0, 0, S(640), S(400) };
    AdjustWindowRect(&rc, WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX, FALSE);
    int wndW = rc.right - rc.left, wndH = rc.bottom - rc.top;

    // 窗口屏幕居中（按工作区，避开任务栏）
    RECT wa{};
    SystemParametersInfoW(SPI_GETWORKAREA, 0, &wa, 0);
    int posX = (wa.right - wa.left - wndW) / 2 + wa.left;
    int posY = (wa.bottom - wa.top - wndH) / 3 + wa.top;
    if (posX < wa.left) posX = wa.left;
    if (posY < wa.top)  posY = wa.top;

    g_hwnd = CreateWindowExW(0, L"GameSaveHelperWnd", caption.c_str(),
                             WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
                             posX, posY, wndW, wndH,
                             nullptr, nullptr, hInst, nullptr);

    ShowWindow(g_hwnd, SW_SHOW);
    UpdateWindow(g_hwnd);

    // 设置初始状态标题
    SetStatusHeader(initHeader.empty() ? L"" : initHeader, initColor);

    // 初始文字一次性灌进编辑框
    SetWindowTextW(g_textBox, g_text.c_str());
    int len = GetWindowTextLengthW(g_textBox);
    SendMessageW(g_textBox, EM_SETSEL, len, len);
    SendMessageW(g_textBox, EM_SCROLLCARET, 0, 0);

    if (hasJob) StartRun(g_hwnd, g_job);

    MSG msg;
    while (GetMessageW(&msg, nullptr, 0, 0) > 0) {
        if (!IsDialogMessageW(g_hwnd, &msg)) {
            TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    }

    LocalFree(argv);
    CoUninitialize();
    return 0;
}
