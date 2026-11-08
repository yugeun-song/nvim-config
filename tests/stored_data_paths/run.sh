#!/bin/sh
# Where Neovim keeps its files, and lua/features/maintenance/stored_data_paths.lua, under every layout variant
# (tests/stored_data_paths/check.lua). Linux and macOS, natively or in the containers of
# tests/stored_data_paths/docker.sh. Everything happens in a throwaway root under $TMPDIR: HOME and every XDG
# directory point into it, and it is removed at the end.
#
#   tests/stored_data_paths/run.sh [--release] [--flatpak APP_ID] [NVIM...]
#
#   NVIM...          Neovim programs to test (default: nvim on PATH). The layout is checked with any; the module
#                    with 0.11 or later.
#   --release        also the official Neovim 0.12.2 build for this system, its SHA-256 checked against the one
#                    GitHub publishes for the release asset.
#   --flatpak ID     Neovim from a Flatpak (io.neovim.nvim), run inside its sandbox.
#   --installed      also this user's own layout: the real $HOME and the configuration where it is installed
#                    (~/.config/nvim). A reset there removes the real data, so it runs only in a container.
#   KEEP_ROOT=1      keep the root for a look afterwards.
#
# Variants: default; xdg (all four XDG_*_HOME elsewhere); appname (NVIM_APPNAME=testapp); appname-nested
# (group/testapp, Neovim 0.10+); flatpak-sim (the variables a Flatpak sets, FLATPAK_ID included); overlap
# (XDG_DATA_HOME = XDG_STATE_HOME = XDG_CONFIG_HOME: the data directory is the configuration, and stays);
# nested (the configuration inside the data directory, which stays too).
# Then the reset's question: a "reset" piped in removes nothing; typed into a pseudo-terminal (script(1)), as a
# person would, it removes; anything else typed keeps everything.
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
CHECK="$REPO/tests/stored_data_paths/check.lua"
RESET="$REPO/scripts/reset_to_fresh_clone.lua"

# check.lua in a started Neovim; an error in it ends Neovim with a FAIL line and code 2, where -c alone would
# leave Neovim waiting.
RUN_CHECK="lua local ok, err = pcall(dofile, os.getenv('PATHS_TEST_FILE')) if not ok then io.stdout:write('FAIL [harness] ' .. tostring(err):gsub('%s+', ' ') .. string.char(10)) vim.cmd('cquit 2') end"

# A rename that left these behind fails here, not as a Neovim waiting on an error.
for file in "$CHECK" "$RESET"; do
  [ -f "$file" ] || {
    echo "FAIL [harness] missing $file" >&2
    exit 2
  }
done
NV_VERSION=0.12.2

release=0
installed=0
flatpak=""
nvims=""

while [ $# -gt 0 ]; do
  case "$1" in
    --release) release=1 ;;
    --installed) installed=1 ;;
    --flatpak) flatpak=${2:?--flatpak needs an app id}; shift ;;
    -h | --help)
      # The comment block at the top of this file, whatever its length.
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    *) nvims="$nvims $1" ;;
  esac
  shift
done

# The root as the system resolves it (macOS: /var is /private/var; TMPDIR may end in "/"), which is how Neovim
# reports the directories under it.
tmp=${TMPDIR:-/tmp}
ROOT=$(mktemp -d "${tmp%/}/nvim-paths.XXXXXX") && ROOT=$(cd "$ROOT" && pwd -P) || exit 2
if [ "${KEEP_ROOT:-0}" = 1 ]; then
  echo "root: $ROOT"
else
  trap 'rm -rf "$ROOT"' EXIT
fi
trap 'exit 130' INT TERM

LOG="$ROOT/results.log"
: >"$LOG"

# To the log and stderr: fetch_release's stdout is the path it returns.
say() {
  echo "$*" >>"$LOG"
  echo "$*" >&2
}

# The official build, checked before it is unpacked.
fetch_release() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) asset=nvim-linux-x86_64 sha=31cf85945cb600d96cdf69f88bc68bec814acbff50863c5546adef3a1bcef260 ;;
    Linux-aarch64 | Linux-arm64) asset=nvim-linux-arm64 sha=f697d4e4582b6e4b5c3c26e76e06ce26efa08ba1768e03fd2733fcc422bb0490 ;;
    Darwin-arm64) asset=nvim-macos-arm64 sha=eeddee1009734f9071266e6b1b8a70308cb60cbcc45f5e1c1023adc471450fee ;;
    Darwin-x86_64) asset=nvim-macos-x86_64 sha=728321db960a9b6af6c03881892a6abfd743bf759bc62d233f52fa1be64ace3c ;;
    *) say "SKIP [release] no official build for $(uname -s) $(uname -m)"; return 1 ;;
  esac

  url="https://github.com/neovim/neovim/releases/download/v$NV_VERSION/$asset.tar.gz"
  file="$ROOT/$asset.tar.gz"

  if ! { curl -fsSL -o "$file" "$url" 2>/dev/null || wget -qO "$file" "$url"; }; then
    say "FAIL [release] could not download $url"
    return 1
  fi

  got=$({ sha256sum "$file" 2>/dev/null || shasum -a 256 "$file"; } | cut -d' ' -f1)

  if [ "$got" != "$sha" ]; then
    say "FAIL [release] $asset.tar.gz: SHA-256 $got, GitHub publishes $sha"
    return 1
  fi

  mkdir -p "$ROOT/release" && tar -xzf "$file" -C "$ROOT/release" || return 1
  echo "$ROOT/release/$asset/bin/nvim"
}

# A clean environment for one variant: nothing of the caller's layout leaks in.
variant_env() {
  h=$1
  unset NVIM_APPNAME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR \
    FLATPAK_ID NEOVIDE_CONFIG SNAP_NAME APPIMAGE NVIM VIMINIT MYVIMRC
  export HOME="$h"

  case "$2" in
    xdg) export XDG_CONFIG_HOME="$h/xc" XDG_DATA_HOME="$h/xd" XDG_STATE_HOME="$h/xs" XDG_CACHE_HOME="$h/xk" ;;
    appname) export NVIM_APPNAME=testapp ;;
    appname-nested) export NVIM_APPNAME=group/testapp ;;
    flatpak-sim)
      a="$h/.var/app/io.neovim.nvim"
      export FLATPAK_ID=io.neovim.nvim XDG_CONFIG_HOME="$a/config" XDG_DATA_HOME="$a/data" \
        XDG_STATE_HOME="$a/.local/state" XDG_CACHE_HOME="$a/cache"
      ;;
    overlap) export XDG_CONFIG_HOME="$h/same" XDG_DATA_HOME="$h/same" XDG_STATE_HOME="$h/same" ;;
    nested) export XDG_DATA_HOME="$h/d" XDG_CONFIG_HOME="$h/d/nvim" ;;
  esac
}

run_check() { # label, nvim, variant
  dir="$ROOT/$1/$3"
  mkdir -p "$dir/home"
  (
    variant_env "$dir/home" "$3"
    # shellcheck disable=SC2030 # local to this subshell on purpose: one variant's settings never leak into the next
    export PATHS_TEST_ROOT="$dir" PATHS_TEST_MODE=module PATHS_TEST_VARIANT="$3" PATHS_TEST_FILE="$CHECK"
    "$2" --headless --clean -c "$RUN_CHECK" </dev/null 2>&1
  ) | sed "s|^|$1 |" | tee -a "$LOG"
}

# script(1) gives the command a terminal and types what comes on its stdin, as a person at that terminal would.
in_pty() {
  if script -V >/dev/null 2>&1; then
    script -q -e -c "$1" /dev/null
  elif [ "$(uname -s)" = Darwin ]; then
    script -q /dev/null sh -c "$1"
  else
    return 77
  fi
}

run_gate() { # label, nvim
  "$2" --headless --clean -c "lua os.exit(vim.fn.has('nvim-0.11') == 1 and 0 or 3)" </dev/null >/dev/null 2>&1 || {
    say "$1 SKIP [gate] the reset script needs Neovim 0.11 or later"
    return
  }

  for answer in piped no reset; do
    dir="$ROOT/$1/gate-$answer"
    sentinel="$dir/home/.local/share/nvim/lazy/plugin/init.lua"
    mkdir -p "$(dirname "$sentinel")" && echo x >"$sentinel"
    out="$dir/out.txt"

    (
      variant_env "$dir/home" default
      cmd="'$2' -l '$RESET'"

      if [ "$answer" = piped ]; then
        printf 'reset\n' | sh -c "$cmd" >"$out" 2>&1
      else
        # Typed once the question is on the terminal, as a person would: macOS's script(1) loses what comes before
        # the program reads it. Ten seconds at most, then typed anyway.
        {
          i=0
          while [ "$i" -lt 100 ] && ! grep -q 'Type "reset"' "$out" 2>/dev/null; do
            sleep 0.1
            i=$((i + 1))
          done
          printf '%s\n' "$answer"
        } | in_pty "$cmd" >"$out" 2>&1
      fi
    )

    if [ "$answer" != piped ] && ! grep -q 'Type "reset"' "$out"; then
      say "$1 SKIP [gate] no pseudo-terminal here (script(1) from util-linux, or macOS's)"
      return
    fi

    case "$answer" in
      piped) want=kept what='"reset" piped in' ;;
      no) want=kept what='"no" typed at the question' ;;
      reset) want=removed what='"reset" typed at the question' ;;
    esac

    if [ -e "$sentinel" ]; then got=kept; else got=removed; fi

    if [ "$got" = "$want" ]; then
      say "$1 PASS [gate] $what: $got"
    else
      say "$1 FAIL [gate] $what: $got, expected $want; it showed:"
      sed 's/^/    | /' "$out" | tee -a "$LOG"
    fi
  done
}

if [ "$release" = 1 ]; then
  bin=$(fetch_release) && nvims="$nvims $bin"
fi

if [ -z "$nvims" ] && [ -z "$flatpak" ]; then
  nvims=$(command -v nvim) || { echo "no nvim on PATH; name one, or pass --release" >&2; exit 2; }
fi

n=0
for nvim in $nvims; do
  n=$((n + 1))
  label="nvim$n"
  say "== $label: $nvim"

  for variant in default xdg appname appname-nested flatpak-sim overlap nested; do
    if [ "$variant" = appname-nested ] &&
      ! "$nvim" --headless --clean -c "lua os.exit(vim.fn.has('nvim-0.10') == 1 and 0 or 3)" </dev/null >/dev/null 2>&1; then
      say "$label SKIP [$variant] a nested NVIM_APPNAME needs Neovim 0.10 or later"
      continue
    fi

    run_check "$label" "$nvim" "$variant"
  done

  run_gate "$label" "$nvim"
done

# The real layout: this user's $HOME, the configuration where it is installed, no variable set.
in_container() {
  [ -e /.dockerenv ] || [ -e /run/.containerenv ] || [ -n "${container:-}" ]
}

if [ "$installed" = 1 ]; then
  if ! in_container; then
    say "FAIL [installed] runs only inside a container: a reset there removes this user's own Neovim data"
  else
    for nvim in $nvims; do
      say "== installed: $nvim, HOME=$HOME"
      (
        unset NVIM_APPNAME XDG_CONFIG_HOME XDG_DATA_HOME XDG_STATE_HOME XDG_CACHE_HOME XDG_RUNTIME_DIR \
          FLATPAK_ID NEOVIDE_CONFIG
        # shellcheck disable=SC2031 # set afresh for this subshell
        export PATHS_TEST_ROOT="$HOME" PATHS_TEST_MODE=module PATHS_TEST_VARIANT=installed PATHS_TEST_FILE="$CHECK"
        "$nvim" --headless --clean -c "$RUN_CHECK" </dev/null 2>&1
      ) | sed 's|^|installed |' | tee -a "$LOG"
    done
  fi
fi

# Inside a real Flatpak sandbox: its own XDG directories, FLATPAK_ID, the app's Neovim.
if [ -n "$flatpak" ]; then
  say "== flatpak: $flatpak"
  dir="$ROOT/flatpak/sandbox"
  mkdir -p "$dir/home"
  (
    variant_env "$dir/home" default
    flatpak run --filesystem="$REPO":ro --filesystem="$ROOT" \
      --env=PATHS_TEST_ROOT="$dir" --env=PATHS_TEST_MODE=module --env=PATHS_TEST_VARIANT=flatpak \
      --env=PATHS_TEST_FILE="$CHECK" --command=nvim "$flatpak" \
      --headless --clean -c "$RUN_CHECK" </dev/null 2>&1
  ) | sed 's|^|flatpak |' | tee -a "$LOG"
fi

passed=$(grep -cE '(^| )PASS ' "$LOG")
failed=$(grep -cE '(^| )FAIL ' "$LOG")
skipped=$(grep -cE '(^| )SKIP ' "$LOG")

echo "== $passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ]
