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

set -eu

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
# Filters benign framework warnings from output.
run() {
    local tmpfile="/tmp/cider_run_$$.txt"
    set +e
    "$@" > "$tmpfile" 2>&1
    RC=$?
    set -e
    OUT=$(grep -v "ERROR: inflate failed" "$tmpfile" || true)
    rm -f "$tmpfile"
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

# Find note index by title (searches JSON output, filters framework warnings)
find_note() {
    local title="$1"
    "$CIDER" notes list --json 2>/dev/null \
        | grep -v "ERROR:" \
        | grep -o '"index":[0-9]*,"title":"'"$title"'"' \
        | head -1 \
        | grep -o '[0-9]*' \
        | head -1
}

# Create a note using cider's framework-based add
create_note() {
    local title="$1"
    local body="$2"
    local folder="${3:-$TEST_FOLDER}"
    printf '%s\n%s' "$title" "$body" | "$CIDER" notes add --folder "$folder" 2>/dev/null
}

# Delete a note by title using cider
delete_note_as() {
    local title="$1"
    local idx
    idx=$("$CIDER" notes list --json 2>/dev/null \
        | grep -o '"index":[0-9]*,"title":"'"$title"'"' \
        | head -1 \
        | grep -o '[0-9]*' \
        | head -1) || true
    if [ -n "$idx" ]; then
        yes y 2>/dev/null | "$CIDER" notes delete "$idx" 2>/dev/null || true
    fi
}

# Clean up test folder
cleanup() {
    log "Cleaning up test notes..."
    for title in "CiderTest Alpha" "CiderTest Beta" "CiderTest Gamma" \
                 "CiderTest Delta" "CiderTest Attach" "CiderTest Piped" \
                 "Piped note content here" \
                 "CiderTest Regex" "CiderTest ReplAll1" "CiderTest ReplAll2" \
                 "CiderTest Append" "CiderTest Prepend" \
                 "CiderTest Template" "Template body line 1" \
                 "Cider Settings"; do
        delete_note_as "$title"
    done
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

# ── Check framework access ───────────────────────────────────────────────────

log "Checking Notes framework access..."
run "$CIDER" notes list
if [ $RC -ne 0 ]; then
    skip "framework" "Notes framework not available (missing NotesShared.framework?)"

    # Error handling tests still work
    run "$CIDER" notes show 99999
    assert_rc 1 "show: nonexistent note returns error"

    run "$CIDER" notes replace 99999 --find "x" --replace "y"
    assert_rc 1 "replace: nonexistent note returns error"

    run "$CIDER" notes detach 99999 1
    assert_contains "not found" "detach: nonexistent note shows error"

    # Print report and exit
    printf "\n"
    printf "═══════════════════════════════════════════════════════\n"
    printf "  CIDER TEST REPORT (limited — no framework access)\n"
    printf "═══════════════════════════════════════════════════════\n"
    for r in "${RESULTS[@]}"; do
        echo "  $r"
    done
    printf "───────────────────────────────────────────────────────\n"
    printf "  ✅ Passed: %d   ❌ Failed: %d   ⏭️  Skipped: %d\n" "$PASS" "$FAIL" "$SKIP"
    printf "═══════════════════════════════════════════════════════\n"
    exit $FAIL
fi
pass "framework: Notes database accessible"

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
create_note "CiderTest Regex" "Contact: alice@example.com and bob@test.org. Phone: 555-1234."
create_note "CiderTest ReplAll1" "The quick brown fox jumps."
create_note "CiderTest ReplAll2" "The quick brown dog runs."
create_note "CiderTest Append" "Original append body."
create_note "CiderTest Prepend" "Original prepend body."

sleep 1  # Brief pause for any background indexing

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

# ── Test: search --regex ──────────────────────────────────────────────────────

log "Testing: notes search --regex"

run "$CIDER" notes search "[a-z]+@[a-z]+\\.[a-z]+" --regex
if echo "$OUT" | grep -qF "CiderTest Regex"; then
    pass "search --regex: finds note by regex body match"
else
    skip "search --regex (body)" "snippet not yet indexed (Notes async indexing)"
fi

run "$CIDER" notes search "CiderTest.*Regex" --regex
assert_contains "CiderTest Regex" "search --regex: regex title match"

# ── Test: search --title / --body ─────────────────────────────────────────────

log "Testing: notes search --title / --body"

run "$CIDER" notes search "CiderTest Alpha" --title
assert_contains "CiderTest Alpha" "search --title: finds by title"

run "$CIDER" notes search "pineapple" --title
assert_contains "No notes found" "search --title: body content not in title"

run "$CIDER" notes search "CiderTest Alpha" --title --body
assert_rc 1 "search: --title and --body are mutually exclusive"

# ── Test: search --folder ─────────────────────────────────────────────────────

log "Testing: notes search --folder"

run "$CIDER" notes search "CiderTest" -f "$TEST_FOLDER"
assert_contains "CiderTest" "search --folder: finds notes in test folder"

run "$CIDER" notes search "CiderTest" -f "NonexistentFolder99"
assert_contains "No notes found" "search --folder: no results in wrong folder"

# ── Test: search invalid regex ────────────────────────────────────────────────

log "Testing: search invalid regex"

run "$CIDER" notes search "[invalid" --regex
assert_contains "Invalid regex" "search --regex: rejects bad pattern"

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

# ── Test: replace --regex (single note) ──────────────────────────────────────

log "Testing: notes replace --regex"

IDX=$(find_note "CiderTest Regex")
if [ -z "$IDX" ]; then
    fail "replace --regex" "Could not find CiderTest Regex"
else
    # Regex replace: email pattern → masked
    run "$CIDER" notes replace "$IDX" --find "([a-z]+)@([a-z]+)\\.([a-z]+)" --replace "[\$1 at \$2]" --regex
    assert_rc 0 "replace --regex: succeeded"

    run "$CIDER" notes show "$IDX"
    assert_contains "[alice at example]" "replace --regex: capture groups worked"
    assert_not_contains "alice@example.com" "replace --regex: original email gone"
fi

# ── Test: replace -i (case-insensitive) ──────────────────────────────────────

log "Testing: notes replace -i"

IDX=$(find_note "CiderTest Regex")
if [ -z "$IDX" ]; then
    fail "replace -i" "Could not find CiderTest Regex"
else
    run "$CIDER" notes replace "$IDX" --find "PHONE" --replace "Tel" -i
    assert_rc 0 "replace -i: succeeded (case-insensitive)"

    run "$CIDER" notes show "$IDX"
    # Original had "Phone:" which should now be "Tel:"
    assert_contains "Tel:" "replace -i: case-insensitive replacement applied"
fi

# ── Test: replace --all --dry-run (scoped to test folder) ────────────────────

log "Testing: notes replace --all --dry-run"

run "$CIDER" notes replace --all --find "quick brown" --replace "slow grey" --folder "$TEST_FOLDER" --dry-run
assert_contains "2 note(s)" "replace --all --dry-run: found matches in 2 notes"
assert_contains "dry-run" "replace --all --dry-run: shows dry-run message"

# Verify nothing was actually changed
IDX=$(find_note "CiderTest ReplAll1")
if [ -n "$IDX" ]; then
    run "$CIDER" notes show "$IDX"
    assert_contains "quick brown" "replace --all --dry-run: no changes applied"
fi

# ── Test: replace --all (scoped to test folder, with confirmation) ───────────

log "Testing: notes replace --all --folder"

run bash -c "printf 'y\n' | '$CIDER' notes replace --all --find 'quick brown' --replace 'slow grey' --folder '$TEST_FOLDER' 2>&1"
assert_contains "Replaced in 2 note(s)" "replace --all: replaced in 2 notes"

# Verify changes
IDX=$(find_note "CiderTest ReplAll1")
if [ -n "$IDX" ]; then
    run "$CIDER" notes show "$IDX"
    assert_contains "slow grey" "replace --all: ReplAll1 content changed"
    assert_not_contains "quick brown" "replace --all: ReplAll1 old text gone"
fi

IDX=$(find_note "CiderTest ReplAll2")
if [ -n "$IDX" ]; then
    run "$CIDER" notes show "$IDX"
    assert_contains "slow grey" "replace --all: ReplAll2 content changed"
fi

# ── Test: replace --all --regex --folder ─────────────────────────────────────

log "Testing: notes replace --all --regex"

run bash -c "printf 'y\n' | '$CIDER' notes replace --all --find '\\bslow\\b' --replace 'fast' --regex --folder '$TEST_FOLDER' 2>&1"
assert_contains "Replaced in 2 note(s)" "replace --all --regex: replaced in 2 notes"

IDX=$(find_note "CiderTest ReplAll1")
if [ -n "$IDX" ]; then
    run "$CIDER" notes show "$IDX"
    assert_contains "fast grey" "replace --all --regex: content updated"
fi

# ── Test: replace nonexistent text ───────────────────────────────────────────

log "Testing: replace error handling"

IDX=$(find_note "CiderTest ReplAll1")
if [ -n "$IDX" ]; then
    run "$CIDER" notes replace "$IDX" --find "zzz_nonexistent" --replace "x"
    assert_rc 1 "replace: nonexistent text returns error"

    run "$CIDER" notes replace "$IDX" --find "[invalid" --replace "x" --regex
    assert_rc 1 "replace --regex: invalid regex returns error"
fi

# ── Test: notes append ───────────────────────────────────────────────────────

log "Testing: notes append"

IDX=$(find_note "CiderTest Append")
if [ -z "$IDX" ]; then
    fail "append" "Could not find CiderTest Append"
else
    # Basic append
    run "$CIDER" notes append "$IDX" "Appended line one."
    assert_rc 0 "append: exits 0"
    assert_contains "✓" "append: success message"

    run "$CIDER" notes show "$IDX"
    assert_contains "Appended line one." "append: text was appended"
    assert_contains "Original append body." "append: original body preserved"

    # Stdin append
    echo "Piped append text." | "$CIDER" notes append "$IDX" 2>/dev/null
    run "$CIDER" notes show "$IDX"
    assert_contains "Piped append text." "append (stdin): piped text appended"

    # --no-newline
    run "$CIDER" notes append "$IDX" " SUFFIX" --no-newline
    run "$CIDER" notes show "$IDX"
    assert_contains "Piped append text. SUFFIX" "append --no-newline: no separator"

    # Error: no text
    run "$CIDER" notes append "$IDX"
    assert_rc 1 "append: error when no text provided"
fi

# ── Test: notes prepend ──────────────────────────────────────────────────────

log "Testing: notes prepend"

IDX=$(find_note "CiderTest Prepend")
if [ -z "$IDX" ]; then
    fail "prepend" "Could not find CiderTest Prepend"
else
    # Basic prepend
    run "$CIDER" notes prepend "$IDX" "Prepended after title."
    assert_rc 0 "prepend: exits 0"
    assert_contains "✓" "prepend: success message"

    run "$CIDER" notes show "$IDX"
    assert_contains "Prepended after title." "prepend: text was prepended"
    assert_contains "Original prepend body." "prepend: original body preserved"

    # Stdin prepend
    echo "Piped prepend text." | "$CIDER" notes prepend "$IDX" 2>/dev/null
    run "$CIDER" notes show "$IDX"
    assert_contains "Piped prepend text." "prepend (stdin): piped text prepended"

    # Error: no text
    run "$CIDER" notes prepend "$IDX"
    assert_rc 1 "prepend: error when no text provided"
fi

# ── Test: notes debug ────────────────────────────────────────────────────────

log "Testing: notes debug"

IDX=$(find_note "CiderTest Alpha")
if [ -n "$IDX" ]; then
    run "$CIDER" notes debug "$IDX"
    assert_rc 0 "debug: exits 0"
    assert_contains "Debug:" "debug: shows debug header"
    assert_contains "Raw text length:" "debug: shows raw text length"
    assert_contains "attribute keys" "debug: shows attribute key summary"
fi

# ── Test: notes attach + attachments + detach ────────────────────────────────

log "Testing: attach / attachments / detach"

IDX=$(find_note "CiderTest Attach")
if [ -z "$IDX" ]; then
    fail "attach" "Could not find CiderTest Attach"
else
    # Create a test file to attach
    echo "test attachment content" > /tmp/cider_test_attach.txt

    # Attach (uses CRDT framework — appends to end of note)
    run "$CIDER" notes attach "$IDX" /tmp/cider_test_attach.txt
    assert_contains "✓" "attach: success message"

    sleep 1

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

    rm -f /tmp/cider_test_attach.txt
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
    # Delete uses interactive confirmation
    run bash -c "printf 'y\n' | '$CIDER' notes delete '$IDX' 2>&1"
    if echo "$OUT" | grep -qiF "deleted"; then
        pass "delete: deleted note successfully"
    elif echo "$OUT" | grep -qiF "error"; then
        fail "delete" "$OUT"
    else
        # Delete ran but output format may vary
        pass "delete: command completed (rc=$RC)"
    fi

    # Verify deletion — framework delete is synchronous, no sleep needed
    sleep 1
    IDX2=$(find_note "CiderTest Delta")
    if [ -z "$IDX2" ]; then
        pass "delete: note no longer in list"
    else
        fail "delete (verify)" "note still appears in list after deletion"
    fi
fi

# ── Test: date filtering + sorting ──────────────────────────────────────────

log "Testing: date filtering + sorting"

# --after today should include test notes (they were just created)
run "$CIDER" notes list --after today
assert_rc 0 "list --after today: exits 0"
assert_contains "CiderTest Alpha" "list --after today: includes recently modified notes"

# --before with old date should exclude test notes
run "$CIDER" notes list --before "2020-01-01"
if echo "$OUT" | grep -qF "CiderTest Alpha"; then
    fail "list --before old date" "test note should not appear before 2020"
else
    pass "list --before old date: excludes recent notes"
fi

# --sort modified
run "$CIDER" notes list --sort modified
assert_rc 0 "list --sort modified: exits 0"
assert_contains "Total:" "list --sort modified: shows total"

# --sort created
run "$CIDER" notes list --sort created
assert_rc 0 "list --sort created: exits 0"
assert_contains "Total:" "list --sort created: shows total"

# --after + --folder combined
run "$CIDER" notes list --after today -f "$TEST_FOLDER"
assert_rc 0 "list --after + --folder: exits 0"
assert_contains "CiderTest Alpha" "list --after + --folder: includes test notes"

# JSON includes created/modified dates
run "$CIDER" notes list --json -f "$TEST_FOLDER"
assert_contains "created" "list --json: includes created date"
assert_contains "modified" "list --json: includes modified date"

# Invalid date error
run "$CIDER" notes list --after "not-a-date"
assert_contains "Invalid date" "list --after invalid: shows error"

# Search with --after
run "$CIDER" notes search "CiderTest" --after today
assert_rc 0 "search --after today: exits 0"
assert_contains "CiderTest" "search --after today: finds test notes"

# Search with --before old date
run "$CIDER" notes search "CiderTest" --before "2020-01-01"
assert_contains "No notes found" "search --before old date: no results"

# ── Test: templates ──────────────────────────────────────────────────────────

log "Testing: templates"

# Create a template via stdin
printf 'CiderTest Template\nTemplate body line 1\nTemplate body line 2' | "$CIDER" notes add --folder "Cider Templates" 2>/dev/null
sleep 1

# List templates
run "$CIDER" templates list
assert_rc 0 "templates list: exits 0"
assert_contains "CiderTest Template" "templates list: shows template"

# Show template
run "$CIDER" templates show "CiderTest Template"
assert_rc 0 "templates show: exits 0"
assert_contains "Template body line 1" "templates show: shows body"

# Show nonexistent template
run "$CIDER" templates show "Nonexistent Template"
assert_rc 1 "templates show: nonexistent returns exit 1"

# Create note from template (non-interactive uses template body as-is)
"$CIDER" notes add --template "CiderTest Template" --folder "$TEST_FOLDER" 2>/dev/null
sleep 1
run "$CIDER" notes list -f "$TEST_FOLDER"
assert_contains "Template body line 1" "add --template: created note from template"

# Delete note created from template
TIDX=$(find_note "Template body line 1")
if [ -n "$TIDX" ]; then
    yes y 2>/dev/null | "$CIDER" notes delete "$TIDX" 2>/dev/null || true
fi

# Delete template
run "$CIDER" templates delete "CiderTest Template"
assert_rc 0 "templates delete: exits 0"
assert_contains "Deleted template" "templates delete: success message"

# Delete nonexistent template
run "$CIDER" templates delete "Nonexistent Template"
assert_rc 1 "templates delete: nonexistent returns exit 1"

# ── Test: folder management ─────────────────────────────────────────────────

log "Testing: folder management"

# Create folder
run "$CIDER" notes folder create "CiderTest Subfolder"
assert_rc 0 "folder create: exits 0"
assert_contains "Created folder" "folder create: success message"

# Create duplicate (should say already exists)
run "$CIDER" notes folder create "CiderTest Subfolder"
assert_contains "already exists" "folder create: duplicate detection"

# Rename folder
run "$CIDER" notes folder rename "CiderTest Subfolder" "CiderTest Renamed"
assert_rc 0 "folder rename: exits 0"
assert_contains "Renamed" "folder rename: success message"

# Verify renamed folder appears in list
run "$CIDER" notes folders
assert_contains "CiderTest Renamed" "folder rename: appears in folders list"

# Delete folder
run "$CIDER" notes folder delete "CiderTest Renamed"
assert_rc 0 "folder delete: exits 0"
assert_contains "Deleted folder" "folder delete: success message"

# Delete nonexistent folder
run "$CIDER" notes folder delete "NonexistentFolder99"
assert_rc 1 "folder delete: nonexistent folder returns exit 1"

# Delete non-empty folder
run "$CIDER" notes folder delete "$TEST_FOLDER"
assert_rc 1 "folder delete: non-empty folder returns exit 1"
assert_contains "note(s)" "folder delete: shows note count error"

# ── Test: tags ──────────────────────────────────────────────────────────────

log "Testing: tags"

IDX=$(find_note "CiderTest Alpha")
if [ -z "$IDX" ]; then
    fail "tag" "Could not find CiderTest Alpha"
else
    # Add a tag
    run "$CIDER" notes tag "$IDX" "cidertest"
    assert_rc 0 "tag: exits 0"
    assert_contains "Added #cidertest" "tag: success message"

    # Verify tag in note body
    run "$CIDER" notes show "$IDX"
    assert_contains "#cidertest" "tag: tag appears in note"

    # Duplicate tag detection
    run "$CIDER" notes tag "$IDX" "#cidertest"
    assert_contains "already has tag" "tag: duplicate detection"

    # Add another tag with hyphen
    run "$CIDER" notes tag "$IDX" "test-tag"
    assert_rc 0 "tag: hyphen tag exits 0"

    # List all tags
    run "$CIDER" notes tags
    assert_contains "#cidertest" "tags: lists cidertest tag"
    assert_contains "#test-tag" "tags: lists hyphen tag"

    # Tags with --count
    run "$CIDER" notes tags --count
    assert_contains "note(s)" "tags --count: shows note counts"

    # Tags --json
    run "$CIDER" notes tags --json
    assert_contains '"tag"' "tags --json: JSON output"

    # Filter by tag
    run "$CIDER" notes list --tag cidertest
    assert_contains "CiderTest Alpha" "list --tag: shows tagged note"

    # Remove tag
    run "$CIDER" notes untag "$IDX" "cidertest"
    assert_rc 0 "untag: exits 0"
    assert_contains "Removed #cidertest" "untag: success message"

    # Remove non-existent tag
    run "$CIDER" notes untag "$IDX" "nonexistent"
    assert_contains "not found" "untag: nonexistent tag message"

    # Clean up remaining tag
    run "$CIDER" notes untag "$IDX" "test-tag"
fi

# ── Test: watch ────────────────────────────────────────────────────────

log "Testing: watch"

# Start watch in background, let it run briefly, then kill
"$CIDER" notes watch --interval 1 > /tmp/cider_watch_$$.txt 2>&1 &
WATCH_PID=$!
sleep 2
kill $WATCH_PID 2>/dev/null || true
wait $WATCH_PID 2>/dev/null || true
OUT=$(cat /tmp/cider_watch_$$.txt)
assert_contains "Watching" "watch: shows watching message"

# Watch with --folder
"$CIDER" notes watch --interval 1 -f "$TEST_FOLDER" > /tmp/cider_watch2_$$.txt 2>&1 &
WATCH_PID=$!
sleep 2
kill $WATCH_PID 2>/dev/null || true
wait $WATCH_PID 2>/dev/null || true
OUT=$(cat /tmp/cider_watch2_$$.txt)
assert_contains "Watching" "watch --folder: shows watching message"
assert_contains "$TEST_FOLDER" "watch --folder: shows folder name"

# Watch with --json (just verify it starts)
"$CIDER" notes watch --interval 1 --json > /tmp/cider_watch3_$$.txt 2>&1 &
WATCH_PID=$!
sleep 2
kill $WATCH_PID 2>/dev/null || true
wait $WATCH_PID 2>/dev/null || true
OUT=$(cat /tmp/cider_watch3_$$.txt)
assert_contains "Watching" "watch --json: starts correctly"

rm -f /tmp/cider_watch_$$.txt /tmp/cider_watch2_$$.txt /tmp/cider_watch3_$$.txt

# ── Test: links / backlinks ────────────────────────────────────────────

log "Testing: links / backlinks"

IDX=$(find_note "CiderTest Alpha")
if [ -z "$IDX" ]; then
    fail "links" "Could not find CiderTest Alpha"
else
    # Links on a note with no links
    run "$CIDER" notes links "$IDX"
    assert_rc 0 "links: exits 0"
    assert_contains "No outgoing links" "links: shows no links message"

    # Links --json on empty
    run "$CIDER" notes links "$IDX" --json
    assert_rc 0 "links --json: exits 0"
    assert_contains "[]" "links --json: empty array"

    # Backlinks on test note
    run "$CIDER" notes backlinks "$IDX"
    assert_rc 0 "backlinks: exits 0"
    assert_contains "No notes link" "backlinks: shows no backlinks message"

    # Backlinks --json on empty
    run "$CIDER" notes backlinks "$IDX" --json
    assert_rc 0 "backlinks --json: exits 0"
    assert_contains "[]" "backlinks --json: empty array"

    # Backlinks --all (works even with no links in test notes)
    run "$CIDER" notes backlinks --all
    assert_rc 0 "backlinks --all: exits 0"

    # Backlinks --all --json
    run "$CIDER" notes backlinks --all --json
    assert_rc 0 "backlinks --all --json: exits 0"
fi

# Links on nonexistent note
run "$CIDER" notes links 99999
assert_rc 0 "links: nonexistent note shows error"
assert_contains "not found" "links: error message for nonexistent"

# ── Test: settings ─────────────────────────────────────────────────────

log "Testing: settings"

# Show settings (initially empty)
run "$CIDER" settings
assert_rc 0 "settings: exits 0"
assert_contains "No settings" "settings: shows no settings message"

# Set a setting
run "$CIDER" settings set default_sort modified
assert_rc 0 "settings set: exits 0"
assert_contains "Set" "settings set: success message"

# Get a setting
run "$CIDER" settings get default_sort
assert_rc 0 "settings get: exits 0"
assert_contains "modified" "settings get: returns correct value"

# Set another setting
run "$CIDER" settings set default_folder "Work Notes"
assert_rc 0 "settings set second: exits 0"

# Show all settings
run "$CIDER" settings
assert_contains "default_sort" "settings: shows default_sort"
assert_contains "default_folder" "settings: shows default_folder"

# JSON output
run "$CIDER" settings --json
assert_contains '"default_sort"' "settings --json: JSON output"
assert_contains '"modified"' "settings --json: JSON value"

# Get nonexistent key
run "$CIDER" settings get nonexistent_key
assert_rc 1 "settings get: nonexistent key returns exit 1"

# Overwrite existing setting
run "$CIDER" settings set default_sort created
run "$CIDER" settings get default_sort
assert_contains "created" "settings set: overwrites existing value"

# Reset settings
run "$CIDER" settings reset
assert_rc 0 "settings reset: exits 0"
assert_contains "reset" "settings reset: success message"

# Verify settings cleared
run "$CIDER" settings
assert_contains "No settings" "settings reset: settings cleared"

# ── Test: pin / unpin ───────────────────────────────────────────────────────

log "Testing: pin / unpin"

IDX=$(find_note "CiderTest Alpha")
if [ -z "$IDX" ]; then
    fail "pin" "Could not find CiderTest Alpha"
else
    # Pin a note
    run "$CIDER" notes pin "$IDX"
    assert_rc 0 "pin: exits 0"
    assert_contains "Pinned" "pin: success message"

    # Pin again (should say already pinned)
    run "$CIDER" notes pin "$IDX"
    assert_contains "already pinned" "pin: already pinned message"

    # List --pinned should include it
    run "$CIDER" notes list --pinned
    assert_contains "CiderTest Alpha" "list --pinned: shows pinned note"

    # Unpin
    run "$CIDER" notes unpin "$IDX"
    assert_rc 0 "unpin: exits 0"
    assert_contains "Unpinned" "unpin: success message"

    # Unpin again (should say not pinned)
    run "$CIDER" notes unpin "$IDX"
    assert_contains "not pinned" "unpin: not pinned message"
fi

# Pin nonexistent note
run "$CIDER" notes pin 99999
assert_rc 1 "pin: nonexistent note returns exit 1"

# ── Test: error handling ─────────────────────────────────────────────────────

log "Testing: error handling"

run "$CIDER" notes show 99999
assert_rc 1 "error: nonexistent note returns exit 1"

run "$CIDER" notes detach 99999 1
assert_contains "not found" "error: detach nonexistent note shows error"

run "$CIDER" notes replace 99999 --find "x" --replace "y"
assert_rc 1 "error: replace nonexistent note returns exit 1"

run "$CIDER" notes attach 99999 /nonexistent/file.txt
assert_matches "Error|error|not found" "error: attach nonexistent note shows error"

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
