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

    switch (data[0] % 4)
    {
    case 0:
        length = size - 1 < FUZZ_NARROW_MAX - 1 ? size - 1 : FUZZ_NARROW_MAX - 1;
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

    default:
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
    }

    return 0;
}
