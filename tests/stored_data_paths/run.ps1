# Where Neovim keeps its files, and lua/features/maintenance/stored_data_paths.lua, under every layout variant
# (tests/stored_data_paths/check.lua), on Windows. Everything happens in a throwaway root under %TEMP%: USERPROFILE,
# HOME, LOCALAPPDATA, APPDATA and TEMP point into it for the test's Neovim only, and it is removed at the end (rmdir,
# which does not follow the junctions the test makes).
#
#   powershell -File tests\stored_data_paths\run.ps1 [-Nvim nvim] [-KeepRoot]
#
# Variants: default; xdg (all four XDG_*_HOME, which Neovim reads on Windows too); appname; appname-nested;
# overlap; nested (the configuration inside the data directory, which then stays). Then the reset's question: a
# "reset" piped in removes nothing (the typed answer needs a console, which this script cannot type into).
param([string]$Nvim = "nvim", [switch]$KeepRoot)

$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$check = Join-Path $repo "tests\stored_data_paths\check.lua"
$reset = Join-Path $repo "scripts\reset_to_fresh_clone.lua"
# check.lua in a started Neovim; an error in it ends Neovim with a FAIL line and code 2, where -c alone would
# leave Neovim waiting.
$runCheck = "lua local ok, err = pcall(dofile, os.getenv('PATHS_TEST_FILE')) if not ok then io.stdout:write('FAIL [harness] ' .. tostring(err):gsub('%s+', ' ') .. string.char(10)) vim.cmd('cquit 2') end"
# A rename that left these behind fails here, not as a Neovim waiting on an error.
foreach ($file in $check, $reset) {
  if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { Write-Output "FAIL [harness] missing $file"; exit 2 }
}
$root = Join-Path ([IO.Path]::GetTempPath()) ("nvim-paths-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
$names = "NVIM_APPNAME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME", "XDG_CACHE_HOME", "XDG_RUNTIME_DIR",
  "USERPROFILE", "HOME", "LOCALAPPDATA", "APPDATA", "TEMP", "TMP", "NEOVIDE_CONFIG", "VIMINIT", "MYVIMRC",
  "PATHS_TEST_ROOT", "PATHS_TEST_MODE", "PATHS_TEST_VARIANT", "PATHS_TEST_FILE"
$saved = @{}
foreach ($n in $names) { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
$results = New-Object System.Collections.Generic.List[string]

function Set-Variant([string]$dir, [string]$variant) {
  foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $null) }
  $h = Join-Path $dir "home"
  $local = Join-Path $h "AppData\Local"
  $temp = Join-Path $local "Temp"
  New-Item -ItemType Directory -Force $temp, (Join-Path $h "AppData\Roaming") | Out-Null
  $set = @{ USERPROFILE = $h; HOME = $h; LOCALAPPDATA = $local; APPDATA = (Join-Path $h "AppData\Roaming"); TEMP = $temp; TMP = $temp }
  switch ($variant) {
    "xdg" { $set.XDG_CONFIG_HOME = "$h\xc"; $set.XDG_DATA_HOME = "$h\xd"; $set.XDG_STATE_HOME = "$h\xs"; $set.XDG_CACHE_HOME = "$h\xk" }
    "appname" { $set.NVIM_APPNAME = "testapp" }
    "appname-nested" { $set.NVIM_APPNAME = "group/testapp" }
    "overlap" { $set.XDG_CONFIG_HOME = "$h\same"; $set.XDG_DATA_HOME = "$h\same"; $set.XDG_STATE_HOME = "$h\same" }
    "nested" { $set.XDG_DATA_HOME = "$h\d"; $set.XDG_CONFIG_HOME = (Join-Path $h "d\nvim-data") }
  }
  foreach ($k in $set.Keys) { [Environment]::SetEnvironmentVariable($k, $set[$k]) }
  return $h
}

function Add-Result([string]$line) { $results.Add($line); $line }

try {
  foreach ($variant in "default", "xdg", "appname", "appname-nested", "overlap", "nested") {
    $dir = Join-Path $root $variant
    Set-Variant $dir $variant | Out-Null
    $env:PATHS_TEST_ROOT = $dir; $env:PATHS_TEST_MODE = "module"; $env:PATHS_TEST_VARIANT = $variant; $env:PATHS_TEST_FILE = $check
    $lines = @(& $Nvim --headless --clean -c $runCheck 2>&1 | ForEach-Object { Add-Result "$_" })
    $code = $LASTEXITCODE
    # A Neovim that crashed, or a check that ended before testing anything, fails without a FAIL line of its own.
    if (-not ($lines -match '^FAIL ')) {
      if ($code -ne 0) { Add-Result "FAIL [$variant] Neovim ended with code $code" }
      elseif (-not ($lines -match '^(PASS|SKIP) ')) { Add-Result "FAIL [$variant] Neovim ended without a result" }
    }
  }

  # The reset's question: a "reset" piped in is not an answer.
  $dir = Join-Path $root "gate"
  $h = Set-Variant $dir "default"
  $sentinel = Join-Path $h "AppData\Local\nvim-data\lazy\plugin\init.lua"
  New-Item -ItemType Directory -Force (Split-Path $sentinel) | Out-Null
  Set-Content $sentinel "x"
  $said = ("reset" | & $Nvim -l $reset 2>&1 | Out-String)
  if (-not (Test-Path $sentinel)) { Add-Result 'FAIL [gate] "reset" piped in: removed' }
  elseif ($said -notmatch 'Nothing was removed') { Add-Result "FAIL [gate] the refusal of a piped answer never showed; it showed: $said" }
  else { Add-Result 'PASS [gate] "reset" piped in: kept' }
} finally {
  foreach ($n in $names) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) }
  if ($KeepRoot) { "root: $root" } elseif (Test-Path $root) { cmd /c rmdir /s /q "$root" }
}

$passed = @($results | Where-Object { $_ -match '^PASS ' }).Count
$failed = @($results | Where-Object { $_ -match '^FAIL ' }).Count
$skipped = @($results | Where-Object { $_ -match '^SKIP ' }).Count
"== $passed passed, $failed failed, $skipped skipped"
# Nothing that passed is no success either: a harness that tested nothing must not look green.
if ($failed -gt 0 -or $passed -eq 0) { exit 1 }
