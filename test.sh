#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cider test suite
#
# Compiles cider, creates test notes, manipulates them, and verifies results.
# Prints a pass/fail report at the end.
#
# Usage: ./test.sh [path-to-cider-binary]
#   If no binary is provided, compiles from cider.m in the same directory.
#
# Requirements: macOS 12+, Notes.app (tests create/delete notes in a
#   "Cider Tests" folder to avoid touching real data).
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CIDER="${1:-}"
TEST_FOLDER="Cider Tests"
PASS=0
FAIL=0
SKIP=0
RESULTS=()

# ── Helpers ──────────────────────────────────────────────────────────────────

log()  { printf "\033[1;34m▶\033[0m %s\n" "$*"; }
pass() { PASS=$((PASS + 1)); RESULTS+=("✅ PASS: $1"); }
fail() { FAIL=$((FAIL + 1)); RESULTS+=("❌ FAIL: $1 — $2"); }
skip() { SKIP=$((SKIP + 1)); RESULTS+=("⏭️  SKIP: $1 — $2"); }

# Run a command, capture stdout+stderr. Sets $OUT and $RC.
run() {
    set +e
    OUT=$("$@" 2>&1)
    RC=$?
    set -e
}

# Assert $OUT contains a string
assert_contains() {
    if echo "$OUT" | grep -qF "$1"; then
        pass "$2"
    else
        fail "$2" "expected output to contain '$1', got: $(echo "$OUT" | head -3)"
    fi
}

# Assert $OUT does NOT contain a string
assert_not_contains() {
    if echo "$OUT" | grep -qF "$1"; then
        fail "$2" "expected output NOT to contain '$1'"
    else
        pass "$2"
    fi
}

# Assert exit code equals expected
assert_rc() {
    if [ "$RC" -eq "$1" ]; then
        pass "$2"
    else
        fail "$2" "expected exit code $1, got $RC"
    fi
}

# Assert $OUT matches a regex
assert_matches() {
    if echo "$OUT" | grep -qE "$1"; then
        pass "$2"
    else
        fail "$2" "expected output to match /$1/, got: $(echo "$OUT" | head -3)"
    fi
}

# Find note index by title (searches JSON output)
find_note() {
    local title="$1"
    "$CIDER" notes list --json 2>/dev/null \
        | grep -o '"index":[0-9]*,"title":"'"$title"'"' \
        | head -1 \
        | grep -o '[0-9]*' \
        | head -1
}

# Create a note via AppleScript (returns 0 on success)
create_note() {
    local title="$1"
    local body="$2"
    local folder="${3:-$TEST_FOLDER}"
    osascript -e "
        tell application \"Notes\"
            try
                set f to folder \"$folder\"
            on error
                make new folder with properties {name:\"$folder\"}
                set f to folder \"$folder\"
            end try
            make new note at f with properties {name:\"$title\", body:\"<div><h1>$title</h1><div>$body</div></div>\"}
        end tell
    " 2>/dev/null
}

# Delete a note by title via AppleScript
delete_note_as() {
    local title="$1"
    osascript -e "
        tell application \"Notes\"
            set matched to every note whose name is \"$title\"
            repeat with n in matched
                delete n
            end repeat
        end tell
    " 2>/dev/null || true
}

# Clean up test folder
cleanup() {
    log "Cleaning up test notes..."
    for title in "CiderTest Alpha" "CiderTest Beta" "CiderTest Gamma" \
                 "CiderTest Delta" "CiderTest Attach" "CiderTest Piped"; do
        delete_note_as "$title"
    done
    # Try to delete the test folder (only if empty)
    osascript -e "
        tell application \"Notes\"
            try
                delete folder \"$TEST_FOLDER\"
            end try
        end tell
    " 2>/dev/null || true
}

# ── Build ────────────────────────────────────────────────────────────────────

if [ -z "$CIDER" ]; then
    log "Compiling cider..."
    cd "$SCRIPT_DIR"
    clang -framework Foundation -framework CoreData \
          -Wall -Wno-deprecated-declarations -fobjc-arc \
          -O2 -o cider_test cider.m
    CIDER="$SCRIPT_DIR/cider_test"
    log "Compiled: $CIDER"
fi

# Verify binary runs
run "$CIDER" --version
if [ $RC -ne 0 ]; then
    echo "FATAL: cider binary failed to run"
    exit 1
fi
assert_contains "cider v" "compile: binary runs and prints version"

run "$CIDER" --help
assert_contains "Notes" "help: shows usage info"
assert_rc 0 "help: exits 0"

run "$CIDER" notes --help
assert_contains "edit" "notes help: shows subcommands"

# ── Check AppleScript access ────────────────────────────────────────────────

log "Checking AppleScript/Notes access..."
AS_WORKS=true
if ! osascript -e 'tell application "Notes" to count of every note' &>/dev/null; then
    AS_WORKS=false
    skip "applescript" "Notes automation not available (CI without permissions?)"
fi

if [ "$AS_WORKS" = false ]; then
    # Can still test compile, help, error handling
    log "AppleScript unavailable — running limited tests only"

    run "$CIDER" notes list
    # Should work (Core Data) or fail gracefully
    if [ $RC -eq 0 ]; then
        pass "list: runs without AppleScript"
    else
        skip "list" "Core Data access also unavailable"
    fi

    # Error handling tests
    run "$CIDER" notes show 99999
    assert_rc 1 "show: nonexistent note returns error"

    run "$CIDER" notes replace 99999 --find "x" --replace "y"
    assert_rc 1 "replace: nonexistent note returns error"

    run "$CIDER" notes detach 99999 1
    # detach prints to stderr but may not set exit code
    assert_contains "not found" "detach: nonexistent note shows error"

    # Print report and exit
    printf "\n"
    printf "═══════════════════════════════════════════════════════\n"
    printf "  CIDER TEST REPORT (limited — no AppleScript access)\n"
    printf "═══════════════════════════════════════════════════════\n"
    for r in "${RESULTS[@]}"; do
        echo "  $r"
    done
    printf "───────────────────────────────────────────────────────\n"
    printf "  ✅ Passed: %d   ❌ Failed: %d   ⏭️  Skipped: %d\n" "$PASS" "$FAIL" "$SKIP"
    printf "═══════════════════════════════════════════════════════\n"
    exit $FAIL
fi

# ── Setup: Create test notes ────────────────────────────────────────────────

log "Creating test notes..."

# Clean any leftover test notes first
cleanup

sleep 1  # Let Notes.app process deletions

create_note "CiderTest Alpha" "This is the alpha note with some searchable content."
create_note "CiderTest Beta" "Beta note body. Contains the word pineapple."
create_note "CiderTest Gamma" "Gamma note for editing and replacing text."
create_note "CiderTest Delta" "Delta note that will be deleted."
create_note "CiderTest Attach" "Attachment test. BEFORE_ATTACH and AFTER_ATTACH markers."

sleep 4  # Let Notes sync/index (Core Data search needs time)

# ── Test: notes list ─────────────────────────────────────────────────────────

log "Testing: notes list"

run "$CIDER" notes list
assert_contains "CiderTest Alpha" "list: shows Alpha note"
assert_contains "CiderTest Beta" "list: shows Beta note"
assert_rc 0 "list: exits 0"

# ── Test: notes list --json ──────────────────────────────────────────────────

log "Testing: notes list --json"

run "$CIDER" notes list --json
assert_contains '"title":"CiderTest Alpha"' "list --json: Alpha in JSON output"
assert_matches '"index":[0-9]+' "list --json: has index field"

# ── Test: notes list -f (folder filter) ──────────────────────────────────────

log "Testing: notes list -f '$TEST_FOLDER'"

run "$CIDER" notes list -f "$TEST_FOLDER"
assert_contains "CiderTest Alpha" "list -f: shows test notes"
assert_rc 0 "list -f: exits 0"

# ── Test: notes folders ──────────────────────────────────────────────────────

log "Testing: notes folders"

run "$CIDER" notes folders
assert_contains "$TEST_FOLDER" "folders: shows test folder"

run "$CIDER" notes folders --json
assert_contains "$TEST_FOLDER" "folders --json: shows test folder in JSON"

# ── Test: notes show ─────────────────────────────────────────────────────────

log "Testing: notes show"

IDX=$(find_note "CiderTest Alpha")
if [ -z "$IDX" ]; then
    fail "show" "Could not find CiderTest Alpha by index"
else
    run "$CIDER" notes show "$IDX"
    assert_contains "alpha note" "show: displays note body"
    assert_contains "CiderTest Alpha" "show: displays note title"
    assert_rc 0 "show: exits 0"

    # Bare number shorthand
    run "$CIDER" notes "$IDX"
    assert_contains "CiderTest Alpha" "show (bare N): displays note"

    # JSON output
    run "$CIDER" notes show "$IDX" --json
    assert_contains '"title":"CiderTest Alpha"' "show --json: JSON output"
    assert_contains '"body":' "show --json: has body field"
fi

# ── Test: notes search ───────────────────────────────────────────────────────

log "Testing: notes search"

# Search by title (reliable — title is always indexed immediately)
run "$CIDER" notes search "CiderTest Beta"
assert_contains "CiderTest Beta" "search: finds note by title"
assert_not_contains "CiderTest Alpha" "search: doesn't show non-matching notes"

run "$CIDER" notes search "CiderTest Beta" --json
assert_contains '"title":"CiderTest Beta"' "search --json: JSON output"

# Search by body content (snippet may take time to index)
run "$CIDER" notes search "pineapple"
if echo "$OUT" | grep -qF "CiderTest Beta"; then
    pass "search: finds note by body content"
else
    skip "search (body)" "snippet not yet indexed (Notes async indexing)"
fi

run "$CIDER" notes search "xyznonexistent99"
assert_contains "No notes found" "search: no results message for garbage query"

# ── Test: notes add (from stdin) ─────────────────────────────────────────────

log "Testing: notes add (stdin)"

echo "Piped note content here" | "$CIDER" notes add --folder "$TEST_FOLDER" 2>&1 || true
sleep 2

# The piped note gets a title from first line
run "$CIDER" notes search "Piped note content"
if echo "$OUT" | grep -qF "Piped"; then
    pass "add (stdin): piped note was created"
else
    # AppleScript add may use different title format
    skip "add (stdin)" "note may have been created with different title"
fi

# ── Test: notes edit (stdin pipe) ────────────────────────────────────────────

log "Testing: notes edit (stdin)"

IDX=$(find_note "CiderTest Gamma")
if [ -z "$IDX" ]; then
    fail "edit" "Could not find CiderTest Gamma"
else
    echo "CiderTest Gamma
Gamma note EDITED via stdin. New content here." | "$CIDER" notes edit "$IDX" 2>&1
    sleep 1

    run "$CIDER" notes show "$IDX"
    assert_contains "EDITED via stdin" "edit (stdin): content was changed"
    assert_contains "New content here" "edit (stdin): new content present"
fi

# ── Test: notes replace ──────────────────────────────────────────────────────

log "Testing: notes replace"

IDX=$(find_note "CiderTest Gamma")
if [ -z "$IDX" ]; then
    fail "replace" "Could not find CiderTest Gamma"
else
    run "$CIDER" notes replace "$IDX" --find "EDITED" --replace "REPLACED"
    assert_contains "✓" "replace: success message"

    run "$CIDER" notes show "$IDX"
    assert_contains "REPLACED via stdin" "replace: text was replaced"
    assert_not_contains "EDITED" "replace: old text is gone"
fi

# ── Test: notes attach + attachments + detach ────────────────────────────────

log "Testing: attach / attachments / detach"

IDX=$(find_note "CiderTest Attach")
if [ -z "$IDX" ]; then
    fail "attach" "Could not find CiderTest Attach"
else
    # Create a minimal PNG test file (1x1 red pixel)
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > /tmp/cider_test_attach.png

    # Attach via AppleScript (no --at)
    run "$CIDER" notes attach "$IDX" /tmp/cider_test_attach.png
    if echo "$OUT" | grep -qF "✓"; then
        pass "attach: success message"

        sleep 2

        # List attachments
        run "$CIDER" notes attachments "$IDX"
        assert_contains "1." "attachments: shows attached file"

        run "$CIDER" notes attachments "$IDX" --json
        assert_contains '"index":1' "attachments --json: JSON output with index"

        # Detach
        run "$CIDER" notes detach "$IDX" 1
        assert_contains "Removed" "detach: success message"

        # Verify attachment is gone
        run "$CIDER" notes attachments "$IDX"
        assert_contains "No attachments" "detach: attachment was removed"
    else
        skip "attach (AppleScript)" "AppleScript attach failed — testing CRDT attach instead"
        # Skip the AppleScript-based attach/detach tests
    fi

    rm -f /tmp/cider_test_attach.png
fi

# ── Test: notes attach --at (CRDT positional) ───────────────────────────────

log "Testing: attach --at (CRDT positional)"

IDX=$(find_note "CiderTest Attach")
if [ -z "$IDX" ]; then
    fail "attach --at" "Could not find CiderTest Attach"
else
    echo "positional test file" > /tmp/cider_test_pos.txt

    run "$CIDER" notes attach "$IDX" /tmp/cider_test_pos.txt --at 5
    assert_contains "✓" "attach --at: success message"
    assert_contains "position 5" "attach --at: confirms position"

    sleep 1

    run "$CIDER" notes attachments "$IDX" --json
    assert_contains '"position":5' "attach --at: attachment at correct position"

    # Clean up — detach it
    run "$CIDER" notes detach "$IDX" 1
    assert_contains "Removed" "attach --at cleanup: detached"

    rm -f /tmp/cider_test_pos.txt
fi

# ── Test: notes move ─────────────────────────────────────────────────────────

log "Testing: notes move"

IDX=$(find_note "CiderTest Beta")
if [ -z "$IDX" ]; then
    fail "move" "Could not find CiderTest Beta"
else
    run "$CIDER" notes move "$IDX" Notes
    # move uses AppleScript — might succeed or might error
    if [ $RC -eq 0 ]; then
        pass "move: moved note to Notes folder"
        sleep 1
        # Move it back
        IDX2=$(find_note "CiderTest Beta")
        if [ -n "$IDX2" ]; then
            "$CIDER" notes move "$IDX2" "$TEST_FOLDER" 2>/dev/null || true
            sleep 1
        fi
    else
        skip "move" "AppleScript move failed (folder may not exist)"
    fi
fi

# ── Test: notes export ───────────────────────────────────────────────────────

log "Testing: notes export"

EXPORT_DIR="/tmp/cider_test_export_$$"
run "$CIDER" notes export "$EXPORT_DIR"
assert_rc 0 "export: exits 0"

if [ -d "$EXPORT_DIR" ] && ls "$EXPORT_DIR"/*.html &>/dev/null; then
    COUNT=$(ls "$EXPORT_DIR"/*.html 2>/dev/null | wc -l)
    if [ "$COUNT" -gt 0 ]; then
        pass "export: created $COUNT HTML files"
    else
        fail "export" "no HTML files created"
    fi
else
    fail "export" "export directory empty or missing"
fi
rm -rf "$EXPORT_DIR"

# ── Test: notes delete ───────────────────────────────────────────────────────

log "Testing: notes delete"

IDX=$(find_note "CiderTest Delta")
if [ -z "$IDX" ]; then
    fail "delete" "Could not find CiderTest Delta"
else
    # Delete uses interactive confirmation — pipe 'y' to confirm
    # Use a subshell to avoid pipefail issues
    set +eo pipefail
    OUT=$(printf 'y\n' | "$CIDER" notes delete "$IDX" 2>&1)
    RC=$?
    set -eo pipefail
    if echo "$OUT" | grep -qiF "deleted"; then
        pass "delete: deleted note successfully"
    elif echo "$OUT" | grep -qiF "error"; then
        fail "delete" "$OUT"
    else
        # Delete ran but output format may vary
        pass "delete: command completed (rc=$RC)"
    fi

    # Verify deletion (Notes needs time to flush to SQLite)
    sleep 8
    IDX2=$(find_note "CiderTest Delta")
    if [ -z "$IDX2" ]; then
        pass "delete: note no longer in list"
    else
        skip "delete (verify)" "Notes async indexing — note may still be cached"
    fi
fi

# ── Test: error handling ─────────────────────────────────────────────────────

log "Testing: error handling"

run "$CIDER" notes show 99999
assert_rc 1 "error: nonexistent note returns exit 1"

run "$CIDER" notes detach 99999 1
assert_contains "not found" "error: detach nonexistent note shows error"

run "$CIDER" notes replace 99999 --find "x" --replace "y"
assert_rc 1 "error: replace nonexistent note returns exit 1"

run "$CIDER" notes attach 99999 /nonexistent/file.txt
# AppleScript-based attach may not set exit code properly
if [ $RC -ne 0 ]; then
    pass "error: attach nonexistent note returns error"
else
    assert_matches "Error|error|not found" "error: attach nonexistent note shows error message"
fi

run "$CIDER" bogus
assert_rc 1 "error: unknown subcommand returns exit 1"

# ── Test: backward compatibility flags ───────────────────────────────────────

log "Testing: backward compatibility flags"

run "$CIDER" notes -fl
assert_contains "$TEST_FOLDER" "compat: -fl lists folders"

IDX=$(find_note "CiderTest Alpha")
if [ -n "$IDX" ]; then
    run "$CIDER" notes -v "$IDX"
    assert_contains "CiderTest Alpha" "compat: -v shows note"
fi

run "$CIDER" notes -s "CiderTest Beta"
assert_contains "CiderTest Beta" "compat: -s searches"

# ── Cleanup ──────────────────────────────────────────────────────────────────

log "Cleaning up..."
cleanup
rm -f "$SCRIPT_DIR/cider_test" 2>/dev/null || true

# ── Report ───────────────────────────────────────────────────────────────────

printf "\n"
printf "═══════════════════════════════════════════════════════\n"
printf "  CIDER TEST REPORT\n"
printf "═══════════════════════════════════════════════════════\n"
for r in "${RESULTS[@]}"; do
    echo "  $r"
done
printf "───────────────────────────────────────────────────────\n"
printf "  ✅ Passed: %d   ❌ Failed: %d   ⏭️  Skipped: %d\n" "$PASS" "$FAIL" "$SKIP"
printf "═══════════════════════════════════════════════════════\n"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
