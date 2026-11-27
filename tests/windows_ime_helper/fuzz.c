// libFuzzer target for native/windows_ime_helper.c's parsers, compiled together with it (WINDOWS_IME_HELPER_NO_MAIN
// drops its own entry point). The first byte picks the parser; the rest is its input. Any broken invariant aborts,
// which libFuzzer reports with the input that did it. tests/windows_ime_helper/run.ps1 builds it with AddressSanitizer
// and runs it.
#define WINDOWS_IME_HELPER_NO_MAIN
#include "../../native/windows_ime_helper.c"

#define FUZZ_WIDE_MAX 512
#define FUZZ_NARROW_MAX 64

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

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
    wchar_t wide[FUZZ_WIDE_MAX] = { 0 };
    wchar_t target[SHIM_PATH_MAX_CHARS] = { 0 };
    char narrow[FUZZ_NARROW_MAX] = { 0 };
    const wchar_t *tail;
    size_t length;
    DWORD number;

    if (size == 0)
    {
        return 0;
    }

    switch (data[0] % 8)
    {
    case 0:
        length = (size - 1 < FUZZ_NARROW_MAX - 1) ? (size - 1) : (FUZZ_NARROW_MAX - 1);
        memcpy(narrow, data + 1, length);
        number = ParseNumber(narrow);
        if (number != 0)
        {
            for (size_t i = 0; narrow[i] != '\0'; ++i)
            {
                Require(narrow[i] >= '0' && narrow[i] <= '9');
            }
        }

        break;

    case 1:
        length = ToWide(data + 1, size - 1, wide, FUZZ_WIDE_MAX);
        tail = SkipProgramName(wide);
        Require(tail >= wide && tail <= wide + wcslen(wide));
        break;

    case 2:
        ToWide(data + 1, size - 1, wide, FUZZ_WIDE_MAX);
        Require(ClassifyPath(wide) <= PATH_REFUSED);
        break;

    case 3:
        // What a parsed .shim must always be: a terminated drive path with no stream and no control character.
        wmemset(target, L'#', ARRAYSIZE(target));
        if (ParseShimContent((const char *)data + 1, size - 1, L"C:\\fuzz\\shims", target, ARRAYSIZE(target)) ==
            SHIM_OK)
        {
            length = wcsnlen(target, ARRAYSIZE(target));
            Require(length < ARRAYSIZE(target));
            Require(ClassifyPath(target) == PATH_ABSOLUTE);
            Require(wcschr(target + 2, L':') == NULL);
            for (size_t i = 0; i < length; ++i)
            {
                Require(target[i] >= 0x20);
            }
        }
        else
        {
            Require(target[0] == L'\0');
        }

        break;

    case 4: {
        wchar_t norm[SHIM_PATH_MAX_CHARS] = { 0 };

        ToWide(data + 1, size - 1, wide, FUZZ_WIDE_MAX);
        if (NormalizeDrivePath(wide, norm, ARRAYSIZE(norm)))
        {
            size_t nlen = wcslen(norm);

            Require(ClassifyPath(norm) == PATH_ABSOLUTE && nlen >= 3);
            Require(norm[1] == L':' && norm[2] == L'\\' && wcschr(norm + 2, L':') == NULL);
            Require(wcschr(norm, L'/') == NULL && wcsstr(norm, L"\\..\\") == NULL && wcsstr(norm, L"\\.\\") == NULL);
            Require(!(nlen >= 3 && wcscmp(norm + nlen - 3, L"\\..") == 0));
            Require(!(nlen >= 2 && wcscmp(norm + nlen - 2, L"\\.") == 0));
            for (size_t i = 0; i < nlen; ++i)
            {
                Require(norm[i] >= 0x20 && norm[i] != 0x7F);
            }
        }

        break;
    }

    case 5: {
        wchar_t arg0[FUZZ_WIDE_MAX] = { 0 };
        wchar_t arg1[FUZZ_WIDE_MAX] = { 0 };
        wchar_t arg2[FUZZ_WIDE_MAX] = { 0 };

        FuzzSplitThree(data + 1, size - 1, arg0, arg1, arg2, FUZZ_WIDE_MAX);
        if (IsWslHostPathUnder(arg0, L"C:\\Windows\\System32", L"C:\\Program Files"))
        {
            Require(CompareStringOrdinal(arg0, -1, L"C:\\Windows\\System32\\wsl.exe", -1, TRUE) == CSTR_EQUAL ||
                    CompareStringOrdinal(arg0, -1, L"C:\\Windows\\System32\\wslhost.exe", -1, TRUE) == CSTR_EQUAL ||
                    CompareStringOrdinal(arg0, -1, L"C:\\Program Files\\WSL\\wsl.exe", -1, TRUE) == CSTR_EQUAL ||
                    CompareStringOrdinal(arg0, -1, L"C:\\Program Files\\WSL\\wslhost.exe", -1, TRUE) == CSTR_EQUAL);
        }

        if (IsWslHostPathUnder(arg0, arg1, arg2))
        {
            Require(EndsWithInsensitive(arg0, L"\\wsl.exe") || EndsWithInsensitive(arg0, L"\\wslhost.exe"));
        }

        break;
    }

    case 6:
        ToWide(data + 1, size - 1, wide, FUZZ_WIDE_MAX);
        if (IsBridgeExeName(wide))
        {
            size_t wlen = wcslen(wide);
            BOOL sawDash = FALSE;

            Require(wlen > 25);
            Require(wcsncmp(wide, L"windows_wsl_bridge-", 19) == 0);
            Require(EndsWithInsensitive(wide, L".exe"));
            Require(wcschr(wide, L'\\') == NULL && wcschr(wide, L'/') == NULL && wcschr(wide, L':') == NULL &&
                    wcsstr(wide, L"..") == NULL);
            for (size_t i = 19; i + 4 < wlen; ++i)
            {
                if (wide[i] == L'-')
                {
                    Require(!sawDash);
                    sawDash = TRUE;
                }
                else
                {
                    Require(IsHexWide(wide[i]));
                }
            }

            Require(sawDash);
        }

        break;

    default: {
        const wchar_t *selfProd =
            L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_ime_helper\\windows_ime_helper-1-2.exe";
        const wchar_t *localAppData = L"C:\\Users\\user\\AppData\\Local";
        wchar_t arg0[FUZZ_WIDE_MAX] = { 0 };
        wchar_t arg1[FUZZ_WIDE_MAX] = { 0 };
        wchar_t arg2[FUZZ_WIDE_MAX] = { 0 };
        wchar_t norm[SHIM_PATH_MAX_CHARS] = { 0 };

        FuzzSplitThree(data + 1, size - 1, arg0, arg1, arg2, FUZZ_WIDE_MAX);
        if (IsBridgeImagePathForSelf(arg0, selfProd, localAppData))
        {
            wchar_t *slash = NULL;

            Require(NormalizeDrivePath(arg0, norm, ARRAYSIZE(norm)));
            slash = wcsrchr(norm, L'\\');
            Require(slash != NULL && IsBridgeExeName(slash + 1));
            *slash = L'\0';
            Require(CompareStringOrdinal(norm, -1,
                                         L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_wsl_bridge",
                                         -1, TRUE) == CSTR_EQUAL);
        }

        if (IsBridgeImagePathForSelf(arg0, arg1, arg2))
        {
            wchar_t *slash = NULL;

            Require(NormalizeDrivePath(arg0, norm, ARRAYSIZE(norm)));
            slash = wcsrchr(norm, L'\\');
            Require(slash != NULL && IsBridgeExeName(slash + 1));
            *slash = L'\0';
            Require(EndsWithInsensitive(norm, L"\\nvim-config\\windows_wsl_bridge"));
        }

        break;
    }
    }

    return 0;
}
