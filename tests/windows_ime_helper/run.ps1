# Every test of native/windows_ime_helper.c and its Lua side, built and run in a fresh temporary directory:
#   format (clang-format), strict builds (cl /W4 /WX /sdl /analyze, clang -Werror and its analyzer), the
#   preprocessor guards (Linux, macOS, MinGW, 32-bit and ARM64 targets must fail), the C unit tests and the
#   Neovim-driven tests under AddressSanitizer, the Lua bridge tests, and the libFuzzer target.
#
#   powershell -File tests\windows_ime_helper\run.ps1 [-FuzzSeconds 60] [-Nvim nvim]
#
# Needs Visual Studio 2022 or later with the C++ tools; outside a Developer PowerShell it enters one itself.
param([int]$FuzzSeconds = 60, [string]$Nvim = "nvim")

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$src = Join-Path $repo "native\windows_ime_helper.c"
$tests = Join-Path $repo "tests\windows_ime_helper"
$style = Join-Path $repo "native\.clang-format"

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  $vs = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $vs) { Write-Error "no Visual Studio with the C++ tools"; exit 2 }
  & (Join-Path $vs "Common7\Tools\Launch-VsDevShell.ps1") -Arch amd64 -HostArch amd64 -SkipAutomaticLocation | Out-Null
}

$llvm = $null
if ($env:VCINSTALLDIR) { $llvm = Join-Path $env:VCINSTALLDIR "Tools\Llvm\x64\bin" }
$clang = if ($llvm -and (Test-Path "$llvm\clang.exe")) { "$llvm\clang.exe" } else { (Get-Command clang -ErrorAction SilentlyContinue).Source }
$format = if ($llvm -and (Test-Path "$llvm\clang-format.exe")) { "$llvm\clang-format.exe" } else { (Get-Command clang-format -ErrorAction SilentlyContinue).Source }

$work = Join-Path ([IO.Path]::GetTempPath()) ("windows_ime_helper-tests-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory $work | Out-Null
Push-Location $work
$results = New-Object System.Collections.Generic.List[string]

function Step([string]$name, [scriptblock]$body, [switch]$MustFail, [string]$Expect) {
  # Every step runs a program: no exit code at all means none started (a command not found), which fails.
  $global:LASTEXITCODE = $null
  $output = & $body 2>&1 | ForEach-Object { "$_" }
  $code = if ($null -eq $LASTEXITCODE) { -1 } else { $LASTEXITCODE }
  $ok = if ($MustFail) { $code -ne 0 -and (-not $Expect -or ($output -join "`n") -match [regex]::Escape($Expect)) } else { $code -eq 0 }
  $results.Add(("{0} {1}" -f ($(if ($ok) { "PASS" } else { "FAIL" })), $name))
  if (-not $ok) { $output | Select-Object -Last 25 | ForEach-Object { "    $_" } }
}

$env:ASAN_OPTIONS = "halt_on_error=1:detect_leaks=0"

if ($format) { Step "clang-format (native/.clang-format)" { & $format --dry-run --Werror --style=file:$style $src } }
else { $results.Add("SKIP clang-format: not found (Visual Studio's C++ Clang tools, or LLVM on PATH)") }
Step "cl /W4 /WX /sdl /analyze, link /WX" { cl /nologo /O2 /MT /W4 /WX /sdl /analyze /analyze:external- /guard:cf /Fewindows_ime_helper.exe $src /link /WX /guard:cf /DEPENDENTLOADFLAG:0x800 /CETCOMPAT }
if ($clang) {
  Step "clang -Wall -Wextra -Werror (MSVC target)" { & $clang --target=x86_64-pc-windows-msvc -O2 -fms-runtime-lib=static -Wall -Wextra -Werror -o windows_ime_helper-clang.exe $src }
  Step "clang --analyze" { & $clang --target=x86_64-pc-windows-msvc --analyze -Wall -Wextra -Werror $src }
  foreach ($guard in @(
      @("x86_64-linux-gnu", "Linux target"), @("arm64-apple-macos", "macOS target"), @("x86_64-w64-mingw32", "MinGW"),
      @("i686-pc-windows-msvc", "64-bit"), @("aarch64-pc-windows-msvc", "x86_64 Windows only"))) {
    Step ("guard refuses " + $guard[0]) { & $clang --target=$($guard[0]) -fsyntax-only $src } -MustFail -Expect $guard[1]
  }
}
else { $results.Add("SKIP clang builds, analyzer and the five preprocessor guards: clang not found") }

Step "C unit tests (AddressSanitizer)" { cl /nologo /W4 /fsanitize=address /Zi /Od /Feunit.exe (Join-Path $tests "unit.c") /link /INCREMENTAL:NO | Out-Null; if ($LASTEXITCODE -eq 0) { .\unit.exe } }
Step "windows_ime_helper (AddressSanitizer)" { cl /nologo /W4 /fsanitize=address /Zi /Od /Fewindows_ime_helper-asan.exe $src /link /INCREMENTAL:NO }
Step "Neovim-driven tests, release build" { & $Nvim -l (Join-Path $tests "test.lua") (Join-Path $work "windows_ime_helper.exe") }
Step "Neovim-driven tests, AddressSanitizer build" { & $Nvim -l (Join-Path $tests "test.lua") (Join-Path $work "windows_ime_helper-asan.exe") }
Step "Lua bridge tests" { & $Nvim -l (Join-Path $tests "bridge.lua") }
if ($FuzzSeconds -gt 0) {
  Step "libFuzzer, $FuzzSeconds s (AddressSanitizer)" {
    cl /nologo /W3 /fsanitize=fuzzer /fsanitize=address /Zi /Od /Fefuzz.exe (Join-Path $tests "fuzz.c") /link /INCREMENTAL:NO | Out-Null
    if ($LASTEXITCODE -eq 0) { New-Item -ItemType Directory -Force corpus | Out-Null; .\fuzz.exe corpus "-max_total_time=$FuzzSeconds" }
  }
}

Pop-Location
$results
$failed = @($results | Where-Object { $_ -like "FAIL*" }).Count
$skipped = @($results | Where-Object { $_ -like "SKIP*" }).Count
"== $($results.Count) steps, $failed failed, $skipped skipped (work directory: $work)"
if ($failed -eq 0) { cmd /c rmdir /s /q "$work" }
exit $(if ($failed -eq 0) { 0 } else { 1 })
