#!/usr/bin/env bash
# shellcheck shell=bash
# tests/lib/stub_codex.sh — factory for the fake `codex` binaries the test suites
# drop on PATH. One place encodes the fragile invariant that a codex stub MUST
# drain stdin (`cat >/dev/null`) or the wrapper's prompt pipe deadlocks the whole
# run — a stale inline copy of that used to hang the suite with no pointer.
#
# make_stub_codex DEST MODE [CAPTURE_DIR]
#   DEST         path of the stub executable to write (chmod +x is applied)
#   MODE
#     ok        print MOCK_CODEX_OK, drain stdin
#     version   `--version` prints a stub version, otherwise drain stdin
#     slow      sleep far longer than any test timeout (watchdog bait)
#     cloud     `login status` = not-logged-in; `login --with-api-key` and `exec`
#               capture their inputs under CAPTURE_DIR (login-key.txt /
#               exec-args.txt / brief.txt) and `exec` echoes MOCK_CODEX_DONE
#   CAPTURE_DIR  required for MODE=cloud
make_stub_codex() {
  local dest="$1" mode="$2" cap="${3:-}"
  case "$mode" in
    ok)
      cat > "$dest" <<'STUB'
#!/usr/bin/env bash
echo "MOCK_CODEX_OK"
cat >/dev/null
STUB
      ;;
    version)
      cat > "$dest" <<'STUB'
#!/usr/bin/env bash
case "${1:-}" in --version) echo "codex 0.0.0-stub" ;; *) cat >/dev/null ;; esac
STUB
      ;;
    slow)
      cat > "$dest" <<'STUB'
#!/usr/bin/env bash
sleep 30
STUB
      ;;
    cloud)
      [ -n "$cap" ] || { echo "make_stub_codex: cloud mode needs CAPTURE_DIR" >&2; return 2; }
      # Only $cap expands; everything else stays literal ($1, $2, $* are the stub's).
      cat > "$dest" <<STUB
#!/usr/bin/env bash
case "\$1" in
  --version) echo "codex-cli 0.0.0-stub" ;;
  login)
    case "\${2:-}" in
      status) exit 1 ;;
      --with-api-key) cat > "$cap/login-key.txt" ;;
    esac ;;
  exec)
    printf '%s\n' "\$*" > "$cap/exec-args.txt"
    cat > "$cap/brief.txt"
    echo "MOCK_CODEX_DONE" ;;
  *) cat >/dev/null ;;
esac
STUB
      ;;
    *) echo "make_stub_codex: unknown mode '$mode'" >&2; return 2 ;;
  esac
  chmod +x "$dest"
}
