// Unit tests for scripts/winctl.c's parsers and checks, compiled together with it (WINCTL_NO_MAIN drops its own
// entry point). tests/winctl/run.ps1 builds it with AddressSanitizer and runs it.
#define WINCTL_NO_MAIN
#include "../../scripts/winctl.c"

static int gs_checkCount = 0;
static int gs_failureCount = 0;

static void Check(_In_ BOOL isPassing, _In_z_ const char *what)
{
    ++gs_checkCount;
    if (!isPassing)
    {
        ++gs_failureCount;
        printf("FAIL %s\n", what);
    }
}

static void TestParseNumber(void)
{
    Check(ParseNumber("0") == 0, "ParseNumber 0");
    Check(ParseNumber("1") == 1, "ParseNumber 1");
    Check(ParseNumber("0001") == 1, "ParseNumber leading zeros");
    Check(ParseNumber("4294967295") == MAXDWORD, "ParseNumber MAXDWORD");
    Check(ParseNumber("4294967296") == 0, "ParseNumber overflow");
    Check(ParseNumber("99999999999999999999") == 0, "ParseNumber long overflow");
    Check(ParseNumber("-1") == 0, "ParseNumber sign");
    Check(ParseNumber("+1") == 0, "ParseNumber plus");
    Check(ParseNumber(" 1") == 0, "ParseNumber leading blank");
    Check(ParseNumber("1 ") == 0, "ParseNumber trailing blank");
    Check(ParseNumber("12x") == 0, "ParseNumber suffix");
    Check(ParseNumber("0x10") == 0, "ParseNumber hex");
    Check(ParseNumber("") == 0, "ParseNumber empty");
    Check(ParseNumber(NULL) == 0, "ParseNumber NULL");
}

static void TestSkipProgramName(void)
{
    Check(wcscmp(SkipProgramName(L"\"C:\\a b\\x.exe\" one two"), L" one two") == 0, "Skip quoted program");
    Check(wcscmp(SkipProgramName(L"x.exe one"), L" one") == 0, "Skip bare program");
    Check(wcscmp(SkipProgramName(L"x.exe\tone"), L"\tone") == 0, "Skip at a tab");
    Check(wcscmp(SkipProgramName(L"\"unterminated"), L"") == 0, "Skip unterminated quote");
    Check(wcscmp(SkipProgramName(L"\"\" rest"), L" rest") == 0, "Skip empty quotes");
    Check(wcscmp(SkipProgramName(L""), L"") == 0, "Skip empty");
    Check(wcscmp(SkipProgramName(NULL), L"") == 0, "Skip NULL");
}

static void TestClassifyPath(void)
{
    Check(ClassifyPath(L"C:\\a.exe") == PATH_ABSOLUTE, "Classify drive path");
    Check(ClassifyPath(L"z:/a.exe") == PATH_ABSOLUTE, "Classify drive path, slash");
    Check(ClassifyPath(L"a.exe") == PATH_RELATIVE, "Classify relative");
    Check(ClassifyPath(L"..\\a.exe") == PATH_RELATIVE, "Classify parent relative");
    Check(ClassifyPath(L"C:a.exe") == PATH_REFUSED, "Classify drive-relative");
    Check(ClassifyPath(L"\\a.exe") == PATH_REFUSED, "Classify rooted");
    Check(ClassifyPath(L"/a.exe") == PATH_REFUSED, "Classify rooted, slash");
    Check(ClassifyPath(L"\\\\server\\share\\a.exe") == PATH_REFUSED, "Classify share");
    Check(ClassifyPath(L"//server/share/a.exe") == PATH_REFUSED, "Classify share, slashes");
    Check(ClassifyPath(L"\\\\.\\C:\\a.exe") == PATH_REFUSED, "Classify device");
    Check(ClassifyPath(L"\\\\?\\C:\\a.exe") == PATH_REFUSED, "Classify long-path device");
    Check(ClassifyPath(L"1:\\a.exe") == PATH_RELATIVE, "Classify digit drive is no drive");
    Check(ClassifyPath(L"") == PATH_REFUSED, "Classify empty");
    Check(ClassifyPath(NULL) == PATH_REFUSED, "Classify NULL");
}

static void ExpectShim(_In_reads_bytes_(size) const char *bytes, _In_ size_t size, _In_ SHIM_RESULT expected,
                       _In_opt_z_ const wchar_t *expectedTarget, _In_z_ const char *what)
{
    wchar_t target[SHIM_PATH_MAX_CHARS];
    SHIM_RESULT result;

    wmemset(target, L'#', ARRAYSIZE(target));
    result = ParseShimContent(bytes, size, L"C:\\base\\shims", target, ARRAYSIZE(target));
    Check(result == expected, what);
    if (result == SHIM_OK && expectedTarget != NULL)
    {
        Check(wcscmp(target, expectedTarget) == 0, what);
    }

    if (result != SHIM_OK)
    {
        Check(target[0] == L'\0', "a refused .shim leaves no target");
    }
}

#define SHIM_CASE(text, expected, target, what) ExpectShim(text, sizeof(text) - 1, expected, target, what)

static void TestParseShimContent(void)
{
    char longFile[SHIM_FILE_MAX_BYTES + 1];
    char longPath[700];
    wchar_t target[8] = { 0 };

    SHIM_CASE("C:\\tools\\a.exe", SHIM_OK, L"C:\\tools\\a.exe", "shim absolute");
    SHIM_CASE("C:/tools/a.exe", SHIM_OK, L"C:\\tools\\a.exe", "shim absolute, slashes");
    SHIM_CASE("C:\\tools\\a.exe\r\nignored", SHIM_OK, L"C:\\tools\\a.exe", "shim CRLF");
    SHIM_CASE("a.exe", SHIM_OK, L"C:\\base\\shims\\a.exe", "shim relative to its directory");
    SHIM_CASE("..\\bin\\a.exe", SHIM_OK, L"C:\\base\\bin\\a.exe", "shim parent relative");
    SHIM_CASE("..\\..\\..\\..\\a.exe", SHIM_OK, L"C:\\a.exe", "shim cannot climb above the drive");
    SHIM_CASE("C:a.exe", SHIM_PATH_REFUSED, NULL, "shim drive-relative");
    SHIM_CASE("\\a.exe", SHIM_PATH_REFUSED, NULL, "shim rooted");
    SHIM_CASE("\\\\server\\share\\a.exe", SHIM_PATH_REFUSED, NULL, "shim share");
    SHIM_CASE("\\\\.\\C:\\a.exe", SHIM_PATH_REFUSED, NULL, "shim device");
    SHIM_CASE("\\\\?\\C:\\a.exe", SHIM_PATH_REFUSED, NULL, "shim long-path device");
    SHIM_CASE("C:\\a.exe:stream", SHIM_STREAM, NULL, "shim stream, absolute");
    SHIM_CASE("a.exe:stream", SHIM_STREAM, NULL, "shim stream, relative");
    SHIM_CASE("\xEF\xBB\xBF"
              "C:\\a.exe",
              SHIM_STREAM, NULL, "shim with a BOM");
    SHIM_CASE("\n", SHIM_EMPTY, NULL, "shim empty first line");
    SHIM_CASE("\r\nC:\\a.exe", SHIM_EMPTY, NULL, "shim empty first line, CRLF");
    SHIM_CASE("C:\\a\tb.exe", SHIM_BAD_CHARACTER, NULL, "shim tab");
    SHIM_CASE("C:\\a\x7F"
              "b.exe",
              SHIM_BAD_CHARACTER, NULL, "shim DEL");
    SHIM_CASE("C:\\a\x00"
              "b.exe",
              SHIM_BAD_CHARACTER, NULL, "shim NUL inside");
    SHIM_CASE("C:\\\xC3\x28.exe", SHIM_NOT_UTF8, NULL, "shim malformed UTF-8");
    SHIM_CASE("C:\\\xED\xA0\x80.exe", SHIM_NOT_UTF8, NULL, "shim encoded surrogate");
    SHIM_CASE("C:\\\xC0\xAF.exe", SHIM_NOT_UTF8, NULL, "shim overlong UTF-8");

    ExpectShim("", 0, SHIM_BAD_ARGUMENT, NULL, "shim zero size");
    ExpectShim(NULL, 4, SHIM_BAD_ARGUMENT, NULL, "shim NULL bytes");

    memset(longFile, 'a', sizeof(longFile));
    ExpectShim(longFile, sizeof(longFile), SHIM_BAD_ARGUMENT, NULL, "shim larger than allowed");

    memset(longPath, 'b', sizeof(longPath));
    longPath[0] = 'C';
    longPath[1] = ':';
    longPath[2] = '\\';
    ExpectShim(longPath, sizeof(longPath), SHIM_NOT_UTF8, NULL, "shim path longer than the target buffer");

    Check(ParseShimContent("a.exe", 5, NULL, target, ARRAYSIZE(target)) == SHIM_BAD_ARGUMENT, "shim NULL directory");
    Check(ParseShimContent("a.exe", 5, L"base", target, ARRAYSIZE(target)) == SHIM_BAD_ARGUMENT,
          "shim relative directory");
    Check(ParseShimContent("C:\\tools\\a.exe", 14, L"C:\\base", target, ARRAYSIZE(target)) == SHIM_CANNOT_RESOLVE,
          "shim target buffer too small");
    Check(target[0] == L'\0', "shim too small leaves no target");
    Check(ParseShimContent("a.exe", 5, L"C:\\base", NULL, 8) == SHIM_BAD_ARGUMENT, "shim NULL target");
    Check(ParseShimContent("a.exe", 5, L"C:\\base", target, 0) == SHIM_BAD_ARGUMENT, "shim zero capacity");
}

static BOOL WriteBytes(_In_z_ const wchar_t *path, _In_reads_bytes_(size) const void *bytes, _In_ DWORD size)
{
    HANDLE file = CreateFileW(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    DWORD written = 0;
    BOOL isWritten;

    if (file == INVALID_HANDLE_VALUE)
    {
        return FALSE;
    }

    isWritten = WriteFile(file, bytes, size, &written, NULL) && written == size;
    CloseHandle(file);
    return isWritten;
}

static void JoinPath(_Out_writes_z_(capacity) wchar_t *out, _In_ size_t capacity, _In_z_ const wchar_t *directory,
                     _In_z_ const wchar_t *name)
{
    if (FAILED(StringCchPrintfW(out, capacity, L"%ls\\%ls", directory, name)))
    {
        out[0] = L'\0';
    }
}

static void TestFiles(void)
{
    wchar_t temp[MAX_PATH] = { 0 };
    wchar_t dir[MAX_PATH] = { 0 };
    wchar_t self[MAX_PATH] = { 0 };
    wchar_t path[MAX_PATH] = { 0 };
    wchar_t other[MAX_PATH] = { 0 };
    wchar_t shortSelf[MAX_PATH] = { 0 };
    wchar_t target[SHIM_PATH_MAX_CHARS] = { 0 };
    char big[SHIM_FILE_MAX_BYTES + 10];
    char content[SHIM_PATH_MAX_CHARS * 3] = { 0 };
    DWORD lastError = 0;
    int length;

    if (GetTempPathW(ARRAYSIZE(temp), temp) == 0 || GetModuleFileNameW(NULL, self, ARRAYSIZE(self)) == 0 ||
        FAILED(StringCchPrintfW(dir, ARRAYSIZE(dir), L"%lswinctl-unit-%lu", temp, GetCurrentProcessId())) ||
        !CreateDirectoryW(dir, NULL))
    {
        Check(FALSE, "cannot set up the file tests");
        return;
    }

    JoinPath(path, ARRAYSIZE(path), dir, L"prog.exe");
    Check(CopyFileW(self, path, FALSE), "copy a program");
    Check(CheckShimTarget(path, self, &lastError) == SHIM_OK, "target: a program");

    JoinPath(path, ARRAYSIZE(path), dir, L"prog.com");
    Check(WriteBytes(path, "x", 1), "write a .com");
    Check(CheckShimTarget(path, self, &lastError) == SHIM_OK, "target: a .com");

    JoinPath(path, ARRAYSIZE(path), dir, L"script.bat");
    Check(WriteBytes(path, "@exit 7", 7), "write a .bat");
    Check(CheckShimTarget(path, self, &lastError) == SHIM_NOT_A_PROGRAM, "target: a .bat");

    JoinPath(path, ARRAYSIZE(path), dir, L"folder.exe");
    Check(CreateDirectoryW(path, NULL), "make a directory named .exe");
    Check(CheckShimTarget(path, self, &lastError) == SHIM_TARGET_IS_DIRECTORY, "target: a directory");

    JoinPath(path, ARRAYSIZE(path), dir, L"missing.exe");
    Check(CheckShimTarget(path, self, &lastError) == SHIM_TARGET_MISSING && lastError != ERROR_SUCCESS,
          "target: missing, with the system's error");

    JoinPath(path, ARRAYSIZE(path), dir, L"shimmed.exe");
    JoinPath(other, ARRAYSIZE(other), dir, L"shimmed.shim");
    Check(CopyFileW(self, path, FALSE) && WriteBytes(other, "C:\\x.exe", 8), "make another shim");
    Check(CheckShimTarget(path, self, &lastError) == SHIM_TARGET_IS_SHIM, "target: another shim");

    Check(CheckShimTarget(self, self, &lastError) == SHIM_TARGET_IS_SELF, "target: itself");

    JoinPath(path, ARRAYSIZE(path), dir, L"hardlink.exe");
    if (CreateHardLinkW(path, self, NULL))
    {
        Check(CheckShimTarget(path, self, &lastError) == SHIM_TARGET_IS_SELF, "target: itself through a hard link");
    }

    if (GetShortPathNameW(self, shortSelf, ARRAYSIZE(shortSelf)) != 0 && wcscmp(shortSelf, self) != 0)
    {
        Check(CheckShimTarget(shortSelf, self, &lastError) == SHIM_TARGET_IS_SELF,
              "target: itself through its 8.3 name");
    }

    Check(CheckShimTarget(L"prog.exe", self, &lastError) == SHIM_BAD_ARGUMENT, "target: relative");
    Check(CheckShimTarget(NULL, self, &lastError) == SHIM_BAD_ARGUMENT, "target: NULL");
    Check(CheckShimTarget(self, self, NULL) == SHIM_BAD_ARGUMENT, "target: NULL error");

    // Reading a .shim from disk.
    JoinPath(path, ARRAYSIZE(path), dir, L"tool.shim");
    JoinPath(other, ARRAYSIZE(other), dir, L"prog.exe");
    length = WideCharToMultiByte(CP_UTF8, 0, other, -1, content, (int)sizeof(content), NULL, NULL);
    Check(length > 1 && WriteBytes(path, content, (DWORD)(length - 1)), "write a .shim");
    Check(ReadShimTarget(path, self, target, ARRAYSIZE(target), &lastError) == SHIM_OK && _wcsicmp(target, other) == 0,
          "read a .shim");

    Check(WriteBytes(path, "prog.exe", 8), "write a relative .shim");
    Check(ReadShimTarget(path, self, target, ARRAYSIZE(target), &lastError) == SHIM_OK && _wcsicmp(target, other) == 0,
          "read a relative .shim");

    Check(WriteBytes(path, "", 0), "write an empty .shim");
    Check(ReadShimTarget(path, self, target, ARRAYSIZE(target), &lastError) == SHIM_BAD_SIZE, "empty .shim");

    memset(big, 'a', sizeof(big));
    Check(WriteBytes(path, big, sizeof(big)), "write a big .shim");
    Check(ReadShimTarget(path, self, target, ARRAYSIZE(target), &lastError) == SHIM_BAD_SIZE, "big .shim");

    JoinPath(path, ARRAYSIZE(path), dir, L"missing.shim");
    Check(ReadShimTarget(path, self, target, ARRAYSIZE(target), &lastError) == SHIM_CANNOT_OPEN &&
              lastError == ERROR_FILE_NOT_FOUND,
          "missing .shim, with the system's error");

    JoinPath(path, ARRAYSIZE(path), dir, L"folder.shim");
    Check(CreateDirectoryW(path, NULL), "make a directory named .shim");
    Check(ReadShimTarget(path, self, target, ARRAYSIZE(target), &lastError) != SHIM_OK, "a directory as .shim");

    Check(ReadShimTarget(L"tool.shim", self, target, ARRAYSIZE(target), &lastError) == SHIM_BAD_ARGUMENT,
          "relative .shim path");
    Check(ReadShimTarget(NULL, self, target, ARRAYSIZE(target), &lastError) == SHIM_BAD_ARGUMENT, "NULL .shim");
    Check(ReadShimTarget(path, self, NULL, 8, &lastError) == SHIM_BAD_ARGUMENT, "NULL target buffer");

    // The test directory and all in it go; nothing outside it was made.
    {
        wchar_t pattern[MAX_PATH] = { 0 };
        WIN32_FIND_DATAW found;
        HANDLE search;

        JoinPath(pattern, ARRAYSIZE(pattern), dir, L"*");
        search = FindFirstFileW(pattern, &found);
        while (search != INVALID_HANDLE_VALUE)
        {
            if (wcscmp(found.cFileName, L".") != 0 && wcscmp(found.cFileName, L"..") != 0)
            {
                JoinPath(path, ARRAYSIZE(path), dir, found.cFileName);
                if (found.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)
                {
                    RemoveDirectoryW(path);
                }
                else
                {
                    DeleteFileW(path);
                }
            }

            if (!FindNextFileW(search, &found))
            {
                FindClose(search);
                search = INVALID_HANDLE_VALUE;
            }
        }

        RemoveDirectoryW(dir);
    }
}

static void TestMisc(void)
{
    DWORD lineage[MAX_LINEAGE] = { 0 };
    char *argv[] = { "winctl", "state", NULL };
    char *argvWithNull[] = { "winctl", NULL };
    wchar_t path[64] = { 0 };
    DWORD lastError = 0;
    int length;

    Check(PrintIndicatorState(-1) == -1 && PrintIndicatorState(4) == -1, "indicator state out of range refused");

    length = GetProcessLineage(GetCurrentProcessId(), lineage, MAX_LINEAGE);
    Check(length >= 1 && lineage[0] == GetCurrentProcessId(), "lineage starts at this process");
    Check(GetProcessLineage(GetCurrentProcessId(), lineage, 0) == -1, "lineage capacity 0");
    Check(GetProcessLineage(GetCurrentProcessId(), NULL, MAX_LINEAGE) == -1, "lineage NULL");
    Check(GetProcessLineage(0, lineage, MAX_LINEAGE) == -1, "lineage of pid 0");
    Check(GetProcessLineage(GetCurrentProcessId(), lineage, MAX_LINEAGE + 1) == -1, "lineage capacity too big");
    Check(FindNeovimCaller(0) == 0 && FindNeovimCaller(MAX_LINEAGE) == 0, "caller depth out of range");

    Check(IsCommand(2, argv, "state", 2), "command matches");
    Check(!IsCommand(3, argv, "state", 2), "command count differs");
    Check(!IsCommand(2, NULL, "state", 2), "command NULL argv");
    Check(!IsCommand(2, argvWithNull, "state", 2), "command NULL argument");
    Check(!IsCommand(2, argv, NULL, 2), "command NULL name");

    for (int result = SHIM_OK; result <= SHIM_BAD_ARGUMENT; ++result)
    {
        const wchar_t *text = DescribeShimResult((SHIM_RESULT)result);

        Check(text != NULL && text[0] != L'\0', "every shim result is described");
    }

    Check(wcscmp(DescribeShimResult((SHIM_RESULT)999), L"invalid argument") == 0, "an unknown result is described");

    Check(SetEnvironmentVariableW(L"PATH", L"C:\\old"), "set PATH");
    Check(PrependOwnDirectory(L"C:\\tools\\x.exe", &lastError), "prepend the program's directory");
    Check(GetEnvironmentVariableW(L"PATH", path, ARRAYSIZE(path)) != 0 && wcscmp(path, L"C:\\tools;C:\\old") == 0,
          "PATH starts with the program's directory");
    Check(!PrependOwnDirectory(L"x.exe", &lastError), "prepend refuses a relative program");
    Check(!PrependOwnDirectory(NULL, &lastError), "prepend refuses NULL");
    Check(!PrependOwnDirectory(L"C:\\x.exe", NULL), "prepend refuses a NULL error");
}

int main(void)
{
    TestParseNumber();
    TestSkipProgramName();
    TestClassifyPath();
    TestParseShimContent();
    TestFiles();
    TestMisc();
    printf("== %d checks, %d failed\n", gs_checkCount, gs_failureCount);
    return gs_failureCount == 0 ? 0 : 1;
}
