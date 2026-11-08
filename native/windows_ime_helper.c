// windows_ime_helper: what Windows lacks for Neovim and Linux has elsewhere (fcitx5-remote, the Caps Lock LED, a
// compositor's window raise, symlinks). lua/features/windows_platform/windows_ime_helper.lua builds it on Windows only.
//
//   windows_ime_helper ime-english                foreground IME to its alphanumeric mode
//   windows_ime_helper input-state                <caps><ime> once, 1 = on / native script
//   windows_ime_helper watch-input-state PID [MS] <caps><ime> on each change until PID exits;
//                                                 stdin e, p, r = ime-english, pause, resume
//   windows_ime_helper raise-window PID           raise the window of PID or of its nearest ancestor that has one
//   windows_ime_helper version                    compiler and architecture; the build runs it to prove every
//                                                 import loads
//
// Copied to NAME.exe beside NAME.shim, it runs the program the .shim names instead
// (lua/features/external_programs/registered_programs.lua).
// Runs only for Neovim: its parent must be nvim.exe (a shim's, an ancestor within a few levels, for :terminal),
// and watch serves only that parent. It ends with Neovim: watch waits on Neovim's process and its stdin pipe, and
// Neovim (libuv) keeps its children in a kill-on-close job.
// Exit codes: 0 done, 1 failed, 2 usage, 3 protocol violation on stdin, 4 not started by Neovim, 127 shim cannot
// run its program.
// It reads no keystrokes, only Caps Lock and the IME's mode, polled rather than hooked: any event source for them
// (a low-level keyboard hook, raw input) would see every key. Even that state is wiped once used.
// Every function releases what it acquired and wipes what it filled on every path, through one Cleanup exit.
// Style: native/.clang-format. Tests: tests/windows_ime_helper/.

// Native x86_64 Windows only: stop before any Windows header is read.
#if defined(__APPLE__)
#error "windows_ime_helper is a Windows program; this is a macOS target."
#elif defined(__linux__)
#error "windows_ime_helper is a Windows program; this is a Linux target."
#elif defined(__CYGWIN__) || defined(__MSYS__)
#error "windows_ime_helper is a native Windows program; Cygwin and MSYS emulate Unix."
#elif !defined(_WIN32) || !defined(_WIN64)
#error "windows_ime_helper is a 64-bit Windows program; this target is not."
#endif

// ARM64EC defines _M_X64 too.
#if !(defined(_M_X64) || defined(__x86_64__)) || defined(_M_ARM64EC) || defined(_M_ARM64) || defined(__aarch64__)
#error "windows_ime_helper targets x86_64 Windows only."
#endif

// MSVC, or clang targeting the MSVC ABI (clang-cl, clang --target=x86_64-pc-windows-msvc); clang defines _MSC_VER
// there too. MinGW (gcc, its clang, zig cc) is refused: another C runtime and other headers than the ones tested.
#if defined(__MINGW32__) || defined(__MINGW64__)
#error "windows_ime_helper: MinGW is not supported; build with Visual Studio's cl, or clang targeting MSVC."
#elif defined(_MSC_VER) && !defined(__clang__)
#define WINDOWS_IME_HELPER_COMPILER "msvc"
#elif defined(_MSC_VER) && defined(__clang__)
#define WINDOWS_IME_HELPER_COMPILER "clang"
#else
#error "windows_ime_helper: unknown compiler; build with Visual Studio's cl, or clang targeting MSVC."
#endif

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <fcntl.h>
#include <imm.h>
#include <io.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <tlhelp32.h>
#include <wchar.h>

// Last, so it retires the unbounded string functions for everything above.
#include <strsafe.h>

#ifdef _MSC_VER
#pragma comment(lib, "imm32.lib")
#pragma comment(lib, "user32.lib")
#endif

// Older MinGW-w64 headers lack it.
#ifndef WM_IME_CONTROL
#define WM_IME_CONTROL 0x0283
#endif

#define IMC_GETCONVERSIONMODE 0x0001
#define IMC_SETCONVERSIONMODE 0x0002
#define IMC_GETOPENSTATUS 0x0005

#define EXIT_DONE 0
#define EXIT_FAILED 1
#define EXIT_USAGE 2
#define EXIT_PROTOCOL 3
#define EXIT_NOT_NEOVIM 4
#define EXIT_SHIM 127

#define IME_TIMEOUT_MS 100
#define DEFAULT_INTERVAL_MS 100
#define MIN_INTERVAL_MS 20
#define MAX_INTERVAL_MS 60000
#define PAUSED_WAKE_MS 1000
#define READER_STOP_ATTEMPTS 20
#define READER_STOP_WAIT_MS 50
#define MAX_LINEAGE 16

// nvim.exe -> shell -> tool from :terminal, with a wrapper or two between.
#define SHIM_CALLER_DEPTH 6

#define MODE_NONE 0
#define MODE_PAUSE 1
#define MODE_RESUME 2

// A .shim this configuration writes is one short line; anything bigger is refused, never truncated.
#define SHIM_FILE_MAX_BYTES (4 * MAX_PATH)
#define SHIM_PATH_MAX_CHARS (2 * MAX_PATH)

// CreateProcess's limit, terminating null included.
#define COMMAND_LINE_MAX_CHARS 32767

#define SHIM_LOG_NAME L"windows_ime_helper_shims.log"
#define SHIM_LOG_MAX_BYTES (64 * 1024)

typedef struct _PROCESS_LINK
{
    DWORD processId;
    DWORD parentProcessId;
} PROCESS_LINK;

typedef struct _WINDOW_QUERY
{
    const DWORD *lineage;
    int length;
    int nearest;
    HWND found;
} WINDOW_QUERY;

typedef enum _PATH_KIND
{
    PATH_ABSOLUTE,
    PATH_RELATIVE,
    PATH_REFUSED
} PATH_KIND;

typedef enum _SHIM_RESULT
{
    SHIM_OK,
    SHIM_NOT_A_SHIM,
    SHIM_NO_SELF,
    SHIM_CANNOT_OPEN,
    SHIM_NOT_A_DISK_FILE,
    SHIM_NO_SIZE,
    SHIM_BAD_SIZE,
    SHIM_CANNOT_READ,
    SHIM_SHORT_READ,
    SHIM_BAD_CHARACTER,
    SHIM_EMPTY,
    SHIM_NOT_UTF8,
    SHIM_PATH_REFUSED,
    SHIM_STREAM,
    SHIM_CANNOT_RESOLVE,
    SHIM_NOT_A_PROGRAM,
    SHIM_NOT_LOCAL,
    SHIM_TARGET_MISSING,
    SHIM_TARGET_IS_DIRECTORY,
    SHIM_TARGET_IS_SHIM,
    SHIM_TARGET_IS_SELF,
    SHIM_CANNOT_IDENTIFY,
    SHIM_BAD_ARGUMENT
} SHIM_RESULT;

static volatile LONG gs_isEnglishWanted = 0;
static volatile LONG gs_requestedMode = MODE_NONE;
static volatile LONG gs_isInputClosed = 0;
static volatile LONG gs_isProtocolViolated = 0;
static volatile LONG gs_isReaderStopping = 0;
static HANDLE gs_commandEvent = NULL;

static HWND GetForegroundImeWindow(_Out_opt_ LANGID *language)
{
    HWND foreground = GetForegroundWindow();

    if (language != NULL)
    {
        *language = foreground ? LOWORD((DWORD_PTR)GetKeyboardLayout(GetWindowThreadProcessId(foreground, NULL))) : 0;
    }

    return foreground ? ImmGetDefaultIMEWnd(foreground) : NULL;
}

// With a timeout: a hung foreground program must not hang Neovim's helper.
_Success_(return != FALSE) static BOOL
    QueryIme(_In_opt_ HWND ime, _In_ WPARAM command, _In_ LPARAM argument, _Out_opt_ DWORD_PTR *result)
{
    DWORD_PTR answer = 0;
    BOOL wasSent = FALSE;

    if (result != NULL)
    {
        *result = 0;
    }

    wasSent = ime != NULL && IsWindow(ime) &&
              SendMessageTimeoutW(ime, WM_IME_CONTROL, command, argument, SMTO_ABORTIFHUNG, IME_TIMEOUT_MS, &answer);
    if (wasSent && result != NULL)
    {
        *result = answer;
    }

    SecureZeroMemory(&answer, sizeof(answer));
    return wasSent;
}

static BOOL IsImeNative(void)
{
    LANGID language = 0;
    HWND ime = GetForegroundImeWindow(&language);
    DWORD_PTR openStatus = 0;
    DWORD_PTR conversionMode = 0;
    BOOL isNative = FALSE;

    if (QueryIme(ime, IMC_GETCONVERSIONMODE, 0, &conversionMode) && (conversionMode & IME_CMODE_NATIVE))
    {
        // Microsoft's Korean IME reports itself closed even in Hangul mode.
        isNative = PRIMARYLANGID(language) == LANG_KOREAN ||
                   (QueryIme(ime, IMC_GETOPENSTATUS, 0, &openStatus) && openStatus != 0);
    }

    SecureZeroMemory(&language, sizeof(language));
    SecureZeroMemory(&openStatus, sizeof(openStatus));
    SecureZeroMemory(&conversionMode, sizeof(conversionMode));
    return isNative;
}

// Clears only the native bit, so the keyboard layout and the user's other IME modes survive. No IME, or one
// already alphanumeric, is success: there is nothing to change.
static int SetImeEnglish(void)
{
    HWND ime = GetForegroundImeWindow(NULL);
    DWORD_PTR conversionMode = 0;
    LPARAM english = 0;
    int result = EXIT_DONE;

    if (QueryIme(ime, IMC_GETCONVERSIONMODE, 0, &conversionMode) && (conversionMode & IME_CMODE_NATIVE))
    {
        english = (LPARAM)(conversionMode & ~(DWORD_PTR)IME_CMODE_NATIVE);
        result = QueryIme(ime, IMC_SETCONVERSIONMODE, english, NULL) ? EXIT_DONE : EXIT_FAILED;
    }

    SecureZeroMemory(&english, sizeof(english));
    SecureZeroMemory(&conversionMode, sizeof(conversionMode));
    return result;
}

static int QueryIndicatorState(void)
{
    BOOL isCapsLockOn = (GetKeyState(VK_CAPITAL) & 1) != 0;
    int state = (isCapsLockOn ? 1 : 0) | (IsImeNative() ? 2 : 0);

    SecureZeroMemory(&isCapsLockOn, sizeof(isCapsLockOn));
    return state;
}

// One write of two digits and a newline: stdout is unbuffered, so nothing is kept to flush.
static int PrintIndicatorState(_In_ int state)
{
    char line[4] = { 0 };
    int result = -1;

    if (state < 0 || state > 3)
    {
        return -1;
    }

    line[0] = (char)('0' + (state & 1));
    line[1] = (char)('0' + ((state >> 1) & 1));
    line[2] = '\n';
    result = fwrite(line, 1, 3, stdout) == 3 ? 0 : -1;
    SecureZeroMemory(line, sizeof(line));
    return result;
}

// Commands come through stdin so Neovim starts no process per Insert leave or focus change. A byte outside the
// protocol means the two sides disagree; guessing could flip the user's IME at random, so the watcher stops.
static DWORD WINAPI ReadCommandsThread(_In_opt_ LPVOID parameter)
{
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    char buffer[64] = { 0 };
    DWORD bytesRead = 0;
    DWORD result = EXIT_DONE;

    UNREFERENCED_PARAMETER(parameter);

    if (input == NULL || input == INVALID_HANDLE_VALUE || gs_commandEvent == NULL)
    {
        InterlockedExchange(&gs_isInputClosed, 1);
        return EXIT_FAILED;
    }

    while (result == EXIT_DONE && !gs_isReaderStopping && ReadFile(input, buffer, sizeof(buffer), &bytesRead, NULL) &&
           bytesRead > 0)
    {
        for (DWORD i = 0; i < bytesRead && i < sizeof(buffer); ++i)
        {
            if (buffer[i] == 'e')
            {
                InterlockedExchange(&gs_isEnglishWanted, 1);
            }
            else if (buffer[i] == 'p')
            {
                InterlockedExchange(&gs_requestedMode, MODE_PAUSE);
            }
            else if (buffer[i] == 'r')
            {
                InterlockedExchange(&gs_requestedMode, MODE_RESUME);
            }
            else if (buffer[i] != '\n' && buffer[i] != '\r')
            {
                InterlockedExchange(&gs_isProtocolViolated, 1);
                result = EXIT_PROTOCOL;
                break;
            }
        }

        SecureZeroMemory(buffer, sizeof(buffer));
        bytesRead = 0;
        SetEvent(gs_commandEvent);
    }

    SecureZeroMemory(buffer, sizeof(buffer));
    InterlockedExchange(&gs_isInputClosed, 1);
    SetEvent(gs_commandEvent);
    return result;
}

// The reader may sit in ReadFile on stdin: it is told to stop, its read cancelled until it ends, and only then is its
// event closed, since closing a handle a thread still uses could hand that number to another object.
static void StopCommandReader(_In_opt_ HANDLE reader)
{
    BOOL hasEnded = reader == NULL;

    InterlockedExchange(&gs_isReaderStopping, 1);
    for (int attempt = 0; attempt < READER_STOP_ATTEMPTS && !hasEnded; ++attempt)
    {
        CancelSynchronousIo(reader);
        hasEnded = WaitForSingleObject(reader, READER_STOP_WAIT_MS) == WAIT_OBJECT_0;
    }

    if (reader != NULL)
    {
        CloseHandle(reader);
    }

    if (hasEnded && gs_commandEvent != NULL)
    {
        CloseHandle(gs_commandEvent);
        gs_commandEvent = NULL;
    }
}

static int WatchIndicatorState(_In_ DWORD ownerPid, _In_ DWORD intervalMs)
{
    HANDLE owner = NULL;
    HANDLE reader = NULL;
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    HANDLE waits[2] = { NULL, NULL };
    DWORD waitCount = 1;
    DWORD waitResult = WAIT_FAILED;
    LONG mode = MODE_NONE;
    int state = 0;
    int lastState = -1;
    int result = EXIT_DONE;
    BOOL isPaused = FALSE;

    if (ownerPid == 0 || intervalMs < MIN_INTERVAL_MS || intervalMs > MAX_INTERVAL_MS)
    {
        return EXIT_USAGE;
    }

    owner = OpenProcess(SYNCHRONIZE, FALSE, ownerPid);
    if (owner == NULL)
    {
        fwprintf(stderr, L"watch-input-state: process %lu not found (error %lu)\n", ownerPid, GetLastError());
        return EXIT_FAILED;
    }

    // Waiting on the owner is the poll's sleep and its exit test in one; the handle also pins the process, so a
    // reused pid cannot stand in for it.
    waits[0] = owner;

    // Only a pipe: reading a console stdin would take the user's keystrokes. A pipe means the caller sends
    // commands, so a watcher that cannot receive them fails instead of silently ignoring them.
    if (input != NULL && input != INVALID_HANDLE_VALUE && GetFileType(input) == FILE_TYPE_PIPE)
    {
        gs_commandEvent = CreateEventW(NULL, FALSE, FALSE, NULL);
        if (gs_commandEvent != NULL)
        {
            reader = CreateThread(NULL, 0, ReadCommandsThread, NULL, 0, NULL);
        }

        if (reader == NULL)
        {
            fwprintf(stderr, L"watch-input-state: cannot read commands (error %lu)\n", GetLastError());
            result = EXIT_FAILED;
            goto Cleanup;
        }

        waits[waitCount] = gs_commandEvent;
        ++waitCount;
    }

    while (1)
    {
        if (!isPaused)
        {
            state = QueryIndicatorState();
            if (state != lastState)
            {
                lastState = state;
                if (PrintIndicatorState(state) != 0)
                {
                    break;
                }
            }
        }

        waitResult = WaitForMultipleObjects(waitCount, waits, FALSE, isPaused ? PAUSED_WAKE_MS : intervalMs);
        if (waitResult == WAIT_OBJECT_0)
        {
            break;
        }

        if (waitResult == WAIT_FAILED)
        {
            result = EXIT_FAILED;
            break;
        }

        // Commands are taken at every wake, not only when signalled: a lost SetEvent then delays them instead
        // of losing them.
        mode = InterlockedExchange(&gs_requestedMode, MODE_NONE);
        if (gs_isProtocolViolated)
        {
            fwprintf(stderr, L"watch-input-state: unknown command on stdin\n");
            result = EXIT_PROTOCOL;
            break;
        }

        if (InterlockedExchange(&gs_isEnglishWanted, 0))
        {
            SetImeEnglish();
        }

        if (mode == MODE_PAUSE)
        {
            isPaused = TRUE;
        }
        else if (mode == MODE_RESUME)
        {
            isPaused = FALSE;
            lastState = -1;
        }

        if (gs_isInputClosed)
        {
            break;
        }
    }

Cleanup:
    StopCommandReader(reader);
    CloseHandle(owner);
    SecureZeroMemory(&state, sizeof(state));
    SecureZeroMemory(&lastState, sizeof(lastState));
    SecureZeroMemory(&mode, sizeof(mode));
    return result;
}

// One pass over the top-level windows serves the whole lineage, keeping the window of the nearest ancestor.
static BOOL CALLBACK MatchLineageWindow(_In_ HWND window, _In_ LPARAM parameter)
{
    WINDOW_QUERY *query = (WINDOW_QUERY *)parameter;
    DWORD processId = 0;

    if (query == NULL || query->lineage == NULL || query->length <= 0 || query->length > MAX_LINEAGE)
    {
        return FALSE;
    }

    if (window == NULL || !IsWindowVisible(window) || GetWindow(window, GW_OWNER) != NULL ||
        GetWindowThreadProcessId(window, &processId) == 0 || processId == 0)
    {
        return TRUE;
    }

    for (int i = 0; i < query->nearest && i < query->length; ++i)
    {
        if (query->lineage[i] == processId)
        {
            query->nearest = i;
            query->found = window;
            break;
        }
    }

    // The process itself has a window: no ancestor can be nearer.
    return query->nearest != 0;
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
    return startTime;
}

// The lineage's length, or -1 when the process list cannot be held: a partial list could raise a stranger.
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
            size_t grown = linkCapacity ? linkCapacity * 2 : 512;
            PROCESS_LINK *next = grown <= SIZE_MAX / sizeof(*links) ? realloc(links, grown * sizeof(*links)) : NULL;

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

    // 0 is the idle process and 4 the kernel: neither is anyone's ancestor worth raising.
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

        // Windows reuses pids: a "parent" started after its child is someone else, and one whose start time cannot
        // be read cannot be told apart from that. A pid that is its own parent would loop.
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
    }

    SecureZeroMemory(&entry, sizeof(entry));
    CloseHandle(snapshot);
    return length;
}

// A process in a classic console owns no window; conhost does, and only AttachConsole reaches it.
static HWND FindConsoleWindow(_In_ DWORD processId)
{
    HWND window = NULL;
    HWND root = NULL;

    if (processId == 0)
    {
        return NULL;
    }

    FreeConsole();
    if (AttachConsole(processId))
    {
        window = GetConsoleWindow();
        FreeConsole();
    }

    if (window != NULL)
    {
        root = GetAncestor(window, GA_ROOTOWNER);
        if (root != NULL)
        {
            window = root;
        }
    }

    return window != NULL && IsWindowVisible(window) ? window : NULL;
}

// The foreground lock refuses SetForegroundWindow to most background processes; joining the foreground
// thread's input, then making a zero-length mouse move the last input event, gets past it.
static BOOL BringToForeground(_In_opt_ HWND window)
{
    HWND foreground = NULL;
    DWORD foregroundThread = 0;
    DWORD currentThread = GetCurrentThreadId();
    BOOL isAttached = FALSE;
    BOOL isForeground = FALSE;
    MSG message;
    INPUT input;

    ZeroMemory(&message, sizeof(message));
    ZeroMemory(&input, sizeof(input));

    // The window may have closed since it was found.
    if (window == NULL || !IsWindow(window))
    {
        return FALSE;
    }

    PeekMessageW(&message, NULL, 0, 0, PM_NOREMOVE);
    if (IsIconic(window))
    {
        ShowWindow(window, SW_RESTORE);
    }

    if (SetForegroundWindow(window) && GetForegroundWindow() == window)
    {
        isForeground = TRUE;
        goto Cleanup;
    }

    foreground = GetForegroundWindow();
    foregroundThread = foreground ? GetWindowThreadProcessId(foreground, NULL) : 0;
    if (foregroundThread != 0 && foregroundThread != currentThread)
    {
        isAttached = AttachThreadInput(currentThread, foregroundThread, TRUE);
    }

    BringWindowToTop(window);
    SetForegroundWindow(window);
    if (isAttached)
    {
        AttachThreadInput(currentThread, foregroundThread, FALSE);
    }

    if (GetForegroundWindow() != window)
    {
        input.type = INPUT_MOUSE;
        input.mi.dwFlags = MOUSEEVENTF_MOVE;
        SendInput(1, &input, sizeof(input));
        SetForegroundWindow(window);
    }

    isForeground = GetForegroundWindow() == window;

Cleanup:
    SecureZeroMemory(&message, sizeof(message));
    SecureZeroMemory(&input, sizeof(input));
    return isForeground;
}

static int RaiseProcessLineage(_In_ DWORD processId)
{
    DWORD lineage[MAX_LINEAGE] = { 0 };
    WINDOW_QUERY query = { lineage, 0, 0, NULL };
    HWND window = NULL;
    int length = -1;
    int result = EXIT_FAILED;

    if (processId != 0)
    {
        length = GetProcessLineage(processId, lineage, MAX_LINEAGE);
    }

    if (length <= 0)
    {
        fwprintf(stderr, L"raise-window: cannot read the lineage of process %lu\n", processId);
        goto Cleanup;
    }

    query.length = length;
    query.nearest = length;
    SetLastError(ERROR_SUCCESS);
    if (!EnumWindows(MatchLineageWindow, (LPARAM)&query) && query.found == NULL && GetLastError() != ERROR_SUCCESS)
    {
        fwprintf(stderr, L"raise-window: cannot list the windows (error %lu)\n", GetLastError());
        goto Cleanup;
    }

    window = query.found;
    for (int i = 0; window == NULL && i < length; ++i)
    {
        window = FindConsoleWindow(lineage[i]);
    }

    if (window != NULL)
    {
        result = BringToForeground(window) ? EXIT_DONE : EXIT_FAILED;
    }

Cleanup:
    SecureZeroMemory(lineage, sizeof(lineage));
    SecureZeroMemory(&query, sizeof(query));
    return result;
}

static BOOL IsNeovimProcess(_In_ DWORD processId)
{
    wchar_t image[SHIM_PATH_MAX_CHARS] = { 0 };
    DWORD length = ARRAYSIZE(image);
    const wchar_t *name = NULL;
    HANDLE process = NULL;
    BOOL isNeovim = FALSE;

    if (processId == 0)
    {
        return FALSE;
    }

    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, processId);
    if (process == NULL)
    {
        return FALSE;
    }

    if (QueryFullProcessImageNameW(process, 0, image, &length) && length > 0 && length < ARRAYSIZE(image))
    {
        name = wcsrchr(image, L'\\');
        name = name != NULL ? name + 1 : image;
        isNeovim = CompareStringOrdinal(name, -1, L"nvim.exe", -1, TRUE) == CSTR_EQUAL;
    }

    CloseHandle(process);
    SecureZeroMemory(image, sizeof(image));
    return isNeovim;
}

// The Neovim among this process's nearest ancestors (depth 1 is the parent), or 0. The lineage stops at a reused
// pid, so a Neovim started after this process cannot pass for its caller.
static DWORD FindNeovimCaller(_In_ int depth)
{
    DWORD lineage[MAX_LINEAGE] = { 0 };
    DWORD caller = 0;
    int length = -1;

    if (depth <= 0 || depth >= MAX_LINEAGE)
    {
        return 0;
    }

    length = GetProcessLineage(GetCurrentProcessId(), lineage, MAX_LINEAGE);
    for (int i = 1; caller == 0 && i < length && i <= depth; ++i)
    {
        if (IsNeovimProcess(lineage[i]))
        {
            caller = lineage[i];
        }
    }

    SecureZeroMemory(lineage, sizeof(lineage));
    return caller;
}

static int RefuseCaller(void)
{
    fwprintf(stderr, L"windows_ime_helper: runs only when Neovim starts it\n");
    return EXIT_NOT_NEOVIM;
}

static const wchar_t *DescribeShimResult(_In_ SHIM_RESULT result)
{
    switch (result)
    {
    case SHIM_OK:
        return L"ok";
    case SHIM_NOT_A_SHIM:
        return L"not a shim";
    case SHIM_NO_SELF:
        return L"cannot read this program's own path";
    case SHIM_CANNOT_OPEN:
        return L"cannot open the .shim";
    case SHIM_NOT_A_DISK_FILE:
        return L"the .shim is not a file on disk";
    case SHIM_NO_SIZE:
        return L"cannot read the .shim's size";
    case SHIM_BAD_SIZE:
        return L"the .shim is empty or too large";
    case SHIM_CANNOT_READ:
        return L"cannot read the .shim";
    case SHIM_SHORT_READ:
        return L"the .shim changed while being read";
    case SHIM_BAD_CHARACTER:
        return L"a control character in the .shim's path";
    case SHIM_EMPTY:
        return L"the .shim's first line is empty";
    case SHIM_NOT_UTF8:
        return L"the .shim is not UTF-8, or its path is too long";
    case SHIM_PATH_REFUSED:
        return L"drive-relative, rooted, device and network paths are refused";
    case SHIM_STREAM:
        return L"alternate data streams are refused";
    case SHIM_CANNOT_RESOLVE:
        return L"cannot resolve the path";
    case SHIM_NOT_A_PROGRAM:
        return L"only .exe and .com programs run";
    case SHIM_NOT_LOCAL:
        return L"only programs on a local disk run";
    case SHIM_TARGET_MISSING:
        return L"the program does not exist";
    case SHIM_TARGET_IS_DIRECTORY:
        return L"the path names a directory or a device";
    case SHIM_TARGET_IS_SHIM:
        return L"the program is another shim";
    case SHIM_TARGET_IS_SELF:
        return L"the program is this shim";
    case SHIM_CANNOT_IDENTIFY:
        return L"cannot identify the program's file";
    case SHIM_BAD_ARGUMENT:
    default:
        return L"invalid argument";
    }
}

// SHIM_OK and both paths when this copy is a shim (NAME.exe beside NAME.shim), SHIM_NOT_A_SHIM when it is
// windows_ime_helper itself; anything else is a failure: without its own path it cannot tell which it is.
static SHIM_RESULT FindShimFile(_Out_writes_z_(capacity) wchar_t *self, _Out_writes_z_(capacity) wchar_t *shim,
                                _In_ DWORD capacity, _Out_ DWORD *lastError)
{
    DWORD length = 0;
    DWORD attributes = INVALID_FILE_ATTRIBUTES;
    wchar_t *extension = NULL;
    SHIM_RESULT result = SHIM_NO_SELF;

    if (lastError == NULL)
    {
        return SHIM_BAD_ARGUMENT;
    }

    *lastError = ERROR_SUCCESS;
    if (self == NULL || shim == NULL || capacity == 0)
    {
        return SHIM_BAD_ARGUMENT;
    }

    ZeroMemory(self, capacity * sizeof(*self));
    ZeroMemory(shim, capacity * sizeof(*shim));

    // length == capacity means the name was cut short.
    length = GetModuleFileNameW(NULL, self, capacity);
    if (length == 0 || length >= capacity)
    {
        *lastError = length == 0 ? GetLastError() : ERROR_INSUFFICIENT_BUFFER;
        goto Cleanup;
    }

    if (FAILED(StringCchCopyW(shim, capacity, self)))
    {
        goto Cleanup;
    }

    extension = wcsrchr(shim, L'.');
    if (extension == NULL || CompareStringOrdinal(extension, -1, L".exe", -1, TRUE) != CSTR_EQUAL ||
        FAILED(StringCchCopyW(extension, capacity - (size_t)(extension - shim), L".shim")))
    {
        goto Cleanup;
    }

    attributes = GetFileAttributesW(shim);
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        // Missing is the plain windows_ime_helper case; anything else (access denied, ...) leaves it undecided.
        *lastError = GetLastError();
        result = *lastError == ERROR_FILE_NOT_FOUND || *lastError == ERROR_PATH_NOT_FOUND ? SHIM_NOT_A_SHIM
                                                                                          : SHIM_CANNOT_OPEN;
        goto Cleanup;
    }

    result = attributes & FILE_ATTRIBUTE_DIRECTORY ? SHIM_NOT_A_DISK_FILE : SHIM_OK;

Cleanup:
    if (result != SHIM_OK)
    {
        SecureZeroMemory(self, capacity * sizeof(*self));
        SecureZeroMemory(shim, capacity * sizeof(*shim));
        self[0] = L'\0';
        shim[0] = L'\0';
    }

    return result;
}

// Only a drive path (C:\...) or a plain relative one. Drive-relative (C:tool.exe) and rooted (\tool.exe) paths change
// meaning with the current drive and directory; device paths (\\.\, \\?\) never name a program here; shares
// (\\server\...) would fetch it from the network, handing the user's credentials to whoever answers.
static PATH_KIND ClassifyPath(_In_opt_z_ const wchar_t *path)
{
    BOOL isLetter = FALSE;

    if (path == NULL || path[0] == L'\0')
    {
        return PATH_REFUSED;
    }

    isLetter = (path[0] >= L'A' && path[0] <= L'Z') || (path[0] >= L'a' && path[0] <= L'z');
    if (isLetter && path[1] == L':')
    {
        return path[2] == L'\\' || path[2] == L'/' ? PATH_ABSOLUTE : PATH_REFUSED;
    }

    return path[0] == L'\\' || path[0] == L'/' ? PATH_REFUSED : PATH_RELATIVE;
}

// The .shim's first line as a full path: UTF-8, no control characters, absolute or relative to the .shim's own
// directory (never the current one, which the caller controls), with "." and ".." resolved. No colon may follow
// the drive's: tool.exe:stream would run an alternate data stream.
static SHIM_RESULT ParseShimContent(_In_reads_bytes_opt_(size) const char *bytes, _In_ size_t size,
                                    _In_opt_z_ const wchar_t *shimDirectory, _Out_writes_z_(capacity) wchar_t *target,
                                    _In_ DWORD capacity)
{
    wchar_t line[SHIM_PATH_MAX_CHARS] = { 0 };
    wchar_t joined[SHIM_PATH_MAX_CHARS] = { 0 };
    const wchar_t *source = NULL;
    size_t lineLength = 0;
    int converted = 0;
    DWORD fullLength = 0;
    PATH_KIND kind = PATH_REFUSED;
    SHIM_RESULT result = SHIM_OK;

    if (target == NULL || capacity == 0)
    {
        return SHIM_BAD_ARGUMENT;
    }

    target[0] = L'\0';
    if (bytes == NULL || shimDirectory == NULL || size == 0 || size > SHIM_FILE_MAX_BYTES ||
        ClassifyPath(shimDirectory) != PATH_ABSOLUTE)
    {
        return SHIM_BAD_ARGUMENT;
    }

    while (lineLength < size && bytes[lineLength] != '\n' && bytes[lineLength] != '\r')
    {
        if ((unsigned char)bytes[lineLength] < 0x20 || bytes[lineLength] == 0x7F)
        {
            result = SHIM_BAD_CHARACTER;
            goto Cleanup;
        }

        ++lineLength;
    }

    if (lineLength == 0)
    {
        result = SHIM_EMPTY;
        goto Cleanup;
    }

    // MB_ERR_INVALID_CHARS: malformed UTF-8 is refused rather than replaced; 0 also means the line is too long.
    converted = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, bytes, (int)lineLength, line, ARRAYSIZE(line) - 1);
    if (converted <= 0 || converted >= (int)ARRAYSIZE(line))
    {
        result = SHIM_NOT_UTF8;
        goto Cleanup;
    }

    line[converted] = L'\0';
    kind = ClassifyPath(line);
    if (kind == PATH_ABSOLUTE)
    {
        source = line;
    }
    else if (kind != PATH_RELATIVE)
    {
        result = SHIM_PATH_REFUSED;
        goto Cleanup;
    }
    else if (FAILED(StringCchPrintfW(joined, ARRAYSIZE(joined), L"%ls\\%ls", shimDirectory, line)))
    {
        result = SHIM_NOT_UTF8;
        goto Cleanup;
    }
    else
    {
        source = joined;
    }

    if (wcschr(source + 2, L':') != NULL)
    {
        result = SHIM_STREAM;
        goto Cleanup;
    }

    fullLength = GetFullPathNameW(source, capacity, target, NULL);
    if (fullLength == 0 || fullLength >= capacity || ClassifyPath(target) != PATH_ABSOLUTE)
    {
        result = SHIM_CANNOT_RESOLVE;
    }

Cleanup:
    if (result != SHIM_OK)
    {
        SecureZeroMemory(target, capacity * sizeof(*target));
    }

    SecureZeroMemory(line, sizeof(line));
    SecureZeroMemory(joined, sizeof(joined));
    return result;
}

// Volume serial number and file index identify a file whatever its spelling: case, 8.3 name, hard link, link.
_Success_(return != FALSE) static BOOL GetFileId(_In_opt_z_ const wchar_t *path, _Out_ BY_HANDLE_FILE_INFORMATION *info)
{
    HANDLE file = INVALID_HANDLE_VALUE;
    BOOL wasRead = FALSE;

    if (info == NULL)
    {
        return FALSE;
    }

    ZeroMemory(info, sizeof(*info));
    if (path == NULL || path[0] == L'\0')
    {
        return FALSE;
    }

    file = CreateFileW(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
    {
        return FALSE;
    }

    wasRead = GetFileInformationByHandle(file, info);
    if (!wasRead)
    {
        SecureZeroMemory(info, sizeof(*info));
    }

    CloseHandle(file);
    return wasRead;
}

// An existing .exe or .com on a local disk that is neither this shim nor another one: shims naming each other
// would start one another forever, and a mapped network drive is a share by another name. What cannot be checked
// is refused.
static SHIM_RESULT CheckShimTarget(_In_opt_z_ const wchar_t *target, _In_opt_z_ const wchar_t *self,
                                   _Out_ DWORD *lastError)
{
    const wchar_t *extension = NULL;
    const wchar_t *separator = NULL;
    wchar_t root[4] = { 0 };
    wchar_t sibling[SHIM_PATH_MAX_CHARS] = { 0 };
    BY_HANDLE_FILE_INFORMATION targetId;
    BY_HANDLE_FILE_INFORMATION selfId;
    UINT driveType = DRIVE_UNKNOWN;
    DWORD attributes = INVALID_FILE_ATTRIBUTES;
    SHIM_RESULT result = SHIM_OK;

    ZeroMemory(&targetId, sizeof(targetId));
    ZeroMemory(&selfId, sizeof(selfId));
    if (lastError == NULL)
    {
        return SHIM_BAD_ARGUMENT;
    }

    *lastError = ERROR_SUCCESS;
    if (target == NULL || self == NULL || ClassifyPath(target) != PATH_ABSOLUTE || ClassifyPath(self) != PATH_ABSOLUTE)
    {
        return SHIM_BAD_ARGUMENT;
    }

    extension = wcsrchr(target, L'.');
    separator = wcsrchr(target, L'\\');
    if (extension == NULL || separator == NULL || extension < separator ||
        (CompareStringOrdinal(extension, -1, L".exe", -1, TRUE) != CSTR_EQUAL &&
         CompareStringOrdinal(extension, -1, L".com", -1, TRUE) != CSTR_EQUAL))
    {
        return SHIM_NOT_A_PROGRAM;
    }

    root[0] = target[0];
    root[1] = L':';
    root[2] = L'\\';
    driveType = GetDriveTypeW(root);
    if (driveType != DRIVE_FIXED && driveType != DRIVE_REMOVABLE && driveType != DRIVE_RAMDISK)
    {
        result = SHIM_NOT_LOCAL;
        goto Cleanup;
    }

    attributes = GetFileAttributesW(target);
    if (attributes == INVALID_FILE_ATTRIBUTES)
    {
        *lastError = GetLastError();
        result = SHIM_TARGET_MISSING;
        goto Cleanup;
    }

    if (attributes & (FILE_ATTRIBUTE_DIRECTORY | FILE_ATTRIBUTE_DEVICE))
    {
        result = SHIM_TARGET_IS_DIRECTORY;
        goto Cleanup;
    }

    if (FAILED(StringCchCopyNW(sibling, ARRAYSIZE(sibling), target, (size_t)(extension - target))) ||
        FAILED(StringCchCatW(sibling, ARRAYSIZE(sibling), L".shim")))
    {
        result = SHIM_CANNOT_RESOLVE;
        goto Cleanup;
    }

    if (GetFileAttributesW(sibling) != INVALID_FILE_ATTRIBUTES)
    {
        result = SHIM_TARGET_IS_SHIM;
        goto Cleanup;
    }

    if (!GetFileId(self, &selfId) || !GetFileId(target, &targetId))
    {
        *lastError = GetLastError();
        result = SHIM_CANNOT_IDENTIFY;
        goto Cleanup;
    }

    if (selfId.dwVolumeSerialNumber == targetId.dwVolumeSerialNumber &&
        selfId.nFileIndexHigh == targetId.nFileIndexHigh && selfId.nFileIndexLow == targetId.nFileIndexLow)
    {
        result = SHIM_TARGET_IS_SELF;
    }

Cleanup:
    SecureZeroMemory(root, sizeof(root));
    SecureZeroMemory(sibling, sizeof(sibling));
    SecureZeroMemory(&targetId, sizeof(targetId));
    SecureZeroMemory(&selfId, sizeof(selfId));
    return result;
}

// Each step's failure is its own result, with the system's error where there is one.
static SHIM_RESULT ReadShimTarget(_In_opt_z_ const wchar_t *shim, _In_opt_z_ const wchar_t *self,
                                  _Out_writes_z_(capacity) wchar_t *target, _In_ DWORD capacity, _Out_ DWORD *lastError)
{
    char buffer[SHIM_FILE_MAX_BYTES] = { 0 };
    wchar_t directory[SHIM_PATH_MAX_CHARS] = { 0 };
    wchar_t *separator = NULL;
    LARGE_INTEGER fileSize = { 0 };
    DWORD bytesRead = 0;
    HANDLE file = INVALID_HANDLE_VALUE;
    SHIM_RESULT result = SHIM_BAD_ARGUMENT;

    if (lastError == NULL)
    {
        return SHIM_BAD_ARGUMENT;
    }

    *lastError = ERROR_SUCCESS;
    if (target == NULL || capacity == 0)
    {
        return SHIM_BAD_ARGUMENT;
    }

    target[0] = L'\0';
    if (shim == NULL || ClassifyPath(shim) != PATH_ABSOLUTE ||
        FAILED(StringCchCopyW(directory, ARRAYSIZE(directory), shim)))
    {
        goto Cleanup;
    }

    separator = wcsrchr(directory, L'\\');
    if (separator == NULL)
    {
        goto Cleanup;
    }

    *separator = L'\0';
    file = CreateFileW(shim, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE)
    {
        *lastError = GetLastError();
        result = SHIM_CANNOT_OPEN;
        goto Cleanup;
    }

    // A .shim swapped for a link to a pipe or a device is not a disk file.
    if (GetFileType(file) != FILE_TYPE_DISK)
    {
        *lastError = GetLastError();
        result = SHIM_NOT_A_DISK_FILE;
        goto Cleanup;
    }

    if (!GetFileSizeEx(file, &fileSize))
    {
        *lastError = GetLastError();
        result = SHIM_NO_SIZE;
        goto Cleanup;
    }

    if (fileSize.QuadPart <= 0 || fileSize.QuadPart > SHIM_FILE_MAX_BYTES)
    {
        result = SHIM_BAD_SIZE;
        goto Cleanup;
    }

    if (!ReadFile(file, buffer, (DWORD)fileSize.QuadPart, &bytesRead, NULL))
    {
        *lastError = GetLastError();
        result = SHIM_CANNOT_READ;
        goto Cleanup;
    }

    if (bytesRead != (DWORD)fileSize.QuadPart)
    {
        result = SHIM_SHORT_READ;
        goto Cleanup;
    }

    result = ParseShimContent(buffer, bytesRead, directory, target, capacity);
    if (result == SHIM_OK)
    {
        result = CheckShimTarget(target, self, lastError);
    }

Cleanup:
    if (file != INVALID_HANDLE_VALUE)
    {
        CloseHandle(file);
    }

    if (result != SHIM_OK)
    {
        SecureZeroMemory(target, capacity * sizeof(*target));
    }

    SecureZeroMemory(buffer, sizeof(buffer));
    SecureZeroMemory(directory, sizeof(directory));
    return result;
}

// The raw tail after argv[0]: re-quoting parsed arguments would change what the program sees.
static const wchar_t *SkipProgramName(_In_opt_z_ const wchar_t *commandLine)
{
    const wchar_t *cursor = commandLine;

    if (cursor == NULL)
    {
        return L"";
    }

    if (*cursor == L'"')
    {
        ++cursor;
        while (*cursor != L'\0' && *cursor != L'"')
        {
            ++cursor;
        }

        if (*cursor == L'"')
        {
            ++cursor;
        }
    }
    else
    {
        while (*cursor != L'\0' && *cursor != L' ' && *cursor != L'\t')
        {
            ++cursor;
        }
    }

    return cursor;
}

// The program's own directory first on its PATH, as where it ships: MSYS2's cscope needs MSYS2's sort, not
// Windows'. FALSE when it cannot be done whole; the caller does not run the program then.
static BOOL PrependOwnDirectory(_In_opt_z_ const wchar_t *target, _Out_ DWORD *lastError)
{
    const wchar_t *separator = NULL;
    DWORD oldLength = 0;
    DWORD copied = 0;
    size_t directoryLength = 0;
    size_t size = 0;
    wchar_t *path = NULL;
    BOOL isSet = FALSE;

    if (lastError == NULL)
    {
        return FALSE;
    }

    *lastError = ERROR_INVALID_PARAMETER;
    if (target == NULL || ClassifyPath(target) != PATH_ABSOLUTE)
    {
        return FALSE;
    }

    separator = wcsrchr(target, L'\\');
    if (separator == NULL || separator == target)
    {
        return FALSE;
    }

    directoryLength = (size_t)(separator - target);
    SetLastError(ERROR_SUCCESS);
    oldLength = GetEnvironmentVariableW(L"PATH", NULL, 0);
    if (oldLength == 0 && GetLastError() != ERROR_ENVVAR_NOT_FOUND && GetLastError() != ERROR_SUCCESS)
    {
        *lastError = GetLastError();
        return FALSE;
    }

    if (directoryLength > COMMAND_LINE_MAX_CHARS || oldLength > COMMAND_LINE_MAX_CHARS)
    {
        *lastError = ERROR_FILENAME_EXCED_RANGE;
        return FALSE;
    }

    size = directoryLength + 2 + oldLength;
    path = calloc(size, sizeof(wchar_t));
    if (path == NULL)
    {
        *lastError = ERROR_NOT_ENOUGH_MEMORY;
        return FALSE;
    }

    wmemcpy(path, target, directoryLength);
    if (oldLength != 0)
    {
        path[directoryLength] = L';';
        copied = GetEnvironmentVariableW(L"PATH", path + directoryLength + 1, oldLength);

        // PATH changed between the two calls: what would be set is not what was read.
        if (copied == 0 || copied >= oldLength)
        {
            *lastError = copied == 0 ? GetLastError() : ERROR_INSUFFICIENT_BUFFER;
            goto Cleanup;
        }
    }

    isSet = SetEnvironmentVariableW(L"PATH", path);
    *lastError = isSet ? ERROR_SUCCESS : GetLastError();

Cleanup:
    SecureZeroMemory(path, size * sizeof(wchar_t));
    free(path);
    return isSet;
}

static HANDLE GetValidStdHandle(_In_ DWORD which)
{
    HANDLE handle = GetStdHandle(which);

    return handle == INVALID_HANDLE_VALUE ? NULL : handle;
}

// Neovim watches this file beside the shims (lua/features/external_programs/registered_programs.lua) and shows each new
// line: a shim runs for other programs, whose stderr Neovim may never see. Past SHIM_LOG_MAX_BYTES it starts over, so
// it cannot grow without bound, and it is written only if it is a disk file.
static void LogShimFailure(_In_opt_z_ const wchar_t *shim, _In_opt_z_ const wchar_t *message)
{
    wchar_t path[SHIM_PATH_MAX_CHARS] = { 0 };
    wchar_t line[SHIM_PATH_MAX_CHARS + 128] = { 0 };
    char utf8[(SHIM_PATH_MAX_CHARS + 128) * 3] = { 0 };
    const wchar_t *name = NULL;
    wchar_t *separator = NULL;
    SYSTEMTIME now;
    LARGE_INTEGER size = { 0 };
    LARGE_INTEGER zero = { 0 };
    HANDLE file = INVALID_HANDLE_VALUE;
    DWORD written = 0;
    BOOL isPositioned = FALSE;
    int bytes = 0;

    ZeroMemory(&now, sizeof(now));
    if (shim == NULL || message == NULL || ClassifyPath(shim) != PATH_ABSOLUTE)
    {
        return;
    }

    name = wcsrchr(shim, L'\\');
    if (name == NULL || FAILED(StringCchCopyW(path, ARRAYSIZE(path), shim)))
    {
        goto Cleanup;
    }

    separator = wcsrchr(path, L'\\');
    if (separator == NULL)
    {
        goto Cleanup;
    }

    separator[1] = L'\0';
    GetLocalTime(&now);
    if (FAILED(StringCchCatW(path, ARRAYSIZE(path), SHIM_LOG_NAME)) ||
        FAILED(StringCchPrintfW(line, ARRAYSIZE(line), L"%04u-%02u-%02u %02u:%02u:%02u %ls: %ls\n", now.wYear,
                                now.wMonth, now.wDay, now.wHour, now.wMinute, now.wSecond, name + 1, message)))
    {
        goto Cleanup;
    }

    bytes = WideCharToMultiByte(CP_UTF8, 0, line, -1, utf8, (int)sizeof(utf8), NULL, NULL);
    if (bytes <= 1)
    {
        goto Cleanup;
    }

    file = CreateFileW(path, GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_ALWAYS,
                       FILE_ATTRIBUTE_NORMAL, NULL);
    if (file == INVALID_HANDLE_VALUE || GetFileType(file) != FILE_TYPE_DISK || !GetFileSizeEx(file, &size))
    {
        goto Cleanup;
    }

    isPositioned = size.QuadPart > SHIM_LOG_MAX_BYTES
                       ? SetFilePointerEx(file, zero, NULL, FILE_BEGIN) && SetEndOfFile(file)
                       : SetFilePointerEx(file, zero, NULL, FILE_END);
    if (isPositioned)
    {
        WriteFile(file, utf8, (DWORD)(bytes - 1), &written, NULL);
    }

Cleanup:
    if (file != INVALID_HANDLE_VALUE)
    {
        CloseHandle(file);
    }

    SecureZeroMemory(path, sizeof(path));
    SecureZeroMemory(line, sizeof(line));
    SecureZeroMemory(utf8, sizeof(utf8));
    SecureZeroMemory(&now, sizeof(now));
}

// To stderr for whoever started the program, and to the log for Neovim.
static int FailShim(_In_opt_z_ const wchar_t *shim, _In_opt_z_ const wchar_t *what, _In_ DWORD lastError)
{
    wchar_t message[256] = { 0 };
    HRESULT formatted = S_OK;

    if (lastError != ERROR_SUCCESS)
    {
        formatted = StringCchPrintfW(message, ARRAYSIZE(message), L"%ls (error %lu)", what != NULL ? what : L"failed",
                                     lastError);
    }
    else
    {
        formatted = StringCchPrintfW(message, ARRAYSIZE(message), L"%ls", what != NULL ? what : L"failed");
    }

    // Cut short is still worth reporting; StringCchPrintf leaves it terminated.
    if (FAILED(formatted) && formatted != STRSAFE_E_INSUFFICIENT_BUFFER)
    {
        StringCchCopyW(message, ARRAYSIZE(message), L"failed");
    }

    fwprintf(stderr, L"shim: %ls\n", message);
    LogShimFailure(shim, message);
    SecureZeroMemory(message, sizeof(message));
    return EXIT_SHIM;
}

// The program runs in a job that ends it with the shim; when that cannot be guaranteed, it does not run at all,
// since a killed shim would leave it orphaned.
// The shim waits through Ctrl+C and Ctrl+Break, which reach every process of the console, and leaves them to the
// program. A handler, not SetConsoleCtrlHandler(NULL, TRUE): that "ignore" is inherited, and the program would
// ignore them too.
static BOOL WINAPI WaitThroughConsoleInterrupt(_In_ DWORD controlType)
{
    return controlType == CTRL_C_EVENT || controlType == CTRL_BREAK_EVENT;
}

static int RunShim(_In_opt_z_ const wchar_t *shim, _In_opt_z_ const wchar_t *self)
{
    wchar_t target[SHIM_PATH_MAX_CHARS] = { 0 };
    const wchar_t *arguments = SkipProgramName(GetCommandLineW());
    size_t targetLength = 0;
    size_t argumentsLength = 0;
    size_t size = 0;
    wchar_t *commandLine = NULL;
    STARTUPINFOW startup;
    PROCESS_INFORMATION process;
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
    HANDLE job = NULL;
    DWORD exitCode = EXIT_SHIM;
    DWORD lastError = ERROR_SUCCESS;
    SHIM_RESULT result = SHIM_OK;
    BOOL wasStarted = FALSE;

    ZeroMemory(&startup, sizeof(startup));
    ZeroMemory(&process, sizeof(process));
    ZeroMemory(&limits, sizeof(limits));

    result = ReadShimTarget(shim, self, target, ARRAYSIZE(target), &lastError);
    if (result != SHIM_OK)
    {
        exitCode = (DWORD)FailShim(shim, DescribeShimResult(result), lastError);
        goto Cleanup;
    }

    if (FAILED(StringCchLengthW(target, ARRAYSIZE(target), &targetLength)) ||
        FAILED(StringCchLengthW(arguments, COMMAND_LINE_MAX_CHARS, &argumentsLength)))
    {
        exitCode = (DWORD)FailShim(shim, L"command line too long", ERROR_SUCCESS);
        goto Cleanup;
    }

    // Quotes around the program, the arguments, the terminating null.
    size = targetLength + argumentsLength + 3;
    if (size > COMMAND_LINE_MAX_CHARS)
    {
        exitCode = (DWORD)FailShim(shim, L"command line too long", ERROR_SUCCESS);
        goto Cleanup;
    }

    commandLine = calloc(size, sizeof(wchar_t));
    if (commandLine == NULL)
    {
        exitCode = (DWORD)FailShim(shim, L"out of memory", ERROR_NOT_ENOUGH_MEMORY);
        goto Cleanup;
    }

    if (FAILED(StringCchPrintfW(commandLine, size, L"\"%ls\"%ls", target, arguments)))
    {
        exitCode = (DWORD)FailShim(shim, L"cannot build the command line", ERROR_SUCCESS);
        goto Cleanup;
    }

    job = CreateJobObjectW(NULL, NULL);
    if (job == NULL)
    {
        exitCode = (DWORD)FailShim(shim, L"cannot create the job that ends the program with the shim", GetLastError());
        goto Cleanup;
    }

    // The program ends with the shim; what the program starts breaks away, as from Neovim's own job (libuv).
    limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK;
    if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof(limits)))
    {
        exitCode = (DWORD)FailShim(shim, L"cannot make the job end the program with the shim", GetLastError());
        goto Cleanup;
    }

    if (!PrependOwnDirectory(target, &lastError))
    {
        exitCode = (DWORD)FailShim(shim, L"cannot put the program's directory on its PATH", lastError);
        goto Cleanup;
    }

    // The shim stays to pass on the exit code. Without a console there is no Ctrl+C to wait through, so a failure
    // here changes nothing.
    SetConsoleCtrlHandler(WaitThroughConsoleInterrupt, TRUE);

    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdInput = GetValidStdHandle(STD_INPUT_HANDLE);
    startup.hStdOutput = GetValidStdHandle(STD_OUTPUT_HANDLE);
    startup.hStdError = GetValidStdHandle(STD_ERROR_HANDLE);

    // By full path, never searched for; suspended so it cannot run before it is in the job; with the default
    // error mode, not the one this process set for itself.
    wasStarted = CreateProcessW(target, commandLine, NULL, NULL, TRUE, CREATE_SUSPENDED | CREATE_DEFAULT_ERROR_MODE,
                                NULL, NULL, &startup, &process);
    if (!wasStarted)
    {
        exitCode = (DWORD)FailShim(shim, L"cannot start the program", GetLastError());
        goto Cleanup;
    }

    if (!AssignProcessToJobObject(job, process.hProcess))
    {
        exitCode = (DWORD)FailShim(shim, L"cannot put the program in the job", GetLastError());
        goto Cleanup;
    }

    if (ResumeThread(process.hThread) == (DWORD)-1)
    {
        exitCode = (DWORD)FailShim(shim, L"cannot resume the program", GetLastError());
        goto Cleanup;
    }

    if (WaitForSingleObject(process.hProcess, INFINITE) != WAIT_OBJECT_0)
    {
        exitCode = (DWORD)FailShim(shim, L"cannot wait for the program", GetLastError());
        goto Cleanup;
    }

    if (!GetExitCodeProcess(process.hProcess, &exitCode))
    {
        exitCode = (DWORD)FailShim(shim, L"cannot read the program's exit code", GetLastError());
    }

Cleanup:
    // A program started but not seen to its end is ended here, never left running unattended.
    if (process.hProcess != NULL)
    {
        if (WaitForSingleObject(process.hProcess, 0) != WAIT_OBJECT_0)
        {
            TerminateProcess(process.hProcess, EXIT_SHIM);
            WaitForSingleObject(process.hProcess, INFINITE);
        }

        CloseHandle(process.hProcess);
    }

    if (process.hThread != NULL)
    {
        CloseHandle(process.hThread);
    }

    if (job != NULL)
    {
        CloseHandle(job);
    }

    if (commandLine != NULL)
    {
        SecureZeroMemory(commandLine, size * sizeof(wchar_t));
        free(commandLine);
    }

    SecureZeroMemory(target, sizeof(target));
    SecureZeroMemory(&startup, sizeof(startup));
    SecureZeroMemory(&process, sizeof(process));
    return (int)exitCode;
}

// Digits only, within 32 bits: strtoul would accept a sign and wrap or clamp into another process's id.
static DWORD ParseNumber(_In_opt_z_ const char *text)
{
    DWORD value = 0;
    DWORD next = 0;

    if (text == NULL || *text == '\0')
    {
        return 0;
    }

    for (const char *digit = text; *digit != '\0'; ++digit)
    {
        if (*digit < '0' || *digit > '9')
        {
            return 0;
        }

        next = (DWORD)(*digit - '0');
        if (value > (MAXDWORD - next) / 10)
        {
            return 0;
        }

        value = value * 10 + next;
    }

    return value;
}

// For the commands that print: lines end in "\n" for the reader (text mode would add "\r"), and stdout is
// unbuffered, so no copy of the state lingers in the C runtime's buffer and every line reaches Neovim when
// written: a buffered watcher would look stuck. ime-en and raise print nothing and may run without a stdout.
static BOOL PrepareStdout(void)
{
    if (_setmode(_fileno(stdout), _O_BINARY) == -1 || setvbuf(stdout, NULL, _IONBF, 0) != 0)
    {
        fwprintf(stderr, L"windows_ime_helper: cannot make stdout binary and unbuffered\n");
        return FALSE;
    }

    return TRUE;
}

static int PrintUsage(void)
{
    fputs("usage: windows_ime_helper ime-english | input-state | watch-input-state PID [MS] | raise-window PID | "
          "version\n",
          stderr);
    return EXIT_USAGE;
}

static BOOL IsCommand(_In_ int argc, _In_reads_opt_(argc) char **argv, _In_opt_z_ const char *name, _In_ int expected)
{
    if (argv == NULL || name == NULL || argc != expected || argc < 2)
    {
        return FALSE;
    }

    for (int i = 0; i < argc; ++i)
    {
        if (argv[i] == NULL)
        {
            return FALSE;
        }
    }

    return strcmp(argv[1], name) == 0;
}

// tests/windows_ime_helper/unit.c and fuzz.c include this file for its functions and bring their own entry point.
#ifndef WINDOWS_IME_HELPER_NO_MAIN
int main(int argc, char **argv)
{
    wchar_t self[SHIM_PATH_MAX_CHARS] = { 0 };
    wchar_t shim[SHIM_PATH_MAX_CHARS] = { 0 };
    DWORD caller = 0;
    DWORD lastError = ERROR_SUCCESS;
    DWORD ownerPid = 0;
    DWORD intervalMs = 0;
    DWORD processId = 0;
    SHIM_RESULT shimResult = SHIM_NOT_A_SHIM;
    int exitCode = EXIT_USAGE;

    // Corrupted heap ends the process at once instead of running on.
    HeapSetInformation(NULL, HeapEnableTerminationOnCorruption, NULL, 0);

    // No system error dialog may block a helper nobody looks at.
    SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOOPENFILEERRORBOX);

    shimResult = FindShimFile(self, shim, ARRAYSIZE(self), &lastError);
    if (shimResult == SHIM_OK)
    {
        exitCode = FindNeovimCaller(SHIM_CALLER_DEPTH) != 0 ? RunShim(shim, self) : RefuseCaller();
        goto Cleanup;
    }

    if (shimResult != SHIM_NOT_A_SHIM)
    {
        exitCode = FailShim(shim, DescribeShimResult(shimResult), lastError);
        goto Cleanup;
    }

    caller = FindNeovimCaller(1);
    if (caller == 0)
    {
        exitCode = RefuseCaller();
        goto Cleanup;
    }

    if (IsCommand(argc, argv, "version", 2))
    {
        exitCode = PrepareStdout() && printf("windows_ime_helper %s x64\n", WINDOWS_IME_HELPER_COMPILER) >= 0
                       ? EXIT_DONE
                       : EXIT_FAILED;
    }
    else if (IsCommand(argc, argv, "ime-english", 2))
    {
        exitCode = SetImeEnglish();
    }
    else if (IsCommand(argc, argv, "input-state", 2))
    {
        exitCode = PrepareStdout() && PrintIndicatorState(QueryIndicatorState()) == 0 ? EXIT_DONE : EXIT_FAILED;
    }
    else if (IsCommand(argc, argv, "watch-input-state", 3) || IsCommand(argc, argv, "watch-input-state", 4))
    {
        ownerPid = ParseNumber(argv[2]);
        intervalMs = argc == 4 ? ParseNumber(argv[3]) : DEFAULT_INTERVAL_MS;
        if (ownerPid == 0 || intervalMs < MIN_INTERVAL_MS || intervalMs > MAX_INTERVAL_MS)
        {
            exitCode = PrintUsage();
        }
        else if (ownerPid != caller)
        {
            // Only the Neovim that started it: watching another would outlive its caller.
            fwprintf(stderr, L"watch-input-state: PID must be the Neovim that started windows_ime_helper\n");
            exitCode = EXIT_USAGE;
        }
        else
        {
            exitCode = PrepareStdout() ? WatchIndicatorState(ownerPid, intervalMs) : EXIT_FAILED;
        }
    }
    else if (IsCommand(argc, argv, "raise-window", 3))
    {
        processId = ParseNumber(argv[2]);
        exitCode = processId != 0 ? RaiseProcessLineage(processId) : PrintUsage();
    }
    else
    {
        exitCode = PrintUsage();
    }

Cleanup:
    SecureZeroMemory(self, sizeof(self));
    SecureZeroMemory(shim, sizeof(shim));
    return exitCode;
}
#endif
