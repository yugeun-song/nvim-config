// libFuzzer target for native/windows_wsl_bridge.c's validators and Win32 argument quoting.
// The first byte selects the target function; any broken invariant aborts.
#define WINDOWS_WSL_BRIDGE_NO_MAIN
#include "../../native/windows_wsl_bridge.c"

#include <shellapi.h>

#ifdef _MSC_VER
#pragma comment(lib, "shell32.lib")
#endif

#define FUZZ_WIDE_MAX 512

static void Require(_In_ BOOL isHeld)
{
    if (!isHeld)
    {
        abort();
    }
}

static size_t ToWide(_In_reads_bytes_(size) const uint8_t *data, _In_ size_t size,
                     _Out_writes_z_(capacity) wchar_t *wide, _In_ size_t capacity)
{
    size_t length = 0;

    while (length + 1 < capacity && (length + 1) * 2 <= size)
    {
        wide[length] = (wchar_t)(data[length * 2] | (data[length * 2 + 1] << 8));
        ++length;
    }

    wide[length] = L'\0';
    return length;
}

static void FuzzSplitThree(_In_reads_bytes_(size) const uint8_t *data, _In_ size_t size,
                           _Out_writes_z_(maxLen) wchar_t *out0, _Out_writes_z_(maxLen) wchar_t *out1,
                           _Out_writes_z_(maxLen) wchar_t *out2, _In_ size_t maxLen)
{
    wchar_t *outputs[3] = { out0, out1, out2 };
    size_t which = 0;
    size_t pos = 0;

    for (size_t i = 0; i < 3; ++i)
    {
        outputs[i][0] = L'\0';
    }

    for (size_t offset = 0; offset + 1 < size && which < 3; offset += 2)
    {
        wchar_t ch = (wchar_t)(data[offset] | (data[offset + 1] << 8));

        if (ch == L'\0')
        {
            outputs[which][pos] = L'\0';
            ++which;
            pos = 0;
        }
        else if (pos + 1 < maxLen)
        {
            outputs[which][pos] = ch;
            ++pos;
            outputs[which][pos] = L'\0';
        }
    }
}

static void FuzzEmbedArgs(_In_reads_bytes_(size) const uint8_t *data, _In_ size_t size)
{
    wchar_t storage[10][64] = { { 0 } };
    const wchar_t *argv[14] = { 0 };
    const wchar_t *outArgv[16] = { 0 };
    uint8_t shape = (size > 0) ? data[0] : 0;
    const uint8_t *rest = (size > 0) ? (data + 1) : data;
    size_t restSize = (size > 0) ? (size - 1) : 0;
    size_t tokenCount = 0;
    size_t pos = 0;
    int argc = 0;
    int outCount = 0;
    BOOL okNorm = FALSE;
    BOOL okVal = FALSE;
    BOOL afterSep = FALSE;

    for (size_t offset = 0; offset + 1 < restSize && tokenCount < ARRAYSIZE(storage); offset += 2)
    {
        wchar_t ch = (wchar_t)(rest[offset] | (rest[offset + 1] << 8));

        if (ch == L'\0')
        {
            if (pos > 0 || (shape & 0x80) != 0)
            {
                ++tokenCount;
                pos = 0;
            }
        }
        else if (pos + 1 < ARRAYSIZE(storage[0]))
        {
            storage[tokenCount][pos] = ch;
            ++pos;
            storage[tokenCount][pos] = L'\0';
        }
    }

    if (pos > 0 && tokenCount < ARRAYSIZE(storage))
    {
        ++tokenCount;
    }

    argv[argc] = L"windows_wsl_bridge.exe";
    ++argc;

    if ((shape & 0x03) == 1)
    {
        argv[argc] = L"--embed";
        ++argc;
    }

    for (size_t i = 0; i < tokenCount && argc < (int)ARRAYSIZE(argv) - 2; ++i)
    {
        if ((shape & 0x04) != 0 && i == ((size_t)(shape >> 4) % (tokenCount + 1)) && argc < (int)ARRAYSIZE(argv) - 3)
        {
            argv[argc] = L"--";
            ++argc;
        }

        argv[argc] = storage[i];
        ++argc;
    }

    if ((shape & 0x03) == 2 || (shape & 0x03) == 3)
    {
        argv[argc] = L"--embed";
        ++argc;
        if ((shape & 0x03) == 3)
        {
            argv[argc] = L"-p";
            ++argc;
        }
    }

    okNorm = BuildNormalizedEmbedArgs(argc, argv, outArgv, ARRAYSIZE(outArgv), &outCount);
    okVal = ValidateForwardedEmbedArgs(argc, argv);
    Require(okNorm == okVal);
    if (!okNorm)
    {
        return;
    }

    Require(outCount >= 1 && outCount < argc && outCount <= (int)ARRAYSIZE(outArgv));
    if (wcscmp(outArgv[0], L"-v") == 0 || wcscmp(outArgv[0], L"--version") == 0)
    {
        Require(outCount == 1);
        return;
    }

    Require(wcscmp(outArgv[0], L"--embed") == 0);
    for (int i = 1; i < outCount; ++i)
    {
        Require(outArgv[i] != NULL && ValidateLinuxArg(outArgv[i]));
        if (!afterSep)
        {
            if (wcscmp(outArgv[i], L"--") == 0)
            {
                Require(i + 1 < outCount);
                afterSep = TRUE;
            }
            else
            {
                Require(IsBenignEmbedFlag(outArgv[i]));
                Require(wcscmp(outArgv[i], L"-c") != 0 && wcscmp(outArgv[i], L"--cmd") != 0 &&
                        wcscmp(outArgv[i], L"-u") != 0 && wcscmp(outArgv[i], L"--listen") != 0 &&
                        wcscmp(outArgv[i], L"-l") != 0 && wcscmp(outArgv[i], L"-S") != 0);
            }
        }
    }
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    wchar_t wide[FUZZ_WIDE_MAX] = { 0 };
    wchar_t cmdLine[2048] = { 0 };
    size_t cmdLen = 0;

    if (size == 0)
    {
        return 0;
    }

    ToWide(data + 1, size - 1, wide, FUZZ_WIDE_MAX);

    switch (data[0] % 9)
    {
    case 0:
        if (ValidateDistroName(wide))
        {
            Require(wide[0] != L'-' && wide[0] != L' ' && wcschr(wide, L';') == NULL && wcschr(wide, L'/') == NULL);
        }

        break;

    case 1:
        if (ValidateLinuxDir(wide))
        {
            Require(!HasControlChar(wide) && (wcscmp(wide, L"~") == 0 || wide[0] == L'/'));
        }

        break;

    case 2:
        if (ValidateLinuxNvim(wide))
        {
            Require(!HasControlChar(wide) && wcschr(wide, L' ') == NULL &&
                    (wcscmp(wide, L"nvim") == 0 || wide[0] == L'/'));
        }

        break;

    case 3:
        if (ValidateLocalWindowsPath(wide))
        {
            Require(!HasControlChar(wide) && wide[1] == L':' && wcschr(wide + 2, L':') == NULL);
        }

        break;

    case 4:
        if (ValidateHelperExeName(wide))
        {
            Require(wcsncmp(wide, L"windows_ime_helper-", 19) == 0 && EndsWithInsensitive(wide, L".exe"));
        }

        break;

    case 5:
        // Any string without NUL/newlines/whitespace-only issues must round-trip cleanly through CommandLineToArgvW.
        if (AppendQuotedArg(cmdLine, ARRAYSIZE(cmdLine), &cmdLen, L"prog.exe") &&
            AppendQuotedArg(cmdLine, ARRAYSIZE(cmdLine), &cmdLen, wide))
        {
            int count = 0;
            LPWSTR *parsed = CommandLineToArgvW(cmdLine, &count);

            Require(parsed != NULL && count == 2);
            Require(wcscmp(parsed[1], wide) == 0);
            LocalFree(parsed);
            parsed = NULL;
        }

        break;

    case 6:
        FuzzEmbedArgs(data + 1, size - 1);
        break;

    case 7: {
        const wchar_t *selfProd = L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_wsl_bridge\\"
                                  L"windows_wsl_bridge-a-b.exe";
        const wchar_t *localAppData = L"C:\\Users\\user\\AppData\\Local";
        wchar_t arg0[FUZZ_WIDE_MAX] = { 0 };
        wchar_t arg1[FUZZ_WIDE_MAX] = { 0 };
        wchar_t arg2[FUZZ_WIDE_MAX] = { 0 };
        wchar_t norm[MAX_WINDOWS_PATH_CHARS] = { 0 };

        FuzzSplitThree(data + 1, size - 1, arg0, arg1, arg2, FUZZ_WIDE_MAX);
        if (NormalizeDrivePath(arg0, norm, ARRAYSIZE(norm)))
        {
            size_t nlen = wcslen(norm);

            Require(nlen >= 3 && norm[1] == L':' && norm[2] == L'\\' && wcschr(norm + 2, L':') == NULL &&
                    wcschr(norm, L'/') == NULL && wcsstr(norm, L"\\..\\") == NULL && wcsstr(norm, L"\\.\\") == NULL &&
                    !HasControlChar(norm));
            Require(!(nlen >= 3 && wcscmp(norm + nlen - 3, L"\\..") == 0));
            Require(!(nlen >= 2 && wcscmp(norm + nlen - 2, L"\\.") == 0));
        }

        if (IsAllowedHelperDirForSelf(arg0, selfProd, localAppData))
        {
            Require(NormalizeDrivePath(arg0, norm, ARRAYSIZE(norm)));
            Require(CompareStringOrdinal(norm, -1,
                                         L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_ime_helper",
                                         -1, TRUE) == CSTR_EQUAL);
        }

        if (IsAllowedHelperDirForSelf(arg0, arg1, arg2))
        {
            Require(NormalizeDrivePath(arg0, norm, ARRAYSIZE(norm)));
            Require(EndsWithInsensitive(norm, L"\\nvim-config\\windows_ime_helper"));
        }

        break;
    }

    default:
        if (ValidateBase64Arg(wide))
        {
            size_t len = wcslen(wide);

            Require(len >= 1 && len <= MAX_BASE64_CHARS && wcschr(wide, L';') == NULL && !HasControlChar(wide));
            for (size_t i = 0; i < len; ++i)
            {
                wchar_t ch = wide[i];

                Require((ch >= L'A' && ch <= L'Z') || (ch >= L'a' && ch <= L'z') || (ch >= L'0' && ch <= L'9') ||
                        ch == L'+' || ch == L'/' || ch == L'=');
            }
        }

        break;
    }

    return 0;
}
