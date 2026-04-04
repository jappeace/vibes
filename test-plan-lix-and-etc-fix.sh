#!/bin/sh
# Test plan: Verify Lix 2.94.0 upgrade + /etc config file fix
# Run this after merging both PRs and rebuilding the container:
#   - linux-config PR #10: Upgrade Lix to 2.94.0
#   - haskell-vibes PR #13: Fix /etc config files from GC
#
# Usage: run this script inside a freshly rebuilt container
# Expected: all checks pass

FAILED=0

check() {
  DESC="$1"
  shift
  if "$@" > /dev/null 2>&1; then
    echo "PASS: $DESC"
  else
    echo "FAIL: $DESC"
    FAILED=$((FAILED + 1))
  fi
}

check_contains() {
  DESC="$1"
  FILE="$2"
  PATTERN="$3"
  if grep -q "$PATTERN" "$FILE" 2>/dev/null; then
    echo "PASS: $DESC"
  else
    echo "FAIL: $DESC (pattern '$PATTERN' not found in $FILE)"
    FAILED=$((FAILED + 1))
  fi
}

echo "=== 1. /etc config files are real files (not broken symlinks) ==="
check "/etc/nix/nix.conf is readable"        test -f /etc/nix/nix.conf
check "/etc/nix/builder-ssh-config readable"  test -f /etc/nix/builder-ssh-config
check "/etc/group is readable"                test -f /etc/group
check "/etc/nsswitch.conf is readable"        test -f /etc/nsswitch.conf
check "/etc/passwd is readable"               test -f /etc/passwd
check "/etc/gitconfig is readable"            test -f /etc/gitconfig

echo ""
echo "=== 2. /etc config file contents are correct ==="
check_contains "nix.conf has trusted-users"     /etc/nix/nix.conf       "trusted-users = root claude"
check_contains "nix.conf has ssh-ng builder"    /etc/nix/nix.conf       "ssh-ng://nix-builder@host.docker.internal"
check_contains "nix.conf has max-jobs = 0"      /etc/nix/nix.conf       "max-jobs = 0"
check_contains "group has nixbld"               /etc/group              "nixbld:x:30000"
check_contains "passwd has claude"              /etc/passwd             "claude"
check_contains "passwd has nixbld users"        /etc/passwd             "nixbld1"
check_contains "nsswitch has passwd: files"     /etc/nsswitch.conf      "passwd:"
check_contains "gitconfig has user"             /etc/gitconfig          "jappeace-sloth"

echo ""
echo "=== 3. Lix version matches ==="
VERSION=$(nix --version 2>&1)
echo "Nix version: $VERSION"
check "Lix 2.94.0 is installed" echo "$VERSION" | grep -q "2.94.0"

echo ""
echo "=== 4. Nix daemon is functional ==="
check "nix-daemon socket exists"   test -S /nix/var/nix/daemon-socket/socket
check "nix-store --version works"  nix-store --version

echo ""
echo "=== 5. Remote builder connectivity (ssh-ng) ==="
# This tests the actual protocol compatibility fix
echo "Attempting a trivial nix-build to test remote builder..."
if nix-build --no-link --expr 'derivation { name = "hello"; system = "x86_64-linux"; builder = "/bin/sh"; args = ["-c" "echo hello > $out"]; }' --timeout 30 > /dev/null 2>&1; then
  echo "PASS: nix-build via remote builder succeeded"
else
  echo "FAIL: nix-build via remote builder failed (check daemon logs: /var/log/nix-daemon.log)"
  FAILED=$((FAILED + 1))
fi

echo ""
echo "=== 6. Git works ==="
check "git config user.name is set" git config user.name

echo ""
echo "================================"
if [ "$FAILED" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "$FAILED CHECK(S) FAILED"
fi
exit "$FAILED"
