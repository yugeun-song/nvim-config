// windows_wsl_bridge: bridges host Windows Neovim/Neovide to Neovim inside WSL without a shell, without TCP, and
// with verified process/pipe identities. lua/features/util/windows/wsl_bridge.lua builds it on Windows only.
//
//   windows_wsl_bridge version
//   windows_wsl_bridge -v | --version | --embed [...]          (launched by neovide.exe as --neovim-bin)
//   windows_wsl_bridge run-tui DISTRO DIR WSL_NVIM HOST_NVIM [-- FILES...]
//   windows_wsl_bridge spawn-console HOST_NVIM SCRIPT_LUA ...  (detached console fallback when wt.exe is absent)
//
// Style: native/.clang-format. Tests: tests/windows_wsl_bridge/.

// Native x86_64 Windows only: stop before any Windows header is read.
#if defined(__APPLE__)
#error "windows_wsl_bridge is a Windows program; this is a macOS target."
#elif defined(__linux__)
#error "windows_wsl_bridge is a Windows program; this is a Linux target."
#elif defined(__CYGWIN__) || defined(__MSYS__)
#error "windows_wsl_bridge is a native Windows program; Cygwin and MSYS emulate Unix."
#elif !defined(_WIN32) || !defined(_WIN64)
#error "windows_wsl_bridge is a 64-bit Windows program; this target is not."
#endif

// ARM64EC defines _M_X64 too.
#if !(defined(_M_X64) || defined(__x86_64__)) || defined(_M_ARM64EC) || defined(_M_ARM64) || defined(__aarch64__)
#error "windows_wsl_bridge targets x86_64 Windows only."
#endif

// Visual Studio's cl (MSVC) builds it. clang targeting the MSVC ABI (clang-cl, clang --target=x86_64-pc-windows-msvc)
// reads it only for the tests' static checks.
#if defined(__MINGW32__) || defined(__MINGW64__)
#error "windows_wsl_bridge: MinGW is not supported; build with Visual Studio's cl."
#elif defined(_MSC_VER) && !defined(__clang__)
#define WINDOWS_WSL_BRIDGE_COMPILER "msvc"
#elif defined(_MSC_VER) && defined(__clang__)
#define WINDOWS_WSL_BRIDGE_COMPILER "clang"
#else
#error "windows_wsl_bridge: unknown compiler; build with Visual Studio's cl."
#endif

#define WIN32_LEAN_AND_MEAN
#define _WIN32_WINNT 0x0A00
#include <windows.h>

#include <bcrypt.h>
#include <fcntl.h>
#include <io.h>
#include <shlobj.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tlhelp32.h>
#include <wchar.h>

// Last, so it retires the unbounded string functions for everything above.
#include <strsafe.h>

#ifdef _MSC_VER
#pragma comment(lib, "advapi32.lib")
#pragma comment(lib, "bcrypt.lib")
#pragma comment(lib, "ole32.lib")
#pragma comment(lib, "shell32.lib")
#pragma comment(lib, "uuid.lib")
#endif

#define EXIT_DONE 0
#define EXIT_FAILED 1
#define EXIT_USAGE 2
#define EXIT_NOT_CALLER 4

#define MAX_LINEAGE 16
#define MAX_DISTRO_CHARS 128
#define MAX_LINUX_PATH_CHARS 4096
#define MAX_WINDOWS_PATH_CHARS (2 * MAX_PATH)
#define MAX_ENV_VALUE_CHARS 4096
#define MAX_BASE64_CHARS 8192
#define COMMAND_LINE_MAX_CHARS 32767
#define PIPE_BUFFER_BYTES 65536
#define RELAY_CHUNK_BYTES 32768
#define CONNECT_TIMEOUT_MS 10000
#define CLEANUP_WAIT_MS 3000
#define STDERR_CAP_BYTES 4096

typedef struct PROCESS_LINK_RECORD
{
    DWORD processId;
    DWORD parentProcessId;
} PROCESS_LINK;

typedef struct RELAY_CONTEXT_RECORD
{
    HANDLE pipe;
    HANDLE wslInWrite;
    HANDLE wslOutRead;
    HANDLE wslErrRead;
    HANDLE stopEvent;
    HANDLE wslOutDoneEvent;
    char stderrTail[STDERR_CAP_BYTES + 1];
    size_t stderrLength;
} RELAY_CONTEXT;

_Success_(return != FALSE) static BOOL
    ReadTokenUser(_In_ HANDLE process, _Outptr_result_maybenull_ PTOKEN_USER *userOut, _Out_ DWORD *sizeOut)
{
    HANDLE token = NULL;
    DWORD needed = 0;
    PTOKEN_USER user = NULL;
    BOOL ok = FALSE;

    *userOut = NULL;
    *sizeOut = 0;
    if (!OpenProcessToken(process, TOKEN_QUERY, &token))
    {
        return FALSE;
    }

    GetTokenInformation(token, TokenUser, NULL, 0, &needed);
    if (needed == 0)
    {
        goto Cleanup;
    }

    user = calloc(1, needed);
    if (user == NULL || !GetTokenInformation(token, TokenUser, user, needed, &needed) || user->User.Sid == NULL ||
        !IsValidSid(user->User.Sid))
    {
        goto Cleanup;
    }

    *userOut = user;
    *sizeOut = needed;
    user = NULL;
    ok = TRUE;

Cleanup:
    if (user != NULL)
    {
        SecureZeroMemory(user, needed);
        free(user);
        user = NULL;
    }

    CloseHandle(token);
    token = NULL;
    return ok;
}

_Success_(return != FALSE) static BOOL
    ReadTokenIntegrityAndAppContainer(_In_ HANDLE process, _Out_ DWORD *integrityRid, _Out_ BOOL *isAppContainer)
{
    HANDLE token = NULL;
    DWORD appContainer = 0;
    DWORD needed = 0;
    PTOKEN_MANDATORY_LABEL label = NULL;
    PUCHAR countPtr = NULL;
    PDWORD ridPtr = NULL;
    BOOL ok = FALSE;

    *integrityRid = 0;
    *isAppContainer = TRUE;
    if (!OpenProcessToken(process, TOKEN_QUERY, &token))
    {
        return FALSE;
    }

    if (!GetTokenInformation(token, TokenIsAppContainer, &appContainer, sizeof(appContainer), &needed))
    {
        goto Cleanup;
    }

    GetTokenInformation(token, TokenIntegrityLevel, NULL, 0, &needed);
    if (needed == 0)
    {
        goto Cleanup;
    }

    label = calloc(1, needed);
    if (label == NULL || !GetTokenInformation(token, TokenIntegrityLevel, label, needed, &needed) ||
        label->Label.Sid == NULL || !IsValidSid(label->Label.Sid))
    {
        goto Cleanup;
    }

    countPtr = GetSidSubAuthorityCount(label->Label.Sid);
    if (countPtr == NULL || *countPtr == 0)
    {
        goto Cleanup;
    }

    ridPtr = GetSidSubAuthority(label->Label.Sid, (DWORD)(*countPtr - 1));
    if (ridPtr == NULL)
    {
        goto Cleanup;
    }

    *integrityRid = *ridPtr;
    *isAppContainer = appContainer != 0;
    ok = TRUE;

Cleanup:
    if (label != NULL)
    {
        SecureZeroMemory(label, needed);
        free(label);
        label = NULL;
    }

    CloseHandle(token);
    token = NULL;
    return ok;
}

_Success_(return != FALSE) static BOOL
    ReadTokenAppContainerSid(_In_ HANDLE process, _Outptr_result_maybenull_ PTOKEN_APPCONTAINER_INFORMATION *infoOut,
                             _Out_ DWORD *sizeOut)
{
    HANDLE token = NULL;
    DWORD needed = 0;
    PTOKEN_APPCONTAINER_INFORMATION info = NULL;
    BOOL ok = FALSE;

    *infoOut = NULL;
    *sizeOut = 0;
    if (!OpenProcessToken(process, TOKEN_QUERY, &token))
    {
        return FALSE;
    }

    GetTokenInformation(token, TokenAppContainerSid, NULL, 0, &needed);
    if (needed == 0)
    {
        goto Cleanup;
    }

    info = calloc(1, needed);
    if (info == NULL || !GetTokenInformation(token, TokenAppContainerSid, info, needed, &needed) ||
        info->TokenAppContainer == NULL || !IsValidSid(info->TokenAppContainer))
    {
        goto Cleanup;
    }

    *infoOut = info;
    *sizeOut = needed;
    info = NULL;
    ok = TRUE;

Cleanup:
    if (info != NULL)
    {
        SecureZeroMemory(info, needed);
        free(info);
        info = NULL;
    }

    CloseHandle(token);
    token = NULL;
    return ok;
}

static BOOL IsSameUserAndIntegrityProcess(_In_ HANDLE process)
{
    PTOKEN_USER selfUser = NULL;
    PTOKEN_USER otherUser = NULL;
    PTOKEN_APPCONTAINER_INFORMATION selfApp = NULL;
    PTOKEN_APPCONTAINER_INFORMATION otherApp = NULL;
    DWORD selfSize = 0;
    DWORD otherSize = 0;
    DWORD selfAppSize = 0;
    DWORD otherAppSize = 0;
    DWORD selfRid = 0;
    DWORD otherRid = 0;
    BOOL selfAppContainer = TRUE;
    BOOL otherAppContainer = TRUE;
    BOOL same = FALSE;

    if (process == NULL)
    {
        return FALSE;
    }

    if (ReadTokenUser(GetCurrentProcess(), &selfUser, &selfSize) && selfUser != NULL &&
        ReadTokenUser(process, &otherUser, &otherSize) && otherUser != NULL &&
        ReadTokenIntegrityAndAppContainer(GetCurrentProcess(), &selfRid, &selfAppContainer) &&
        ReadTokenIntegrityAndAppContainer(process, &otherRid, &otherAppContainer) &&
        selfAppContainer == otherAppContainer && selfRid == otherRid &&
        EqualSid(selfUser->User.Sid, otherUser->User.Sid))
    {
        if (!selfAppContainer)
        {
            same = TRUE;
        }
        else if (ReadTokenAppContainerSid(GetCurrentProcess(), &selfApp, &selfAppSize) && selfApp != NULL &&
                 ReadTokenAppContainerSid(process, &otherApp, &otherAppSize) && otherApp != NULL)
        {
            same = EqualSid(selfApp->TokenAppContainer, otherApp->TokenAppContainer);
        }
    }

    if (otherApp != NULL)
    {
        SecureZeroMemory(otherApp, otherAppSize);
        free(otherApp);
        otherApp = NULL;
    }

    if (selfApp != NULL)
    {
        SecureZeroMemory(selfApp, selfAppSize);
        free(selfApp);
        selfApp = NULL;
    }

    if (otherUser != NULL)
    {
        SecureZeroMemory(otherUser, otherSize);
        free(otherUser);
        otherUser = NULL;
    }

    if (selfUser != NULL)
    {
        SecureZeroMemory(selfUser, selfSize);
        free(selfUser);
        selfUser = NULL;
    }

    return same;
}

static ULONGLONG GetProcessStartTime(_In_ DWORD processId)
{
    HANDLE process = NULL;
    FILETIME creation = { 0 };
    FILETIME unusedExit = { 0 };
    FILETIME unusedKernel = { 0 };
    FILETIME unusedUser = { 0 };
    ULONGLONG startTime = 0;

    if (processId == 0)
    {
        return 0;
    }

    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (process == NULL)
    {
        return 0;
    }

    if (GetProcessTimes(process, &creation, &unusedExit, &unusedKernel, &unusedUser))
    {
        startTime = ((ULONGLONG)creation.dwHighDateTime << 32) | creation.dwLowDateTime;
    }

    CloseHandle(process);
    process = NULL;
    return startTime;
}

_Success_(return >= 0) static int GetProcessLineage(_In_ DWORD processId,
                                                    _Out_writes_to_(capacity, return) DWORD *lineage, _In_ int capacity)
{
    HANDLE snapshot = INVALID_HANDLE_VALUE;
    PROCESSENTRY32W entry;
    PROCESS_LINK *links = NULL;
    size_t linkCount = 0;
    size_t linkCapacity = 0;
    int length = -1;

    if (lineage == NULL || capacity <= 0 || capacity > MAX_LINEAGE)
    {
        return -1;
    }

    ZeroMemory(lineage, (size_t)capacity * sizeof(*lineage));
    ZeroMemory(&entry, sizeof(entry));
    if (processId == 0)
    {
        return -1;
    }

    snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snapshot == INVALID_HANDLE_VALUE)
    {
        return -1;
    }

    entry.dwSize = sizeof(entry);
    for (BOOL isFound = Process32FirstW(snapshot, &entry); isFound; isFound = Process32NextW(snapshot, &entry))
    {
        if (linkCount == linkCapacity)
        {
            size_t grown = (linkCapacity != 0) ? (linkCapacity * 2) : 512;
            PROCESS_LINK *next = (grown <= SIZE_MAX / sizeof(*links)) ? realloc(links, grown * sizeof(*links)) : NULL;

            if (next == NULL)
            {
                goto Cleanup;
            }

            links = next;
            linkCapacity = grown;
        }

        links[linkCount].processId = entry.th32ProcessID;
        links[linkCount].parentProcessId = entry.th32ParentProcessID;
        ++linkCount;
    }

    length = 0;
    while (processId > 4 && length < capacity)
    {
        DWORD parentId = 0;

        lineage[length] = processId;
        ++length;

        for (size_t i = 0; i < linkCount; ++i)
        {
            if (links[i].processId == processId)
            {
                parentId = links[i].parentProcessId;
                break;
            }
        }

        if (parentId != 0)
        {
            ULONGLONG childStart = GetProcessStartTime(processId);
            ULONGLONG parentStart = GetProcessStartTime(parentId);

            if (parentId == processId || childStart == 0 || parentStart == 0 || parentStart > childStart)
            {
                break;
            }
        }

        processId = parentId;
    }

Cleanup:
    if (length < 0)
    {
        ZeroMemory(lineage, (size_t)capacity * sizeof(*lineage));
    }

    if (links != NULL)
    {
        SecureZeroMemory(links, linkCapacity * sizeof(*links));
        free(links);
        links = NULL;
    }

    SecureZeroMemory(&entry, sizeof(entry));
    CloseHandle(snapshot);
    snapshot = INVALID_HANDLE_VALUE;
    return length;
}

static BOOL HasControlChar(_In_opt_z_ const wchar_t *text)
{
    if (text == NULL)
    {
        return TRUE;
    }

    for (size_t i = 0; text[i] != L'\0'; ++i)
    {
        if (text[i] < 0x20 || text[i] == 0x7F)
        {
            return TRUE;
        }
    }

    return FALSE;
}

static BOOL ValidateDistroName(_In_opt_z_ const wchar_t *name)
{
    size_t len = 0;

    if (name == NULL || name[0] == L'\0' || name[0] == L'-' || name[0] == L' ')
    {
        return FALSE;
    }

    for (; name[len] != L'\0'; ++len)
    {
        wchar_t ch = name[len];
        BOOL ok = (ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z') || (ch >= L'0' && ch <= L'9') ||
                  ch == L'.' || ch == L'_' || ch == L'-' || ch == L' ';

        if (!ok || len >= MAX_DISTRO_CHARS)
        {
            return FALSE;
        }
    }

    return len > 0 && name[len - 1] != L' ';
}

static BOOL ValidateLinuxDir(_In_opt_z_ const wchar_t *dir)
{
    size_t len = 0;

    if (dir == NULL || dir[0] == L'\0' || HasControlChar(dir))
    {
        return FALSE;
    }

    if (wcscmp(dir, L"~") == 0)
    {
        return TRUE;
    }

    len = wcslen(dir);
    return len <= MAX_LINUX_PATH_CHARS && dir[0] == L'/';
}

static BOOL ValidateLinuxNvim(_In_opt_z_ const wchar_t *bin)
{
    size_t len = 0;

    if (bin == NULL || bin[0] == L'\0' || HasControlChar(bin))
    {
        return FALSE;
    }

    if (wcscmp(bin, L"nvim") == 0)
    {
        return TRUE;
    }

    len = wcslen(bin);
    if (len > MAX_LINUX_PATH_CHARS || bin[0] != L'/')
    {
        return FALSE;
    }

    for (size_t i = 0; i < len; ++i)
    {
        if (bin[i] == L' ' || bin[i] == L'\t')
        {
            return FALSE;
        }
    }

    if (wcsstr(bin, L"/../") != NULL || (len >= 3 && wcscmp(bin + len - 3, L"/..") == 0))
    {
        return FALSE;
    }

    return TRUE;
}

static BOOL ValidateLinuxArg(_In_opt_z_ const wchar_t *arg)
{
    size_t len = 0;

    if (arg == NULL || arg[0] == L'\0' || HasControlChar(arg))
    {
        return FALSE;
    }

    len = wcslen(arg);
    return len > 0 && len <= MAX_LINUX_PATH_CHARS;
}

static BOOL IsHexDigit(_In_ wchar_t ch)
{
    return (ch >= L'0' && ch <= L'9') || (ch >= L'a' && ch <= L'f') || (ch >= L'A' && ch <= L'F');
}

// windows_ime_helper-<hex>-<hex>.exe, no separators or traversal.
static BOOL ValidateHelperExeName(_In_opt_z_ const wchar_t *name)
{
    const wchar_t *prefix = L"windows_ime_helper-";
    const size_t prefixLen = 19;
    const wchar_t *cursor = NULL;
    size_t part1 = 0;
    size_t part2 = 0;

    if (name == NULL || wcsncmp(name, prefix, prefixLen) != 0)
    {
        return FALSE;
    }

    cursor = name + prefixLen;
    while (IsHexDigit(*cursor) && part1 < 64)
    {
        ++cursor;
        ++part1;
    }

    if (part1 == 0 || *cursor != L'-')
    {
        return FALSE;
    }

    ++cursor;
    while (IsHexDigit(*cursor) && part2 < 64)
    {
        ++cursor;
        ++part2;
    }

    return part2 > 0 && wcscmp(cursor, L".exe") == 0;
}

static BOOL ValidateBase64Arg(_In_opt_z_ const wchar_t *text)
{
    size_t len = 0;

    if (text == NULL || text[0] == L'\0')
    {
        return FALSE;
    }

    for (; text[len] != L'\0'; ++len)
    {
        wchar_t ch = text[len];
        BOOL ok = (ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z') || (ch >= L'0' && ch <= L'9') ||
                  ch == L'+' || ch == L'/' || ch == L'=';

        if (!ok || len >= MAX_BASE64_CHARS)
        {
            return FALSE;
        }
    }

    return len > 0;
}

// Drive-absolute only (X:\... or X:/...); rejects relative, rooted, UNC, device paths, ADS, and control chars.
static BOOL ValidateLocalWindowsPath(_In_opt_z_ const wchar_t *path)
{
    BOOL isLetter = FALSE;
    size_t len = 0;

    if (path == NULL || HasControlChar(path))
    {
        return FALSE;
    }

    len = wcslen(path);
    if (len < 3 || len >= MAX_WINDOWS_PATH_CHARS)
    {
        return FALSE;
    }

    isLetter = (path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z');
    if (!isLetter || path[1] != L':' || (path[2] != L'\\' && path[2] != L'/'))
    {
        return FALSE;
    }

    return wcschr(path + 2, L':') == NULL;
}

static BOOL IsLocalDrivePath(_In_z_ const wchar_t *path)
{
    wchar_t root[4] = { 0 };
    UINT driveType = DRIVE_UNKNOWN;

    root[0] = path[0];
    root[1] = L':';
    root[2] = L'\\';
    driveType = GetDriveTypeW(root);
    return driveType == DRIVE_FIXED || driveType == DRIVE_REMOVABLE || driveType == DRIVE_RAMDISK;
}

static DWORD FindDirectParent(_In_z_ const wchar_t *expectedBasename)
{
    DWORD lineage[2] = { 0 };
    HANDLE parent = NULL;
    wchar_t image[MAX_WINDOWS_PATH_CHARS] = { 0 };
    DWORD length = ARRAYSIZE(image);
    const wchar_t *name = NULL;
    ULONGLONG selfStart = 0;
    ULONGLONG parentStart = 0;
    DWORD caller = 0;

    if (expectedBasename == NULL || GetProcessLineage(GetCurrentProcessId(), lineage, 2) < 2 || lineage[1] == 0)
    {
        goto Cleanup;
    }

    selfStart = GetProcessStartTime(GetCurrentProcessId());
    parentStart = GetProcessStartTime(lineage[1]);
    if (selfStart == 0 || parentStart == 0 || parentStart > selfStart)
    {
        goto Cleanup;
    }

    parent = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, lineage[1]);
    if (parent == NULL)
    {
        goto Cleanup;
    }

    if (IsSameUserAndIntegrityProcess(parent) && QueryFullProcessImageNameW(parent, 0, image, &length) && length > 0 &&
        length < ARRAYSIZE(image) && ValidateLocalWindowsPath(image) && IsLocalDrivePath(image))
    {
        name = wcsrchr(image, L'\\');
        name = (name != NULL) ? name + 1 : image;
        if (CompareStringOrdinal(name, -1, expectedBasename, -1, TRUE) == CSTR_EQUAL)
        {
            caller = lineage[1];
        }
    }

Cleanup:
    if (parent != NULL)
    {
        CloseHandle(parent);
        parent = NULL;
    }

    SecureZeroMemory(image, sizeof(image));
    SecureZeroMemory(lineage, sizeof(lineage));
    return caller;
}

static BOOL EndsWithInsensitive(_In_z_ const wchar_t *text, _In_z_ const wchar_t *suffix)
{
    size_t textLen = wcslen(text);
    size_t suffixLen = wcslen(suffix);

    if (textLen < suffixLen)
    {
        return FALSE;
    }

    return CompareStringOrdinal(text + textLen - suffixLen, -1, suffix, -1, TRUE) == CSTR_EQUAL;
}

static BOOL ValidateLocalFileOnDisk(_In_opt_z_ const wchar_t *path)
{
    DWORD attributes = INVALID_FILE_ATTRIBUTES;
    HANDLE file = INVALID_HANDLE_VALUE;
    FILE_REMOTE_PROTOCOL_INFO remote;
    BOOL valid = FALSE;

    ZeroMemory(&remote, sizeof(remote));
    if (path == NULL || !ValidateLocalWindowsPath(path) || !IsLocalDrivePath(path))
    {
        return FALSE;
    }

    attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES || (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_DEVICE)))
    {
        return FALSE;
    }

    file = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
    {
        return FALSE;
    }

    if (!GetFileInformationByHandleEx(file, FileRemoteProtocolInfo, &remote, sizeof(remote)))
    {
        valid = TRUE;
    }

    CloseHandle(file);
    file = INVALID_HANDLE_VALUE;
    return valid;
}

static BOOL ValidateWindowsExeOnDisk(_In_opt_z_ const wchar_t *path, _In_z_ const wchar_t *expectedBasename)
{
    const wchar_t *slash = NULL;
    const wchar_t *backslash = NULL;
    const wchar_t *name = NULL;

    if (path == NULL || !ValidateLocalFileOnDisk(path) || expectedBasename == NULL)
    {
        return FALSE;
    }

    slash = wcsrchr(path, L'/');
    backslash = wcsrchr(path, L'\\');
    name = (slash > backslash) ? slash : backslash;
    name = (name != NULL) ? name + 1 : path;
    return CompareStringOrdinal(name, -1, expectedBasename, -1, TRUE) == CSTR_EQUAL;
}

static BOOL ValidateWindowsDirOnDisk(_In_opt_z_ const wchar_t *path)
{
    DWORD attributes = INVALID_FILE_ATTRIBUTES;
    HANDLE dir = INVALID_HANDLE_VALUE;
    FILE_REMOTE_PROTOCOL_INFO remote;
    BOOL valid = FALSE;

    ZeroMemory(&remote, sizeof(remote));
    if (path == NULL || !ValidateLocalWindowsPath(path) || !IsLocalDrivePath(path))
    {
        return FALSE;
    }

    attributes = GetFileAttributesW(path);
    if (attributes == INVALID_FILE_ATTRIBUTES || !(attributes & FILE_ATTRIBUTE_DIRECTORY) ||
        (attributes & FILE_ATTRIBUTE_DEVICE))
    {
        return FALSE;
    }

    dir = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                      FILE_FLAG_BACKUP_SEMANTICS, NULL);
    if (dir == INVALID_HANDLE_VALUE)
    {
        return FALSE;
    }

    if (!GetFileInformationByHandleEx(dir, FileRemoteProtocolInfo, &remote, sizeof(remote)))
    {
        valid = TRUE;
    }

    CloseHandle(dir);
    dir = INVALID_HANDLE_VALUE;
    return valid;
}

static BOOL IsBenignEmbedFlag(_In_z_ const wchar_t *arg)
{
    if (wcscmp(arg, L"--headless") == 0 || wcscmp(arg, L"--api-info") == 0 || wcscmp(arg, L"-p") == 0 ||
        wcscmp(arg, L"-R") == 0 || wcscmp(arg, L"-n") == 0)
    {
        return TRUE;
    }

    if (arg[0] == L'+' && arg[1] != L'\0')
    {
        size_t digits = 0;

        for (const wchar_t *p = arg + 1; *p != L'\0'; ++p)
        {
            if (*p < L'0' || *p > L'9' || digits >= 9)
            {
                return FALSE;
            }

            ++digits;
        }

        return TRUE;
    }

    return FALSE;
}

static BOOL IsNeovideInvocation(_In_ int argc, _In_reads_opt_(argc) const wchar_t *const *argv)
{
    if (argv == NULL || argc < 2 || argv[1] == NULL)
    {
        return FALSE;
    }

    if (argc == 2 && (wcscmp(argv[1], L"-v") == 0 || wcscmp(argv[1], L"--version") == 0))
    {
        return TRUE;
    }

    if (wcscmp(argv[1], L"--embed") == 0)
    {
        return TRUE;
    }

    if (argv[argc - 1] != NULL && wcscmp(argv[argc - 1], L"--embed") == 0)
    {
        return TRUE;
    }

    return argc >= 3 && argv[argc - 2] != NULL && argv[argc - 1] != NULL && wcscmp(argv[argc - 2], L"--embed") == 0 &&
           wcscmp(argv[argc - 1], L"-p") == 0;
}

static BOOL EmitNormalizedArg(_Inout_updates_opt_(outCapacity) const wchar_t **outArgv, _In_ int outCapacity,
                              _Inout_ int *outCount, _In_z_ const wchar_t *value)
{
    if (outArgv != NULL)
    {
        if (*outCount < 0 || *outCount >= outCapacity)
        {
            return FALSE;
        }

        outArgv[*outCount] = value;
    }

    *outCount += 1;
    return TRUE;
}

// Accepts prefix (--embed ...) and Neovide tail (... --embed [-p]) orders, emitting --embed [-p] [flags] [-- files...].
_Success_(return != FALSE) static BOOL
    BuildNormalizedEmbedArgs(_In_ int argc, _In_reads_opt_(argc) const wchar_t *const *argv,
                             _Inout_updates_opt_(outCapacity) const wchar_t **outArgv, _In_ int outCapacity,
                             _Out_opt_ int *outCount)
{
    int bodyStart = 0;
    int bodyEnd = 0;
    int sepIndex = -1;
    int emitted = 0;
    BOOL tailHasP = FALSE;

    if (outCount != NULL)
    {
        *outCount = 0;
    }

    if (argv == NULL || argc < 2 || argv[1] == NULL)
    {
        return FALSE;
    }

    if (argc == 2 && (wcscmp(argv[1], L"-v") == 0 || wcscmp(argv[1], L"--version") == 0))
    {
        if (!EmitNormalizedArg(outArgv, outCapacity, &emitted, argv[1]))
        {
            return FALSE;
        }

        if (outCount != NULL)
        {
            *outCount = emitted;
        }

        return TRUE;
    }

    if (wcscmp(argv[1], L"--embed") == 0)
    {
        bodyStart = 2;
        bodyEnd = argc;
    }
    else if (argv[argc - 1] != NULL && wcscmp(argv[argc - 1], L"--embed") == 0)
    {
        bodyStart = 1;
        bodyEnd = argc - 1;
    }
    else if (argc >= 3 && argv[argc - 2] != NULL && argv[argc - 1] != NULL && wcscmp(argv[argc - 2], L"--embed") == 0 &&
             wcscmp(argv[argc - 1], L"-p") == 0)
    {
        bodyStart = 1;
        bodyEnd = argc - 2;
        tailHasP = TRUE;
    }
    else
    {
        return FALSE;
    }

    for (int i = bodyStart; i < bodyEnd; ++i)
    {
        const wchar_t *arg = argv[i];

        if (arg == NULL || !ValidateLinuxArg(arg))
        {
            return FALSE;
        }

        if (sepIndex >= 0)
        {
            continue;
        }

        if (wcscmp(arg, L"--") == 0)
        {
            sepIndex = i;
        }
        else if (!IsBenignEmbedFlag(arg))
        {
            return FALSE;
        }
    }

    if (!EmitNormalizedArg(outArgv, outCapacity, &emitted, L"--embed"))
    {
        return FALSE;
    }

    if (tailHasP && !EmitNormalizedArg(outArgv, outCapacity, &emitted, L"-p"))
    {
        return FALSE;
    }

    {
        int flagEnd = (sepIndex >= 0) ? sepIndex : bodyEnd;

        for (int i = bodyStart; i < flagEnd; ++i)
        {
            if (tailHasP && wcscmp(argv[i], L"-p") == 0)
            {
                continue;
            }

            if (!EmitNormalizedArg(outArgv, outCapacity, &emitted, argv[i]))
            {
                return FALSE;
            }
        }
    }

    if (sepIndex >= 0 && sepIndex + 1 < bodyEnd)
    {
        if (!EmitNormalizedArg(outArgv, outCapacity, &emitted, L"--"))
        {
            return FALSE;
        }

        for (int i = sepIndex + 1; i < bodyEnd; ++i)
        {
            if (!EmitNormalizedArg(outArgv, outCapacity, &emitted, argv[i]))
            {
                return FALSE;
            }
        }
    }

    if (outCount != NULL)
    {
        *outCount = emitted;
    }

    return TRUE;
}

static BOOL ValidateForwardedEmbedArgs(_In_ int argc, _In_reads_opt_(argc) const wchar_t *const *argv)
{
    return BuildNormalizedEmbedArgs(argc, argv, NULL, 0, NULL);
}

static BOOL AppendChar(_Inout_updates_(capacity) wchar_t *buf, _In_ size_t capacity, _Inout_ size_t *length,
                       _In_ wchar_t ch)
{
    if (*length + 1 >= capacity)
    {
        return FALSE;
    }

    buf[*length] = ch;
    *length += 1;
    buf[*length] = L'\0';
    return TRUE;
}

// Exact CommandLineToArgvW / CreateProcessW quoting so spaces, tabs, quotes and backslashes survive intact.
static BOOL AppendQuotedArg(_Inout_updates_(capacity) wchar_t *buf, _In_ size_t capacity, _Inout_ size_t *length,
                            _In_opt_z_ const wchar_t *arg)
{
    BOOL needsQuotes = FALSE;

    if (buf == NULL || length == NULL || arg == NULL || *length >= capacity)
    {
        return FALSE;
    }

    if (*length > 0 && !AppendChar(buf, capacity, length, L' '))
    {
        return FALSE;
    }

    needsQuotes = arg[0] == L'\0';
    for (const wchar_t *p = arg; *p != L'\0' && !needsQuotes; ++p)
    {
        if (*p == L' ' || *p == L'\t' || *p == L'"')
        {
            needsQuotes = TRUE;
        }
    }

    if (!needsQuotes)
    {
        for (const wchar_t *p = arg; *p != L'\0'; ++p)
        {
            if (!AppendChar(buf, capacity, length, *p))
            {
                return FALSE;
            }
        }

        return TRUE;
    }

    if (!AppendChar(buf, capacity, length, L'"'))
    {
        return FALSE;
    }

    for (const wchar_t *p = arg;; ++p)
    {
        size_t backslashes = 0;

        while (*p == L'\\')
        {
            ++backslashes;
            ++p;
        }

        if (*p == L'\0')
        {
            for (size_t i = 0; i < backslashes * 2; ++i)
            {
                if (!AppendChar(buf, capacity, length, L'\\'))
                {
                    return FALSE;
                }
            }

            break;
        }

        if (*p == L'"')
        {
            for (size_t i = 0; i < backslashes * 2 + 1; ++i)
            {
                if (!AppendChar(buf, capacity, length, L'\\'))
                {
                    return FALSE;
                }
            }

            if (!AppendChar(buf, capacity, length, L'"'))
            {
                return FALSE;
            }
        }
        else
        {
            for (size_t i = 0; i < backslashes; ++i)
            {
                if (!AppendChar(buf, capacity, length, L'\\'))
                {
                    return FALSE;
                }
            }

            if (!AppendChar(buf, capacity, length, *p))
            {
                return FALSE;
            }
        }
    }

    return AppendChar(buf, capacity, length, L'"');
}

static BOOL ResolveSystemWslExe(_Out_writes_z_(capacity) wchar_t *out, _In_ DWORD capacity)
{
    wchar_t systemDir[MAX_PATH] = { 0 };
    UINT sysLen = 0;
    BOOL ok = FALSE;

    if (out == NULL || capacity == 0)
    {
        return FALSE;
    }

    out[0] = L'\0';
    sysLen = GetSystemDirectoryW(systemDir, ARRAYSIZE(systemDir));
    if (sysLen > 0 && sysLen < ARRAYSIZE(systemDir) &&
        SUCCEEDED(StringCchPrintfW(out, capacity, L"%ls\\wsl.exe", systemDir)))
    {
        ok = ValidateWindowsExeOnDisk(out, L"wsl.exe");
    }

    if (!ok)
    {
        SecureZeroMemory(out, capacity * sizeof(*out));
    }

    SecureZeroMemory(systemDir, sizeof(systemDir));
    return ok;
}

static BOOL AppendWslEnvTokens(_In_ BOOL includeHelper)
{
    wchar_t *current = calloc(MAX_ENV_VALUE_CHARS, sizeof(*current));
    wchar_t *updated = calloc(MAX_ENV_VALUE_CHARS, sizeof(*updated));
    const wchar_t *suffix = L"NVIM_WSL_UI_PID/u";
    DWORD len = 0;
    HRESULT hr = S_OK;
    BOOL ok = FALSE;

    if (current == NULL || updated == NULL)
    {
        goto Cleanup;
    }

    if (includeHelper)
    {
        suffix = L"NVIM_WSL_UI_PID/u:NVIM_WSL_HOST_HELPER_DIR/pu:NVIM_WSL_HOST_HELPER_EXE/u";
    }

    SetLastError(ERROR_SUCCESS);
    len = GetEnvironmentVariableW(L"WSLENV", current, MAX_ENV_VALUE_CHARS);
    if (len >= MAX_ENV_VALUE_CHARS ||
        (len == 0 && GetLastError() != ERROR_ENVVAR_NOT_FOUND && GetLastError() != ERROR_SUCCESS))
    {
        goto Cleanup;
    }

    while (len > 0 && current[len - 1] == L':')
    {
        current[len - 1] = L'\0';
        --len;
    }

    if (len > 0)
    {
        hr = StringCchPrintfW(updated, MAX_ENV_VALUE_CHARS, L"%ls:%ls", current, suffix);
    }
    else
    {
        hr = StringCchCopyW(updated, MAX_ENV_VALUE_CHARS, suffix);
    }

    ok = SUCCEEDED(hr) && SetEnvironmentVariableW(L"WSLENV", updated);

Cleanup:
    if (current != NULL)
    {
        SecureZeroMemory(current, MAX_ENV_VALUE_CHARS * sizeof(*current));
        free(current);
        current = NULL;
    }

    if (updated != NULL)
    {
        SecureZeroMemory(updated, MAX_ENV_VALUE_CHARS * sizeof(*updated));
        free(updated);
        updated = NULL;
    }

    return ok;
}

_Success_(return != FALSE) static BOOL
    ReadKnownFolderPath(_In_ REFKNOWNFOLDERID folderId, _Out_writes_z_(capacity) wchar_t *out, _In_ DWORD capacity)
{
    PWSTR path = NULL;
    HRESULT hr = E_FAIL;
    BOOL ok = FALSE;

    if (out == NULL || capacity == 0)
    {
        return FALSE;
    }

    out[0] = L'\0';
    hr = SHGetKnownFolderPath(folderId, KF_FLAG_DONT_VERIFY | KF_FLAG_NO_ALIAS, NULL, &path);
    if (SUCCEEDED(hr) && path != NULL && path[0] != L'\0' && SUCCEEDED(StringCchCopyW(out, capacity, path)))
    {
        ok = TRUE;
    }

    if (path != NULL)
    {
        CoTaskMemFree(path);
        path = NULL;
    }

    if (!ok)
    {
        SecureZeroMemory(out, capacity * sizeof(*out));
    }

    return ok;
}

_Success_(return != FALSE) static BOOL
    NormalizeDrivePath(_In_opt_z_ const wchar_t *path, _Out_writes_z_(capacity) wchar_t *out, _In_ DWORD capacity)
{
    size_t outLen = 0;

    if (out == NULL || capacity == 0)
    {
        return FALSE;
    }

    out[0] = L'\0';
    if (path == NULL || !ValidateLocalWindowsPath(path))
    {
        return FALSE;
    }

    for (size_t i = 0; path[i] != L'\0'; ++i)
    {
        wchar_t ch = path[i];

        if (ch == L'/')
        {
            ch = L'\\';
        }

        if (ch == L'\\' && outLen > 0 && out[outLen - 1] == L'\\')
        {
            continue;
        }

        if (outLen + 1 >= capacity)
        {
            SecureZeroMemory(out, capacity * sizeof(*out));
            return FALSE;
        }

        out[outLen] = ch;
        ++outLen;
    }

    out[outLen] = L'\0';
    while (outLen > 3 && out[outLen - 1] == L'\\')
    {
        out[outLen - 1] = L'\0';
        --outLen;
    }

    if (outLen < 3 || wcsstr(out, L"\\..\\") != NULL || (outLen >= 3 && wcscmp(out + outLen - 3, L"\\..") == 0) ||
        wcsstr(out, L"\\.\\") != NULL || (outLen >= 2 && wcscmp(out + outLen - 2, L"\\.") == 0))
    {
        SecureZeroMemory(out, capacity * sizeof(*out));
        return FALSE;
    }

    return TRUE;
}

static BOOL IsAllowedHelperDirForSelf(_In_opt_z_ const wchar_t *dir, _In_opt_z_ const wchar_t *selfModulePath,
                                      _In_opt_z_ const wchar_t *localAppDataDir)
{
    wchar_t normDir[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t normSelf[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t expectedDir[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t normLocal[MAX_WINDOWS_PATH_CHARS] = { 0 };
    BOOL matched = FALSE;

    if (!NormalizeDrivePath(dir, normDir, ARRAYSIZE(normDir)) ||
        !EndsWithInsensitive(normDir, L"\\nvim-config\\windows_ime_helper"))
    {
        goto Cleanup;
    }

    if (NormalizeDrivePath(selfModulePath, normSelf, ARRAYSIZE(normSelf)))
    {
        wchar_t *selfSlash = wcsrchr(normSelf, L'\\');

        if (selfSlash != NULL)
        {
            *selfSlash = L'\0';
            if (EndsWithInsensitive(normSelf, L"\\nvim-config\\windows_wsl_bridge"))
            {
                const size_t tailLen = 18; // "windows_wsl_bridge"
                size_t selfDirLen = wcslen(normSelf);

                if (selfDirLen > tailLen)
                {
                    normSelf[selfDirLen - tailLen] = L'\0';
                    if (SUCCEEDED(
                            StringCchPrintfW(expectedDir, ARRAYSIZE(expectedDir), L"%lswindows_ime_helper", normSelf)))
                    {
                        matched = CompareStringOrdinal(normDir, -1, expectedDir, -1, TRUE) == CSTR_EQUAL;
                    }
                }

                goto Cleanup;
            }
        }
    }

    if (NormalizeDrivePath(localAppDataDir, normLocal, ARRAYSIZE(normLocal)))
    {
        size_t localLen = wcslen(normLocal);
        size_t dirLen = wcslen(normDir);

        if (localLen == 3)
        {
            matched = dirLen > 3 && CompareStringOrdinal(normDir, 3, normLocal, 3, TRUE) == CSTR_EQUAL;
        }
        else if (dirLen > localLen + 1 && normDir[localLen] == L'\\')
        {
            matched = CompareStringOrdinal(normDir, (int)localLen, normLocal, (int)localLen, TRUE) == CSTR_EQUAL;
        }
    }

Cleanup:
    SecureZeroMemory(normDir, sizeof(normDir));
    SecureZeroMemory(normSelf, sizeof(normSelf));
    SecureZeroMemory(expectedDir, sizeof(expectedDir));
    SecureZeroMemory(normLocal, sizeof(normLocal));
    return matched;
}

static BOOL IsAllowedHelperDir(_In_opt_z_ const wchar_t *dir)
{
    wchar_t selfPath[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t localAppData[MAX_WINDOWS_PATH_CHARS] = { 0 };
    DWORD selfLen = GetModuleFileNameW(NULL, selfPath, ARRAYSIZE(selfPath));
    BOOL hasLocalAppData = ReadKnownFolderPath(&FOLDERID_LocalAppData, localAppData, ARRAYSIZE(localAppData));
    BOOL allowed = IsAllowedHelperDirForSelf(dir, (selfLen > 0 && selfLen < ARRAYSIZE(selfPath)) ? selfPath : NULL,
                                             (hasLocalAppData) ? localAppData : NULL);

    SecureZeroMemory(selfPath, sizeof(selfPath));
    SecureZeroMemory(localAppData, sizeof(localAppData));
    return allowed;
}

static BOOL ConfigureWslBridgeEnvironment(_In_ DWORD uiPid)
{
    wchar_t helperDir[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t helperExe[128] = { 0 };
    wchar_t helperFull[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t pidText[32] = { 0 };
    DWORD dirLen = 0;
    DWORD exeLen = 0;
    BOOL includeHelper = FALSE;
    BOOL ok = FALSE;

    SetEnvironmentVariableW(L"NVIM_WSL_DISTRO", NULL);
    SetEnvironmentVariableW(L"NVIM_WSL_DIR", NULL);
    SetEnvironmentVariableW(L"NVIM_WSL_NVIM", NULL);
    SetEnvironmentVariableW(L"NVIM", NULL);
    SetEnvironmentVariableW(L"NVIM_LISTEN_ADDRESS", NULL);

    if (FAILED(StringCchPrintfW(pidText, ARRAYSIZE(pidText), L"%lu", uiPid)) ||
        !SetEnvironmentVariableW(L"NVIM_WSL_UI_PID", pidText))
    {
        goto Cleanup;
    }

    dirLen = GetEnvironmentVariableW(L"NVIM_WSL_HOST_HELPER_DIR", helperDir, ARRAYSIZE(helperDir));
    exeLen = GetEnvironmentVariableW(L"NVIM_WSL_HOST_HELPER_EXE", helperExe, ARRAYSIZE(helperExe));
    if (dirLen > 0 && dirLen < ARRAYSIZE(helperDir) && exeLen > 0 && exeLen < ARRAYSIZE(helperExe) &&
        IsAllowedHelperDir(helperDir) && ValidateWindowsDirOnDisk(helperDir) && ValidateHelperExeName(helperExe) &&
        SUCCEEDED(StringCchPrintfW(helperFull, ARRAYSIZE(helperFull), L"%ls\\%ls", helperDir, helperExe)) &&
        ValidateWindowsExeOnDisk(helperFull, helperExe))
    {
        includeHelper = TRUE;
    }
    else
    {
        SetEnvironmentVariableW(L"NVIM_WSL_HOST_HELPER_DIR", NULL);
        SetEnvironmentVariableW(L"NVIM_WSL_HOST_HELPER_EXE", NULL);
    }

    ok = AppendWslEnvTokens(includeHelper);

Cleanup:
    SecureZeroMemory(helperDir, sizeof(helperDir));
    SecureZeroMemory(helperExe, sizeof(helperExe));
    SecureZeroMemory(helperFull, sizeof(helperFull));
    SecureZeroMemory(pidText, sizeof(pidText));
    return ok;
}

static HANDLE GetValidStdHandle(_In_ DWORD which)
{
    HANDLE handle = GetStdHandle(which);

    return (handle == INVALID_HANDLE_VALUE) ? NULL : handle;
}

static HANDLE CreateKillOnCloseJob(void)
{
    HANDLE job = CreateJobObjectW(NULL, NULL);
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;

    ZeroMemory(&limits, sizeof(limits));
    if (job == NULL)
    {
        return NULL;
    }

    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
    {
        CloseHandle(job);
        job = NULL;
        return NULL;
    }

    return job;
}

static BOOL SpawnWithExplicitHandles(_In_z_ const wchar_t *application, _Inout_z_ wchar_t *commandLine,
                                     _In_ DWORD flags, _In_ HANDLE stdIn, _In_ HANDLE stdOut, _In_ HANDLE stdErr,
                                     _Out_ PROCESS_INFORMATION *process)
{
    HANDLE inherited[3] = { 0 };
    DWORD inheritedCount = 0;
    HANDLE standard[3] = { stdIn, stdOut, stdErr };
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = NULL;
    SIZE_T attributesSize = 0;
    BOOL isAttributeListReady = FALSE;
    STARTUPINFOEXW startup;
    BOOL started = FALSE;

    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(process, sizeof(*process));
    startup.StartupInfo.cb = sizeof(startup);
    startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
    startup.StartupInfo.hStdInput = stdIn;
    startup.StartupInfo.hStdOutput = stdOut;
    startup.StartupInfo.hStdError = stdErr;

    for (DWORD i = 0; i < ARRAYSIZE(standard); ++i)
    {
        BOOL isListed = FALSE;
        DWORD handleFlags = 0;

        for (DWORD j = 0; j < inheritedCount; ++j)
        {
            isListed = isListed || inherited[j] == standard[i];
        }

        if (standard[i] == NULL || isListed || !GetHandleInformation(standard[i], &handleFlags))
        {
            continue;
        }

        if ((handleFlags & HANDLE_FLAG_INHERIT) ||
            SetHandleInformation(standard[i], HANDLE_FLAG_INHERIT, HANDLE_FLAG_INHERIT))
        {
            inherited[inheritedCount] = standard[i];
            ++inheritedCount;
        }
    }

    if (inheritedCount > 0)
    {
        InitializeProcThreadAttributeList(NULL, 1, 0, &attributesSize);
        attributes = calloc(1, attributesSize);
        if (attributes == NULL)
        {
            goto Cleanup;
        }

        isAttributeListReady = InitializeProcThreadAttributeList(attributes, 1, 0, &attributesSize);
        if (!isAttributeListReady || !UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_HANDLE_LIST,
                                                                inherited, inheritedCount * sizeof(HANDLE), NULL, NULL))
        {
            goto Cleanup;
        }

        startup.lpAttributeList = attributes;
    }

    started = CreateProcessW(application, commandLine, NULL, NULL, inheritedCount > 0,
                             flags | EXTENDED_STARTUPINFO_PRESENT, NULL, NULL, &startup.StartupInfo, process);

Cleanup:
    if (isAttributeListReady)
    {
        DeleteProcThreadAttributeList(attributes);
    }

    free(attributes);
    attributes = NULL;
    SecureZeroMemory(inherited, sizeof(inherited));
    SecureZeroMemory(&startup, sizeof(startup));
    return started;
}

static BOOL BuildWslCommandLine(_Out_writes_z_(capacity) wchar_t *commandLine, _In_ size_t capacity,
                                _In_z_ const wchar_t *wslExe, _In_z_ const wchar_t *distro,
                                _In_opt_z_ const wchar_t *dir, _In_z_ const wchar_t *wslNvim, _In_ int forwardArgc,
                                _In_reads_opt_(forwardArgc) const wchar_t *const *forwardArgv)
{
    size_t len = 0;

    if (commandLine == NULL || capacity == 0)
    {
        return FALSE;
    }

    commandLine[0] = L'\0';
    if (!AppendQuotedArg(commandLine, capacity, &len, wslExe) ||
        !AppendQuotedArg(commandLine, capacity, &len, L"--distribution") ||
        !AppendQuotedArg(commandLine, capacity, &len, distro))
    {
        return FALSE;
    }

    if (dir != NULL)
    {
        if (!AppendQuotedArg(commandLine, capacity, &len, L"--cd") ||
            !AppendQuotedArg(commandLine, capacity, &len, dir))
        {
            return FALSE;
        }
    }

    if (!AppendQuotedArg(commandLine, capacity, &len, L"--exec") ||
        !AppendQuotedArg(commandLine, capacity, &len, wslNvim))
    {
        return FALSE;
    }

    for (int i = 0; i < forwardArgc; ++i)
    {
        if (forwardArgv == NULL || forwardArgv[i] == NULL ||
            !AppendQuotedArg(commandLine, capacity, &len, forwardArgv[i]))
        {
            return FALSE;
        }
    }

    return TRUE;
}

static int RunNeovideEmbed(_In_ DWORD neovidePid, _In_ int argc, _In_reads_(argc) const wchar_t *const *argv)
{
    wchar_t distro[MAX_DISTRO_CHARS + 2] = { 0 };
    wchar_t wslExe[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t *dir = NULL;
    wchar_t *wslNvim = NULL;
    wchar_t *commandLine = NULL;
    const wchar_t **forwardArgv = NULL;
    int forwardCount = 0;
    HANDLE job = NULL;
    PROCESS_INFORMATION process;
    DWORD dLen = 0;
    DWORD dirLen = 0;
    DWORD nvimLen = 0;
    DWORD exitCode = EXIT_FAILED;
    BOOL isVersion = FALSE;

    ZeroMemory(&process, sizeof(process));
    if (!ValidateForwardedEmbedArgs(argc, argv))
    {
        fwprintf(stderr, L"windows_wsl_bridge: refused unexpected Neovide arguments\n");
        return EXIT_USAGE;
    }

    dir = calloc(MAX_LINUX_PATH_CHARS + 2, sizeof(*dir));
    wslNvim = calloc(MAX_LINUX_PATH_CHARS + 2, sizeof(*wslNvim));
    if (dir == NULL || wslNvim == NULL)
    {
        goto Cleanup;
    }

    dLen = GetEnvironmentVariableW(L"NVIM_WSL_DISTRO", distro, ARRAYSIZE(distro));
    if (dLen == 0 || dLen >= ARRAYSIZE(distro) || !ValidateDistroName(distro))
    {
        fwprintf(stderr, L"windows_wsl_bridge: invalid or missing NVIM_WSL_DISTRO\n");
        goto Cleanup;
    }

    dirLen = GetEnvironmentVariableW(L"NVIM_WSL_DIR", dir, MAX_LINUX_PATH_CHARS + 2);
    if (dirLen == 0)
    {
        StringCchCopyW(dir, MAX_LINUX_PATH_CHARS + 2, L"~");
    }
    else if (dirLen >= MAX_LINUX_PATH_CHARS + 2 || !ValidateLinuxDir(dir))
    {
        fwprintf(stderr, L"windows_wsl_bridge: invalid NVIM_WSL_DIR\n");
        goto Cleanup;
    }

    nvimLen = GetEnvironmentVariableW(L"NVIM_WSL_NVIM", wslNvim, MAX_LINUX_PATH_CHARS + 2);
    if (nvimLen == 0)
    {
        StringCchCopyW(wslNvim, MAX_LINUX_PATH_CHARS + 2, L"nvim");
    }
    else if (nvimLen >= MAX_LINUX_PATH_CHARS + 2 || !ValidateLinuxNvim(wslNvim))
    {
        fwprintf(stderr, L"windows_wsl_bridge: invalid NVIM_WSL_NVIM\n");
        goto Cleanup;
    }

    if (!ResolveSystemWslExe(wslExe, ARRAYSIZE(wslExe)))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot locate System32\\wsl.exe\n");
        goto Cleanup;
    }

    isVersion = argc == 2 && (wcscmp(argv[1], L"-v") == 0 || wcscmp(argv[1], L"--version") == 0);
    commandLine = calloc(COMMAND_LINE_MAX_CHARS, sizeof(*commandLine));
    forwardArgv = calloc((size_t)argc, sizeof(*forwardArgv));
    if (commandLine == NULL || forwardArgv == NULL ||
        !BuildNormalizedEmbedArgs(argc, argv, forwardArgv, argc, &forwardCount) ||
        !BuildWslCommandLine(commandLine, COMMAND_LINE_MAX_CHARS, wslExe, distro, (isVersion) ? NULL : dir, wslNvim,
                             forwardCount, forwardArgv))
    {
        fwprintf(stderr, L"windows_wsl_bridge: command line too long\n");
        goto Cleanup;
    }

    if (!ConfigureWslBridgeEnvironment(neovidePid))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot configure WSLENV\n");
        goto Cleanup;
    }

    job = CreateKillOnCloseJob();
    if (job == NULL)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot create job object (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    if (!SpawnWithExplicitHandles(wslExe, commandLine, CREATE_SUSPENDED | CREATE_DEFAULT_ERROR_MODE,
                                  GetValidStdHandle(STD_INPUT_HANDLE), GetValidStdHandle(STD_OUTPUT_HANDLE),
                                  GetValidStdHandle(STD_ERROR_HANDLE), &process))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot start wsl.exe (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    if (!AssignProcessToJobObject(job, process.hProcess) || ResumeThread(process.hThread) == (DWORD)-1)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot start wsl.exe in job (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    WaitForSingleObject(process.hProcess, INFINITE);
    if (!GetExitCodeProcess(process.hProcess, &exitCode))
    {
        exitCode = EXIT_FAILED;
    }

Cleanup:
    if (process.hProcess != NULL)
    {
        if (WaitForSingleObject(process.hProcess, 0) != WAIT_OBJECT_0)
        {
            TerminateProcess(process.hProcess, EXIT_FAILED);
            WaitForSingleObject(process.hProcess, CLEANUP_WAIT_MS);
        }

        CloseHandle(process.hProcess);
        process.hProcess = NULL;
    }

    if (process.hThread != NULL)
    {
        CloseHandle(process.hThread);
        process.hThread = NULL;
    }

    if (job != NULL)
    {
        CloseHandle(job);
        job = NULL;
    }

    free((void *)forwardArgv);
    forwardArgv = NULL;
    if (commandLine != NULL)
    {
        SecureZeroMemory(commandLine, COMMAND_LINE_MAX_CHARS * sizeof(*commandLine));
        free(commandLine);
        commandLine = NULL;
    }

    if (dir != NULL)
    {
        SecureZeroMemory(dir, (MAX_LINUX_PATH_CHARS + 2) * sizeof(*dir));
        free(dir);
        dir = NULL;
    }

    if (wslNvim != NULL)
    {
        SecureZeroMemory(wslNvim, (MAX_LINUX_PATH_CHARS + 2) * sizeof(*wslNvim));
        free(wslNvim);
        wslNvim = NULL;
    }

    SecureZeroMemory(distro, sizeof(distro));
    SecureZeroMemory(wslExe, sizeof(wslExe));
    return (int)exitCode;
}

static BOOL CreateOwnerOnlyNamedPipe(_Out_writes_z_(pipeNameCapacity) wchar_t *pipeName, _In_ size_t pipeNameCapacity,
                                     _Out_ HANDLE *pipeOut)
{
    uint8_t random[16] = { 0 };
    wchar_t hex[33] = { 0 };
    PTOKEN_USER selfUser = NULL;
    DWORD selfSize = 0;
    DWORD aclSize = 0;
    PACL acl = NULL;
    SECURITY_DESCRIPTOR sd;
    SECURITY_ATTRIBUTES sa;
    HANDLE pipe = INVALID_HANDLE_VALUE;
    BOOL ok = FALSE;

    *pipeOut = INVALID_HANDLE_VALUE;
    if (pipeNameCapacity > 0)
    {
        pipeName[0] = L'\0';
    }

    if (BCryptGenRandom(NULL, random, sizeof(random), BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0)
    {
        return FALSE;
    }

    for (size_t i = 0; i < sizeof(random); ++i)
    {
        StringCchPrintfW(hex + i * 2, 3, L"%02x", random[i]);
    }

    if (FAILED(StringCchPrintfW(pipeName, pipeNameCapacity, L"\\\\.\\pipe\\nvim-wsl-%ls", hex)))
    {
        goto Cleanup;
    }

    if (!ReadTokenUser(GetCurrentProcess(), &selfUser, &selfSize) || selfUser == NULL)
    {
        goto Cleanup;
    }

    aclSize = sizeof(ACL) + sizeof(ACCESS_ALLOWED_ACE) - sizeof(DWORD) + GetLengthSid(selfUser->User.Sid);
    acl = calloc(1, aclSize);
    if (acl == NULL || !InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION) ||
        !InitializeAcl(acl, aclSize, ACL_REVISION) ||
        !AddAccessAllowedAce(acl, ACL_REVISION, GENERIC_READ | GENERIC_WRITE, selfUser->User.Sid) ||
        !SetSecurityDescriptorDacl(&sd, TRUE, acl, FALSE))
    {
        goto Cleanup;
    }

    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = &sd;
    sa.bInheritHandle = FALSE;

    pipe = CreateNamedPipeW(pipeName, PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE | FILE_FLAG_OVERLAPPED,
                            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT | PIPE_REJECT_REMOTE_CLIENTS, 1,
                            PIPE_BUFFER_BYTES, PIPE_BUFFER_BYTES, 0, &sa);
    if (pipe != INVALID_HANDLE_VALUE)
    {
        *pipeOut = pipe;
        ok = TRUE;
    }

Cleanup:
    if (acl != NULL)
    {
        SecureZeroMemory(acl, aclSize);
        free(acl);
        acl = NULL;
    }

    if (selfUser != NULL)
    {
        SecureZeroMemory(selfUser, selfSize);
        free(selfUser);
        selfUser = NULL;
    }

    SecureZeroMemory(random, sizeof(random));
    SecureZeroMemory(hex, sizeof(hex));
    return ok;
}

static void CloseWslInWrite(_Inout_ RELAY_CONTEXT *ctx)
{
    HANDLE handle = InterlockedExchangePointer((volatile PVOID *)&ctx->wslInWrite, NULL);

    if (handle != NULL && handle != INVALID_HANDLE_VALUE)
    {
        CloseHandle(handle);
        handle = NULL;
    }
}

static BOOL WriteAllToPipe(_In_ HANDLE pipe, _In_ HANDLE stopEvent, _In_reads_bytes_(size) const char *data,
                           _In_ DWORD size)
{
    OVERLAPPED ov;
    HANDLE event = CreateEventW(NULL, TRUE, FALSE, NULL);
    DWORD offset = 0;
    BOOL ok = FALSE;

    if (event == NULL)
    {
        return FALSE;
    }

    while (offset < size)
    {
        DWORD written = 0;
        HANDLE waits[2] = { event, stopEvent };

        ZeroMemory(&ov, sizeof(ov));
        ResetEvent(event);
        ov.hEvent = event;
        if (!WriteFile(pipe, data + offset, size - offset, &written, &ov))
        {
            if (GetLastError() != ERROR_IO_PENDING)
            {
                goto Cleanup;
            }

            if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) != WAIT_OBJECT_0 ||
                !GetOverlappedResult(pipe, &ov, &written, FALSE))
            {
                goto Cleanup;
            }
        }

        if (written == 0)
        {
            goto Cleanup;
        }

        offset += written;
    }

    ok = TRUE;

Cleanup:
    CloseHandle(event);
    event = NULL;
    return ok;
}

static DWORD WINAPI PipeToWslThread(_In_ LPVOID parameter)
{
    RELAY_CONTEXT *ctx = (RELAY_CONTEXT *)parameter;
    char *buffer = calloc(RELAY_CHUNK_BYTES, sizeof(*buffer));
    HANDLE event = CreateEventW(NULL, TRUE, FALSE, NULL);

    if (ctx == NULL || event == NULL || buffer == NULL)
    {
        if (buffer != NULL)
        {
            free(buffer);
            buffer = NULL;
        }

        if (event != NULL)
        {
            CloseHandle(event);
            event = NULL;
        }

        return 1;
    }

    while (WaitForSingleObject(ctx->stopEvent, 0) != WAIT_OBJECT_0)
    {
        OVERLAPPED ov;
        DWORD nRead = 0;
        DWORD total = 0;
        HANDLE target = NULL;
        HANDLE waits[2] = { event, ctx->stopEvent };

        ZeroMemory(&ov, sizeof(ov));
        ResetEvent(event);
        ov.hEvent = event;
        if (!ReadFile(ctx->pipe, buffer, RELAY_CHUNK_BYTES, &nRead, &ov))
        {
            if (GetLastError() != ERROR_IO_PENDING)
            {
                break;
            }

            if (WaitForMultipleObjects(2, waits, FALSE, INFINITE) != WAIT_OBJECT_0 ||
                !GetOverlappedResult(ctx->pipe, &ov, &nRead, FALSE))
            {
                break;
            }
        }

        if (nRead == 0)
        {
            break;
        }

        target = ctx->wslInWrite;
        if (target == NULL)
        {
            break;
        }

        while (total < nRead)
        {
            DWORD written = 0;

            if (!WriteFile(target, buffer + total, nRead - total, &written, NULL) || written == 0)
            {
                goto Done;
            }

            total += written;
        }
    }

Done:
    CloseWslInWrite(ctx);
    SecureZeroMemory(buffer, RELAY_CHUNK_BYTES);
    free(buffer);
    buffer = NULL;
    CloseHandle(event);
    event = NULL;
    return 0;
}

static DWORD WINAPI WslToPipeThread(_In_ LPVOID parameter)
{
    RELAY_CONTEXT *ctx = (RELAY_CONTEXT *)parameter;
    char *buffer = calloc(RELAY_CHUNK_BYTES, sizeof(*buffer));

    if (ctx == NULL || buffer == NULL)
    {
        if (buffer != NULL)
        {
            free(buffer);
            buffer = NULL;
        }

        if (ctx != NULL)
        {
            SetEvent(ctx->wslOutDoneEvent);
        }

        return 1;
    }

    while (WaitForSingleObject(ctx->stopEvent, 0) != WAIT_OBJECT_0)
    {
        DWORD nRead = 0;

        if (!ReadFile(ctx->wslOutRead, buffer, RELAY_CHUNK_BYTES, &nRead, NULL) || nRead == 0)
        {
            break;
        }

        if (!WriteAllToPipe(ctx->pipe, ctx->stopEvent, buffer, nRead))
        {
            break;
        }
    }

    SecureZeroMemory(buffer, RELAY_CHUNK_BYTES);
    free(buffer);
    buffer = NULL;
    SetEvent(ctx->wslOutDoneEvent);
    return 0;
}

static DWORD WINAPI DrainStderrThread(_In_ LPVOID parameter)
{
    RELAY_CONTEXT *ctx = (RELAY_CONTEXT *)parameter;
    char buffer[512] = { 0 };
    DWORD nRead = 0;
    size_t length = 0;

    if (ctx == NULL)
    {
        return 1;
    }

    while (ReadFile(ctx->wslErrRead, buffer, (DWORD)sizeof(buffer), &nRead, NULL) && nRead > 0)
    {
        DWORD limit = (nRead < (DWORD)sizeof(buffer)) ? nRead : (DWORD)sizeof(buffer);

        for (DWORD i = 0; i < limit && length < STDERR_CAP_BYTES; ++i)
        {
            ctx->stderrTail[length] = buffer[i];
            ++length;
        }
    }

    if (length <= STDERR_CAP_BYTES)
    {
        ctx->stderrTail[length] = '\0';
        ctx->stderrLength = length;
    }

    SecureZeroMemory(buffer, sizeof(buffer));
    return 0;
}

static BOOL WINAPI WaitThroughConsoleInterrupt(_In_ DWORD controlType)
{
    return controlType == CTRL_C_EVENT || controlType == CTRL_BREAK_EVENT;
}

static BOOL CreatePipePair(_Out_ HANDLE *readEnd, _Out_ HANDLE *writeEnd, _In_ BOOL inheritRead, _In_ BOOL inheritWrite)
{
    SECURITY_ATTRIBUTES sa;

    sa.nLength = sizeof(sa);
    sa.lpSecurityDescriptor = NULL;
    sa.bInheritHandle = TRUE;

    *readEnd = NULL;
    *writeEnd = NULL;
    if (!CreatePipe(readEnd, writeEnd, &sa, 0))
    {
        return FALSE;
    }

    if ((!inheritRead && !SetHandleInformation(*readEnd, HANDLE_FLAG_INHERIT, 0)) ||
        (!inheritWrite && !SetHandleInformation(*writeEnd, HANDLE_FLAG_INHERIT, 0)))
    {
        CloseHandle(*readEnd);
        CloseHandle(*writeEnd);
        *readEnd = NULL;
        *writeEnd = NULL;
        return FALSE;
    }

    return TRUE;
}

static int RunTui(_In_ int argc, _In_reads_(argc) const wchar_t *const *argv)
{
    const wchar_t *distro = NULL;
    const wchar_t *dir = NULL;
    const wchar_t *wslNvim = NULL;
    const wchar_t *hostNvim = NULL;
    const wchar_t *const *files = NULL;
    int fileCount = 0;
    wchar_t wslExe[MAX_WINDOWS_PATH_CHARS] = { 0 };
    wchar_t pipeName[128] = { 0 };
    wchar_t *hostCmd = NULL;
    wchar_t *wslCmd = NULL;
    const wchar_t **wslForward = NULL;
    size_t hostLen = 0;
    HANDLE pipe = INVALID_HANDLE_VALUE;
    HANDLE connectEvent = NULL;
    OVERLAPPED connectOv;
    HANDLE job = NULL;
    PROCESS_INFORMATION hostProc;
    PROCESS_INFORMATION wslProc;
    HANDLE wslInRead = NULL;
    HANDLE wslOutWrite = NULL;
    HANDLE wslErrWrite = NULL;
    HANDLE threads[3] = { NULL, NULL, NULL };
    DWORD threadCount = 0;
    RELAY_CONTEXT ctx;
    DWORD waitResult = WAIT_FAILED;
    DWORD hostExit = EXIT_FAILED;
    DWORD wslExit = 0;
    DWORD clientPid = 0;
    BOOL connected = FALSE;

    ZeroMemory(&connectOv, sizeof(connectOv));
    ZeroMemory(&hostProc, sizeof(hostProc));
    ZeroMemory(&wslProc, sizeof(wslProc));
    ZeroMemory(&ctx, sizeof(ctx));
    ctx.pipe = INVALID_HANDLE_VALUE;

    if (argc < 6)
    {
        fwprintf(stderr, L"usage: windows_wsl_bridge run-tui DISTRO DIR WSL_NVIM HOST_NVIM [-- FILES...]\n");
        return EXIT_USAGE;
    }

    distro = argv[2];
    dir = argv[3];
    wslNvim = argv[4];
    hostNvim = argv[5];

    if (!ValidateDistroName(distro) || !ValidateLinuxDir(dir) || !ValidateLinuxNvim(wslNvim) ||
        !ValidateWindowsExeOnDisk(hostNvim, L"nvim.exe"))
    {
        fwprintf(stderr, L"windows_wsl_bridge: invalid run-tui argument\n");
        return EXIT_USAGE;
    }

    if (argc > 6)
    {
        if (wcscmp(argv[6], L"--") != 0)
        {
            fwprintf(stderr, L"windows_wsl_bridge: expected '--' before file arguments\n");
            return EXIT_USAGE;
        }

        files = argv + 7;
        fileCount = argc - 7;
        for (int i = 0; i < fileCount; ++i)
        {
            if (!ValidateLinuxArg(files[i]))
            {
                fwprintf(stderr, L"windows_wsl_bridge: invalid file argument\n");
                return EXIT_USAGE;
            }
        }
    }

    if (!ResolveSystemWslExe(wslExe, ARRAYSIZE(wslExe)))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot locate System32\\wsl.exe\n");
        return EXIT_FAILED;
    }

    if (!CreateOwnerOnlyNamedPipe(pipeName, ARRAYSIZE(pipeName), &pipe) || pipe == NULL || pipe == INVALID_HANDLE_VALUE)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot create owner-only Named Pipe (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    connectEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    ctx.stopEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    ctx.wslOutDoneEvent = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (connectEvent == NULL || ctx.stopEvent == NULL || ctx.wslOutDoneEvent == NULL)
    {
        goto Cleanup;
    }

    connectOv.hEvent = connectEvent;
    if (!ConnectNamedPipe(pipe, &connectOv))
    {
        DWORD err = GetLastError();

        if (err == ERROR_PIPE_CONNECTED)
        {
            SetEvent(connectEvent);
        }
        else if (err != ERROR_IO_PENDING)
        {
            fwprintf(stderr, L"windows_wsl_bridge: ConnectNamedPipe failed (error %lu)\n", err);
            goto Cleanup;
        }
    }

    hostCmd = calloc(COMMAND_LINE_MAX_CHARS, sizeof(*hostCmd));
    if (hostCmd == NULL || !AppendQuotedArg(hostCmd, COMMAND_LINE_MAX_CHARS, &hostLen, hostNvim) ||
        !AppendQuotedArg(hostCmd, COMMAND_LINE_MAX_CHARS, &hostLen, L"--server") ||
        !AppendQuotedArg(hostCmd, COMMAND_LINE_MAX_CHARS, &hostLen, pipeName) ||
        !AppendQuotedArg(hostCmd, COMMAND_LINE_MAX_CHARS, &hostLen, L"--remote-ui"))
    {
        fwprintf(stderr, L"windows_wsl_bridge: host nvim command line too long\n");
        goto Cleanup;
    }

    job = CreateKillOnCloseJob();
    if (job == NULL)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot create job object (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    SetConsoleCtrlHandler(WaitThroughConsoleInterrupt, TRUE);
    SetEnvironmentVariableW(L"NVIM", NULL);

    if (!SpawnWithExplicitHandles(hostNvim, hostCmd, CREATE_SUSPENDED | CREATE_DEFAULT_ERROR_MODE,
                                  GetValidStdHandle(STD_INPUT_HANDLE), GetValidStdHandle(STD_OUTPUT_HANDLE),
                                  GetValidStdHandle(STD_ERROR_HANDLE), &hostProc))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot start host nvim.exe (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    if (!AssignProcessToJobObject(job, hostProc.hProcess) || ResumeThread(hostProc.hThread) == (DWORD)-1)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot resume host nvim.exe (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    {
        HANDLE waitConnect[2] = { connectEvent, hostProc.hProcess };
        DWORD dummy = 0;

        waitResult = WaitForMultipleObjects(2, waitConnect, FALSE, CONNECT_TIMEOUT_MS);
        if (waitResult != WAIT_OBJECT_0 || !GetOverlappedResult(pipe, &connectOv, &dummy, FALSE))
        {
            fwprintf(stderr, L"windows_wsl_bridge: host nvim --remote-ui did not connect\n");
            goto Cleanup;
        }
    }

    connected = TRUE;
    if (!GetNamedPipeClientProcessId(pipe, &clientPid) || clientPid != hostProc.dwProcessId ||
        !IsSameUserAndIntegrityProcess(hostProc.hProcess))
    {
        fwprintf(stderr, L"windows_wsl_bridge: unexpected client connected to pipe\n");
        goto Cleanup;
    }

    if (!CreatePipePair(&wslInRead, &ctx.wslInWrite, TRUE, FALSE) ||
        !CreatePipePair(&ctx.wslOutRead, &wslOutWrite, FALSE, TRUE) ||
        !CreatePipePair(&ctx.wslErrRead, &wslErrWrite, FALSE, TRUE))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot create WSL stdio pipes\n");
        goto Cleanup;
    }

    {
        int totalForward = (fileCount > 0) ? fileCount + 2 : 1;

        wslForward = calloc((size_t)totalForward, sizeof(*wslForward));
        wslCmd = calloc(COMMAND_LINE_MAX_CHARS, sizeof(*wslCmd));
        if (wslForward == NULL || wslCmd == NULL)
        {
            goto Cleanup;
        }

        wslForward[0] = L"--embed";
        if (fileCount > 0)
        {
            wslForward[1] = L"--";
            for (int i = 0; i < fileCount; ++i)
            {
                wslForward[i + 2] = files[i];
            }
        }

        if (!BuildWslCommandLine(wslCmd, COMMAND_LINE_MAX_CHARS, wslExe, distro, dir, wslNvim, totalForward,
                                 wslForward))
        {
            fwprintf(stderr, L"windows_wsl_bridge: WSL command line too long\n");
            goto Cleanup;
        }
    }

    if (!ConfigureWslBridgeEnvironment(hostProc.dwProcessId))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot configure WSLENV\n");
        goto Cleanup;
    }

    if (!SpawnWithExplicitHandles(wslExe, wslCmd, CREATE_SUSPENDED | CREATE_NO_WINDOW | CREATE_DEFAULT_ERROR_MODE,
                                  wslInRead, wslOutWrite, wslErrWrite, &wslProc))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot start wsl.exe (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    CloseHandle(wslInRead);
    wslInRead = NULL;
    CloseHandle(wslOutWrite);
    wslOutWrite = NULL;
    CloseHandle(wslErrWrite);
    wslErrWrite = NULL;

    if (!AssignProcessToJobObject(job, wslProc.hProcess) || ResumeThread(wslProc.hThread) == (DWORD)-1)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot start wsl.exe in job (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    ctx.pipe = pipe;
    threads[0] = CreateThread(NULL, 0, PipeToWslThread, &ctx, 0, NULL);
    threads[1] = CreateThread(NULL, 0, WslToPipeThread, &ctx, 0, NULL);
    threads[2] = CreateThread(NULL, 0, DrainStderrThread, &ctx, 0, NULL);
    for (DWORD i = 0; i < 3; ++i)
    {
        if (threads[i] == NULL)
        {
            fwprintf(stderr, L"windows_wsl_bridge: cannot start relay thread\n");
            goto Cleanup;
        }

        ++threadCount;
    }

    {
        HANDLE procWaits[2] = { hostProc.hProcess, wslProc.hProcess };

        waitResult = WaitForMultipleObjects(2, procWaits, FALSE, INFINITE);
        if (waitResult == WAIT_OBJECT_0 + 1)
        {
            WaitForSingleObject(ctx.wslOutDoneEvent, 2000);
            SetEvent(ctx.stopEvent);
            CancelIoEx(pipe, NULL);
            DisconnectNamedPipe(pipe);
            connected = FALSE;
            WaitForSingleObject(hostProc.hProcess, CLEANUP_WAIT_MS);
        }
        else
        {
            CloseWslInWrite(&ctx);
            WaitForSingleObject(wslProc.hProcess, CLEANUP_WAIT_MS);
        }
    }

Cleanup:
    if (ctx.stopEvent != NULL)
    {
        SetEvent(ctx.stopEvent);
    }

    if (pipe != NULL && pipe != INVALID_HANDLE_VALUE)
    {
        CancelIoEx(pipe, NULL);
        if (connected)
        {
            DisconnectNamedPipe(pipe);
        }
    }

    CloseWslInWrite(&ctx);

    if (wslInRead != NULL)
    {
        CloseHandle(wslInRead);
        wslInRead = NULL;
    }

    if (wslOutWrite != NULL)
    {
        CloseHandle(wslOutWrite);
        wslOutWrite = NULL;
    }

    if (wslErrWrite != NULL)
    {
        CloseHandle(wslErrWrite);
        wslErrWrite = NULL;
    }

    if (wslProc.hProcess != NULL)
    {
        if (WaitForSingleObject(wslProc.hProcess, 0) != WAIT_OBJECT_0)
        {
            TerminateProcess(wslProc.hProcess, EXIT_FAILED);
            WaitForSingleObject(wslProc.hProcess, CLEANUP_WAIT_MS);
        }

        if (!GetExitCodeProcess(wslProc.hProcess, &wslExit))
        {
            wslExit = EXIT_FAILED;
        }
    }

    if (hostProc.hProcess != NULL)
    {
        if (WaitForSingleObject(hostProc.hProcess, 0) != WAIT_OBJECT_0)
        {
            TerminateProcess(hostProc.hProcess, EXIT_FAILED);
            WaitForSingleObject(hostProc.hProcess, CLEANUP_WAIT_MS);
        }

        if (!GetExitCodeProcess(hostProc.hProcess, &hostExit))
        {
            hostExit = EXIT_FAILED;
        }
    }

    for (DWORD i = 0; i < threadCount; ++i)
    {
        CancelSynchronousIo(threads[i]);
    }

    if (threadCount > 0)
    {
        WaitForMultipleObjects(threadCount, threads, TRUE, CLEANUP_WAIT_MS);
        for (DWORD i = 0; i < threadCount; ++i)
        {
            CloseHandle(threads[i]);
            threads[i] = NULL;
        }
    }

    if (ctx.wslOutRead != NULL)
    {
        CloseHandle(ctx.wslOutRead);
        ctx.wslOutRead = NULL;
    }

    if (ctx.wslErrRead != NULL)
    {
        CloseHandle(ctx.wslErrRead);
        ctx.wslErrRead = NULL;
    }

    if (pipe != NULL && pipe != INVALID_HANDLE_VALUE)
    {
        CloseHandle(pipe);
        pipe = INVALID_HANDLE_VALUE;
    }

    if (connectEvent != NULL)
    {
        CloseHandle(connectEvent);
        connectEvent = NULL;
    }

    if (ctx.stopEvent != NULL)
    {
        CloseHandle(ctx.stopEvent);
        ctx.stopEvent = NULL;
    }

    if (ctx.wslOutDoneEvent != NULL)
    {
        CloseHandle(ctx.wslOutDoneEvent);
        ctx.wslOutDoneEvent = NULL;
    }

    if (hostProc.hProcess != NULL)
    {
        CloseHandle(hostProc.hProcess);
        hostProc.hProcess = NULL;
    }

    if (hostProc.hThread != NULL)
    {
        CloseHandle(hostProc.hThread);
        hostProc.hThread = NULL;
    }

    if (wslProc.hProcess != NULL)
    {
        CloseHandle(wslProc.hProcess);
        wslProc.hProcess = NULL;
    }

    if (wslProc.hThread != NULL)
    {
        CloseHandle(wslProc.hThread);
        wslProc.hThread = NULL;
    }

    if (job != NULL)
    {
        CloseHandle(job);
        job = NULL;
    }

    if (wslExit != 0 && ctx.stderrLength > 0)
    {
        fwprintf(stderr, L"windows_wsl_bridge: wsl exited with code %lu: %hs\n", wslExit, ctx.stderrTail);
    }

    free((void *)wslForward);
    wslForward = NULL;
    if (hostCmd != NULL)
    {
        SecureZeroMemory(hostCmd, COMMAND_LINE_MAX_CHARS * sizeof(*hostCmd));
        free(hostCmd);
        hostCmd = NULL;
    }

    if (wslCmd != NULL)
    {
        SecureZeroMemory(wslCmd, COMMAND_LINE_MAX_CHARS * sizeof(*wslCmd));
        free(wslCmd);
        wslCmd = NULL;
    }

    SecureZeroMemory(&ctx, sizeof(ctx));
    SecureZeroMemory(wslExe, sizeof(wslExe));
    SecureZeroMemory(pipeName, sizeof(pipeName));
    return (int)hostExit;
}

static int SpawnConsole(_In_ int argc, _In_reads_(argc) const wchar_t *const *argv)
{
    const wchar_t *hostNvim = NULL;
    const wchar_t *scriptPath = NULL;
    wchar_t *commandLine = NULL;
    size_t len = 0;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    BOOL expectDir = FALSE;
    BOOL expectDistro = FALSE;
    BOOL expectNvim = FALSE;
    BOOL expectFile = FALSE;
    BOOL hasTui = FALSE;
    BOOL hasDistro = FALSE;
    int exitCode = EXIT_FAILED;

    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(&process, sizeof(process));

    if (argc < 7)
    {
        fwprintf(stderr, L"usage: windows_wsl_bridge spawn-console HOST_NVIM WSL_LUA --tui --distro NAME ...\n");
        return EXIT_USAGE;
    }

    hostNvim = argv[2];
    scriptPath = argv[3];
    if (!ValidateWindowsExeOnDisk(hostNvim, L"nvim.exe") || !ValidateLocalFileOnDisk(scriptPath) ||
        (!EndsWithInsensitive(scriptPath, L"\\scripts\\wsl.lua") &&
         !EndsWithInsensitive(scriptPath, L"/scripts/wsl.lua")))
    {
        fwprintf(stderr, L"windows_wsl_bridge: invalid host nvim or script path\n");
        return EXIT_USAGE;
    }

    commandLine = calloc(COMMAND_LINE_MAX_CHARS, sizeof(*commandLine));
    if (commandLine == NULL || !AppendQuotedArg(commandLine, COMMAND_LINE_MAX_CHARS, &len, hostNvim) ||
        !AppendQuotedArg(commandLine, COMMAND_LINE_MAX_CHARS, &len, L"-l") ||
        !AppendQuotedArg(commandLine, COMMAND_LINE_MAX_CHARS, &len, scriptPath))
    {
        goto Cleanup;
    }

    for (int i = 4; i < argc; ++i)
    {
        const wchar_t *arg = argv[i];

        if (arg == NULL)
        {
            exitCode = EXIT_USAGE;
            goto Cleanup;
        }

        if (expectDistro)
        {
            if (!ValidateDistroName(arg))
            {
                exitCode = EXIT_USAGE;
                goto Cleanup;
            }

            hasDistro = TRUE;
            expectDistro = FALSE;
        }
        else if (expectDir)
        {
            if (!ValidateBase64Arg(arg))
            {
                exitCode = EXIT_USAGE;
                goto Cleanup;
            }

            expectDir = FALSE;
        }
        else if (expectNvim)
        {
            if (!ValidateLinuxNvim(arg))
            {
                exitCode = EXIT_USAGE;
                goto Cleanup;
            }

            expectNvim = FALSE;
        }
        else if (expectFile)
        {
            if (!ValidateBase64Arg(arg))
            {
                exitCode = EXIT_USAGE;
                goto Cleanup;
            }

            expectFile = FALSE;
        }
        else if (wcscmp(arg, L"--tui") == 0)
        {
            hasTui = TRUE;
        }
        else if (wcscmp(arg, L"--distro") == 0)
        {
            expectDistro = TRUE;
        }
        else if (wcscmp(arg, L"--dir-b64") == 0)
        {
            expectDir = TRUE;
        }
        else if (wcscmp(arg, L"--nvim") == 0)
        {
            expectNvim = TRUE;
        }
        else if (wcscmp(arg, L"--file-b64") == 0)
        {
            expectFile = TRUE;
        }
        else
        {
            exitCode = EXIT_USAGE;
            goto Cleanup;
        }

        if (!AppendQuotedArg(commandLine, COMMAND_LINE_MAX_CHARS, &len, arg))
        {
            exitCode = EXIT_USAGE;
            goto Cleanup;
        }
    }

    if (expectDistro || expectDir || expectNvim || expectFile || !hasTui || !hasDistro)
    {
        exitCode = EXIT_USAGE;
        goto Cleanup;
    }

    SetEnvironmentVariableW(L"NVIM", NULL);
    startup.cb = sizeof(startup);
    if (!CreateProcessW(hostNvim, commandLine, NULL, NULL, FALSE, CREATE_NEW_CONSOLE | CREATE_DEFAULT_ERROR_MODE, NULL,
                        NULL, &startup, &process))
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot open console window (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    exitCode = EXIT_DONE;

Cleanup:
    if (process.hProcess != NULL)
    {
        CloseHandle(process.hProcess);
        process.hProcess = NULL;
    }

    if (process.hThread != NULL)
    {
        CloseHandle(process.hThread);
        process.hThread = NULL;
    }

    if (commandLine != NULL)
    {
        SecureZeroMemory(commandLine, COMMAND_LINE_MAX_CHARS * sizeof(*commandLine));
        free(commandLine);
        commandLine = NULL;
    }

    return exitCode;
}

static BOOL PrepareStdout(void)
{
    if (_setmode(_fileno(stdout), _O_BINARY) == -1 || setvbuf(stdout, NULL, _IONBF, 0) != 0)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot make stdout binary and unbuffered\n");
        return FALSE;
    }

    return TRUE;
}

static void LeaveCallerDirectory(void)
{
    wchar_t systemDirectory[MAX_PATH] = { 0 };
    UINT length = GetSystemDirectoryW(systemDirectory, ARRAYSIZE(systemDirectory));

    if (length > 0 && length < ARRAYSIZE(systemDirectory))
    {
        SetCurrentDirectoryW(systemDirectory);
    }

    SecureZeroMemory(systemDirectory, sizeof(systemDirectory));
}

#ifndef WINDOWS_WSL_BRIDGE_NO_MAIN
int wmain(int argc, wchar_t **argv)
{
    DWORD loadingError = ERROR_SUCCESS;
    DWORD parentPid = 0;

    HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0);
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);

    if (!SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_SYSTEM32))
    {
        loadingError = GetLastError();
    }

    if (loadingError != ERROR_SUCCESS)
    {
        fwprintf(stderr, L"windows_wsl_bridge: cannot limit library loading to System32 (error %lu)\n", loadingError);
        return EXIT_FAILED;
    }

    LeaveCallerDirectory();
    if (argc < 2 || argv == NULL)
    {
        return EXIT_USAGE;
    }

    if (argc == 2 && wcscmp(argv[1], L"version") == 0)
    {
        if (FindDirectParent(L"nvim.exe") == 0)
        {
            fwprintf(stderr, L"windows_wsl_bridge: runs only when Neovim starts it\n");
            return EXIT_NOT_CALLER;
        }

        return (PrepareStdout() && printf("windows_wsl_bridge %s x64\n", WINDOWS_WSL_BRIDGE_COMPILER) >= 0)
                   ? EXIT_DONE
                   : EXIT_FAILED;
    }

    if (wcscmp(argv[1], L"run-tui") == 0)
    {
        if (FindDirectParent(L"nvim.exe") == 0)
        {
            fwprintf(stderr, L"windows_wsl_bridge: run-tui runs only when Neovim starts it\n");
            return EXIT_NOT_CALLER;
        }

        return RunTui(argc, (const wchar_t *const *)argv);
    }

    if (wcscmp(argv[1], L"spawn-console") == 0)
    {
        if (FindDirectParent(L"nvim.exe") == 0)
        {
            fwprintf(stderr, L"windows_wsl_bridge: spawn-console runs only when Neovim starts it\n");
            return EXIT_NOT_CALLER;
        }

        return SpawnConsole(argc, (const wchar_t *const *)argv);
    }

    if (IsNeovideInvocation(argc, (const wchar_t *const *)argv))
    {
        parentPid = FindDirectParent(L"neovide.exe");
        if (parentPid == 0)
        {
            fwprintf(stderr, L"windows_wsl_bridge: --embed mode runs only when Neovide starts it\n");
            return EXIT_NOT_CALLER;
        }

        return RunNeovideEmbed(parentPid, argc, (const wchar_t *const *)argv);
    }

    fwprintf(stderr, L"usage: windows_wsl_bridge version | --embed | run-tui ... | spawn-console ...\n");
    return EXIT_USAGE;
}
#endif
