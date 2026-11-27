// Unit tests for native/windows_wsl_bridge.c's validators and Win32 argument quoting, compiled together with it
// (WINDOWS_WSL_BRIDGE_NO_MAIN drops wmain). tests/windows_wsl_bridge/run.ps1 builds and runs it under ASan.
#define WINDOWS_WSL_BRIDGE_NO_MAIN
#include "../../native/windows_wsl_bridge.c"

#include <shellapi.h>

#ifdef _MSC_VER
#pragma comment(lib, "shell32.lib")
#endif

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

static void TestDistroName(void)
{
    wchar_t tooLong[MAX_DISTRO_CHARS + 4];

    Check(ValidateDistroName(L"archlinux"), "distro: archlinux");
    Check(ValidateDistroName(L"Ubuntu-24.04"), "distro: Ubuntu-24.04");
    Check(ValidateDistroName(L"Ubuntu 24.04"), "distro: space inside");
    Check(ValidateDistroName(L"openSUSE_Tumbleweed"), "distro: underscore");
    Check(!ValidateDistroName(NULL), "distro: NULL");
    Check(!ValidateDistroName(L""), "distro: empty");
    Check(!ValidateDistroName(L"-d"), "distro: leading dash");
    Check(!ValidateDistroName(L" arch"), "distro: leading space");
    Check(!ValidateDistroName(L"arch "), "distro: trailing space");
    Check(!ValidateDistroName(L"arch;id"), "distro: semicolon");
    Check(!ValidateDistroName(L"arch/root"), "distro: slash");
    Check(!ValidateDistroName(L"arch\\root"), "distro: backslash");
    Check(!ValidateDistroName(L"arch\"x"), "distro: quote");
    Check(!ValidateDistroName(L"arch\nx"), "distro: newline");

    for (size_t i = 0; i < MAX_DISTRO_CHARS + 1; ++i)
    {
        tooLong[i] = L'a';
    }

    tooLong[MAX_DISTRO_CHARS + 1] = L'\0';
    Check(!ValidateDistroName(tooLong), "distro: over max length");
}

static void TestLinuxPathsAndArgs(void)
{
    Check(ValidateLinuxDir(L"~"), "dir: tilde");
    Check(ValidateLinuxDir(L"/home/user/proj"), "dir: absolute");
    Check(ValidateLinuxDir(L"/mnt/c/a & b/한글"), "dir: space, &, Korean");
    Check(!ValidateLinuxDir(NULL), "dir: NULL");
    Check(!ValidateLinuxDir(L""), "dir: empty");
    Check(!ValidateLinuxDir(L"relative"), "dir: relative");
    Check(!ValidateLinuxDir(L"~root"), "dir: ~root");
    Check(!ValidateLinuxDir(L"/tmp\nid"), "dir: newline");
    Check(!ValidateLinuxDir(L"/tmp\x7Fid"), "dir: DEL");

    Check(ValidateLinuxNvim(L"nvim"), "nvim: bare nvim");
    Check(ValidateLinuxNvim(L"/usr/bin/nvim"), "nvim: /usr/bin/nvim");
    Check(!ValidateLinuxNvim(NULL), "nvim: NULL");
    Check(!ValidateLinuxNvim(L"sh"), "nvim: arbitrary bare name");
    Check(!ValidateLinuxNvim(L"/usr/bin/nvim --cmd"), "nvim: space");
    Check(!ValidateLinuxNvim(L"/usr/../bin/nvim"), "nvim: /../ traversal");
    Check(!ValidateLinuxNvim(L"/usr/.."), "nvim: trailing /..");
    Check(!ValidateLinuxNvim(L"/usr/bin/nvim\n"), "nvim: newline");

    Check(ValidateLinuxArg(L"src/main.c"), "arg: relative file");
    Check(ValidateLinuxArg(L"/home/user/a;b & $(id)"), "arg: literal characters safe under execve");
    Check(!ValidateLinuxArg(NULL), "arg: NULL");
    Check(!ValidateLinuxArg(L""), "arg: empty");
    Check(!ValidateLinuxArg(L"a\nb"), "arg: newline");
}

static void TestWindowsValidators(void)
{
    Check(ValidateHelperExeName(L"windows_ime_helper-193cd248da984790-10beb.exe"), "helper name: valid");
    Check(!ValidateHelperExeName(NULL), "helper name: NULL");
    Check(!ValidateHelperExeName(L"windows_ime_helper.exe"), "helper name: missing hashes");
    Check(!ValidateHelperExeName(L"windows_ime_helper-1234-zzzz.exe"), "helper name: non-hex");
    Check(!ValidateHelperExeName(L"..\\windows_ime_helper-1-2.exe"), "helper name: traversal");
    Check(!ValidateHelperExeName(L"windows_ime_helper-1-2.exe.bat"), "helper name: extra suffix");

    Check(ValidateLocalWindowsPath(L"C:\\Program Files\\Neovide\\neovide.exe"), "win path: drive backslash");
    Check(ValidateLocalWindowsPath(L"D:/tools/nvim.exe"), "win path: drive forward slash");
    Check(!ValidateLocalWindowsPath(NULL), "win path: NULL");
    Check(!ValidateLocalWindowsPath(L"C:nvim.exe"), "win path: drive-relative");
    Check(!ValidateLocalWindowsPath(L"\\nvim.exe"), "win path: rooted");
    Check(!ValidateLocalWindowsPath(L"\\\\server\\share\\nvim.exe"), "win path: UNC");
    Check(!ValidateLocalWindowsPath(L"\\\\.\\C:\\nvim.exe"), "win path: device");
    Check(!ValidateLocalWindowsPath(L"C:\\nvim.exe:stream"), "win path: ADS");
    Check(!ValidateLocalWindowsPath(L"C:\\a\nb.exe"), "win path: newline");

    Check(ValidateBase64Arg(L"L2hvbWUvdXNlcg=="), "b64: valid");
    Check(!ValidateBase64Arg(NULL), "b64: NULL");
    Check(!ValidateBase64Arg(L""), "b64: empty");
    Check(!ValidateBase64Arg(L"abc;def"), "b64: semicolon");
    Check(!ValidateBase64Arg(L"abc def"), "b64: space");

    {
        const wchar_t *selfProd = L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_wsl_bridge\\"
                                  L"windows_wsl_bridge-1-2.exe";
        const wchar_t *selfXdg = L"D:\\xdg\\nvim-data\\nvim-config\\windows_wsl_bridge\\windows_wsl_bridge-1-2.exe";
        const wchar_t *selfTemp = L"C:\\Temp\\unit.exe";
        const wchar_t *localAppData = L"C:\\Users\\user\\AppData\\Local";

        Check(IsAllowedHelperDirForSelf(L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_ime_helper",
                                        selfProd, localAppData),
              "helper dir: matches default sibling");
        Check(IsAllowedHelperDirForSelf(L"C:/Users/user/AppData/Local/nvim-data/nvim-config/windows_ime_helper/",
                                        selfProd, localAppData),
              "helper dir: normalizes slashes and trailing slash");
        Check(IsAllowedHelperDirForSelf(L"D:\\xdg\\nvim-data\\nvim-config\\windows_ime_helper", selfXdg, localAppData),
              "helper dir: matches custom XDG_DATA_HOME sibling");
        Check(!IsAllowedHelperDirForSelf(L"C:\\Temp\\nvim-config\\windows_ime_helper", selfProd, localAppData),
              "helper dir: rejects Fake Temp path in production");
        Check(!IsAllowedHelperDirForSelf(L"C:\\Temp\\nvim-config\\windows_ime_helper", selfTemp, localAppData),
              "helper dir: rejects Fake Temp path in standalone test");
        Check(IsAllowedHelperDirForSelf(L"C:\\Users\\user\\AppData\\Local\\nvim-data\\nvim-config\\windows_ime_helper",
                                        selfTemp, localAppData),
              "helper dir: standalone test accepts LocalAppData dir");
        Check(!IsAllowedHelperDirForSelf(L"C:\\Users\\user\\AppData\\Local\\..\\Temp\\nvim-config\\windows_ime_helper",
                                         selfTemp, localAppData),
              "helper dir: rejects .. traversal");
        Check(!IsAllowedHelperDirForSelf(L"C:\\Windows\\System32", selfProd, localAppData),
              "helper dir: rejects System32");
        Check(!IsAllowedHelperDirForSelf(NULL, selfProd, localAppData), "helper dir: rejects NULL");
    }
}

static void TestForwardedEmbedArgs(void)
{
    const wchar_t *okVersion[] = { L"bridge", L"--version" };
    const wchar_t *okShortV[] = { L"bridge", L"-v" };
    const wchar_t *okEmbed[] = { L"bridge", L"--embed" };
    const wchar_t *okEmbedP[] = { L"bridge", L"--embed", L"-p" };
    const wchar_t *okEmbedFiles[] = { L"bridge", L"--embed", L"-p", L"+42", L"--", L"a.c", L"-u" };
    const wchar_t *okTailFiles[] = { L"bridge", L"--", L"/tmp/a.txt", L"-u", L"--embed", L"-p" };
    const wchar_t *okTailEmbedFile[] = { L"bridge", L"--", L"--embed", L"--embed", L"-p" };
    const wchar_t *okTailFlags[] = { L"bridge", L"+42", L"-R", L"--", L"/tmp/a.txt", L"--embed" };
    const wchar_t *badCmd[] = { L"bridge", L"--embed", L"--cmd", L"!calc" };
    const wchar_t *badTailCmd[] = { L"bridge", L"--cmd", L"!calc", L"--embed", L"-p" };
    const wchar_t *badInit[] = { L"bridge", L"--embed", L"-u", L"/tmp/evil.lua" };
    const wchar_t *badTailInit[] = { L"bridge", L"-u", L"/tmp/evil.lua", L"--embed", L"-p" };
    const wchar_t *badListen[] = { L"bridge", L"--embed", L"--listen", L"0.0.0.0:6666" };
    const wchar_t *badPositionalBeforeSep[] = { L"bridge", L"--embed", L"file.txt" };
    const wchar_t *badTailPositionalBeforeSep[] = { L"bridge", L"/tmp/a.txt", L"--embed", L"-p" };
    const wchar_t *badDuplicateEmbed[] = { L"bridge", L"--embed", L"--embed" };
    const wchar_t *badPlusCmd[] = { L"bridge", L"--embed", L"+!calc" };
    const wchar_t *norm[8] = { 0 };
    int normCount = 0;

    Check(ValidateForwardedEmbedArgs(ARRAYSIZE(okVersion), okVersion), "forward: --version");
    Check(ValidateForwardedEmbedArgs(ARRAYSIZE(okShortV), okShortV), "forward: -v");
    Check(ValidateForwardedEmbedArgs(ARRAYSIZE(okEmbed), okEmbed), "forward: --embed");
    Check(BuildNormalizedEmbedArgs(ARRAYSIZE(okEmbedP), okEmbedP, norm, ARRAYSIZE(norm), &normCount) &&
              normCount == 2 && wcscmp(norm[0], L"--embed") == 0 && wcscmp(norm[1], L"-p") == 0,
          "normalize: --embed -p");
    Check(ValidateForwardedEmbedArgs(ARRAYSIZE(okEmbedFiles), okEmbedFiles), "forward: --embed -p +42 -- files");
    Check(BuildNormalizedEmbedArgs(ARRAYSIZE(okTailFiles), okTailFiles, norm, ARRAYSIZE(norm), &normCount) &&
              normCount == 5 && wcscmp(norm[0], L"--embed") == 0 && wcscmp(norm[1], L"-p") == 0 &&
              wcscmp(norm[2], L"--") == 0 && wcscmp(norm[3], L"/tmp/a.txt") == 0 && wcscmp(norm[4], L"-u") == 0,
          "normalize: -- /tmp/a.txt -u --embed -p");
    Check(BuildNormalizedEmbedArgs(ARRAYSIZE(okTailEmbedFile), okTailEmbedFile, norm, ARRAYSIZE(norm), &normCount) &&
              normCount == 4 && wcscmp(norm[0], L"--embed") == 0 && wcscmp(norm[1], L"-p") == 0 &&
              wcscmp(norm[2], L"--") == 0 && wcscmp(norm[3], L"--embed") == 0,
          "normalize: -- --embed --embed -p");
    Check(BuildNormalizedEmbedArgs(ARRAYSIZE(okTailFlags), okTailFlags, norm, ARRAYSIZE(norm), &normCount) &&
              normCount == 5 && wcscmp(norm[0], L"--embed") == 0 && wcscmp(norm[1], L"+42") == 0 &&
              wcscmp(norm[2], L"-R") == 0 && wcscmp(norm[3], L"--") == 0 && wcscmp(norm[4], L"/tmp/a.txt") == 0,
          "normalize: +42 -R -- /tmp/a.txt --embed");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badCmd), badCmd), "forward: refuses --cmd");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badTailCmd), badTailCmd), "forward: refuses tail --cmd");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badInit), badInit), "forward: refuses -u");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badTailInit), badTailInit), "forward: refuses tail -u");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badListen), badListen), "forward: refuses --listen");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badPositionalBeforeSep), badPositionalBeforeSep),
          "forward: refuses positional file before --");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badTailPositionalBeforeSep), badTailPositionalBeforeSep),
          "forward: refuses tail positional file before --");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badDuplicateEmbed), badDuplicateEmbed),
          "forward: refuses duplicate --embed");
    Check(!ValidateForwardedEmbedArgs(ARRAYSIZE(badPlusCmd), badPlusCmd), "forward: refuses +command");
}

static void TestAppendQuotedArg(void)
{
    const wchar_t *cases[] = {
        L"simple",
        L"",
        L"two words",
        L"tab\there",
        L"trailing\\backslash\\",
        L"quote\"inside",
        L"\\\"mixed\\\\\"slashes\\",
        L"한글 & ; $(id) %PATH%",
    };
    wchar_t cmdLine[4096] = { 0 };
    size_t len = 0;
    int parsedCount = 0;
    LPWSTR *parsed = NULL;

    Check(AppendQuotedArg(cmdLine, ARRAYSIZE(cmdLine), &len, L"C:\\Program Files\\prog.exe"), "quote argv0");
    for (size_t i = 0; i < ARRAYSIZE(cases); ++i)
    {
        Check(AppendQuotedArg(cmdLine, ARRAYSIZE(cmdLine), &len, cases[i]), "append arg");
    }

    parsed = CommandLineToArgvW(cmdLine, &parsedCount);
    Check(parsed != NULL && parsedCount == (int)ARRAYSIZE(cases) + 1, "CommandLineToArgvW count matches");
    if (parsed != NULL)
    {
        Check(wcscmp(parsed[0], L"C:\\Program Files\\prog.exe") == 0, "round-trip argv0");
        for (int i = 0; i < (int)ARRAYSIZE(cases) && i + 1 < parsedCount; ++i)
        {
            Check(wcscmp(parsed[i + 1], cases[i]) == 0, "round-trip argument matches verbatim");
        }

        LocalFree(parsed);
        parsed = NULL;
    }
}

static void TestDrainStderrThreadCap(void)
{
    HANDLE readPipe = NULL;
    HANDLE writePipe = NULL;
    HANDLE thread = NULL;
    RELAY_CONTEXT ctx;
    BYTE input[STDERR_CAP_BYTES * 2 + 123];
    DWORD offset = 0;

    ZeroMemory(&ctx, sizeof(ctx));
    for (size_t i = 0; i < sizeof(input); ++i)
    {
        input[i] = (BYTE)('a' + (i % 26));
    }

    Check(CreatePipePair(&readPipe, &writePipe, FALSE, FALSE), "stderr pipe created");
    if (readPipe != NULL && writePipe != NULL)
    {
        ctx.wslErrRead = readPipe;
        thread = CreateThread(NULL, 0, DrainStderrThread, &ctx, 0, NULL);
        Check(thread != NULL, "DrainStderrThread created");
        if (thread != NULL)
        {
            while (offset < (DWORD)sizeof(input))
            {
                DWORD chunk = (DWORD)sizeof(input) - offset;
                DWORD written = 0;

                if (chunk > 2048)
                {
                    chunk = 2048;
                }

                if (!WriteFile(writePipe, input + offset, chunk, &written, NULL) || written == 0)
                {
                    break;
                }

                offset += written;
            }

            CloseHandle(writePipe);
            writePipe = NULL;
            Check(offset == (DWORD)sizeof(input), "stderr test payload written in full");
            Check(WaitForSingleObject(thread, 5000) == WAIT_OBJECT_0, "DrainStderrThread exited cleanly");
            {
                DWORD threadExit = 1;

                Check(GetExitCodeThread(thread, &threadExit) && threadExit == 0, "DrainStderrThread exit code 0");
            }
            CloseHandle(thread);
            thread = NULL;
        }

        if (writePipe != NULL)
        {
            CloseHandle(writePipe);
            writePipe = NULL;
        }

        Check(ctx.stderrLength == STDERR_CAP_BYTES, "DrainStderrThread caps length at STDERR_CAP_BYTES");
        Check(ctx.stderrTail[STDERR_CAP_BYTES] == '\0', "DrainStderrThread NUL-terminates tail");
        Check(memcmp(ctx.stderrTail, input, STDERR_CAP_BYTES) == 0,
              "DrainStderrThread keeps exact leading stderr prefix");
        CloseHandle(readPipe);
        readPipe = NULL;
    }
}

int main(void)
{
    TestDistroName();
    TestLinuxPathsAndArgs();
    TestWindowsValidators();
    TestForwardedEmbedArgs();
    TestAppendQuotedArg();
    TestDrainStderrThreadCap();
    printf("== %d checks, %d failed\n", gs_checkCount, gs_failureCount);
    return (gs_failureCount == 0) ? 0 : 1;
}
