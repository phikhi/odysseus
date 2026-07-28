# shellcheck shell=bash
# Assertions shared by the suite. Deliberately small and dependency-free:
# bats-assert is a separate install and the pack must test itself with nothing
# but bash. Every failure prints what it saw, because the process seam gives
# no stack trace.

fail() {
  printf '%s\n' "$*" >&2
  return 1
}

assert_success() {
  if [ "$status" -ne 0 ]; then
    fail "expected success, got exit $status
--- output ---
$output"
  fi
}

assert_failure() {
  local expected="${1:-}"
  if [ -n "$expected" ]; then
    if [ "$status" -ne "$expected" ]; then
      fail "expected exit $expected, got $status
--- output ---
$output"
    fi
  elif [ "$status" -eq 0 ]; then
    fail "expected failure, got exit 0
--- output ---
$output"
  fi
}

assert_output_contains() {
  case "$output" in
    *"$1"*) ;;
    *) fail "expected output to contain: $1
--- output ---
$output" ;;
  esac
}

refute_output_contains() {
  case "$output" in
    *"$1"*) fail "expected output NOT to contain: $1
--- output ---
$output" ;;
  esac
}

assert_equal() {
  if [ "$1" != "$2" ]; then
    fail "expected: $2
     actual: $1"
  fi
}

assert_file_exists() {
  [ -f "$1" ] || fail "expected file to exist: $1"
}

refute_file_exists() {
  [ ! -f "$1" ] || fail "expected file NOT to exist: $1"
}

assert_file_contains() {
  local file="$1" needle="$2"
  assert_file_exists "$file"
  if ! grep -qF -- "$needle" "$file"; then
    fail "expected $file to contain: $needle
--- file ---
$(cat "$file")"
  fi
}

# A missing file is not the absence of the needle: it is a test asserting on
# something that is not there, which would pass for the wrong reason.
refute_file_contains() {
  local file="$1" needle="$2"
  assert_file_exists "$file"
  if grep -qF -- "$needle" "$file"; then
    fail "expected $file NOT to contain: $needle
--- file ---
$(cat "$file")"
  fi
}

# The tracker is the observation point of the process seam, so ticket state
# gets a first-class assertion.
assert_ticket_status() {
  local ticket="$1" expected="$2" file actual
  file="$(ticket_file "$ticket")"
  assert_file_exists "$file"
  actual="$(ticket_status "$ticket")"
  if [ "$actual" != "$expected" ]; then
    fail "ticket $ticket: expected status '$expected', got '$actual'
--- $file ---
$(cat "$file")"
  fi
}
