#!/bin/sh
# Inside a prepared container of tests/containers/run.sh, without network: the configuration from the read-only
# mount /cfg is copied where a user clones it, then each Neovim of the image starts it (startup_check.lua) and
# tests/managed_paths/run.sh checks the paths in the user's real layout and every variant.
set -u

read -r user home </etc/nvim-config-test-user || {
  echo "FAIL [inside] not a prepared container (no /etc/nvim-config-test-user)"
  exit 2
}

# Removed rather than reused: a directory the image made (nvim --version as root on NixOS) sits in a lower overlay
# layer, where a reset cannot rename it (EXDEV).
rm -rf "$home/.config/nvim" "$home/.local/share/nvim" "$home/.local/state/nvim" "$home/.cache/nvim" &&
  mkdir -p "$home/.config" "$home/.local/share/nvim" &&
  cp -R /cfg "$home/.config/nvim" && cp -R /opt/nvim-config-test/data/. "$home/.local/share/nvim/" || exit 2
mkdir -p "$home/samples/src" "$home/samples/arch" "$home/samples/.git"
printf '#include "foo.h"\nint main(void)\n{\n\treturn FOO;\n}\n' >"$home/samples/src/main.c"
printf '#define FOO 1\n' >"$home/samples/src/foo.h"
printf '\t.globl entry\nentry:\n\tret\n' >"$home/samples/arch/entry.S"
printf -- '-Isrc\n' >"$home/samples/compile_flags.txt"
printf 'print(1)\n' >"$home/samples/a.py"
printf '# Title\n\ntext\n' >"$home/samples/a.md"
printf 'local x = 1\nreturn x\n' >"$home/samples/a.lua"
chown -R "$user" "$home" 2>/dev/null

as_user() {
  if [ "$user" = root ]; then sh -c "$1"; else su -s /bin/sh "$user" -c "$1"; fi
}

nvims=""
for nvim in $(command -v nvim 2>/dev/null) /opt/nvim-official/bin/nvim; do
  [ -x "$nvim" ] && nvims="$nvims $nvim"
done

check="$home/.config/nvim/tests/containers/startup_check.lua"
files="$home/samples/src/main.c:$home/samples/arch/entry.S:$home/samples/a.py:$home/samples/a.md:$home/samples/a.lua"

{
  for nvim in $nvims; do
    version=$("$nvim" --version 2>/dev/null | head -n 1)
    echo "== startup: $nvim ($version)"

    if "$nvim" --headless --clean -c "lua os.exit(vim.fn.has('nvim-0.11.2') == 1 and 0 or 3)" </dev/null >/dev/null 2>&1; then
      # The check prints its own PASS and FAIL lines and exits 0; any other exit is a crash or a hang.
      as_user "cd '$home/samples' && STARTUP_FILES='$files' timeout 300 '$nvim' --headless -i NONE \
        -c 'luafile $check' </dev/null 2>&1; rc=\$?; [ \$rc -eq 0 ] || echo \"FAIL [startup] Neovim ended with code \$rc\""
    else
      # LazyVim refuses Neovim before 0.11.2 and waits for a key; one is given so the refusal can end.
      out=$(as_user "cd '$home/samples' && printf ' ' | timeout 60 '$nvim' --headless 2>&1")
      if printf '%s' "$out" | grep -q "LazyVim requires Neovim"; then
        echo "PASS [refusal] $version is refused with LazyVim's own message"
      else
        echo "FAIL [refusal] $version is not refused cleanly: $(printf '%s' "$out" | tr '\n' ' ' | cut -c1-300)"
      fi
    fi
  done

  as_user "NVIM_PATHS_THROWAWAY_CONTAINER=1 sh '$home/.config/nvim/tests/managed_paths/run.sh' --installed $nvims"
} 2>&1 | tee /tmp/inside.log

passed=$(grep -cE '(^| )PASS ' /tmp/inside.log)
failed=$(grep -cE '(^| )FAIL ' /tmp/inside.log)
skipped=$(grep -cE '(^| )SKIP ' /tmp/inside.log)
echo "== $passed passed, $failed failed, $skipped skipped"
[ "$failed" -eq 0 ] && [ "$passed" -gt 0 ]
