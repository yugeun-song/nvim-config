#!/bin/sh
# tests/stored_data_paths/run.sh on desktop Linux distributions, each in a throwaway container from the distribution's
# own official image. Inside, the distribution's package manager installs its own Neovim (verifying signatures as it
# always does), a user is created, and the configuration is copied where a user clones it (~/.config/nvim); run.sh then
# runs as that user, with --release (the official 0.12.2 build, SHA-256 checked) and --installed (that user's real
# layout). The repository is mounted read-only; nothing else from the host is shared.
#
#   tests/stored_data_paths/docker.sh [--engine podman|docker] [DISTRIBUTION...]
#       arch debian ubuntu fedora rocky opensuse void gentoo nixos (default; gentoo takes longest); flatpak
#       (Flathub's io.neovim.nvim in its sandbox: needs --privileged, about 1 GB)
#   tests/stored_data_paths/docker.sh --clean
#       remove the containers this script made, from any run, and only those
#   tests/stored_data_paths/docker.sh --clean-images
#       remove the images this script pulled (none that were there before)
#
# podman is used when present, else docker; --engine (or NVIM_TEST_ENGINE) chooses. With neither, or one that
# does not answer, it stops before doing anything. Every container is named nvim-paths-<run>-<distribution>,
# labelled org.nvim-config.test=paths, and started with --rm.
# Logs: $TMPDIR/nvim-paths-docker/<run>/<distribution>.log
set -u

REPO=$(cd "$(dirname "$0")/../.." && pwd)
STATE="${TMPDIR:-/tmp}/nvim-paths-docker"
LABEL="org.nvim-config.test=paths"
PULLED="$STATE/pulled-images"
DEFAULT="arch debian ubuntu fedora rocky opensuse void gentoo nixos"

engine=${NVIM_TEST_ENGINE:-}
clean=""
names=""

while [ $# -gt 0 ]; do
  case "$1" in
    --engine)
      engine=${2:?--engine needs podman or docker}
      shift
      ;;
    --clean) clean=containers ;;
    --clean-images) clean=images ;;
    -h | --help)
      # The comment block at the top of this file, whatever its length.
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

if [ -z "$engine" ]; then
  if command -v podman >/dev/null 2>&1; then
    engine=podman
  elif command -v docker >/dev/null 2>&1; then
    engine=docker
  fi
fi

case "$engine" in
  podman | docker) command -v "$engine" >/dev/null 2>&1 || {
    echo "error: $engine is not installed" >&2
    exit 2
  } ;;
  "")
    echo "error: neither podman nor docker is installed; install one of them (podman is preferred) and run again" >&2
    exit 2
    ;;
  *)
    echo "error: --engine takes podman or docker, not $engine" >&2
    exit 2
    ;;
esac

# Installed is not enough: docker's daemon may be stopped, rootless podman not set up for this user.
if ! "$engine" info >/dev/null 2>&1; then
  echo "error: $engine is installed but does not answer ($engine info fails); start its service or finish its setup" >&2
  exit 2
fi

mkdir -p "$STATE"

# Only what carries this script's label, so no other container is ever touched.
if [ "$clean" = containers ]; then
  ids=$("$engine" ps -aq --filter "label=$LABEL")
  if [ -n "$ids" ]; then
    # shellcheck disable=SC2086 # one id per word
    "$engine" rm -f $ids
  fi
  echo "removed $(echo "$ids" | grep -c .) container(s) labelled $LABEL"
  exit 0
fi

# Only images recorded as pulled by this script (absent before its run), and only when no container uses them.
if [ "$clean" = images ]; then
  if [ -f "$PULLED" ]; then
    sort -u "$PULLED" | while IFS= read -r image; do
      [ -n "$image" ] || continue
      if [ -n "$("$engine" ps -aq --filter "ancestor=$image")" ]; then
        echo "kept $image: a container still uses it"
        continue
      fi
      "$engine" rmi "$image" >/dev/null 2>&1 && echo "removed $image"
    done
    : >"$PULLED"
  fi
  exit 0
fi

# Fully qualified, each from the registry its distribution publishes to: a short name would let podman guess.
# Sets image, setup (run in the container as root), args (run.sh's) and opts (extra container options); each is a
# variable of its own, so a setup may hold any shell text, || and | included.
target() {
  args="--release --installed" opts=""
  case "$1" in
    arch)
      image=docker.io/library/archlinux:latest
      setup="pacman -Syu --noconfirm --needed neovim util-linux shadow curl tar gzip"
      ;;
    debian | ubuntu)
      image=docker.io/library/$([ "$1" = debian ] && echo debian:stable || echo ubuntu:latest)
      setup="apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends neovim \
        util-linux bsdutils passwd ca-certificates curl tar gzip"
      ;;
    fedora)
      image=registry.fedoraproject.org/fedora:latest
      # --allowerasing: the image's curl-minimal yields to curl instead of failing the install as a conflict.
      setup="dnf -y install --allowerasing neovim util-linux shadow-utils curl tar gzip \
        && { command -v script >/dev/null || dnf -y install util-linux-script; }"
      ;;
    rocky)
      # The Rocky project's own image (Docker Hub's library/rockylinux stopped at 9). Neovim is EPEL's, which needs
      # CRB for its libraries; epel-release comes from Rocky's extras repository.
      image=docker.io/rockylinux/rockylinux:10
      setup="dnf -y install epel-release \
        && dnf -y --enablerepo=crb install --allowerasing neovim util-linux shadow-utils curl tar gzip \
        && { command -v script >/dev/null || dnf -y install util-linux-script; }"
      ;;
    opensuse)
      image=registry.opensuse.org/opensuse/tumbleweed:latest
      setup="zypper --non-interactive install neovim util-linux shadow curl tar gzip"
      ;;
    void)
      image=ghcr.io/void-linux/void-glibc-full:latest
      setup="xbps-install -Syu xbps && xbps-install -Syu && xbps-install -y neovim util-linux shadow curl tar gzip"
      ;;
    nixos)
      # Nix's store has no /lib64 loader for the official build, and the image no useradd: Nixpkgs' Neovim, as root.
      image=docker.io/nixos/nix:latest
      setup="nix-channel --update && nix-env -iA nixpkgs.neovim nixpkgs.util-linux"
      args="--installed"
      ;;
    gentoo)
      image=docker.io/gentoo/stage3:latest
      setup="emerge-webrsync && getuto && emerge --getbinpkg --usepkgonly app-editors/neovim"
      ;;
    flatpak)
      image=registry.fedoraproject.org/fedora:latest
      setup="dnf -y install flatpak util-linux \
        && flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo \
        && flatpak install -y --noninteractive flathub io.neovim.nvim"
      args="--flatpak io.neovim.nvim" opts="--privileged"
      ;;
    *) return 1 ;;
  esac
}

image_present() {
  "$engine" image inspect "$1" >/dev/null 2>&1
}

RUN=$(date +%Y%m%d-%H%M%S)-$$
LOGS="$STATE/$RUN"
mkdir -p "$LOGS"

current=""
trap '[ -n "$current" ] && "$engine" rm -f "$current" >/dev/null 2>&1; exit 130' INT TERM

# Inside each container: install, add a user, put the configuration where it is installed, run as that user.
# A setup failure prints its log's tail and ends the container with 1. Expanded in the container, not here.
# shellcheck disable=SC2016
INNER='set -u
# Bounded where the image has timeout(1): a hung mirror or key server ends as a FAIL with its log, not at the CI
# job time limit with nothing to show.
bounded() {
  limit=$1
  shift
  if command -v timeout >/dev/null 2>&1; then timeout "$limit" "$@"; else "$@"; fi
}
# Five tries, the pauses doubling from half a minute: a mirror caught mid-sync fails an install that works minutes
# later. A try that hangs for 25 minutes is not repeated.
tries=0
pause=30
until bounded 1500 sh -c "$SETUP" >/tmp/setup.log 2>&1; do
  rc=$?
  tries=$((tries + 1))
  if [ "$rc" -eq 124 ]; then tail -n 40 /tmp/setup.log; echo "FAIL [setup] no answer for 25 minutes"; exit 1; fi
  [ "$tries" -lt 5 ] || { tail -n 40 /tmp/setup.log; echo "FAIL [setup] could not install"; exit 1; }
  sleep "$pause"
  pause=$((pause * 2))
done
user=root
home=/root
if command -v useradd >/dev/null 2>&1 && command -v su >/dev/null 2>&1 && useradd -m -s /bin/sh nvimtest; then
  user=nvimtest
  home=/home/nvimtest
fi
mkdir -p "$home/.config" && cp -R /cfg "$home/.config/nvim" && chown -R "$user" "$home/.config" || exit 1
nv=$(command -v nvim || true)
cmd="NVIM_PATHS_THROWAWAY_CONTAINER=1 sh $home/.config/nvim/tests/stored_data_paths/run.sh $ARGS $nv"
if [ "$user" = root ]; then bounded 1200 sh -c "$cmd"; else bounded 1200 su -s /bin/sh "$user" -c "$cmd"; fi
rc=$?
[ "$rc" -ne 124 ] || echo "FAIL [run] no answer for 20 minutes"
exit "$rc"'

summary=""
status=0

[ -n "$names" ] || names=$DEFAULT

for name in $names; do
  target "$name" || {
    echo "unknown distribution: $name (known: $DEFAULT flatpak)" >&2
    status=2
    continue
  }

  log="$LOGS/$name.log"
  current="nvim-paths-$RUN-$name"

  image_present "$image" || echo "$image" >>"$PULLED"
  echo "== $name ($image) as $current"

  # label=disable: on an SELinux host (Fedora, RHEL) the container cannot read the repository's mount otherwise, and
  # relabelling it (:z) would change the user's checkout.
  # shellcheck disable=SC2086 # opts is a word list on purpose
  "$engine" run --rm --name "$current" --label "$LABEL" --label "org.nvim-config.run=$RUN" \
    --pull=missing --security-opt no-new-privileges --security-opt label=disable --pids-limit 4096 $opts \
    -e SETUP="$setup" -e ARGS="$args" -v "$REPO:/cfg:ro" "$image" sh -c "$INNER" >"$log" 2>&1
  rc=$?
  current=""

  versions=$(grep -o 'NVIM v[^,]*' "$log" | sort -u | tr '\n' ' ')
  summary="$summary
$(printf '%-10s %s  %s' "$name" "$(tail -n 1 "$log")" "$versions")"

  grep -E '(^| )FAIL ' "$log" | head -n 20
  [ "$rc" -eq 0 ] || status=1
done

echo
echo "== summary ($engine; logs in $LOGS)$summary"
echo "Containers ran with --rm; tests/stored_data_paths/docker.sh --clean removes any left by an interrupted run,"
echo "--clean-images the images this script pulled."
exit "$status"
