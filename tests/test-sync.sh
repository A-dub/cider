#!/bin/bash
#
# test-sync.sh — Integration tests for cider sync
#
# Creates test notes, syncs to Markdown, tests bidirectional editing,
# and verifies pre-existing notes are never modified.
#
# Usage: ./test-sync.sh [./cider]
#

set -euo pipefail

CIDER="${1:-./cider}"
SYNC_DIR=$(mktemp -d)/CiderSyncTest
PASS=0
FAIL=0
TEST_PREFIX="CSyncTest"
TEST_FOLDER="CiderSync Tests"

cleanup() {
    echo ""
    echo "=== Cleanup ==="
    # Delete test notes from Apple Notes
    local notes
    notes=$($CIDER notes list --json 2>/dev/null || echo "[]")
    local indices
    indices=$(echo "$notes" | python3 -c "
import json, sys
notes = json.load(sys.stdin)
for n in notes:
    if n.get('title','').startswith('$TEST_PREFIX'):
        print(n['index'])
" 2>/dev/null || true)
    for idx in $indices; do
        echo "y" | $CIDER notes delete "$idx" 2>/dev/null || true
    done

    # Remove sync directory
    rm -rf "$SYNC_DIR"
    echo "Cleaned up test data."
}

trap cleanup EXIT

ok() {
    PASS=$((PASS + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL=$((FAIL + 1))
    echo "  FAIL: $1"
}

check() {
    local desc="$1"
    shift
    if "$@" > /dev/null 2>&1; then
        ok "$desc"
    else
        fail "$desc"
    fi
}

echo "=== Cider Sync Tests ==="
echo "Binary: $CIDER"
echo "Sync dir: $SYNC_DIR"
echo ""

# ── Test 1: Help text ──────────────────────────────────────────────────────

echo "--- Test: Help text ---"
if $CIDER sync --help 2>&1 | grep -q "Bidirectional"; then
    ok "sync help displays"
else
    fail "sync help"
fi

# ── Test 2: Backup ─────────────────────────────────────────────────────────

echo "--- Test: Backup ---"
mkdir -p "$SYNC_DIR"
if $CIDER sync backup --dir "$SYNC_DIR" 2>&1 | grep -q "Backup complete"; then
    ok "backup completes"
else
    fail "backup"
fi

if [ -f "$SYNC_DIR/.cider-backups/"*/backup-manifest.json ]; then
    ok "backup manifest exists"
else
    fail "backup manifest"
fi

if [ -f "$SYNC_DIR/.cider-backups/"*/NoteStore.sqlite ]; then
    ok "database backed up"
else
    fail "database backup"
fi

# ── Test 3: Create test notes, then sync ───────────────────────────────────

echo "--- Test: Initial sync (Notes -> MD) ---"

# Create test notes
echo "${TEST_PREFIX}_TextOnly" | $CIDER notes add --folder "$TEST_FOLDER" > /dev/null 2>&1
echo "${TEST_PREFIX}_WithContent body here" | $CIDER notes add --folder "$TEST_FOLDER" > /dev/null 2>&1

# Run sync
if $CIDER sync run --dir "$SYNC_DIR" 2>&1 | grep -q -e "Exported" -e "note(s)"; then
    ok "sync run completes"
else
    fail "sync run"
fi

# Check that MD files were created
FOLDER_DIR="$SYNC_DIR/CiderSync_Tests"
if [ ! -d "$FOLDER_DIR" ]; then
    # Try alternate sanitization
    FOLDER_DIR=$(find "$SYNC_DIR" -maxdepth 1 -type d -name "*CiderSync*" | head -1)
fi

if [ -n "$FOLDER_DIR" ] && ls "$FOLDER_DIR"/*.md > /dev/null 2>&1; then
    ok "markdown files created"
else
    fail "markdown files creation"
fi

# Check frontmatter exists
if ls "$FOLDER_DIR"/*.md 2>/dev/null | head -1 | xargs grep -q "note_id:" 2>/dev/null; then
    ok "frontmatter contains note_id"
else
    fail "frontmatter note_id"
fi

if ls "$FOLDER_DIR"/*.md 2>/dev/null | head -1 | xargs grep -q "editable: false" 2>/dev/null; then
    ok "pre-existing notes marked editable: false"
else
    fail "editable: false"
fi

# ── Test 4: Sync state file ───────────────────────────────────────────────

echo "--- Test: Sync state ---"
if [ -f "$SYNC_DIR/.cider-sync-state.json" ]; then
    ok "sync state file created"
else
    fail "sync state file"
fi

if python3 -c "import json; json.load(open('$SYNC_DIR/.cider-sync-state.json'))" 2>/dev/null; then
    ok "sync state is valid JSON"
else
    fail "sync state JSON"
fi

# ── Test 5: New MD file -> Apple Note ─────────────────────────────────────

echo "--- Test: New MD file -> Apple Note ---"
# Find or create the folder directory
if [ -z "$FOLDER_DIR" ] || [ ! -d "$FOLDER_DIR" ]; then
    FOLDER_DIR="$SYNC_DIR/CiderSync_Tests"
    mkdir -p "$FOLDER_DIR"
fi

cat > "$FOLDER_DIR/${TEST_PREFIX}_FromMD.md" <<'MDEOF'
This is a note created from Markdown.
It should appear in Apple Notes.
MDEOF

$CIDER sync run --dir "$SYNC_DIR" > /dev/null 2>&1

# Check if the note was created
if $CIDER notes list --json 2>/dev/null | python3 -c "
import json, sys
notes = json.load(sys.stdin)
found = any('${TEST_PREFIX}_FromMD' in n.get('title','') or 'from Markdown' in n.get('title','') for n in notes)
sys.exit(0 if found else 1)
" 2>/dev/null; then
    ok "new MD file creates Apple Note"
else
    fail "new MD creates note"
fi

# Check file was rewritten with frontmatter
if grep -q "editable: true" "$FOLDER_DIR/${TEST_PREFIX}_FromMD.md" 2>/dev/null; then
    ok "new note marked editable: true"
else
    fail "editable: true marking"
fi

# ── Test 6: Pre-existing notes not modified ───────────────────────────────

echo "--- Test: Pre-existing notes safety ---"

# Get hash of a pre-existing note's content before any edits
PRE_NOTE=$($CIDER notes list --json 2>/dev/null | python3 -c "
import json, sys
notes = json.load(sys.stdin)
for n in notes:
    if n.get('title','').startswith('${TEST_PREFIX}_TextOnly'):
        print(n['index'])
        break
" 2>/dev/null || echo "")

if [ -n "$PRE_NOTE" ]; then
    BEFORE=$($CIDER notes show "$PRE_NOTE" --json 2>/dev/null | python3 -c "
import json, sys; print(json.load(sys.stdin).get('body',''))" 2>/dev/null)

    # Try to modify the read-only MD file
    for f in "$FOLDER_DIR"/*TextOnly*.md; do
        if [ -f "$f" ]; then
            echo "TAMPERED CONTENT" >> "$f"
            break
        fi
    done

    $CIDER sync run --dir "$SYNC_DIR" > /dev/null 2>&1

    AFTER=$($CIDER notes show "$PRE_NOTE" --json 2>/dev/null | python3 -c "
import json, sys; print(json.load(sys.stdin).get('body',''))" 2>/dev/null)

    if [ "$BEFORE" = "$AFTER" ]; then
        ok "pre-existing note NOT modified by local MD edit"
    else
        fail "pre-existing note was modified!"
    fi
else
    fail "could not find pre-existing test note"
fi

# ── Test 7: Deleted MD doesn't delete note ────────────────────────────────

echo "--- Test: Deleted MD safety ---"

# Count notes before
BEFORE_COUNT=$($CIDER notes list --json 2>/dev/null | python3 -c "
import json, sys; print(len(json.load(sys.stdin)))" 2>/dev/null)

# Delete an MD file
for f in "$FOLDER_DIR"/*TextOnly*.md; do
    if [ -f "$f" ]; then
        rm "$f"
        break
    fi
done

$CIDER sync run --dir "$SYNC_DIR" > /dev/null 2>&1

AFTER_COUNT=$($CIDER notes list --json 2>/dev/null | python3 -c "
import json, sys; print(len(json.load(sys.stdin)))" 2>/dev/null)

if [ "$BEFORE_COUNT" = "$AFTER_COUNT" ]; then
    ok "deleting MD file does NOT delete Apple Note"
else
    fail "note was deleted when MD was removed"
fi

# ── Test 8: Unicode/edge cases ────────────────────────────────────────────

echo "--- Test: Edge cases ---"

echo "${TEST_PREFIX}_UnicodeTitleEmoji" | $CIDER notes add --folder "$TEST_FOLDER" > /dev/null 2>&1

$CIDER sync run --dir "$SYNC_DIR" > /dev/null 2>&1

if ls "$FOLDER_DIR"/*Emoji*.md > /dev/null 2>&1 || ls "$FOLDER_DIR"/*Unicode*.md > /dev/null 2>&1; then
    ok "unicode title exported"
else
    fail "unicode title export"
fi

# Empty note
echo "" | $CIDER notes add --folder "$TEST_FOLDER" > /dev/null 2>&1 || true

# ── Results ───────────────────────────────────────────────────────────────

echo ""
echo "=== Results ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
echo "Total:  $((PASS + FAIL))"

if [ "$FAIL" -gt 0 ]; then
    echo ""
    echo "SOME TESTS FAILED"
    exit 1
else
    echo ""
    echo "ALL TESTS PASSED"
    exit 0
fi
