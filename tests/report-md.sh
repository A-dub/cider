#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# cider test report — Markdown output showing before/after for every operation
# ─────────────────────────────────────────────────────────────────────────────

set -eu

CIDER="${1:-./cider}"
TEST_FOLDER="Cider Tests"
CASE=0

# ── Helpers ──────────────────────────────────────────────────────────────────

header() {
    CASE=$((CASE + 1))
    printf "\n### Test %02d: %s\n\n" "$CASE" "$1"
}

section() {
    printf "\n**%s**\n\n" "$1"
}

cmd() {
    printf '```\n$ %s\n' "$*"
    "$@" 2>&1 || true
    printf '```\n'
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

show_note() {
    local idx
    idx=$(find_note "$1") || true
    if [ -n "$idx" ]; then
        printf '```\n'
        "$CIDER" notes show "$idx" 2>/dev/null | grep -v "ERROR: inflate"
        printf '```\n'
    else
        printf '```\n(note not found)\n```\n'
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

VERSION=$("$CIDER" --version 2>&1 | grep -o '[0-9]*\.[0-9]*\.[0-9]*')
DATE=$(date '+%Y-%m-%d %H:%M:%S')

cat <<EOF
# Cider v${VERSION} — Test Report

> Generated: ${DATE}
>
> This report shows **before and after** state for every cider operation,
> demonstrating how each command works with real Apple Notes data.
> All test notes are created in a "Cider Tests" folder and cleaned up afterwards.

---

## Section 1: Basic Operations

EOF


header "Version"
cmd "$CIDER" --version


header "Help (top-level)"
cmd "$CIDER" --help


header "Notes help"
printf "Shows the full search/replace documentation with all flags and examples.\n\n"
cmd "$CIDER" notes --help


header "Create test notes"

section "BEFORE: Notes in test folder"
cmd "$CIDER" notes list -f "$TEST_FOLDER"

section "COMMAND: Create 9 test notes via stdin pipe"
printf '```\n'
create_note "CiderTest Alpha" "This is the alpha note with some searchable content."  "$TEST_FOLDER"
create_note "CiderTest Beta" "Beta note body. Contains the word pineapple."  "$TEST_FOLDER"
create_note "CiderTest Gamma" "Gamma note for editing and replacing text."  "$TEST_FOLDER"
create_note "CiderTest Delta" "Delta note that will be deleted."  "$TEST_FOLDER"
create_note "CiderTest Attach" "Attachment test. BEFORE_ATTACH and AFTER_ATTACH markers."  "$TEST_FOLDER"
create_note "CiderTest Regex" "Contact: alice@example.com and bob@test.org. Phone: 555-1234."  "$TEST_FOLDER"
create_note "CiderTest ReplAll1" "The quick brown fox jumps over the lazy dog."  "$TEST_FOLDER"
create_note "CiderTest ReplAll2" "The quick brown dog runs through the quick brown meadow."  "$TEST_FOLDER"
create_note "CiderTest CaseTest" "TODO: fix the todo list and update TODO tracker."  "$TEST_FOLDER"
printf '```\n'

sleep 1

section "AFTER: Notes in test folder"
cmd "$CIDER" notes list -f "$TEST_FOLDER"


header "List notes (JSON)"
cmd "$CIDER" notes list -f "$TEST_FOLDER" --json


header "List folders"
cmd "$CIDER" notes folders


header "List folders (JSON)"
cmd "$CIDER" notes folders --json


header "Show note by index"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes show "$IDX"


header "Show note (JSON)"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes show "$IDX" --json


header "Show note (bare number shorthand)"
IDX=$(find_note "CiderTest Beta")
printf 'Bare number shorthand: \`cider notes N\` is equivalent to \`cider notes show N\`.\n\n'
cmd "$CIDER" notes "$IDX"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 2: Search\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Search — literal (title + body, default)"
printf "By default, search checks **both title and body** (case-insensitive).\n\n"
cmd "$CIDER" notes search "CiderTest Beta"


header "Search — literal body content"
printf 'Finds notes where the **body** contains "pineapple".\n\n'
cmd "$CIDER" notes search "pineapple"


header "Search — JSON output"
cmd "$CIDER" notes search "CiderTest Alpha" --json


header "Search — no results"
cmd "$CIDER" notes search "xyznonexistent99"


header "Search — \`--regex\` (find email addresses)"
printf 'Pattern: \`[a-z]+@[a-z]+\\.[a-z]+\` matches email addresses in note content.\n\n'
cmd "$CIDER" notes search '[a-z]+@[a-z]+\.[a-z]+' --regex


header "Search — \`--regex\` (title pattern)"
printf 'Pattern: \`CiderTest.*Repl\` matches ReplAll1 and ReplAll2 by title.\n\n'
cmd "$CIDER" notes search 'CiderTest.*Repl' --regex


header "Search — \`--regex\` (digit pattern)"
printf 'Pattern: \`\\d{3}-\\d{4}\` finds phone numbers like 555-1234.\n\n'
cmd "$CIDER" notes search '\d{3}-\d{4}' --regex


header "Search — \`--title\` only"
printf 'Searches **only the title**, not body content.\n\n'
printf "Search for a title:\n\n"
cmd "$CIDER" notes search "CiderTest Alpha" --title
printf '\nSearch for body-only content with \`--title\` (should find nothing):\n\n'
cmd "$CIDER" notes search "pineapple" --title


header "Search — \`--body\` only"
printf 'Searches **only the body**, not the title.\n\n'
cmd "$CIDER" notes search "pineapple" --body


header "Search — \`--folder\` scoping"
printf 'Scope search to a specific folder.\n\n'
printf "Search in test folder:\n\n"
cmd "$CIDER" notes search "CiderTest" -f "$TEST_FOLDER"
printf "\nSearch in a nonexistent folder:\n\n"
cmd "$CIDER" notes search "CiderTest" -f "NonexistentFolder99"


header "Search — \`--regex\` + \`--folder\`"
printf 'Combine regex search with folder scoping.\n\n'
cmd "$CIDER" notes search 'quick.*fox' --regex -f "$TEST_FOLDER"


header "Search — \`--title\` and \`--body\` mutual exclusion"
printf 'Using both flags returns an error.\n\n'
cmd "$CIDER" notes search "test" --title --body


header "Search — invalid regex"
printf 'Malformed regex pattern returns a clear error.\n\n'
cmd "$CIDER" notes search "[invalid" --regex


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 3: Replace (Single Note)\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Replace — literal (basic find & replace)"
IDX=$(find_note "CiderTest Gamma")
section "BEFORE"
show_note "CiderTest Gamma"
section "COMMAND"
cmd "$CIDER" notes replace "$IDX" --find "editing" --replace "TESTING"
section "AFTER"
show_note "CiderTest Gamma"


header "Replace — \`--regex\` with capture groups"
IDX=$(find_note "CiderTest Regex")
printf 'Regex: \`(\\w+)@(\\w+)\` with template \`[$1 at $2]\` masks email addresses using capture group backreferences.\n\n'
section "BEFORE"
show_note "CiderTest Regex"
section "COMMAND"
cmd "$CIDER" notes replace "$IDX" --find '(\w+)@(\w+)' --replace '[$1 at $2]' --regex
section "AFTER"
show_note "CiderTest Regex"


header "Replace — \`-i\` (case-insensitive)"
IDX=$(find_note "CiderTest CaseTest")
printf 'Case-insensitive flag replaces **all case variants** (TODO, todo, TODO) with a single command.\n\n'
section "BEFORE"
show_note "CiderTest CaseTest"
section "COMMAND"
cmd "$CIDER" notes replace "$IDX" --find "todo" --replace "DONE" -i
section "AFTER"
show_note "CiderTest CaseTest"


header "Replace — \`--regex\` + \`-i\` combined"
IDX=$(find_note "CiderTest Regex")
section "BEFORE"
show_note "CiderTest Regex"
section "COMMAND"
printf 'Regex + case-insensitive: replace "phone" (matches "Phone") with "Tel".\n\n'
cmd "$CIDER" notes replace "$IDX" --find 'phone' --replace 'Tel' --regex -i
section "AFTER"
show_note "CiderTest Regex"


header "Replace — text not found (error)"
IDX=$(find_note "CiderTest Gamma")
cmd "$CIDER" notes replace "$IDX" --find "zzz_nonexistent_text" --replace "x"


header "Replace — invalid regex (error)"
IDX=$(find_note "CiderTest Gamma")
cmd "$CIDER" notes replace "$IDX" --find "[invalid" --replace "x" --regex


header "Replace — nonexistent note (error)"
cmd "$CIDER" notes replace 99999 --find "x" --replace "y"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 4: Replace --all (Multi-Note)\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Replace \`--all --dry-run\` (preview only)"
printf '`--dry-run` shows what **would** change without modifying anything.\n\n'
section "BEFORE: ReplAll1"
show_note "CiderTest ReplAll1"
section "BEFORE: ReplAll2"
show_note "CiderTest ReplAll2"
section "COMMAND"
cmd "$CIDER" notes replace --all --find "quick brown" --replace "slow grey" --folder "$TEST_FOLDER" --dry-run
section "AFTER: ReplAll1 (unchanged)"
show_note "CiderTest ReplAll1"
section "AFTER: ReplAll2 (unchanged)"
show_note "CiderTest ReplAll2"


header "Replace \`--all --folder\` (with confirmation)"
printf 'Replaces in **all matching notes** within a folder. Shows summary and requires `y/N` confirmation.\n\n'
section "BEFORE: ReplAll1"
show_note "CiderTest ReplAll1"
section "BEFORE: ReplAll2"
show_note "CiderTest ReplAll2"
section "COMMAND"
printf '```\n$ printf "y\\n" | cider notes replace --all --find "quick brown" --replace "slow grey" --folder "Cider Tests"\n'
printf 'y\n' | "$CIDER" notes replace --all --find "quick brown" --replace "slow grey" --folder "$TEST_FOLDER" 2>&1
printf '```\n'
section "AFTER: ReplAll1"
show_note "CiderTest ReplAll1"
section "AFTER: ReplAll2"
show_note "CiderTest ReplAll2"


header "Replace \`--all --regex --folder\`"
printf 'Regex replace across multiple notes. Pattern \`\\bslow\\b\` uses word boundary to match whole words only.\n\n'
section "BEFORE: ReplAll1"
show_note "CiderTest ReplAll1"
section "BEFORE: ReplAll2"
show_note "CiderTest ReplAll2"
section "COMMAND"
printf '```\n$ printf "y\\n" | cider notes replace --all --find "\\bslow\\b" --replace "fast" --regex --folder "Cider Tests"\n'
printf 'y\n' | "$CIDER" notes replace --all --find '\bslow\b' --replace 'fast' --regex --folder "$TEST_FOLDER" 2>&1
printf '```\n'
section "AFTER: ReplAll1"
show_note "CiderTest ReplAll1"
section "AFTER: ReplAll2"
show_note "CiderTest ReplAll2"


header "Replace \`--all\` — no matches"
cmd "$CIDER" notes replace --all --find "xyzNonexistent99" --replace "x" --folder "$TEST_FOLDER" --dry-run


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 5: Append / Prepend\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Append text to note"
IDX=$(find_note "CiderTest Alpha")
section "BEFORE"
show_note "CiderTest Alpha"
section "COMMAND"
cmd "$CIDER" notes append "$IDX" "This line was appended."
section "AFTER"
show_note "CiderTest Alpha"


header "Append via stdin pipe"
IDX=$(find_note "CiderTest Beta")
section "BEFORE"
show_note "CiderTest Beta"
section "COMMAND"
printf '```\n$ echo "Piped content here." | cider notes append %s\n' "$IDX"
echo "Piped content here." | "$CIDER" notes append "$IDX" 2>&1
printf '```\n'
section "AFTER"
show_note "CiderTest Beta"


header "Append \`--no-newline\`"
IDX=$(find_note "CiderTest Alpha")
section "BEFORE"
show_note "CiderTest Alpha"
section "COMMAND"
printf 'Appends without a newline separator — text is concatenated directly.\n\n'
cmd "$CIDER" notes append "$IDX" " (suffix)" --no-newline
section "AFTER"
show_note "CiderTest Alpha"


header "Prepend text after title"
IDX=$(find_note "CiderTest Gamma")
section "BEFORE"
show_note "CiderTest Gamma"
section "COMMAND"
cmd "$CIDER" notes prepend "$IDX" "Prepended after the title line."
section "AFTER"
show_note "CiderTest Gamma"


header "Prepend via stdin pipe"
IDX=$(find_note "CiderTest Gamma")
section "BEFORE"
show_note "CiderTest Gamma"
section "COMMAND"
printf '```\n$ echo "Piped prepend." | cider notes prepend %s\n' "$IDX"
echo "Piped prepend." | "$CIDER" notes prepend "$IDX" 2>&1
printf '```\n'
section "AFTER"
show_note "CiderTest Gamma"


header "Debug — dump attributed string attributes"
IDX=$(find_note "CiderTest Alpha")
printf 'Shows all NSAttributedString attribute keys and values stored in the note'\''s CRDT.\n\n'
cmd "$CIDER" notes debug "$IDX"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 6: Date Filtering & Sorting\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "List notes modified after today"
cmd "$CIDER" notes list --after today -f "$TEST_FOLDER"

header "List notes modified before 2020-01-01"
cmd "$CIDER" notes list --before "2020-01-01" -f "$TEST_FOLDER"

header "List notes sorted by modification date"
cmd "$CIDER" notes list --sort modified -f "$TEST_FOLDER"

header "List notes sorted by creation date"
cmd "$CIDER" notes list --sort created -f "$TEST_FOLDER"

header "JSON output with created/modified dates"
cmd "$CIDER" notes list --json -f "$TEST_FOLDER"

header "Date filtering with --after and --folder combined"
cmd "$CIDER" notes list --after "1 week ago" -f "$TEST_FOLDER"

header "Search with --after date filter"
cmd "$CIDER" notes search "CiderTest" --after today

header "Invalid date shows error"
cmd "$CIDER" notes list --after "not-a-date"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 7: Templates\n\n"
# ─────────────────────────────────────────────────────────────────────────────


# Create a template
printf 'CiderTest Template\nMeeting Date: \nAttendees: \n\n## Agenda\n\n## Notes\n\n## Action Items\n' | "$CIDER" notes add --folder "Cider Templates" 2>/dev/null
sleep 1

header "List templates"
cmd "$CIDER" templates list

header "Show template content"
cmd "$CIDER" templates show "CiderTest Template"

header "Create note from template"
cmd "$CIDER" notes add --template "CiderTest Template" --folder "$TEST_FOLDER"

header "Show nonexistent template (error)"
cmd "$CIDER" templates show "Nonexistent"

header "Delete template"
cmd "$CIDER" templates delete "CiderTest Template"

# Clean up template-created note
TIDX=$("$CIDER" notes list --json -f "$TEST_FOLDER" 2>/dev/null | grep -v "ERROR:" | grep -o '"index":[0-9]*,"title":"Meeting Date' | head -1 | grep -o '[0-9]*' | head -1)
if [ -n "$TIDX" ]; then
    yes y 2>/dev/null | "$CIDER" notes delete "$TIDX" 2>/dev/null || true
fi


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 8: Settings\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Show settings (initially empty)"
cmd "$CIDER" settings

header "Set a setting"
cmd "$CIDER" settings set default_sort modified

header "Set another setting"
cmd "$CIDER" settings set default_folder "Work Notes"

header "Show all settings"
cmd "$CIDER" settings

header "Get a single setting"
cmd "$CIDER" settings get default_sort

header "Settings JSON output"
cmd "$CIDER" settings --json

header "Get nonexistent key (error)"
cmd "$CIDER" settings get nonexistent_key

header "Overwrite existing setting"
cmd "$CIDER" settings set default_sort created
printf "\nVerify:\n\n"
cmd "$CIDER" settings get default_sort

header "Reset settings"
cmd "$CIDER" settings reset
printf "\nVerify:\n\n"
cmd "$CIDER" settings


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 9: Note Links / Backlinks\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Show outgoing links"
IDX=$(find_note "CiderTest Alpha")
printf 'Test notes have no >> links, so this shows the empty-links output.\n\n'
cmd "$CIDER" notes links "$IDX"

header "Show outgoing links (JSON)"
cmd "$CIDER" notes links "$IDX" --json

header "Show backlinks"
cmd "$CIDER" notes backlinks "$IDX"

header "Show backlinks (JSON)"
cmd "$CIDER" notes backlinks "$IDX" --json

header "Full link graph"
printf 'Shows all note-to-note links across all notes (including real user notes).\n\n'
cmd "$CIDER" notes backlinks --all

header "Full link graph (JSON)"
cmd "$CIDER" notes backlinks --all --json


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 10: Watch / Events\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Watch for note changes (2 second sample)"
printf 'Starts watch, creates a note, then stops. Shows the change event.\n\n'
printf '```\n$ cider notes watch --interval 1 &\n'
"$CIDER" notes watch --interval 1 > /tmp/cider_report_watch_$$.txt 2>&1 &
WATCH_PID=$!
sleep 2
# Create a note to trigger an event
printf '%s\n%s' "CiderTest WatchNote" "Created during watch test." | "$CIDER" notes add --folder "$TEST_FOLDER" 2>/dev/null
sleep 2
kill $WATCH_PID 2>/dev/null || true
wait $WATCH_PID 2>/dev/null || true
cat /tmp/cider_report_watch_$$.txt
printf '```\n'
rm -f /tmp/cider_report_watch_$$.txt
delete_note "CiderTest WatchNote"

header "Watch with JSON output"
printf '```\n$ cider notes watch --interval 1 --json (2 second sample)\n'
"$CIDER" notes watch --interval 1 --json > /tmp/cider_report_watch2_$$.txt 2>&1 &
WATCH_PID=$!
sleep 3
kill $WATCH_PID 2>/dev/null || true
wait $WATCH_PID 2>/dev/null || true
cat /tmp/cider_report_watch2_$$.txt
printf '```\n'
rm -f /tmp/cider_report_watch2_$$.txt

header "Watch with --folder filter"
printf '```\n$ cider notes watch --interval 1 -f "Cider Tests" (header only)\n'
"$CIDER" notes watch --interval 1 -f "$TEST_FOLDER" > /tmp/cider_report_watch3_$$.txt 2>&1 &
WATCH_PID=$!
sleep 2
kill $WATCH_PID 2>/dev/null || true
wait $WATCH_PID 2>/dev/null || true
cat /tmp/cider_report_watch3_$$.txt
printf '```\n'
rm -f /tmp/cider_report_watch3_$$.txt


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 11: Checklists\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Checklist items on test note (no checklists)"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes checklist "$IDX"


header "Checklist --json on empty note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes checklist "$IDX" --json


header "Checklist --summary on empty note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes checklist "$IDX" --summary


header "Check on nonexistent note"
cmd "$CIDER" notes check 99999 1


header "Uncheck on nonexistent note"
cmd "$CIDER" notes uncheck 99999 1


header "Check on note without checklists"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes check "$IDX" 1


header "Missing item number"
cmd "$CIDER" notes check 1


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 12: Tables\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Table on note without tables"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes table "$IDX"


header "Table --list on empty note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes table "$IDX" --list


header "Table --json on empty note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes table "$IDX" --json


header "Table on nonexistent note"
cmd "$CIDER" notes table 99999


header "Table --headers on empty note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes table "$IDX" --headers


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 13: Sharing\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Share status on unshared note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes share "$IDX"


header "Share status --json"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes share "$IDX" --json


header "List shared notes"
cmd "$CIDER" notes shared


header "List shared notes --json (first 3)"
printf '```\n'
"$CIDER" notes shared --json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(json.dumps(d[:3],indent=2))" 2>/dev/null || "$CIDER" notes shared --json 2>/dev/null | head -c 500
printf '\n```\n'
((CASE++))


header "Share status on nonexistent note"
cmd "$CIDER" notes share 99999


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 14: Folder Management\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Create a folder"
cmd "$CIDER" notes folder create "CiderTest Subfolder"

header "Create duplicate folder"
cmd "$CIDER" notes folder create "CiderTest Subfolder"

header "Rename folder"
cmd "$CIDER" notes folder rename "CiderTest Subfolder" "CiderTest Renamed"

header "List folders (shows renamed)"
cmd "$CIDER" notes folders

header "Delete empty folder"
cmd "$CIDER" notes folder delete "CiderTest Renamed"

header "Delete non-empty folder (error)"
cmd "$CIDER" notes folder delete "$TEST_FOLDER"

header "Delete nonexistent folder (error)"
cmd "$CIDER" notes folder delete "NonexistentFolder99"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 15: Tags\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Add a tag"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes tag "$IDX" "project-x"

header "Show note with tag"
cmd "$CIDER" notes show "$IDX"

header "Duplicate tag detection"
cmd "$CIDER" notes tag "$IDX" "project-x"

header "Add second tag"
cmd "$CIDER" notes tag "$IDX" "important"

header "List all tags"
cmd "$CIDER" notes tags

header "Tags with counts"
cmd "$CIDER" notes tags --count

header "Tags JSON output"
cmd "$CIDER" notes tags --json

header "Filter notes by tag"
cmd "$CIDER" notes list --tag project-x

header "Remove a tag"
cmd "$CIDER" notes untag "$IDX" "project-x"
section "AFTER"
show_note "CiderTest Alpha"

header "Remove nonexistent tag"
cmd "$CIDER" notes untag "$IDX" "nonexistent"

# Clean up remaining tag
"$CIDER" notes untag "$IDX" "important" 2>/dev/null || true


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 16: Pin / Unpin\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Pin a note"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes pin "$IDX"

header "Pin already-pinned note"
cmd "$CIDER" notes pin "$IDX"

header "List pinned notes"
cmd "$CIDER" notes list --pinned

header "Unpin a note"
cmd "$CIDER" notes unpin "$IDX"

header "Unpin non-pinned note"
cmd "$CIDER" notes unpin "$IDX"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 17: Edit (CRDT)\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Edit via stdin pipe"
IDX=$(find_note "CiderTest Gamma")
section "BEFORE"
show_note "CiderTest Gamma"
section "COMMAND"
printf '```\n$ echo "CiderTest Gamma\nGamma note fully rewritten via stdin pipe." | cider notes edit %s\n' "$IDX"
printf 'CiderTest Gamma\nGamma note fully rewritten via stdin pipe.' | "$CIDER" notes edit "$IDX" 2>&1
printf '```\n'
section "AFTER"
show_note "CiderTest Gamma"


header "Add note via stdin pipe"
section "BEFORE"
cmd "$CIDER" notes search "CiderTest Piped"
section "COMMAND"
printf '```\n$ echo "CiderTest Piped\nThis note was created from a pipe." | cider notes add --folder "Cider Tests"\n'
printf 'CiderTest Piped\nThis note was created from a pipe.' | "$CIDER" notes add --folder "$TEST_FOLDER" 2>&1
printf '```\n'
sleep 1
section "AFTER"
cmd "$CIDER" notes search "CiderTest Piped"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 18: Attachments\n\n"
# ─────────────────────────────────────────────────────────────────────────────


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
section "BEFORE"
cmd "$CIDER" notes attachments "$IDX"
section "COMMAND"
cmd "$CIDER" notes detach "$IDX" 1
section "AFTER"
cmd "$CIDER" notes attachments "$IDX"


header "Attach at specific CRDT position"
IDX=$(find_note "CiderTest Attach")
echo "positional test" > /tmp/cider_report_pos.txt
section "COMMAND"
cmd "$CIDER" notes attach "$IDX" /tmp/cider_report_pos.txt --at 5
sleep 1
section "AFTER (JSON — note position field)"
cmd "$CIDER" notes attachments "$IDX" --json
printf "\nCleanup:\n\n"
cmd "$CIDER" notes detach "$IDX" 1

rm -f /tmp/cider_report_attach.txt /tmp/cider_report_pos.txt


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 19: Move\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Move note to different folder"
IDX=$(find_note "CiderTest Beta")
section "BEFORE"
printf '```\n'
"$CIDER" notes show "$IDX" --json 2>/dev/null | grep -o '"folder":"[^"]*"'
printf '```\n'
section "COMMAND"
cmd "$CIDER" notes move "$IDX" Notes
sleep 1
IDX2=$(find_note "CiderTest Beta")
if [ -n "$IDX2" ]; then
    section "AFTER"
    printf '```\n'
    "$CIDER" notes show "$IDX2" --json 2>/dev/null | grep -o '"folder":"[^"]*"'
    printf '```\n'
    printf "\nCleanup — move back:\n\n"
    cmd "$CIDER" notes move "$IDX2" "$TEST_FOLDER"
    sleep 1
fi


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 20: Delete\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Delete note"
IDX=$(find_note "CiderTest Delta")
section "BEFORE"
cmd "$CIDER" notes search "CiderTest Delta"
section "COMMAND"
printf '```\n$ printf "y\\n" | cider notes delete %s\n' "$IDX"
printf 'y\n' | "$CIDER" notes delete "$IDX" 2>&1
printf '```\n'
sleep 1
section "AFTER"
cmd "$CIDER" notes search "CiderTest Delta"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 21: Export\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Export all notes to HTML"
EXPORT_DIR="/tmp/cider_report_export_$$"
cmd "$CIDER" notes export "$EXPORT_DIR"
printf "\nFiles created:\n\n"
printf '```\n'
printf "%s HTML files exported\n" "$(ls "$EXPORT_DIR"/*.html 2>/dev/null | wc -l | tr -d ' ')"
printf "Sample files:\n"
ls "$EXPORT_DIR"/*.html 2>/dev/null | head -5
printf '```\n'
rm -rf "$EXPORT_DIR"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 22: Error Handling\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Show nonexistent note"
cmd "$CIDER" notes show 99999

header "Replace in nonexistent note"
cmd "$CIDER" notes replace 99999 --find "x" --replace "y"

header "Detach from nonexistent note"
cmd "$CIDER" notes detach 99999 1

header "Attach nonexistent file"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes attach "$IDX" /nonexistent/file.txt

header "Unknown command"
cmd "$CIDER" bogus

header "Unknown notes subcommand"
cmd "$CIDER" notes bogus

header "Missing replace arguments"
cmd "$CIDER" notes replace 1 --find "x"


# ─────────────────────────────────────────────────────────────────────────────
printf "\n---\n\n## Section 23: Backward Compatibility\n\n"
# ─────────────────────────────────────────────────────────────────────────────


header "Legacy \`-fl\` (folders)"
cmd "$CIDER" notes -fl

header "Legacy \`-v\` (view)"
IDX=$(find_note "CiderTest Alpha")
cmd "$CIDER" notes -v "$IDX"

header "Legacy \`-s\` (search)"
cmd "$CIDER" notes -s "CiderTest Beta"

header "Legacy \`-f\` (folder filter)"
cmd "$CIDER" notes -f "$TEST_FOLDER"


# ─────────────────────────────────────────────────────────────────────────────
# CLEANUP
# ─────────────────────────────────────────────────────────────────────────────

for t in "CiderTest Alpha" "CiderTest Beta" "CiderTest Gamma" \
         "CiderTest Delta" "CiderTest Attach" "CiderTest Regex" \
         "CiderTest ReplAll1" "CiderTest ReplAll2" "CiderTest CaseTest" \
         "CiderTest Piped" "Piped note content here"; do
    delete_note "$t"
done

printf "\n---\n\n"
printf "*Report complete — %d test cases demonstrated. All test notes cleaned up.*\n" "$CASE"
