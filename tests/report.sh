#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cider test report — shows before/after state for every operation
# ─────────────────────────────────────────────────────────────────────────────

set -eu

CIDER="${1:-./cider}"
TEST_FOLDER="Cider Tests"
SEP="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
SUBSEP="──────────────────────────────────────────────────────────────────────────"
CASE=0

# ── Helpers ──────────────────────────────────────────────────────────────────

header() {
    CASE=$((CASE + 1))
    printf "\n\n%s\n" "$SEP"
    printf "  TEST %02d: %s\n" "$CASE" "$1"
    printf "%s\n" "$SEP"
}

section() {
    printf "\n%s\n" "$SUBSEP"
    printf "  %s\n" "$1"
    printf "%s\n" "$SUBSEP"
}

cmd() {
    printf "\n  \$ %s\n\n" "$*"
    "$@" 2>&1 | sed 's/^/    /' || true
    printf "\n"
}

# Filter benign warnings
run_quiet() {
    "$@" 2>/dev/null | grep -v "ERROR: inflate" || true
}

find_note() {
    "$CIDER" notes list --json 2>/dev/null \
        | grep -v "ERROR:" \
        | grep -o '"index":[0-9]*,"title":"'"$1"'"' \
        | head -1 \
        | grep -o '[0-9]*' \
        | head -1
}

create_note() {
    printf '%s\n%s' "$1" "$2" | "$CIDER" notes add --folder "$3" 2>/dev/null
}

delete_note() {
    local idx
    idx=$(find_note "$1") || true
    if [ -n "$idx" ]; then
        yes y 2>/dev/null | "$CIDER" notes delete "$idx" 2>/dev/null || true
    fi
}

show_note_content() {
    local idx
    idx=$(find_note "$1") || true
    if [ -n "$idx" ]; then
        run_quiet "$CIDER" notes show "$idx" | sed 's/^/    /'
    else
        printf "    (note not found)\n"
    fi
}

# ── Cleanup any prior test notes ─────────────────────────────────────────────

for t in "CiderTest Alpha" "CiderTest Beta" "CiderTest Gamma" \
         "CiderTest Delta" "CiderTest Attach" "CiderTest Regex" \
         "CiderTest ReplAll1" "CiderTest ReplAll2" "CiderTest CaseTest" \
         "CiderTest Piped" "Piped note content here"; do
    delete_note "$t"
done
sleep 1

# ═══════════════════════════════════════════════════════════════════════════════
printf "\n%s\n" "$SEP"
printf "  CIDER v%s — COMPREHENSIVE TEST REPORT\n" "$("$CIDER" --version 2>&1 | grep -o '[0-9]*\.[0-9]*\.[0-9]*')"
printf "  Generated: %s\n" "$(date '+%Y-%m-%d %H:%M:%S')"
printf "%s\n" "$SEP"
# ═══════════════════════════════════════════════════════════════════════════════


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 1: BASIC OPERATIONS
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 1: BASIC OPERATIONS                       ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Version"
cmd "$CIDER" --version


header "Help (top-level)"
cmd "$CIDER" --help


header "Notes help (shows search/replace docs)"
cmd "$CIDER" notes --help


header "Create test notes via stdin"

section "BEFORE: List notes in test folder"
cmd "$CIDER" notes list -f "$TEST_FOLDER"

section "COMMAND: Create 8 test notes"
printf "  Creating notes...\n\n"
create_note "CiderTest Alpha" "This is the alpha note with some searchable content."  "$TEST_FOLDER"
printf "    Created: CiderTest Alpha\n"
create_note "CiderTest Beta" "Beta note body. Contains the word pineapple."  "$TEST_FOLDER"
printf "    Created: CiderTest Beta\n"
create_note "CiderTest Gamma" "Gamma note for editing and replacing text."  "$TEST_FOLDER"
printf "    Created: CiderTest Gamma\n"
create_note "CiderTest Delta" "Delta note that will be deleted."  "$TEST_FOLDER"
printf "    Created: CiderTest Delta\n"
create_note "CiderTest Attach" "Attachment test. BEFORE_ATTACH and AFTER_ATTACH markers."  "$TEST_FOLDER"
printf "    Created: CiderTest Attach\n"
create_note "CiderTest Regex" "Contact: alice@example.com and bob@test.org. Phone: 555-1234."  "$TEST_FOLDER"
printf "    Created: CiderTest Regex\n"
create_note "CiderTest ReplAll1" "The quick brown fox jumps over the lazy dog."  "$TEST_FOLDER"
printf "    Created: CiderTest ReplAll1\n"
create_note "CiderTest ReplAll2" "The quick brown dog runs through the quick brown meadow."  "$TEST_FOLDER"
printf "    Created: CiderTest ReplAll2\n"
create_note "CiderTest CaseTest" "TODO: fix the todo list and update TODO tracker."  "$TEST_FOLDER"
printf "    Created: CiderTest CaseTest\n"

sleep 1

section "AFTER: List notes in test folder"
cmd "$CIDER" notes list -f "$TEST_FOLDER"


header "List notes (JSON)"
cmd "$CIDER" notes list -f "$TEST_FOLDER" --json


header "List folders"
cmd "$CIDER" notes folders


header "List folders (JSON)"
cmd "$CIDER" notes folders --json


header "Show note by index"
IDX=$(find_note "CiderTest Alpha")
section "COMMAND"
cmd "$CIDER" notes show "$IDX"


header "Show note (JSON)"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes show "$IDX" --json


header "Show note (bare number shorthand)"
IDX=$(find_note "CiderTest Beta")
cmd "$CIDER" notes "$IDX"


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 2: SEARCH
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 2: SEARCH                                 ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Search — literal (title + body, default)"
section "Searches title AND body by default, case-insensitive"
cmd "$CIDER" notes search "CiderTest Beta"


header "Search — literal body content"
section "Finds notes where body contains 'pineapple'"
cmd "$CIDER" notes search "pineapple"


header "Search — JSON output"
cmd "$CIDER" notes search "CiderTest Alpha" --json


header "Search — no results"
cmd "$CIDER" notes search "xyznonexistent99"


header "Search — --regex (find email addresses)"
section "Pattern: [a-z]+@[a-z]+\\.[a-z]+ (matches email addresses)"
cmd "$CIDER" notes search '[a-z]+@[a-z]+\.[a-z]+' --regex


header "Search — --regex (title pattern)"
section "Pattern: CiderTest.*Repl (matches ReplAll1 and ReplAll2)"
cmd "$CIDER" notes search 'CiderTest.*Repl' --regex


header "Search — --regex (digit pattern)"
section "Pattern: \\d{3}-\\d{4} (matches phone numbers like 555-1234)"
cmd "$CIDER" notes search '\d{3}-\d{4}' --regex


header "Search — --title only"
section "Searches only the note title, NOT body content"
cmd "$CIDER" notes search "CiderTest Alpha" --title
printf "  Now search for body-only content with --title (should find nothing):\n"
cmd "$CIDER" notes search "pineapple" --title


header "Search — --body only"
section "Searches only the note body, NOT the title"
cmd "$CIDER" notes search "pineapple" --body
printf "  Now search for a title with --body (won't match the title):\n"
cmd "$CIDER" notes search "CiderTest Alpha" --body


header "Search — --folder scoping"
section "Scoped to test folder"
cmd "$CIDER" notes search "CiderTest" -f "$TEST_FOLDER"
printf "  Now search in a nonexistent folder:\n"
cmd "$CIDER" notes search "CiderTest" -f "NonexistentFolder99"


header "Search — --regex + --folder"
section "Regex search scoped to a folder"
cmd "$CIDER" notes search 'quick.*fox' --regex -f "$TEST_FOLDER"


header "Search — --title and --body mutual exclusion"
section "Should return an error — can't use both"
cmd "$CIDER" notes search "test" --title --body


header "Search — invalid regex"
section "Should return an error for malformed pattern"
cmd "$CIDER" notes search "[invalid" --regex


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 3: REPLACE (SINGLE NOTE)
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 3: REPLACE (SINGLE NOTE)                  ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Replace — literal (basic find & replace)"
IDX=$(find_note "CiderTest Gamma")
section "BEFORE: Note content"
show_note_content "CiderTest Gamma"
section "COMMAND: Replace 'editing' with 'TESTING'"
cmd "$CIDER" notes replace "$IDX" --find "editing" --replace "TESTING"
section "AFTER: Note content"
show_note_content "CiderTest Gamma"


header "Replace — --regex with capture groups"
IDX=$(find_note "CiderTest Regex")
section "BEFORE: Note content"
show_note_content "CiderTest Regex"
section "COMMAND: Regex replace emails — (\\w+)@(\\w+) → [\$1 at \$2]"
cmd "$CIDER" notes replace "$IDX" --find '(\w+)@(\w+)' --replace '[$1 at $2]' --regex
section "AFTER: Note content (emails masked with capture groups)"
show_note_content "CiderTest Regex"


header "Replace — -i (case-insensitive)"
IDX=$(find_note "CiderTest CaseTest")
section "BEFORE: Note content (has TODO, todo, TODO)"
show_note_content "CiderTest CaseTest"
section "COMMAND: Case-insensitive replace 'todo' → 'DONE'"
cmd "$CIDER" notes replace "$IDX" --find "todo" --replace "DONE" -i
section "AFTER: Note content (all case variants replaced)"
show_note_content "CiderTest CaseTest"


header "Replace — --regex with case-insensitive"
IDX=$(find_note "CiderTest Regex")
section "BEFORE: Note content"
show_note_content "CiderTest Regex"
section "COMMAND: Regex + case-insensitive — replace 'phone' → 'Tel'"
cmd "$CIDER" notes replace "$IDX" --find 'phone' --replace 'Tel' --regex -i
section "AFTER: Note content"
show_note_content "CiderTest Regex"


header "Replace — text not found (error)"
IDX=$(find_note "CiderTest Gamma")
section "COMMAND: Try to replace text that doesn't exist"
cmd "$CIDER" notes replace "$IDX" --find "zzz_nonexistent_text" --replace "x"


header "Replace — invalid regex (error)"
IDX=$(find_note "CiderTest Gamma")
section "COMMAND: Try an invalid regex pattern"
cmd "$CIDER" notes replace "$IDX" --find "[invalid" --replace "x" --regex


header "Replace — nonexistent note (error)"
section "COMMAND: Try to replace in note 99999"
cmd "$CIDER" notes replace 99999 --find "x" --replace "y"


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 4: REPLACE --ALL (MULTI-NOTE)
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 4: REPLACE --ALL (MULTI-NOTE)             ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Replace --all --dry-run (preview only)"
section "BEFORE: ReplAll1 content"
show_note_content "CiderTest ReplAll1"
section "BEFORE: ReplAll2 content"
show_note_content "CiderTest ReplAll2"
section "COMMAND: Dry-run — find 'quick brown' across test folder"
cmd "$CIDER" notes replace --all --find "quick brown" --replace "slow grey" --folder "$TEST_FOLDER" --dry-run
section "AFTER: ReplAll1 content (unchanged — dry-run)"
show_note_content "CiderTest ReplAll1"
section "AFTER: ReplAll2 content (unchanged — dry-run)"
show_note_content "CiderTest ReplAll2"


header "Replace --all --folder (with confirmation)"
section "BEFORE: ReplAll1 content"
show_note_content "CiderTest ReplAll1"
section "BEFORE: ReplAll2 content"
show_note_content "CiderTest ReplAll2"
section "COMMAND: Replace 'quick brown' → 'slow grey' in test folder (answering y)"
printf 'y\n' | "$CIDER" notes replace --all --find "quick brown" --replace "slow grey" --folder "$TEST_FOLDER" 2>&1 | sed 's/^/    /'
printf "\n"
section "AFTER: ReplAll1 content"
show_note_content "CiderTest ReplAll1"
section "AFTER: ReplAll2 content"
show_note_content "CiderTest ReplAll2"


header "Replace --all --regex --folder"
section "BEFORE: ReplAll1 content"
show_note_content "CiderTest ReplAll1"
section "BEFORE: ReplAll2 content"
show_note_content "CiderTest ReplAll2"
section "COMMAND: Regex replace '\\bslow\\b' → 'fast' in test folder"
printf 'y\n' | "$CIDER" notes replace --all --find '\bslow\b' --replace 'fast' --regex --folder "$TEST_FOLDER" 2>&1 | sed 's/^/    /'
printf "\n"
section "AFTER: ReplAll1 content"
show_note_content "CiderTest ReplAll1"
section "AFTER: ReplAll2 content"
show_note_content "CiderTest ReplAll2"


header "Replace --all — no matches"
section "COMMAND: Search for text that doesn't exist anywhere"
cmd "$CIDER" notes replace --all --find "xyzNonexistent99" --replace "x" --folder "$TEST_FOLDER" --dry-run


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 5: EDIT (CRDT)
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 5: EDIT (CRDT)                            ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Edit via stdin pipe"
IDX=$(find_note "CiderTest Gamma")
section "BEFORE: Note content"
show_note_content "CiderTest Gamma"
section "COMMAND: Pipe new content via stdin"
printf "  \$ echo 'CiderTest Gamma\nGamma note fully rewritten via stdin pipe.' | cider notes edit %s\n\n" "$IDX"
printf 'CiderTest Gamma\nGamma note fully rewritten via stdin pipe.' | "$CIDER" notes edit "$IDX" 2>&1 | sed 's/^/    /'
printf "\n"
section "AFTER: Note content"
show_note_content "CiderTest Gamma"


header "Add note via stdin pipe"
section "BEFORE: Search for 'Piped note'"
cmd "$CIDER" notes search "CiderTest Piped"
section "COMMAND: Pipe a new note from stdin"
printf "  \$ echo 'CiderTest Piped\nThis note was created from a pipe.' | cider notes add --folder '%s'\n\n" "$TEST_FOLDER"
printf 'CiderTest Piped\nThis note was created from a pipe.' | "$CIDER" notes add --folder "$TEST_FOLDER" 2>&1 | sed 's/^/    /'
printf "\n"
sleep 1
section "AFTER: Search for 'CiderTest Piped'"
cmd "$CIDER" notes search "CiderTest Piped"


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 6: ATTACHMENTS
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 6: ATTACHMENTS                            ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


echo "test attachment content" > /tmp/cider_report_attach.txt

header "Attach file to note"
IDX=$(find_note "CiderTest Attach")
section "BEFORE: Attachments"
cmd "$CIDER" notes attachments "$IDX"
section "COMMAND: Attach file"
cmd "$CIDER" notes attach "$IDX" /tmp/cider_report_attach.txt
sleep 1
section "AFTER: Attachments"
cmd "$CIDER" notes attachments "$IDX"


header "List attachments (JSON)"
IDX=$(find_note "CiderTest Attach")
cmd "$CIDER" notes attachments "$IDX" --json


header "Detach attachment"
IDX=$(find_note "CiderTest Attach")
section "BEFORE: Attachments"
cmd "$CIDER" notes attachments "$IDX"
section "COMMAND: Detach attachment #1"
cmd "$CIDER" notes detach "$IDX" 1
section "AFTER: Attachments"
cmd "$CIDER" notes attachments "$IDX"


header "Attach at specific position"
IDX=$(find_note "CiderTest Attach")
echo "positional test" > /tmp/cider_report_pos.txt
section "COMMAND: Attach at position 5"
cmd "$CIDER" notes attach "$IDX" /tmp/cider_report_pos.txt --at 5
sleep 1
section "AFTER: Attachments (JSON — check position)"
cmd "$CIDER" notes attachments "$IDX" --json
section "Cleanup: Detach"
cmd "$CIDER" notes detach "$IDX" 1

rm -f /tmp/cider_report_attach.txt /tmp/cider_report_pos.txt


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 7: MOVE
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 7: MOVE                                   ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Move note to different folder"
IDX=$(find_note "CiderTest Beta")
section "BEFORE: Note folder"
printf "    "
run_quiet "$CIDER" notes show "$IDX" --json | grep -o '"folder":"[^"]*"'
printf "\n"
section "COMMAND: Move to 'Notes' folder"
cmd "$CIDER" notes move "$IDX" Notes
sleep 1
IDX2=$(find_note "CiderTest Beta")
if [ -n "$IDX2" ]; then
    section "AFTER: Note folder"
    printf "    "
    run_quiet "$CIDER" notes show "$IDX2" --json | grep -o '"folder":"[^"]*"'
    printf "\n"
    section "Cleanup: Move back"
    cmd "$CIDER" notes move "$IDX2" "$TEST_FOLDER"
    sleep 1
fi


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 8: DELETE
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 8: DELETE                                  ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Delete note"
IDX=$(find_note "CiderTest Delta")
section "BEFORE: Search for Delta note"
cmd "$CIDER" notes search "CiderTest Delta"
section "COMMAND: Delete (answering y to confirmation)"
printf "  \$ printf 'y\\n' | cider notes delete %s\n\n" "$IDX"
printf 'y\n' | "$CIDER" notes delete "$IDX" 2>&1 | sed 's/^/    /'
printf "\n"
sleep 1
section "AFTER: Search for Delta note"
cmd "$CIDER" notes search "CiderTest Delta"


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 9: EXPORT
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 9: EXPORT                                 ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Export all notes to HTML"
EXPORT_DIR="/tmp/cider_report_export_$$"
cmd "$CIDER" notes export "$EXPORT_DIR"
section "Files created"
printf "    %s HTML files exported\n" "$(ls "$EXPORT_DIR"/*.html 2>/dev/null | wc -l | tr -d ' ')"
printf "    Sample files:\n"
ls "$EXPORT_DIR"/*.html 2>/dev/null | head -5 | sed 's/^/      /'
printf "\n"
rm -rf "$EXPORT_DIR"


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 10: ERROR HANDLING
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 10: ERROR HANDLING                        ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Show nonexistent note"
cmd "$CIDER" notes show 99999

header "Replace in nonexistent note"
cmd "$CIDER" notes replace 99999 --find "x" --replace "y"

header "Detach from nonexistent note"
cmd "$CIDER" notes detach 99999 1

header "Attach to nonexistent file"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes attach "$IDX" /nonexistent/file.txt

header "Unknown command"
cmd "$CIDER" bogus

header "Unknown notes subcommand"
cmd "$CIDER" notes bogus

header "Missing replace arguments"
cmd "$CIDER" notes replace 1 --find "x"


# ─────────────────────────────────────────────────────────────────────────────
# SECTION 11: BACKWARD COMPATIBILITY
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n\n"
printf "  ╔══════════════════════════════════════════════════════════════════╗\n"
printf "  ║              SECTION 11: BACKWARD COMPATIBILITY                ║\n"
printf "  ╚══════════════════════════════════════════════════════════════════╝\n"


header "Legacy -fl (folders)"
cmd "$CIDER" notes -fl

header "Legacy -v (view)"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes -v "$IDX"

header "Legacy -s (search)"
cmd "$CIDER" notes -s "CiderTest Beta"

header "Legacy -f (folder filter)"
cmd "$CIDER" notes -f "$TEST_FOLDER"


# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n%s\n" "$SEP"
printf "  CLEANUP\n"
printf "%s\n\n" "$SEP"

for t in "CiderTest Alpha" "CiderTest Beta" "CiderTest Gamma" \
         "CiderTest Delta" "CiderTest Attach" "CiderTest Regex" \
         "CiderTest ReplAll1" "CiderTest ReplAll2" "CiderTest CaseTest" \
         "CiderTest Piped" "Piped note content here"; do
    delete_note "$t"
done
printf "  All test notes cleaned up.\n"


# ─────────────────────────────────────────────────────────────────────────────
# SUMMARY
# ─────────────────────────────────────────────────────────────────────────────

printf "\n\n%s\n" "$SEP"
printf "  REPORT COMPLETE — %d test cases demonstrated\n" "$CASE"
printf "%s\n" "$SEP"
