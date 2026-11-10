#!/bin/sh
# This configuration in the official images of desktop Linux distributions, through rootless podman. Nothing runs
# it by itself: start it by hand on a Linux host.
#
#   sh tests/containers/run.sh [--keep] [--rebuild] [DISTRIBUTION...]
#   sh tests/containers/run.sh --clean
#
# Once per run, on the host (network): the official Neovim 0.12.6 build (SHA-256 checked), and the plugins at
# lazy-lock.json's commits with their tree-sitter parsers, in an isolated directory.
# Per distribution:
#   prepare (network)  from the distribution's official image: its own Neovim and the tools the tests use, a test
#                      user, the official build (not on NixOS), the plugins and parsers; kept as the image
#                      localhost/nvim-config-test/<name>:prepared.
#   test (no network)  a container of that image runs tests/managed_paths/run.sh in the user's real layout and every
#                      variant, and starts the whole configuration with each Neovim (startup_check.lua).
#
# Default: when the run ends, or is interrupted, everything of these tests is removed: the containers and images
# labelled org.nvim-config.test=containers, the official images this script pulled, the host directory, the records
# and the logs. --keep keeps all of it (a later run reuses a prepared image while lazy-lock.json is unchanged;
# --rebuild prepares again), and --clean removes what --keep left. An image that was there before this script pulled
# it, and anything without its label, is never touched.
#
# Distributions (official images; rolling releases or the latest stable or LTS):
#   arch debian ubuntu fedora rocky opensuse void nixos gentoo (default: all)
# Logs (removed at the end unless --keep): ${XDG_STATE_HOME:-~/.local/state}/nvim-config-container-tests/logs/
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
LABEL="org.nvim-config.test=containers"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/nvim-config-container-tests"
PULLED="$STATE/pulled-images"
DEFAULT="arch debian ubuntu fedora rocky opensuse void nixos gentoo"
NV_VERSION=0.12.6
# Per container, swap included: a runaway test is stopped inside its own cgroup instead of pressing the whole host.
MEMORY=4g

keep=0
rebuild=0
clean=0
names=""

while [ $# -gt 0 ]; do
  case "$1" in
    --keep) keep=1 ;;
    --rebuild) rebuild=1 ;;
    --clean) clean=1 ;;
    -h | --help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    -*)
      echo "unknown option: $1" >&2
      exit 2
      ;;
    *) names="$names $1" ;;
  esac
  shift
done

if [ "$(uname -s)" != Linux ]; then
  echo "error: the container tests need a Linux host (this is $(uname -s))" >&2
  exit 2
fi

# podman only: it runs rootless, without a root daemon, and its signature policy can check cosign signatures, which
# openSUSE publishes; Docker's Notary signatures no longer cover the official images' current builds (2026-11-11).
command -v podman >/dev/null 2>&1 || {
  echo "error: podman is not installed" >&2
  exit 2
}

# Installed is not enough: rootless podman may not be set up for this user.
if ! podman info >/dev/null 2>&1; then
  echo "error: podman does not answer (podman info fails); finish its rootless setup" >&2
  exit 2
fi

mkdir -p "$STATE"

# A directory of this name made by someone else would take this script's records of what it pulled.
[ -n "$(find "$STATE" -prune -user "$(id -u)")" ] || {
  echo "error: $STATE belongs to another user" >&2
  exit 2
}

image_present() {
  podman image inspect "$1" >/dev/null 2>&1
}

# Only what carries this script's label, and official images it recorded as pulled while no container uses them.
remove_kept() {
  ids=$(podman ps -aq --filter "label=$LABEL")
  # shellcheck disable=SC2086 # one id per word
  [ -z "$ids" ] || podman rm -f $ids >/dev/null
  echo "removed $(printf '%s' "$ids" | grep -c .) container(s) labelled $LABEL"
  ids=$(podman images -q --filter "label=$LABEL" | sort -u)
  # shellcheck disable=SC2086
  [ -z "$ids" ] || podman rmi -f $ids >/dev/null
  echo "removed $(printf '%s' "$ids" | grep -c .) prepared image(s)"

  if [ -f "$PULLED" ]; then
    sort -u "$PULLED" | while IFS= read -r image; do
      [ -n "$image" ] || continue
      if [ -n "$(podman ps -aq --filter "ancestor=$image")" ]; then
        echo "kept $image: a container still uses it" >&2
        echo "$image"
      elif podman rmi "$image" >/dev/null 2>&1; then
        echo "removed $image" >&2
      elif image_present "$image"; then
        echo "kept $image: podman rmi failed" >&2
        echo "$image"
      fi
    done >"$PULLED.left"
    mv "$PULLED.left" "$PULLED"
  fi

  rm -rf "$STATE/host" "$STATE/logs"
  # The record stays only for an image a container of someone else still uses.
  [ -s "$PULLED" ] || rm -rf "$STATE"
}

if [ "$clean" = 1 ]; then
  remove_kept
  exit 0
fi

# Fully qualified names from each project's own registry or Docker's official library; tags follow the newest
# release (rolling distributions) or the newest stable or LTS one.
target() {
  official=1
  case "$1" in
    arch)
      image=docker.io/library/archlinux:latest
      setup="pacman -Syu --noconfirm --needed neovim util-linux shadow"
      ;;
    debian | ubuntu)
      image=docker.io/library/$([ "$1" = debian ] && echo debian:stable || echo ubuntu:latest)
      setup="apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends neovim \
        util-linux bsdutils passwd"
      ;;
    fedora)
      image=registry.fedoraproject.org/fedora:latest
      setup="dnf -y install neovim util-linux shadow-utils \
        && { command -v script >/dev/null || dnf -y install util-linux-script; }"
      ;;
    rocky)
      # The Rocky project's own organisation; Neovim is EPEL's, which needs CRB for its libraries.
      image=docker.io/rockylinux/rockylinux:10
      setup="dnf -y install epel-release && dnf -y --enablerepo=crb install neovim util-linux shadow-utils \
        && { command -v script >/dev/null || dnf -y install util-linux-script; }"
      ;;
    opensuse)
      image=registry.opensuse.org/opensuse/tumbleweed:latest
      setup="zypper --non-interactive install neovim util-linux shadow"
      ;;
    void)
      image=ghcr.io/void-linux/void-glibc-full:latest
      setup="xbps-install -Syu xbps && xbps-install -Syu && xbps-install -y neovim util-linux shadow"
      ;;
    nixos)
      # Nix's store has no /lib64 loader for the official build, and the image no useradd: Nixpkgs' Neovim as root.
      image=docker.io/nixos/nix:latest
      setup="nix-channel --update && nix-env -iA nixpkgs.neovim nixpkgs.util-linux nixpkgs.gnused nixpkgs.gawk"
      official=0
      ;;
    gentoo)
      # Gentoo's binary neovim does not resolve with --usepkgonly (slot conflicts and USE mismatches among the
      # binhost's packages, 2026-11-09) and building it takes hours: the official build on Gentoo's own userland.
      image=docker.io/gentoo/stage3:latest
      setup="true"
      ;;
    *) return 1 ;;
  esac
}

[ -n "$names" ] || names=$DEFAULT

for name in $names; do
  target "$name" || {
    echo "unknown distribution: $name (known: $DEFAULT)" >&2
    exit 2
  }
done

RUN=$(date +%Y%m%d-%H%M%S)-$$
LOGS="$STATE/logs/$RUN"
# The lockfile and the layout of a prepared image: a change to either prepares again.
LOCK=$( (sha256sum "$REPO/lazy-lock.json" 2>/dev/null || shasum -a 256 "$REPO/lazy-lock.json") | cut -c1-16)-4
HOST="$STATE/host/$LOCK"
mkdir -p "$LOGS"

case "$(uname -m)" in
  x86_64) asset=nvim-linux-x86_64 sha=474430d53e6264f6d6dd18db42d6dc9df3a1b56ca9e88a325bbf860e1a811d87 ;;
  aarch64 | arm64) asset=nvim-linux-arm64 sha=8f1f64a0bdb97247034038c3823c6cbad5bdf9ecd5751b85494b71c3ee04c815 ;;
  *)
    echo "error: no official Neovim build for $(uname -m)" >&2
    exit 2
    ;;
esac

current=""

# shellcheck disable=SC2329 # the trap calls it
interrupted() {
  [ -z "$current" ] || podman rm -f "$current" >/dev/null 2>&1
  [ "$keep" = 1 ] || remove_kept >/dev/null 2>&1
  exit 130
}

trap interrupted INT TERM

# A container of this name is removed only when it carries this script's label.
remove_ours() {
  ids=$(podman ps -aq --filter "name=^$1\$" --filter "label=$LABEL")
  # shellcheck disable=SC2086 # one id per word
  [ -z "$ids" ] || podman rm -f $ids >/dev/null 2>&1
}

# The official build and the plugins with their parsers, once per lockfile, in a directory of this script.
host_prepare() {
  if [ -x "$HOST/nvim/bin/nvim" ] && [ -f "$HOST/ready" ] && [ "$rebuild" = 0 ]; then
    return 0
  fi

  rm -rf "$HOST" && mkdir -p "$HOST/xdg/config" || return 1
  # Another lockfile's directory is this script's too, and no prepared image will use it again.
  find "$STATE/host" -mindepth 1 -maxdepth 1 ! -name "$LOCK" -exec rm -rf {} +
  url="https://github.com/neovim/neovim/releases/download/v$NV_VERSION/$asset.tar.gz"

  if ! curl -fsSL --proto '=https' --tlsv1.2 -o "$HOST/nvim.tar.gz" "$url"; then
    echo "FAIL [host] could not download $url"
    return 1
  fi

  got=$( (sha256sum "$HOST/nvim.tar.gz" 2>/dev/null || shasum -a 256 "$HOST/nvim.tar.gz") | cut -d' ' -f1)

  if [ "$got" != "$sha" ]; then
    echo "FAIL [host] $asset.tar.gz: SHA-256 $got, GitHub publishes $sha"
    return 1
  fi

  tar -xzf "$HOST/nvim.tar.gz" -C "$HOST" && mv "$HOST/$asset" "$HOST/nvim" && rm -f "$HOST/nvim.tar.gz" || return 1
  # A copy: lazy.nvim rewrites the lockfile of the configuration it runs, and the repository's must stay as it is.
  mkdir -p "$HOST/xdg/config/nvim" && tar -C "$REPO" --exclude=./.git -cf - . | tar -C "$HOST/xdg/config/nvim" -xf - ||
    return 1

  # An isolated Neovim: nothing of the user's own data is read or written.
  (
    export XDG_CONFIG_HOME="$HOST/xdg/config" XDG_DATA_HOME="$HOST/xdg/data" XDG_STATE_HOME="$HOST/xdg/state" \
      XDG_CACHE_HOME="$HOST/xdg/cache"
    unset NVIM_APPNAME XDG_RUNTIME_DIR DISPLAY WAYLAND_DISPLAY
    timeout 1200 "$HOST/nvim/bin/nvim" --headless "+Lazy! restore" +qa </dev/null >"$LOGS/host-plugins.log" 2>&1 || {
      echo "FAIL [host] the plugins did not install (log: $LOGS/host-plugins.log)"
      return 1
    }

    # The restore's parser downloads outlive it (curl, tar): up to a minute to end, then stopped. Only processes
    # naming this host directory match.
    waited=0
    while pgrep -u "$(id -u)" -f "$HOST/xdg" >/dev/null 2>&1 && [ "$waited" -lt 60 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    pkill -u "$(id -u)" -f "$HOST/xdg" 2>/dev/null

    if command -v tree-sitter >/dev/null 2>&1 && { command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1; }; then
      # The configuration lists the parsers; a Neovim without it builds them afresh. The restore above starts
      # LazyVim's own install, which +qa cuts off half-done (ENOTEMPTY). A parser missing from an image makes LazyVim
      # build it there, without a compiler.
      timeout 120 "$HOST/nvim/bin/nvim" --headless -c "lua vim.fn.writefile( \
          LazyVim.dedup(LazyVim.opts('nvim-treesitter').ensure_installed or {}), '$HOST/parsers')" +qa \
        </dev/null >"$LOGS/host-parsers.log" 2>&1 && [ -s "$HOST/parsers" ] || {
        echo "FAIL [host] the configuration's parser list could not be read (log: $LOGS/host-parsers.log)"
        return 1
      }
      rm -rf "$HOST/xdg/cache/nvim" "$HOST/xdg/data/nvim/site"
      timeout 1800 "$HOST/nvim/bin/nvim" --clean --headless --cmd "set rtp^=$HOST/xdg/data/nvim/lazy/nvim-treesitter" \
        -c "lua local ok, err = pcall(function() \
          local TS, want = require('nvim-treesitter'), vim.fn.readfile('$HOST/parsers') \
          TS.install(want):wait(1500000) \
          local missing = vim.tbl_filter(function(l) return not vim.list_contains(TS.get_installed(), l) end, want) \
          assert(#missing == 0, 'missing parsers: ' .. table.concat(missing, ' ')) \
        end) if not ok then io.stderr:write(tostring(err), '\\n') end vim.cmd(ok and 'qa!' or 'cquit 1')" \
        </dev/null >>"$LOGS/host-parsers.log" 2>&1 || {
        echo "FAIL [host] the parsers did not all build (log: $LOGS/host-parsers.log)"
        return 1
      }
      # nvim-treesitter links each language's queries into its checkout by an absolute host path: copied instead.
      queries="$HOST/xdg/data/nvim/site/queries"
      cp -RL "$queries" "$queries.copy" && rm -rf "$queries" && mv "$queries.copy" "$queries" || return 1
    else
      echo "SKIP [host] no tree-sitter CLI or C compiler: the containers start without parsers"
    fi
  ) || return 1

  touch "$HOST/ready"
}

echo "== host: official Neovim $NV_VERSION, plugins and parsers for lazy-lock.json $LOCK"
host_prepare || {
  # The logs go with the rest unless --keep: their ends are shown here.
  for log in "$LOGS"/host-*.log; do
    [ ! -s "$log" ] || { echo "--- $log" && tail -n 20 "$log"; }
  done
  [ "$keep" = 1 ] || remove_kept >/dev/null
  exit 1
}

# shellcheck disable=SC2016 # expanded inside the container
PREPARE='set -u
bounded() {
  limit=$1
  shift
  if command -v timeout >/dev/null 2>&1; then timeout "$limit" "$@"; else "$@"; fi
}
# A mirror caught mid-sync fails an install that works minutes later: up to five tries, pauses doubling from 30 s.
tries=0
pause=30
until bounded 1500 sh -c "$SETUP" >/tmp/setup.log 2>&1; do
  rc=$?
  tries=$((tries + 1))
  if [ "$rc" -eq 124 ] || [ "$tries" -ge 5 ]; then tail -n 40 /tmp/setup.log; echo "FAIL [prepare] could not install"; exit 1; fi
  sleep "$pause"
  pause=$((pause * 2))
done
user=root
home=/root
if command -v useradd >/dev/null 2>&1 && command -v su >/dev/null 2>&1 && useradd -m -s /bin/sh nvimtest; then
  user=nvimtest
  home=/home/nvimtest
fi
# Outside the user'"'"'s home: inside.sh copies them in at each test, into the container'"'"'s own layer, where a reset
# can rename them as on a real system (a directory of a lower overlay layer cannot be renamed: EXDEV).
mkdir -p /opt/nvim-config-test/data && cp -R /prepared/xdg/data/nvim/lazy /opt/nvim-config-test/data/lazy || exit 1
[ ! -d /prepared/xdg/data/nvim/site ] || cp -R /prepared/xdg/data/nvim/site /opt/nvim-config-test/data/site || exit 1
if [ "$OFFICIAL" = 1 ]; then cp -R /prepared/nvim /opt/nvim-official || exit 1; fi
echo "$user $home" >/etc/nvim-config-test-user
echo "prepared: $(nvim --version 2>/dev/null | head -n 1)"'

summary=""
status=0

for name in $names; do
  target "$name"
  log="$LOGS/$name.log"
  prepared="localhost/nvim-config-test/$name:prepared"
  tester="nvim-config-test-$name"
  remove_ours "$tester"

  if [ "$rebuild" = 1 ] || ! image_present "$prepared" ||
    [ "$(podman image inspect -f '{{ index .Config.Labels "org.nvim-config.test.lock" }}' "$prepared" 2>/dev/null)" != "$LOCK" ]; then
    echo "== $name: prepare from $image"
    if ! image_present "$image"; then
      if podman pull "$image" >>"$log" 2>&1; then
        # Recorded at once, so an interrupted run or --clean removes it too.
        echo "$image" >>"$PULLED"
      else
        echo "FAIL [$name] could not pull $image" | tee -a "$log"
        status=1
        continue
      fi
    fi

    current="nvim-config-test-prepare-$name-$$"
    # label=disable: on an SELinux host the container cannot read the mounts otherwise, and relabelling them would
    # change the user's files.
    podman run --name "$current" --label "$LABEL" --security-opt no-new-privileges --security-opt label=disable \
      --pids-limit 4096 --memory "$MEMORY" --memory-swap "$MEMORY" -e SETUP="$setup" -e OFFICIAL="$official" \
      -v "$HOST:/prepared:ro" "$image" sh -c "$PREPARE" \
      >>"$log" 2>&1 || {
      echo "FAIL [$name] prepare (log: $log)"
      tail -n 20 "$log"
      podman rm -f "$current" >/dev/null 2>&1
      current=""
      status=1
      continue
    }
    # The image this tag named before is this script's own; replaced rather than left dangling.
    podman rmi "$prepared" >/dev/null 2>&1
    # The tag moves with each release; the label records the build the image was prepared from.
    base="$image@$(podman image inspect -f '{{.Digest}}' "$image" 2>/dev/null)"
    podman commit --change "LABEL $LABEL" --change "LABEL org.nvim-config.test.lock=$LOCK" \
      --change "LABEL org.nvim-config.test.base=$base" "$current" "$prepared" >>"$log" 2>&1
    podman rm -f "$current" >/dev/null 2>&1
    current=""
  else
    echo "== $name: reuse $prepared"
  fi

  base=$(podman image inspect -f '{{ index .Config.Labels "org.nvim-config.test.base" }}' "$prepared" 2>/dev/null)
  echo "base image: ${base:-unknown (prepared before digests were recorded)}" >>"$log"

  current=$tester
  rm_flag=--rm
  [ "$keep" = 0 ] || rm_flag=""
  # shellcheck disable=SC2086 # rm_flag is empty or one word
  podman run $rm_flag --name "$tester" --label "$LABEL" --label "org.nvim-config.test.run=$RUN" --network none \
    --security-opt no-new-privileges --security-opt label=disable --pids-limit 4096 --memory "$MEMORY" \
    --memory-swap "$MEMORY" -v "$REPO:/cfg:ro" \
    "$prepared" sh /cfg/tests/containers/inside.sh >>"$log" 2>&1
  rc=$?
  current=""

  grep -E '(^| )(FAIL) ' "$log" | head -n 20
  summary="$summary
$(printf '%-9s %s  %s %s' "$name" "$(grep -E '^== [0-9]+ passed' "$log" | tail -n 1)" \
    "$(grep -o 'NVIM v[0-9][0-9.]*' "$log" | sort -u | tr '\n' ' ')" "$(printf '%s' "${base##*sha256:}" | cut -c1-12)")"
  [ "$rc" -eq 0 ] || status=1
done

echo
if [ "$keep" = 0 ]; then
  echo "== summary (podman, run $RUN)$summary"
  remove_kept >/dev/null
  echo "removed: the test containers and images, the official images this script pulled, the host directory and the"
  echo "logs (--keep keeps them for a look)"
else
  echo "== summary (podman, run $RUN; logs in $LOGS)$summary"
  echo "kept (--keep): containers nvim-config-test-<name>, images localhost/nvim-config-test/<name>:prepared, the"
  echo "official images it pulled and $STATE; sh tests/containers/run.sh --clean removes them"
fi
exit "$status"
