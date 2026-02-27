Delete note "CiderTest Alpha"? (y/N) Deleted: "CiderTest Alpha"
Delete note "CiderTest Beta"? (y/N) Deleted: "CiderTest Beta"
Delete note "CiderTest Gamma"? (y/N) Deleted: "CiderTest Gamma"
Delete note "CiderTest Attach"? (y/N) Deleted: "CiderTest Attach"
Delete note "CiderTest Regex"? (y/N) Deleted: "CiderTest Regex"
Delete note "CiderTest ReplAll1"? (y/N) Deleted: "CiderTest ReplAll1"
Delete note "CiderTest ReplAll2"? (y/N) Deleted: "CiderTest ReplAll2"
Delete note "Piped note content here"? (y/N) Deleted: "Piped note content here"
# Cider v3.16.0 — Test Report

> Generated: 2026-02-26 20:25:07
>
> This report shows **before and after** state for every cider operation,
> demonstrating how each command works with real Apple Notes data.
> All test notes are created in a "Cider Tests" folder and cleaned up afterwards.

---

## Section 1: Basic Operations


### Test 01: Version

```
$ ./cider --version
cider v3.16.0
```

### Test 02: Help (top-level)

```
$ ./cider --help
cider v3.16.0 — Apple Notes CLI with CRDT attachment support

USAGE:
  cider notes [subcommand]   Notes operations
  cider templates [sub]      Template management
  cider settings [sub]       Cider configuration
  cider rem [subcommand]     Reminders operations
  cider sync [subcommand]    Bidirectional Notes <-> Markdown sync
  cider --version            Show version
  cider --help               Show this help

NOTES SUBCOMMANDS:
  list [-f <folder>] [--json] [--after <date>] [--before <date>] [--sort <mode>]
       [--pinned]                      List notes (default when no subcommand)
  show <N> [--json]                   View note N  (also: cider notes <N>)
  folders [--json]                    List all folders
  add [--folder <f>] [--template <t>] Add note (stdin, $EDITOR, or template)
  edit <N>                            Edit note N (CRDT — preserves attachments!)
  delete <N>                          Delete note N
  move <N> <folder>                   Move note N to folder
  pin <N>                             Pin note N
  unpin <N>                           Unpin note N
  tag <N> <tag>                       Add #tag to note N
  untag <N> <tag>                     Remove #tag from note N
  tags [--count] [--json]             List all unique tags
  share <N> [--json]                 Show sharing status for note N
  shared [--json]                    List all shared notes
  table <N> [options]                Show table data (aligned, CSV, JSON)
  checklist <N> [--summary] [--json] Show checklist items with status
  check <N> <item#>                 Check off checklist item
  uncheck <N> <item#>               Uncheck checklist item
  watch [options]                    Stream note change events
  links <N> [--json]                 Show outgoing note links
  backlinks <N> [--json]             Show notes linking to note N
  backlinks --all [--json]           Full link graph
  link <N> <target title>            Create link to another note
  folder create <name> [--parent <p>] Create a new folder
  folder delete <name>                Delete empty folder
  folder rename <old> <new>           Rename folder
  replace <N> --find <s> --replace <s> [--regex] [-i]
                                       Find & replace in note N (full content)
  replace --all --find <s> --replace <s> [--folder <f>] [--regex] [-i] [--dry-run]
                                       Find & replace across multiple notes
  append <N> <text> [--no-newline] [-f <folder>]
                                       Append text to end of note N
  prepend <N> <text> [--no-newline] [-f <folder>]
                                       Insert text after title of note N
  search <query> [--json] [--regex] [--title] [--body] [-f <folder>]
                                       Search notes (title + body by default)
  export <path>                       Export all notes to HTML
  attachments <N> [--json]             List attachments in note N
  attach <N> <file> [--at <pos>]      Add file attachment to note N
  detach <N> [<A>]                    Remove attachment A (1-based) from note N

REMINDERS SUBCOMMANDS:
  list                               List incomplete reminders (default)
  add <title> [due-date]             Add reminder
  edit <N> <new-title>               Edit reminder N
  delete <N>                         Delete reminder N
  complete <N>                       Complete reminder N

SYNC SUBCOMMANDS:
  run [--dir <path>]                 One sync cycle (auto-inits on first run)
  watch [--dir <path>] [--interval N] Continuous sync daemon (default: 2s)
  backup [--dir <path>]              Backup Notes database

  Sync mirrors Notes to local Markdown files with YAML frontmatter.
  New .md files create Apple Notes; edits to owned notes sync back.
  Pre-existing notes are NEVER modified or deleted (editable: false).
  Default sync dir: ~/CiderSync. Run 'cider sync --help' for details.

  Examples:
    cider sync run                        First run: backup + export all notes
    cider sync run --dir ~/my-notes       Sync to a custom directory
    cider sync watch                      Continuous sync (polls every 2s)
    cider sync watch --interval 10        Poll every 10 seconds
    cider sync backup                     Manual backup of Notes database

SETTINGS:
  cider settings                     Show current settings
  cider settings get <key>           Get a single setting
  cider settings set <key> <value>   Set a setting
  cider settings reset               Reset all settings
  cider settings --json              JSON output

  Settings are stored in a "Cider Settings" note. Available keys:
    default_folder    Default folder for new notes
    default_sort      Default sort order (title|modified|created)
    editor            Preferred editor ($EDITOR override)

  Examples:
    cider settings set default_folder "Work Notes"
    cider settings set default_sort modified
    cider settings get default_folder

BACKWARDS COMPAT (old flags still work):
  cider notes -fl             →  cider notes folders
  cider notes -v N            →  cider notes show N
  cider notes -e N            →  cider notes edit N
  cider notes -d N            →  cider notes delete N
  cider notes -s query        →  cider notes search query
  cider notes --attach N file →  cider notes attach N file
  cider notes --export path   →  cider notes export path

CRDT EDIT:
  'edit' opens the note in $EDITOR with %ATTACHMENT_N_name%
  markers where images/files are. Edit the text freely; do NOT remove
  or rename the markers. Changes are applied via ICTTMergeableString.
  Pipe content instead: echo 'new body' | cider notes edit N
```

### Test 03: Notes help

Shows the full search/replace documentation with all flags and examples.

```
$ ./cider notes --help
cider notes v3.16.0 — Apple Notes CLI

USAGE:
  cider notes                              List all notes
  cider notes list [options]               List notes (filter, sort, date range)
  cider notes <N>                          View note N
  cider notes show <N> [--json]            View note N
  cider notes folders [--json]             List all folders
  cider notes add [--folder <f>]           Add note (reads stdin or $EDITOR)
  cider notes edit <N>                     Edit note N via CRDT (preserves attachments)
                                           Pipe: echo 'content' | cider notes edit N
  cider notes delete <N>                   Delete note N
  cider notes move <N> <folder>            Move note N to folder
  cider notes export <path>                Export notes to HTML
  cider notes attachments <N> [--json]     List attachments with positions
  cider notes attach <N> <file> [--at <pos>]  Attach file at position (CRDT)
  cider notes detach <N> [<A>]             Remove attachment A from note N

APPEND / PREPEND:
  cider notes append <N> <text> [options]
  cider notes prepend <N> <text> [options]

  Append adds text to the end of the note. Prepend inserts text right
  after the title line. Both support stdin piping.

  --no-newline     Don't add newline separator
  -f, --folder <f> Scope note index to folder

  Examples:
    cider notes append 3 "Added at the bottom"
    cider notes prepend 3 "Inserted after title"
    echo "piped text" | cider notes append 3
    cider notes append 3 "no gap" --no-newline
    cider notes prepend 3 "text" -f "Work Notes"

TEMPLATES:
  cider templates list                    List templates
  cider templates show <name>             View template content
  cider templates add                     Create new template ($EDITOR)
  cider templates delete <name>           Delete template
  cider notes add --template <name>       Create note from template

  Templates are stored as notes in the "Cider Templates" folder.
  When creating from a template, the body is pre-filled in $EDITOR.

  Examples:
    cider templates add                   Create a template in $EDITOR
    cider templates list                  List all templates
    cider templates show "Meeting Notes"  View template content
    cider notes add --template "Meeting Notes"  Create note from template
    cider notes add --template "TODO" -f Work   Template + target folder

SHARING:
  cider notes share <N>                     Show sharing status for note N
  cider notes share <N> --json              JSON share status
  cider notes shared                        List all shared notes
  cider notes shared --json                 JSON list of shared notes

  Shows iCloud collaboration status and participant count.
  Share URLs are not programmatically accessible; use Apple Notes
  Share button to create/manage collaboration links.

  Examples:
    cider notes share 5                     Show share status for note 5
    cider notes shared                      List all shared notes
    cider notes shared --json               JSON output for piping

TABLES:
  cider notes table <N>                     Show first table (aligned columns)
  cider notes table <N> --list              List all tables with row/col counts
  cider notes table <N> --index 1           Show second table (0-based)
  cider notes table <N> --json              Table as JSON array of objects
  cider notes table <N> --csv               Table as CSV
  cider notes table <N> --row 2             Specific row (0-based)
  cider notes table <N> --headers           Column headers only

  Reads native Apple Notes tables (com.apple.notes.table attachments).
  Uses ICAttachmentTableModel and ICTable to access row/column data.
  Row 0 is treated as the header row for JSON key names.

  Examples:
    cider notes table 5                     Show first table, aligned
    cider notes table 5 --list              List tables in note 5
    cider notes table 5 --json              JSON array of {header: value}
    cider notes table 5 --csv               CSV output
    cider notes table 5 --row 0             First row (headers)
    cider notes table 5 --index 1 --csv     Second table as CSV
    cider notes table 5 --headers           Column headers only

CHECKLISTS:
  cider notes checklist <N>                 Show checklist items with status
  cider notes checklist <N> --summary       Summary only (e.g. "3/6 complete")
  cider notes checklist <N> --json          JSON output
  cider notes checklist <N> --add "text"    Add a new checklist item
  cider notes check <N> <item#>             Check off item by number
  cider notes uncheck <N> <item#>           Uncheck item by number

  Reads native Apple Notes checklist formatting (style 103 paragraphs).
  Items are numbered sequentially (1-based). Check/uncheck toggles
  the done state via the CRDT attributed string.

  Examples:
    cider notes checklist 5                Show all items with [x]/[ ] status
    cider notes checklist 5 --summary      "3/6 items complete"
    cider notes check 5 2                  Check off item 2
    cider notes uncheck 5 2                Uncheck item 2
    cider notes checklist 5 --add "Buy milk"  Add new item
    cider notes checklist 5 --json         JSON with items array

WATCH / EVENTS:
  cider notes watch                          Stream note change events
  cider notes watch --folder <f>             Watch specific folder
  cider notes watch --interval 5             Poll interval (default 2s)
  cider notes watch --json                   JSON event stream for AI piping

  Polls for note changes and streams events: created, modified, deleted.
  Reads watch_interval from Cider Settings if no --interval flag.

  Examples:
    cider notes watch                        Watch all notes (2s poll)
    cider notes watch -f "Work Notes"         Watch specific folder
    cider notes watch --interval 10           Poll every 10 seconds
    cider notes watch --json                  JSON events for piping
    cider notes watch --json | while read e; do echo "$e" | jq; done

NOTE LINKS / BACKLINKS:
  cider notes links <N> [--json]             Show outgoing note links
  cider notes backlinks <N> [--json]         Show notes linking to note N
  cider notes backlinks --all [--json]       Full link graph
  cider notes link <N> <target title>       Create link to another note

  Links use Apple Notes native inline attachments (same as >> syntax).
  Cider can both create and read note-to-note links.

  Examples:
    cider notes links 5                Show what note 5 links to
    cider notes backlinks 5            Show notes that link to note 5
    cider notes backlinks --all        Full link graph across all notes
    cider notes link 5 Meeting Notes   Link note 5 to "Meeting Notes"
    cider notes links 5 --json         JSON output

FOLDER MANAGEMENT:
  cider notes folder create <name>           Create a new folder
  cider notes folder create <name> --parent <p>  Nested folder
  cider notes folder delete <name>           Delete empty folder
  cider notes folder rename <old> <new>      Rename folder

  Delete requires the folder to be empty (move/delete notes first).
  Rename checks that the new name doesn't already exist.

  Examples:
    cider notes folder create "Work Notes"
    cider notes folder create "Meetings" --parent "Work Notes"
    cider notes folder delete "Old Stuff"
    cider notes folder rename "Work" "Work Notes"

TAGS:
  cider notes tag <N> <tag>           Add #tag to end of note
  cider notes untag <N> <tag>         Remove all occurrences of #tag
  cider notes tags [--count] [--json] List all unique tags across all notes
  cider notes list --tag <tag>        Filter notes containing #tag
  cider notes search <q> --tag <tag>  Combine search + tag filter

  Tags are #word patterns in note text (Apple Notes native hashtags).
  Auto-prepends # if omitted. Case-insensitive matching.

  Examples:
    cider notes tag 3 "project-x"         Add #project-x to note 3
    cider notes untag 3 "#project-x"      Remove #project-x from note 3
    cider notes tags --count              Show tags with note counts
    cider notes list --tag project-x      List notes with #project-x
    cider notes search "meeting" --tag work  Search + tag filter

PIN / UNPIN:
  cider notes pin <N> [-f <folder>]
  cider notes unpin <N> [-f <folder>]

  Pin or unpin a note. Pinned notes appear at the top in Apple Notes.
  Use --pinned with list to show only pinned notes.

  Examples:
    cider notes pin 3
    cider notes unpin 3
    cider notes list --pinned
    cider notes pin 1 -f Work

DEBUG:
  cider notes debug <N> [-f <folder>]

  Dumps all attributed string attribute keys and values for a note.
  Useful for discovering how Apple Notes stores checklists, tables,
  links, and other rich formatting internally.

LIST (date filtering & sorting):
  cider notes list [options]

  --after <date>              Notes modified after date
  --before <date>             Notes modified before date
  --sort created|modified|title  Sort order (default: title)
  --pinned                   Show only pinned notes
  --tag <tag>                Filter notes containing #tag
  -f, --folder <f>           Filter by folder
  --json                     JSON output (includes created/modified dates)

  Date formats:
    ISO 8601:   2024-01-15, 2024-01-15T10:30:00
    Relative:   today, yesterday, "3 days ago", "1 week ago", "2 months ago"

  Examples:
    cider notes list --after today
    cider notes list --before 2024-06-01
    cider notes list --after yesterday --sort modified
    cider notes list --sort created --json
    cider notes list --after "1 week ago" -f Work
    cider notes search "meeting" --after today

SEARCH:
  cider notes search <query> [options]

  Searches note title AND body by default (case-insensitive).

  --regex          Treat query as ICU regular expression
  --title          Search title only (mutually exclusive with --body)
  --body           Search body only (mutually exclusive with --title)
  -f, --folder <f> Scope search to a specific folder
  --after <date>   Only notes modified after date
  --before <date>  Only notes modified before date
  --json           Output results as JSON

  Examples:
    cider notes search "meeting"                  Literal search (title + body)
    cider notes search "\\d{3}-\\d{4}" --regex     Find phone numbers
    cider notes search "TODO" --title              Search titles only
    cider notes search "important" --body -f Work  Search body in Work folder
    cider notes search "meeting" --after today     Search with date filter

REPLACE (single note):
  cider notes replace <N> --find <s> --replace <s> [options]

  Replaces text in the full content (title is the first line) of note N.
  Operates on a single note. Attachments are never touched.

  --regex          Treat --find as ICU regex; --replace supports $1, $2 backrefs
  -i, --case-insensitive   Case-insensitive matching

  Examples:
    cider notes replace 3 --find old --replace new
    cider notes replace 3 --find "(\\w+)@(\\w+)" --replace "[$1 at $2]" --regex
    cider notes replace 3 --find "todo" --replace "DONE" -i

REPLACE (multiple notes):
  cider notes replace --all --find <s> --replace <s> [options]

  Replaces across ALL notes (or folder-scoped). Shows a summary and asks
  for confirmation before applying. Skips notes where attachments would change.

  --all             Required: enables multi-note mode
  --folder <f>, -f  Scope to a specific folder
  --dry-run         Preview changes without applying
  --regex           ICU regex (--replace supports $1, $2)
  -i, --case-insensitive   Case-insensitive matching

  Examples:
    cider notes replace --all --find old --replace new --dry-run
    cider notes replace --all --find old --replace new -f Work
    cider notes replace --all --find "http://" --replace "https://" --folder Work

OPTIONS:
  --json    Output as JSON (for list, show, search, folders)
  -f, --folder <name>   Filter by folder (for list, search, replace --all)

Interactive mode: if <N> is omitted from edit/delete/move/show/replace/attach,
you'll be prompted to enter it (when stdin is a terminal).
```

### Test 04: Create test notes


**BEFORE: Notes in test folder**

```
$ ./cider notes list -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 Untag Test                                 Cider Tests            
  2 CiderTest Prepend                          Cider Tests            
  3 CiderTest Append                           Cider Tests            
  4 Live Refresh Test                          Cider Tests            
  5 AS Created Note                            Cider Tests            
  6 Serialize Test                             Cider Tests            
  7 New Note                                   Cider Tests            
  8 New Note                                   Cider Tests            
  9 New Note                                   Cider Tests            
 10 New Note                                   Cider Tests            

Total: 10 note(s)
```

**COMMAND: Create 9 test notes via stdin pipe**

```
Created note: "CiderTest Alpha"
Created note: "CiderTest Beta"
Created note: "CiderTest Gamma"
Created note: "CiderTest Delta"
Created note: "CiderTest Attach"
Created note: "CiderTest Regex"
Created note: "CiderTest ReplAll1"
Created note: "CiderTest ReplAll2"
Created note: "CiderTest CaseTest"
```

**AFTER: Notes in test folder**

```
$ ./cider notes list -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest CaseTest                         Cider Tests            
  2 CiderTest ReplAll2                         Cider Tests            
  3 CiderTest ReplAll1                         Cider Tests            
  4 CiderTest Regex                            Cider Tests            
  5 CiderTest Attach                           Cider Tests            
  6 CiderTest Delta                            Cider Tests            
  7 CiderTest Gamma                            Cider Tests            
  8 CiderTest Beta                             Cider Tests            
  9 CiderTest Alpha                            Cider Tests            
 10 Untag Test                                 Cider Tests            
 11 CiderTest Prepend                          Cider Tests            
 12 CiderTest Append                           Cider Tests            
 13 Live Refresh Test                          Cider Tests            
 14 AS Created Note                            Cider Tests            
 15 Serialize Test                             Cider Tests            
 16 New Note                                   Cider Tests            
 17 New Note                                   Cider Tests            
 18 New Note                                   Cider Tests            
 19 New Note                                   Cider Tests            

Total: 19 note(s)
```

### Test 05: List notes (JSON)

```
$ ./cider notes list -f Cider Tests --json
[
  {"index":1,"title":"CiderTest CaseTest","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":2,"title":"CiderTest ReplAll2","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":3,"title":"CiderTest ReplAll1","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":4,"title":"CiderTest Regex","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":5,"title":"CiderTest Attach","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":6,"title":"CiderTest Delta","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":7,"title":"CiderTest Gamma","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":8,"title":"CiderTest Beta","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":9,"title":"CiderTest Alpha","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":10,"title":"Untag Test","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:23:21Z","modified":"2026-02-27T01:23:21Z"},
  {"index":11,"title":"CiderTest Prepend","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:19:55Z","modified":"2026-02-27T01:19:55Z"},
  {"index":12,"title":"CiderTest Append","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:19:55Z","modified":"2026-02-27T01:19:55Z"},
  {"index":13,"title":"Live Refresh Test","folder":"Cider Tests","attachments":0,"created":"2026-02-19T11:24:58Z","modified":"2026-02-19T11:24:58Z"},
  {"index":14,"title":"AS Created Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T11:21:34Z","modified":"2026-02-19T11:21:34Z"},
  {"index":15,"title":"Serialize Test","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:58:40Z","modified":"2026-02-19T10:58:40Z"},
  {"index":16,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:56:43Z","modified":"2026-02-19T10:56:43Z"},
  {"index":17,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:55:31Z","modified":"2026-02-19T10:55:31Z"},
  {"index":18,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:53:59Z","modified":"2026-02-19T10:53:59Z"},
  {"index":19,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:47:51Z","modified":"2026-02-19T10:47:51Z"}
]
```

### Test 06: List folders

```
$ ./cider notes folders
Folders:
  Agendas
  Archive
  Art
  Cider Templates
  Cider Tests
  CiderSync Tests
  CiderSync_Tests
  Documents
  Drafts
  Finance
  Gg
  Gifts
  Groceries
  Health
  Hobbies
  Home
  Ideas
  Misc
  New Smart Folder
  Notes
  Passwords
  Phone Numbers
  Places
  Recently Deleted
  Recipes
  Relationship
  TODO
  Wedding
  Work

Total: 29 folder(s)
```

### Test 07: List folders (JSON)

```
$ ./cider notes folders --json
[
  {"name":"Agendas","parent":""},
  {"name":"Archive","parent":""},
  {"name":"Art","parent":""},
  {"name":"Cider Templates","parent":""},
  {"name":"Cider Tests","parent":""},
  {"name":"CiderSync Tests","parent":""},
  {"name":"CiderSync_Tests","parent":""},
  {"name":"Documents","parent":""},
  {"name":"Drafts","parent":""},
  {"name":"Finance","parent":""},
  {"name":"Gg","parent":""},
  {"name":"Gifts","parent":""},
  {"name":"Groceries","parent":""},
  {"name":"Health","parent":""},
  {"name":"Hobbies","parent":""},
  {"name":"Home","parent":""},
  {"name":"Ideas","parent":""},
  {"name":"Misc","parent":""},
  {"name":"New Smart Folder","parent":""},
  {"name":"Notes","parent":""},
  {"name":"Passwords","parent":""},
  {"name":"Phone Numbers","parent":""},
  {"name":"Places","parent":""},
  {"name":"Recently Deleted","parent":""},
  {"name":"Recipes","parent":""},
  {"name":"Relationship","parent":""},
  {"name":"TODO","parent":""},
  {"name":"Wedding","parent":""},
  {"name":"Work","parent":""}
]
```

### Test 08: Show note by index

```
$ ./cider notes show 9
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
```

### Test 09: Show note (JSON)

```
$ ./cider notes show 9 --json
{"index":9,"title":"CiderTest Alpha","folder":"Cider Tests","attachments":0,"attachment_names":[],"body":"CiderTest Alpha\nThis is the alpha note with some searchable content."}
```

### Test 10: Show note (bare number shorthand)

Bare number shorthand: \`cider notes N\` is equivalent to \`cider notes show N\`.

```
$ ./cider notes 8
╔══════════════════════════════════════════╗
  CiderTest Beta
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Beta
Beta note body. Contains the word pineapple.
```

---

## Section 2: Search


### Test 11: Search — literal (title + body, default)

By default, search checks **both title and body** (case-insensitive).

```
$ ./cider notes search CiderTest Beta
Found 1 note(s) matching "CiderTest Beta":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Beta                             Cider Tests           
```

### Test 12: Search — literal body content

Finds notes where the **body** contains "pineapple".

```
$ ./cider notes search pineapple
Found 1 note(s) matching "pineapple":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Beta                             Cider Tests           
```

### Test 13: Search — JSON output

```
$ ./cider notes search CiderTest Alpha --json
[
  {"index":1,"title":"CiderTest Alpha","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"}
]
```

### Test 14: Search — no results

```
$ ./cider notes search xyznonexistent99
No notes found matching "xyznonexistent99"
```

### Test 15: Search — `--regex` (find email addresses)

Pattern: \`[a-z]+@[a-z]+\.[a-z]+\` matches email addresses in note content.

```
$ ./cider notes search [a-z]+@[a-z]+\.[a-z]+ --regex
Found 10 note(s) matching "[a-z]+@[a-z]+\.[a-z]+":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Regex                            Cider Tests           
  2 Aptive                                     Home                  
  3 Service@ngic.com                           Finance               
  4 Suits still need                           Notes                 
  5 Kitchen                                    Notes                 
  6 Reporting neighbor                         Notes                 
  7 Call Sam                                   Home                  
  8 piazzini_juri@lilly.com                    Work                  
  9 Mailing address medical bills: po box 51.. Finance               
 10 3178088590                                 Phone Numbers         
```

### Test 16: Search — `--regex` (title pattern)

Pattern: \`CiderTest.*Repl\` matches ReplAll1 and ReplAll2 by title.

```
$ ./cider notes search CiderTest.*Repl --regex
Found 2 note(s) matching "CiderTest.*Repl":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest ReplAll2                         Cider Tests           
  2 CiderTest ReplAll1                         Cider Tests           
```

### Test 17: Search — `--regex` (digit pattern)

Pattern: \`\d{3}-\d{4}\` finds phone numbers like 555-1234.

```
$ ./cider notes search \d{3}-\d{4} --regex
Found 18 note(s) matching "\d{3}-\d{4}":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Regex                            Cider Tests           
  2 FTIS                                       Work                  
  3 060564059-0001                             Misc                  
  4 Islamorada Recs                            Places                
  5 Florida Keys Babymoon                      Places                
  6 Homebridge nest                            Hobbies               
  7 Budget planning-old                        Finance               
  8 https://www.etsy.com/listing/1806420277/.. Gifts                 
  9 NYC 2023                                   Notes                 
 10 ARYN'S AUSTIN TRIP                         Notes                 
 11 New Note                                   Places                
 12 Mortgage info                              Home                  
 13 Aryn b day                                 Relationship          
 14 FLOORING                                   Home                  
 15 Elements                                   Finance               
 16 PSA. There is free INDOT provided roadsi.. Phone Numbers         
 17 IS7802M-373-50                             Work                  
 18 Xmas list                                  Gifts                 
```

### Test 18: Search — `--title` only

Searches **only the title**, not body content.

Search for a title:

```
$ ./cider notes search CiderTest Alpha --title
Found 1 note(s) matching "CiderTest Alpha":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Alpha                            Cider Tests           
```

Search for body-only content with \`--title\` (should find nothing):

```
$ ./cider notes search pineapple --title
No notes found matching "pineapple"
```

### Test 19: Search — `--body` only

Searches **only the body**, not the title.

```
$ ./cider notes search pineapple --body
Found 3 note(s) matching "pineapple":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Beta                             Cider Tests           
  2 ARYN'S BLOOD SUGAR                         Art                   
  3 Meals                                      Groceries             
```

### Test 20: Search — `--folder` scoping

Scope search to a specific folder.

Search in test folder:

```
$ ./cider notes search CiderTest -f Cider Tests
Found 11 note(s) matching "CiderTest":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest CaseTest                         Cider Tests           
  2 CiderTest ReplAll2                         Cider Tests           
  3 CiderTest ReplAll1                         Cider Tests           
  4 CiderTest Regex                            Cider Tests           
  5 CiderTest Attach                           Cider Tests           
  6 CiderTest Delta                            Cider Tests           
  7 CiderTest Gamma                            Cider Tests           
  8 CiderTest Beta                             Cider Tests           
  9 CiderTest Alpha                            Cider Tests           
 10 CiderTest Prepend                          Cider Tests           
 11 CiderTest Append                           Cider Tests           
```

Search in a nonexistent folder:

```
$ ./cider notes search CiderTest -f NonexistentFolder99
No notes found matching "CiderTest"
```

### Test 21: Search — `--regex` + `--folder`

Combine regex search with folder scoping.

```
$ ./cider notes search quick.*fox --regex -f Cider Tests
Found 1 note(s) matching "quick.*fox":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest ReplAll1                         Cider Tests           
```

### Test 22: Search — `--title` and `--body` mutual exclusion

Using both flags returns an error.

```
$ ./cider notes search test --title --body
Error: --title and --body are mutually exclusive
```

### Test 23: Search — invalid regex

Malformed regex pattern returns a clear error.

```
$ ./cider notes search [invalid --regex
Error: Invalid regex: The value “[invalid” is invalid.
```

---

## Section 3: Replace (Single Note)


### Test 24: Replace — literal (basic find & replace)


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Gamma note for editing and replacing text.
```

**COMMAND**

```
$ ./cider notes replace 7 --find editing --replace TESTING
✓ Replaced "editing" → "TESTING" in note 7.
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Gamma note for TESTING and replacing text.
```

### Test 25: Replace — `--regex` with capture groups

Regex: \`(\w+)@(\w+)\` with template \`[$1 at $2]\` masks email addresses using capture group backreferences.


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Regex
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Regex
Contact: alice@example.com and bob@test.org. Phone: 555-1234.
```

**COMMAND**

```
$ ./cider notes replace 4 --find (\w+)@(\w+) --replace [$1 at $2] --regex
✓ Replaced "(\w+)@(\w+)" → "[$1 at $2]" in note 4.
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Regex
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Regex
Contact: [alice at example].com and [bob at test].org. Phone: 555-1234.
```

### Test 26: Replace — `-i` (case-insensitive)

Case-insensitive flag replaces **all case variants** (TODO, todo, TODO) with a single command.


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest CaseTest
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest CaseTest
TODO: fix the todo list and update TODO tracker.
```

**COMMAND**

```
$ ./cider notes replace 1 --find todo --replace DONE -i
✓ Replaced "todo" → "DONE" in note 1.
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest CaseTest
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest CaseTest
DONE: fix the DONE list and update DONE tracker.
```

### Test 27: Replace — `--regex` + `-i` combined


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Regex
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Regex
Contact: [alice at example].com and [bob at test].org. Phone: 555-1234.
```

**COMMAND**

Regex + case-insensitive: replace "phone" (matches "Phone") with "Tel".

```
$ ./cider notes replace 4 --find phone --replace Tel --regex -i
✓ Replaced "phone" → "Tel" in note 4.
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Regex
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Regex
Contact: [alice at example].com and [bob at test].org. Tel: 555-1234.
```

### Test 28: Replace — text not found (error)

```
$ ./cider notes replace 7 --find zzz_nonexistent_text --replace x
Error: Text not found in note 7: "zzz_nonexistent_text"
```

### Test 29: Replace — invalid regex (error)

```
$ ./cider notes replace 7 --find [invalid --replace x --regex
Error: Invalid regex: The value “[invalid” is invalid.
```

### Test 30: Replace — nonexistent note (error)

```
$ ./cider notes replace 99999 --find x --replace y
Error: Note 99999 not found
```

---

## Section 4: Replace --all (Multi-Note)


### Test 31: Replace `--all --dry-run` (preview only)

`--dry-run` shows what **would** change without modifying anything.


**BEFORE: ReplAll1**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll1
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll1
The quick brown fox jumps over the lazy dog.
```

**BEFORE: ReplAll2**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll2
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll2
The quick brown dog runs through the quick brown meadow.
```

**COMMAND**

```
$ ./cider notes replace --all --find quick brown --replace slow grey --folder Cider Tests --dry-run
Found 3 match(es) in 2 note(s) in "Cider Tests":

  CiderTest ReplAll2 (Cider Tests) — 2 match(es)
  CiderTest ReplAll1 (Cider Tests) — 1 match(es)

[dry-run] No changes made.
```

**AFTER: ReplAll1 (unchanged)**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll1
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll1
The quick brown fox jumps over the lazy dog.
```

**AFTER: ReplAll2 (unchanged)**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll2
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll2
The quick brown dog runs through the quick brown meadow.
```

### Test 32: Replace `--all --folder` (with confirmation)

Replaces in **all matching notes** within a folder. Shows summary and requires `y/N` confirmation.


**BEFORE: ReplAll1**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll1
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll1
The quick brown fox jumps over the lazy dog.
```

**BEFORE: ReplAll2**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll2
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll2
The quick brown dog runs through the quick brown meadow.
```

**COMMAND**

```
$ printf "y\n" | cider notes replace --all --find "quick brown" --replace "slow grey" --folder "Cider Tests"
Found 3 match(es) in 2 note(s) in "Cider Tests":

  CiderTest ReplAll2 (Cider Tests) — 2 match(es)
  CiderTest ReplAll1 (Cider Tests) — 1 match(es)

Replace "quick brown" → "slow grey" in all 2 note(s)? (y/N) ✓ Replaced in 2 note(s).
```

**AFTER: ReplAll1**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll1
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll1
The slow grey fox jumps over the lazy dog.
```

**AFTER: ReplAll2**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll2
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll2
The slow grey dog runs through the slow grey meadow.
```

### Test 33: Replace `--all --regex --folder`

Regex replace across multiple notes. Pattern \`\bslow\b\` uses word boundary to match whole words only.


**BEFORE: ReplAll1**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll1
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll1
The slow grey fox jumps over the lazy dog.
```

**BEFORE: ReplAll2**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll2
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll2
The slow grey dog runs through the slow grey meadow.
```

**COMMAND**

```
$ printf "y\n" | cider notes replace --all --find "\bslow\b" --replace "fast" --regex --folder "Cider Tests"
Found 3 match(es) in 2 note(s) in "Cider Tests":

  CiderTest ReplAll2 (Cider Tests) — 2 match(es)
  CiderTest ReplAll1 (Cider Tests) — 1 match(es)

Replace "\bslow\b" → "fast" in all 2 note(s)? (y/N) ✓ Replaced in 2 note(s).
```

**AFTER: ReplAll1**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll1
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll1
The fast grey fox jumps over the lazy dog.
```

**AFTER: ReplAll2**

```
╔══════════════════════════════════════════╗
  CiderTest ReplAll2
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest ReplAll2
The fast grey dog runs through the fast grey meadow.
```

### Test 34: Replace `--all` — no matches

```
$ ./cider notes replace --all --find xyzNonexistent99 --replace x --folder Cider Tests --dry-run
No matches found for "xyzNonexistent99" in folder "Cider Tests".
```

---

## Section 5: Append / Prepend


### Test 35: Append text to note


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
```

**COMMAND**

```
$ ./cider notes append 9 This line was appended.
✓ Appended to note 9
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
This line was appended.
```

### Test 36: Append via stdin pipe


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Beta
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Beta
Beta note body. Contains the word pineapple.
```

**COMMAND**

```
$ echo "Piped content here." | cider notes append 8
✓ Appended to note 8
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Beta
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Beta
Beta note body. Contains the word pineapple.
Piped content here.
```

### Test 37: Append `--no-newline`


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
This line was appended.
```

**COMMAND**

Appends without a newline separator — text is concatenated directly.

```
$ ./cider notes append 9  (suffix) --no-newline
✓ Appended to note 9
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
This line was appended. (suffix)
```

### Test 38: Prepend text after title


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Gamma note for TESTING and replacing text.
```

**COMMAND**

```
$ ./cider notes prepend 7 Prepended after the title line.
✓ Prepended to note 7
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Prepended after the title line.
Gamma note for TESTING and replacing text.
```

### Test 39: Prepend via stdin pipe


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Prepended after the title line.
Gamma note for TESTING and replacing text.
```

**COMMAND**

```
$ echo "Piped prepend." | cider notes prepend 7
✓ Prepended to note 7
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Piped prepend.
Prepended after the title line.
Gamma note for TESTING and replacing text.
```

### Test 40: Debug — dump attributed string attributes

Shows all NSAttributedString attribute keys and values stored in the note's CRDT.

```
$ ./cider notes debug 9
Debug: "CiderTest Alpha" (note 9)

Raw text length: 101 characters

Attributed string attribute keys found: 0

```

---

## Section 6: Date Filtering & Sorting


### Test 41: List notes modified after today

```
$ ./cider notes list --after today -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest CaseTest                         Cider Tests            
  2 CiderTest ReplAll2                         Cider Tests            
  3 CiderTest ReplAll1                         Cider Tests            
  4 CiderTest Regex                            Cider Tests            
  5 CiderTest Attach                           Cider Tests            
  6 CiderTest Delta                            Cider Tests            
  7 CiderTest Gamma                            Cider Tests            
  8 CiderTest Beta                             Cider Tests            
  9 CiderTest Alpha                            Cider Tests            
 10 Untag Test                                 Cider Tests            
 11 CiderTest Prepend                          Cider Tests            
 12 CiderTest Append                           Cider Tests            

Total: 12 note(s)
```

### Test 42: List notes modified before 2020-01-01

```
$ ./cider notes list --before 2020-01-01 -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  (no notes in folder "Cider Tests")
```

### Test 43: List notes sorted by modification date

```
$ ./cider notes list --sort modified -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest CaseTest                         Cider Tests            
  2 CiderTest ReplAll2                         Cider Tests            
  3 CiderTest ReplAll1                         Cider Tests            
  4 CiderTest Regex                            Cider Tests            
  5 CiderTest Attach                           Cider Tests            
  6 CiderTest Delta                            Cider Tests            
  7 CiderTest Gamma                            Cider Tests            
  8 CiderTest Beta                             Cider Tests            
  9 CiderTest Alpha                            Cider Tests            
 10 Untag Test                                 Cider Tests            
 11 CiderTest Prepend                          Cider Tests            
 12 CiderTest Append                           Cider Tests            
 13 Live Refresh Test                          Cider Tests            
 14 AS Created Note                            Cider Tests            
 15 Serialize Test                             Cider Tests            
 16 New Note                                   Cider Tests            
 17 New Note                                   Cider Tests            
 18 New Note                                   Cider Tests            
 19 New Note                                   Cider Tests            

Total: 19 note(s)
```

### Test 44: List notes sorted by creation date

```
$ ./cider notes list --sort created -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest CaseTest                         Cider Tests            
  2 CiderTest ReplAll2                         Cider Tests            
  3 CiderTest ReplAll1                         Cider Tests            
  4 CiderTest Regex                            Cider Tests            
  5 CiderTest Attach                           Cider Tests            
  6 CiderTest Delta                            Cider Tests            
  7 CiderTest Gamma                            Cider Tests            
  8 CiderTest Beta                             Cider Tests            
  9 CiderTest Alpha                            Cider Tests            
 10 Untag Test                                 Cider Tests            
 11 CiderTest Prepend                          Cider Tests            
 12 CiderTest Append                           Cider Tests            
 13 Live Refresh Test                          Cider Tests            
 14 AS Created Note                            Cider Tests            
 15 Serialize Test                             Cider Tests            
 16 New Note                                   Cider Tests            
 17 New Note                                   Cider Tests            
 18 New Note                                   Cider Tests            
 19 New Note                                   Cider Tests            

Total: 19 note(s)
```

### Test 45: JSON output with created/modified dates

```
$ ./cider notes list --json -f Cider Tests
[
  {"index":1,"title":"CiderTest CaseTest","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":2,"title":"CiderTest ReplAll2","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":3,"title":"CiderTest ReplAll1","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":4,"title":"CiderTest Regex","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":5,"title":"CiderTest Attach","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":6,"title":"CiderTest Delta","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":7,"title":"CiderTest Gamma","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":8,"title":"CiderTest Beta","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":9,"title":"CiderTest Alpha","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:25:07Z","modified":"2026-02-27T01:25:07Z"},
  {"index":10,"title":"Untag Test","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:23:21Z","modified":"2026-02-27T01:23:21Z"},
  {"index":11,"title":"CiderTest Prepend","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:19:55Z","modified":"2026-02-27T01:19:55Z"},
  {"index":12,"title":"CiderTest Append","folder":"Cider Tests","attachments":0,"created":"2026-02-27T01:19:55Z","modified":"2026-02-27T01:19:55Z"},
  {"index":13,"title":"Live Refresh Test","folder":"Cider Tests","attachments":0,"created":"2026-02-19T11:24:58Z","modified":"2026-02-19T11:24:58Z"},
  {"index":14,"title":"AS Created Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T11:21:34Z","modified":"2026-02-19T11:21:34Z"},
  {"index":15,"title":"Serialize Test","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:58:40Z","modified":"2026-02-19T10:58:40Z"},
  {"index":16,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:56:43Z","modified":"2026-02-19T10:56:43Z"},
  {"index":17,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:55:31Z","modified":"2026-02-19T10:55:31Z"},
  {"index":18,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:53:59Z","modified":"2026-02-19T10:53:59Z"},
  {"index":19,"title":"New Note","folder":"Cider Tests","attachments":0,"created":"2026-02-19T10:47:51Z","modified":"2026-02-19T10:47:51Z"}
]
```

### Test 46: Date filtering with --after and --folder combined

```
$ ./cider notes list --after 1 week ago -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest CaseTest                         Cider Tests            
  2 CiderTest ReplAll2                         Cider Tests            
  3 CiderTest ReplAll1                         Cider Tests            
  4 CiderTest Regex                            Cider Tests            
  5 CiderTest Attach                           Cider Tests            
  6 CiderTest Delta                            Cider Tests            
  7 CiderTest Gamma                            Cider Tests            
  8 CiderTest Beta                             Cider Tests            
  9 CiderTest Alpha                            Cider Tests            
 10 Untag Test                                 Cider Tests            
 11 CiderTest Prepend                          Cider Tests            
 12 CiderTest Append                           Cider Tests            
 13 Live Refresh Test                          Cider Tests            
 14 AS Created Note                            Cider Tests            
 15 Serialize Test                             Cider Tests            
 16 New Note                                   Cider Tests            
 17 New Note                                   Cider Tests            
 18 New Note                                   Cider Tests            
 19 New Note                                   Cider Tests            

Total: 19 note(s)
```

### Test 47: Search with --after date filter

```
$ ./cider notes search CiderTest --after today
Found 11 note(s) matching "CiderTest":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest CaseTest                         Cider Tests           
  2 CiderTest ReplAll2                         Cider Tests           
  3 CiderTest ReplAll1                         Cider Tests           
  4 CiderTest Regex                            Cider Tests           
  5 CiderTest Attach                           Cider Tests           
  6 CiderTest Delta                            Cider Tests           
  7 CiderTest Gamma                            Cider Tests           
  8 CiderTest Beta                             Cider Tests           
  9 CiderTest Alpha                            Cider Tests           
 10 CiderTest Prepend                          Cider Tests           
 11 CiderTest Append                           Cider Tests           
```

### Test 48: Invalid date shows error

```
$ ./cider notes list --after not-a-date
Error: Invalid date 'not-a-date'. Use ISO 8601 (2024-01-15) or relative (today, yesterday, "3 days ago").
```

---

## Section 7: Templates

Created note: "CiderTest Template"

### Test 49: List templates

```
$ ./cider templates list
Templates (in "Cider Templates" folder):

  1. CiderTest Template

Total: 1 template(s)
```

### Test 50: Show template content

```
$ ./cider templates show CiderTest Template
Meeting Date: 
Attendees: 

## Agenda

## Notes

## Action Items

```

### Test 51: Create note from template

```
$ ./cider notes add --template CiderTest Template --folder Cider Tests
Created note from template "CiderTest Template": "Meeting Date:"
```

### Test 52: Show nonexistent template (error)

```
$ ./cider templates show Nonexistent
Error: Template "Nonexistent" not found
```

### Test 53: Delete template

```
$ ./cider templates delete CiderTest Template
Deleted template: "CiderTest Template"
```
Delete note "Meeting Date:"? (y/N) Deleted: "Meeting Date:"

---

## Section 8: Settings


### Test 54: Show settings (initially empty)

```
$ ./cider settings
No settings configured.
Set one with: cider settings set <key> <value>
```

### Test 55: Set a setting

```
$ ./cider settings set default_sort modified
Set default_sort = modified
```

### Test 56: Set another setting

```
$ ./cider settings set default_folder Work Notes
Set default_folder = Work Notes
```

### Test 57: Show all settings

```
$ ./cider settings
Cider Settings:

  default_folder            Work Notes
  default_sort              modified
```

### Test 58: Get a single setting

```
$ ./cider settings get default_sort
modified
```

### Test 59: Settings JSON output

```
$ ./cider settings --json
{
  "default_folder":"Work Notes",
  "default_sort":"modified"
}
```

### Test 60: Get nonexistent key (error)

```
$ ./cider settings get nonexistent_key
Setting 'nonexistent_key' not found.
```

### Test 61: Overwrite existing setting

```
$ ./cider settings set default_sort created
Set default_sort = created
```

Verify:

```
$ ./cider settings get default_sort
created
```

### Test 62: Reset settings

```
$ ./cider settings reset
Settings reset to defaults.
```

Verify:

```
$ ./cider settings
No settings configured.
Set one with: cider settings set <key> <value>
```

---

## Section 9: Note Links / Backlinks


### Test 63: Show outgoing links

Test notes have no >> links, so this shows the empty-links output.

```
$ ./cider notes links 9
No outgoing links in "CiderTest Alpha".
```

### Test 64: Show outgoing links (JSON)

```
$ ./cider notes links 9 --json
[]
```

### Test 65: Show backlinks

```
$ ./cider notes backlinks 9
No notes link to "CiderTest Alpha".
```

### Test 66: Show backlinks (JSON)

```
$ ./cider notes backlinks 9 --json
[]
```

### Test 67: Full link graph

Shows all note-to-note links across all notes (including real user notes).

```
$ ./cider notes backlinks --all
Note link graph (3 notes with links):

  "Flowers":
    → "Valentine’s Day" (as "Valentine’s Day")
  "Tickets":
    → "Valentine’s Day" (as "Valentine’s Day")
  "Valentine’s Day":
    → "Aryn present ideas" (as "Aryn present ideas")
    → "Flowers" (as "Flowers")
    → "Aryn vday gift 2026" (as "Aryn vday gift 2026")
    → "Tickets" (as "Tickets")
    → "Reservations" (as "Reservations")
    → "Agenda vday 2026" (as "Agenda vday 2026")
```

### Test 68: Full link graph (JSON)

```
$ ./cider notes backlinks --all --json
{"Flowers":{"title":"Flowers","links":[{"displayText":"Valentine’s Day","targetTitle":"Valentine’s Day"}]},"Tickets":{"title":"Tickets","links":[{"displayText":"Valentine’s Day","targetTitle":"Valentine’s Day"}]},"Valentine’s Day":{"title":"Valentine’s Day","links":[{"displayText":"Aryn vday gift 2026","targetTitle":"Aryn vday gift 2026"},{"displayText":"Tickets","targetTitle":"Tickets"},{"displayText":"Agenda vday 2026","targetTitle":"Agenda vday 2026"},{"displayText":"Aryn present ideas","targetTitle":"Aryn present ideas"},{"displayText":"Reservations","targetTitle":"Reservations"},{"displayText":"Flowers","targetTitle":"Flowers"}]}}
```

---

## Section 10: Watch / Events


### Test 69: Watch for note changes (2 second sample)

Starts watch, creates a note, then stops. Shows the change event.

```
$ cider notes watch --interval 1 &
Created note: "CiderTest WatchNote"
Watching for note changes (interval: 1s, Ctrl-C to stop)

[2026-02-26 20:25:19] created: "CiderTest WatchNote"
```
Delete note "CiderTest WatchNote"? (y/N) Deleted: "CiderTest WatchNote"

### Test 70: Watch with JSON output

```
$ cider notes watch --interval 1 --json (2 second sample)
Watching for note changes (interval: 1s, Ctrl-C to stop)

```

### Test 71: Watch with --folder filter

```
$ cider notes watch --interval 1 -f "Cider Tests" (header only)
Watching for note changes in "Cider Tests" (interval: 1s, Ctrl-C to stop)

```

---

## Section 11: Checklists


### Test 72: Checklist items on test note (no checklists)

```
$ ./cider notes checklist 9
No checklist items in "CiderTest Alpha".
```

### Test 73: Checklist --json on empty note

```
$ ./cider notes checklist 9 --json
{"title":"CiderTest Alpha","items":[],"checked":0,"total":0}
```

### Test 74: Checklist --summary on empty note

```
$ ./cider notes checklist 9 --summary
0/0 items complete
```

### Test 75: Check on nonexistent note

```
$ ./cider notes check 99999 1
Error: Note 99999 not found
```

### Test 76: Uncheck on nonexistent note

```
$ ./cider notes uncheck 99999 1
Error: Note 99999 not found
```

### Test 77: Check on note without checklists

```
$ ./cider notes check 9 1
Error: No checklist items in note 9
```

### Test 78: Missing item number

```
$ ./cider notes check 1
Usage: cider notes check <N> <item#>
```

---

## Section 12: Tables


### Test 79: Table on note without tables

```
$ ./cider notes table 9
No tables in "CiderTest Alpha".
```

### Test 80: Table --list on empty note

```
$ ./cider notes table 9 --list
No tables in "CiderTest Alpha".
```

### Test 81: Table --json on empty note

```
$ ./cider notes table 9 --json
{"error":"No tables in note"}
```

### Test 82: Table on nonexistent note

```
$ ./cider notes table 99999
Error: Note 99999 not found
```

### Test 83: Table --headers on empty note

```
$ ./cider notes table 9 --headers
No tables in "CiderTest Alpha".
```

---

## Section 13: Sharing


### Test 84: Share status on unshared note

```
$ ./cider notes share 9
Share status for "CiderTest Alpha":

  Shared: No

  Note is not currently shared.
  To share, use the Share button in Apple Notes.
```

### Test 85: Share status --json

```
$ ./cider notes share 9 --json
{"title":"CiderTest Alpha","shared":false,"participants":0}
```

### Test 86: List shared notes

```
$ ./cider notes shared
Shared notes:

  # Title                                      Folder                 Participants
--- ------------------------------------------ ---------------------- ------------
  1 Returns                                    Notes                  2
  2 Arts typical schedule                      Art                    2
  3 TO DO HOUSE                                TODO                   2
  4 Grocery                                    Groceries              2
  5 Bonus Performance                          Notes                  2
  6 Aryn present ideas                         Gifts                  2
  7 GROCERY                                    Groceries              2
  8 2026 Annual Planning                       Notes                  2
  9 2025 tax docs                              Documents              1
 10 SATURDAY                                   TODO                   2
 11 Sleep                                      Art                    1
 12 baby names                                 Relationship           2
 13 Salads                                     Recipes                1
 14 CHRISTMAS SCHEDULE                         Agendas                2
 15 Christmas list                             Gifts                  2
 16 Islamorada Recs                            Places                 6
 17 Milk Schedule                              Art                    2
 18 Notes for Arthur                           Art                    2
 19 THIS WEEK                                  TODO                   2
 20 Florida Keys Babymoon                      Places                 2
 21 bananas                                    Groceries              3
 22 Pork Butt Recipe-Electric Smoker           Recipes                4
 23 Flight Cheat Sheet                         Places                 2
 24 Lactation bites                            Recipes                2
 25 Milestone photos                           Art                    2
 26 Starting with the first few days and end.. Art                    2
 27 Photos                                     TODO                   2
 28 To Do for photos                           TODO                   2
 29 Vanilla extract                            Groceries              2
 30 TO DO                                      TODO                   2
 31 Baby Williams Updates                      Art                    12
 32 Don’t forget                               Art                    2
 33 HOSPITAL BAG                               Art                    2
 34 DR                                         Art                    2
 35 Pediatrician Options                       Art                    2
 36 Car Insurance cards                        Documents              1
 37 House B4 BB                                Home                   2
 38 Italian Chopped Salad                      Recipes                2
 39 TO DO                                      TODO                   2
 40 TO DO                                      TODO                   2
 41 BABY SHOWER RSVPS                          Art                    2
 42 TODAY                                      TODO                   2
 43 To do                                      TODO                   2
 44 House projects 2025                        Home                   2
 45 ARYN'S BLOOD SUGAR                         Art                    2
 46 Diabetes Specialist                        Art                    2
 47 Backyard                                   Home                   2
 48 BANK                                       Finance                2
 49 Sex                                        Relationship           2
 50 Budget Planning-New                        Finance                1
 51 12 march                                   Home                   1
 52 TO DO                                      TODO                   2
 53 Credit Cards                               Finance                2
 54 WEDNESDAY                                  TODO                   2
 55 Cholesterol Foods                          Health                 2
 56 Todo b4 18th                               Home                   2
 57 16 Jan todo                                Home                   2
 58 Todo                                       TODO                   2
 59 Unfinished house items                     Home                   2
 60 Home front door codes                      Home                   2
 61 Switch plates                              Home                   1
 62 Xmas list                                  Gifts                  2
 63 Christmas list                             Gifts                  2
 64 Compose                                    Hobbies                2
 65 Strasbourg                                 Places                 2
 66 BEFORE TRIP TO DO                          Archive                2
 67 SEPTEMBER - FRANCE                         Places                 2
 68 HOME                                       Home                   2
 69 Questions for doctor                       Health                 2
 70 CHS Wed                                    Places                 1
 71 Basement doors                             Notes                  1
 72 ARYNS BIRTHDAY LIST                        Notes                  3
 73 Basement schedule                          Notes                  2
 74 Xmas                                       Notes                  1
 75 Chat                                       Notes                  2
 76 Fulfords- Chrome cast                      Notes                  1
 77 Out of town guests                         Wedding                2
 78 Wedding                                    Notes                  2
 79 This week                                  Notes                  2
 80 Free weekends 2023                         Notes                  1
 81 Honeymoon                                  Notes                  1
 82 Schedule planning                          Notes                  1
 83 Addison’s weekend plan                     Agendas                2
 84 26Mar                                      TODO                   1
 85 ARYN'S AUSTIN TRIP                         Notes                  2
 86 TO DO                                      Notes                  2
 87 VDAY                                       Notes                  2
 88 WEDDING                                    Notes                  2
 89 H O M E                                    Notes                  2
 90 Kitchen open points                        Notes                  2
 91 ITALY TRIP                                 Notes                  2
 92 Italy recommendations                      Notes                  5
 93 LOWES                                      Notes                  2
 94 NYC                                        Places                 2
 95 New York trip                              Places                 2
 96 OUTSIDE                                    Home                   2
 97 HONEY DO LIST                              TODO                   2
 98 Thing to be done                           TODO                   2
 99 t h a n k  u’s:                            Relationship           2
100 Moving shit for floors                     Home                   1
101 GROCERY                                    Groceries              2
102 FLOORING                                   Home                   2
103 C H R I S T M A S  L I S T                 Gifts                  2
104 t💕h💕a💕n💕k💕💕u💕                       Relationship           1
105 116 W 49th                                 Home                   2
106 This Week                                  TODO                   1
107 ~9:30 - Addison gets call from Sean Marl.. Work                   1
108 Paris                                      Places                 1
109 Ad wishlist                                Hobbies                2

Total: 109 shared note(s)
```

### Test 87: List shared notes --json (first 3)

```
[
  {
    "title": "Returns",
    "folder": "Notes",
    "participants": 2
  },
  {
    "title": "Arts typical schedule",
    "folder": "Art",
    "participants": 2
  },
  {
    "title": "TO DO HOUSE",
    "folder": "TODO",
    "participants": 2
  }
]

```

### Test 89: Share status on nonexistent note

```
$ ./cider notes share 99999
Error: Note 99999 not found
```

---

## Section 14: Folder Management


### Test 90: Create a folder

```
$ ./cider notes folder create CiderTest Subfolder
Created folder: "CiderTest Subfolder"
```

### Test 91: Create duplicate folder

```
$ ./cider notes folder create CiderTest Subfolder
Folder "CiderTest Subfolder" already exists.
```

### Test 92: Rename folder

```
$ ./cider notes folder rename CiderTest Subfolder CiderTest Renamed
Renamed folder: "CiderTest Subfolder" → "CiderTest Renamed"
```

### Test 93: List folders (shows renamed)

```
$ ./cider notes folders
Folders:
  Agendas
  Archive
  Art
  Cider Templates
  Cider Tests
  CiderSync Tests
  CiderSync_Tests
  CiderTest Renamed
  Documents
  Drafts
  Finance
  Gg
  Gifts
  Groceries
  Health
  Hobbies
  Home
  Ideas
  Misc
  New Smart Folder
  Notes
  Passwords
  Phone Numbers
  Places
  Recently Deleted
  Recipes
  Relationship
  TODO
  Wedding
  Work

Total: 30 folder(s)
```

### Test 94: Delete empty folder

```
$ ./cider notes folder delete CiderTest Renamed
Deleted folder: "CiderTest Renamed"
```

### Test 95: Delete non-empty folder (error)

```
$ ./cider notes folder delete Cider Tests
Error: Folder "Cider Tests" has 14 note(s). Move or delete them first.
```

### Test 96: Delete nonexistent folder (error)

```
$ ./cider notes folder delete NonexistentFolder99
Error: Folder "NonexistentFolder99" not found
```

---

## Section 15: Tags


### Test 97: Add a tag

```
$ ./cider notes tag 9 project-x
Added #project-x to note 9
```

### Test 98: Show note with tag

```
$ ./cider notes show 9
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
This line was appended. (suffix) [📎 attachment]
```

### Test 99: Duplicate tag detection

```
$ ./cider notes tag 9 project-x
Note 9 already has tag #project-x
```

### Test 100: Add second tag

```
$ ./cider notes tag 9 important
Added #important to note 9
```

### Test 101: List all tags

```
$ ./cider notes tags
  #a
  #add
  #ai-hub
  #b
  #change
  #check
  #cider
  #d6
  #default
  #encoded
  #endregion
  #for
  #import
  #important
  #include
  #init
  #k5udouvpqi9ix0fdb44if-ezn3xrnbgp3awurgtyniu
  #loop
  #mail
  #optional
  #print
  #processed
  #project-x
  #proxy_set_header
  #region
  #remindme
  #s9y
  #sendfile
  #showcase
  #test
  #testremove
  #this
  #token
  #uncommented
  #uncommneted

Total: 35 unique tag(s)
```

### Test 102: Tags with counts

```
$ ./cider notes tags --count
  #a                             1 note(s)
  #add                           1 note(s)
  #ai-hub                        1 note(s)
  #b                             1 note(s)
  #change                        1 note(s)
  #check                         1 note(s)
  #cider                         1 note(s)
  #d6                            1 note(s)
  #default                       1 note(s)
  #encoded                       1 note(s)
  #endregion                     1 note(s)
  #for                           1 note(s)
  #import                        1 note(s)
  #important                     1 note(s)
  #include                       1 note(s)
  #init                          1 note(s)
  #k5udouvpqi9ix0fdb44if-ezn3xrnbgp3awurgtyniu 1 note(s)
  #loop                          1 note(s)
  #mail                          1 note(s)
  #optional                      1 note(s)
  #print                         1 note(s)
  #processed                     1 note(s)
  #project-x                     1 note(s)
  #proxy_set_header              1 note(s)
  #region                        1 note(s)
  #remindme                      1 note(s)
  #s9y                           1 note(s)
  #sendfile                      1 note(s)
  #showcase                      1 note(s)
  #test                          1 note(s)
  #testremove                    1 note(s)
  #this                          1 note(s)
  #token                         1 note(s)
  #uncommented                   1 note(s)
  #uncommneted                   1 note(s)

Total: 35 unique tag(s)
```

### Test 103: Tags JSON output

```
$ ./cider notes tags --json
[
  {"tag":"#a","count":1},
  {"tag":"#add","count":1},
  {"tag":"#ai-hub","count":1},
  {"tag":"#b","count":1},
  {"tag":"#change","count":1},
  {"tag":"#check","count":1},
  {"tag":"#cider","count":1},
  {"tag":"#d6","count":1},
  {"tag":"#default","count":1},
  {"tag":"#encoded","count":1},
  {"tag":"#endregion","count":1},
  {"tag":"#for","count":1},
  {"tag":"#import","count":1},
  {"tag":"#important","count":1},
  {"tag":"#include","count":1},
  {"tag":"#init","count":1},
  {"tag":"#k5udouvpqi9ix0fdb44if-ezn3xrnbgp3awurgtyniu","count":1},
  {"tag":"#loop","count":1},
  {"tag":"#mail","count":1},
  {"tag":"#optional","count":1},
  {"tag":"#print","count":1},
  {"tag":"#processed","count":1},
  {"tag":"#project-x","count":1},
  {"tag":"#proxy_set_header","count":1},
  {"tag":"#region","count":1},
  {"tag":"#remindme","count":1},
  {"tag":"#s9y","count":1},
  {"tag":"#sendfile","count":1},
  {"tag":"#showcase","count":1},
  {"tag":"#test","count":1},
  {"tag":"#testremove","count":1},
  {"tag":"#this","count":1},
  {"tag":"#token","count":1},
  {"tag":"#uncommented","count":1},
  {"tag":"#uncommneted","count":1}
]
```

### Test 104: Filter notes by tag

```
$ ./cider notes list --tag project-x
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest Alpha                            Cider Tests            

Total: 1 note(s)
```

### Test 105: Remove a tag

```
$ ./cider notes untag 9 project-x
Removed #project-x from note 9
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
This line was appended. (suffix) [📎 attachment]
```

### Test 106: Remove nonexistent tag

```
$ ./cider notes untag 9 nonexistent
Tag #nonexistent not found in note 9
```
Removed #important from note 9

---

## Section 16: Pin / Unpin


### Test 107: Pin a note

```
$ ./cider notes pin 9
📌 Pinned note 9: "CiderTest Alpha"
```

### Test 108: Pin already-pinned note

```
$ ./cider notes pin 9
Note 9 is already pinned.
```

### Test 109: List pinned notes

```
$ ./cider notes list --pinned
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest Alpha                            Cider Tests            
  2 Cider Feature Showcase                     Notes                  📎 1
  3 Returns                                    Notes                  📎 3
  4 Arts typical schedule                      Art                    
  5 Bonus Performance                          Notes                  📎 4
  6 2026 Annual Planning                       Notes                  

Total: 6 note(s)
```

### Test 110: Unpin a note

```
$ ./cider notes unpin 9
📌 Unpinned note 9: "CiderTest Alpha"
```

### Test 111: Unpin non-pinned note

```
$ ./cider notes unpin 9
Note 9 is not pinned.
```

---

## Section 17: Edit (CRDT)


### Test 112: Edit via stdin pipe


**BEFORE**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Piped prepend.
Prepended after the title line.
Gamma note for TESTING and replacing text.
```

**COMMAND**

```
$ echo "CiderTest Gamma
Gamma note fully rewritten via stdin pipe." | cider notes edit 7
✓ Note saved (CRDT, attachments preserved).
```

**AFTER**

```
╔══════════════════════════════════════════╗
  CiderTest Gamma
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Gamma
Gamma note fully rewritten via stdin pipe.
```

### Test 113: Add note via stdin pipe


**BEFORE**

```
$ ./cider notes search CiderTest Piped
No notes found matching "CiderTest Piped"
```

**COMMAND**

```
$ echo "CiderTest Piped
This note was created from a pipe." | cider notes add --folder "Cider Tests"
Created note: "CiderTest Piped"
```

**AFTER**

```
$ ./cider notes search CiderTest Piped
Found 1 note(s) matching "CiderTest Piped":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Piped                            Cider Tests           
```

---

## Section 18: Attachments


### Test 114: Attach file to note


**BEFORE: Attachments**

```
$ ./cider notes attachments 6
No attachments in "CiderTest Attach"
```

**COMMAND: Attach file**

```
$ ./cider notes attach 6 /tmp/cider_report_attach.txt
✓ Attachment inserted at position 73 in "CiderTest Attach" (id: 98E110B0-5AE3-47CB-953B-C50F4D0C432D)
```

**AFTER: Attachments**

```
$ ./cider notes attachments 6
Attachments in "CiderTest Attach":
  1. [public.plain-text]  (public.plain-text, position 73)
```

### Test 115: List attachments (JSON)

```
$ ./cider notes attachments 6 --json
[{"index":1,"name":"[public.plain-text]","type":"public.plain-text","position":73,"id":"98E110B0-5AE3-47CB-953B-C50F4D0C432D"}]
```

### Test 116: Detach attachment


**BEFORE**

```
$ ./cider notes attachments 6
Attachments in "CiderTest Attach":
  1. [public.plain-text]  (public.plain-text, position 73)
```

**COMMAND**

```
$ ./cider notes detach 6 1
✓ Removed attachment 1 ([public.plain-text]) from "CiderTest Attach"
```

**AFTER**

```
$ ./cider notes attachments 6
No attachments in "CiderTest Attach"
```

### Test 117: Attach at specific CRDT position


**COMMAND**

```
$ ./cider notes attach 6 /tmp/cider_report_pos.txt --at 5
✓ Attachment inserted at position 5 in "CiderTest Attach" (id: ACD00914-1654-447A-862C-41D5A44457F9)
```

**AFTER (JSON — note position field)**

```
$ ./cider notes attachments 6 --json
[{"index":1,"name":"[public.plain-text]","type":"public.plain-text","position":5,"id":"ACD00914-1654-447A-862C-41D5A44457F9"}]
```

Cleanup:

```
$ ./cider notes detach 6 1
✓ Removed attachment 1 ([public.plain-text]) from "CiderTest Attach"
```

---

## Section 19: Move


### Test 118: Move note to different folder


**BEFORE**

```
"folder":"Cider Tests"
```

**COMMAND**

```
$ ./cider notes move 9 Notes
Moved "CiderTest Beta" → "Notes"
```

**AFTER**

```
"folder":"Notes"
```

Cleanup — move back:

```
$ ./cider notes move 1 Cider Tests
Moved "CiderTest Beta" → "Cider Tests"
```

---

## Section 20: Delete


### Test 119: Delete note


**BEFORE**

```
$ ./cider notes search CiderTest Delta
Found 1 note(s) matching "CiderTest Delta":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Delta                            Cider Tests           
```

**COMMAND**

```
$ printf "y\n" | cider notes delete 8
Delete note "CiderTest Delta"? (y/N) Deleted: "CiderTest Delta"
```

**AFTER**

```
$ ./cider notes search CiderTest Delta
No notes found matching "CiderTest Delta"
```

---

## Section 21: Export


### Test 120: Export all notes to HTML

```
$ ./cider notes export /tmp/cider_report_export_55551
Exported 586 notes to: /tmp/cider_report_export_55551
Index:    /tmp/cider_report_export_55551/index.html
```

Files created:

```
587 HTML files exported
Sample files:
/tmp/cider_report_export_55551/0001_CiderTest Beta.html
/tmp/cider_report_export_55551/0002_CiderTest Piped.html
/tmp/cider_report_export_55551/0003_CiderTest CaseTest.html
/tmp/cider_report_export_55551/0004_CiderTest ReplAll2.html
/tmp/cider_report_export_55551/0005_CiderTest ReplAll1.html
```

---

## Section 22: Error Handling


### Test 121: Show nonexistent note

```
$ ./cider notes show 99999
Error: Note 99999 not found
```

### Test 122: Replace in nonexistent note

```
$ ./cider notes replace 99999 --find x --replace y
Error: Note 99999 not found
```

### Test 123: Detach from nonexistent note

```
$ ./cider notes detach 99999 1
Error: Note 99999 not found
```

### Test 124: Attach nonexistent file

```
$ ./cider notes attach 9 /nonexistent/file.txt
Error: File not found: /nonexistent/file.txt
```

### Test 125: Unknown command

```
$ ./cider bogus
Unknown command: bogus
Run 'cider --help' for usage.
```

### Test 126: Unknown notes subcommand

```
$ ./cider notes bogus
Unknown notes subcommand: bogus
cider notes v3.16.0 — Apple Notes CLI

USAGE:
  cider notes                              List all notes
  cider notes list [options]               List notes (filter, sort, date range)
  cider notes <N>                          View note N
  cider notes show <N> [--json]            View note N
  cider notes folders [--json]             List all folders
  cider notes add [--folder <f>]           Add note (reads stdin or $EDITOR)
  cider notes edit <N>                     Edit note N via CRDT (preserves attachments)
                                           Pipe: echo 'content' | cider notes edit N
  cider notes delete <N>                   Delete note N
  cider notes move <N> <folder>            Move note N to folder
  cider notes export <path>                Export notes to HTML
  cider notes attachments <N> [--json]     List attachments with positions
  cider notes attach <N> <file> [--at <pos>]  Attach file at position (CRDT)
  cider notes detach <N> [<A>]             Remove attachment A from note N

APPEND / PREPEND:
  cider notes append <N> <text> [options]
  cider notes prepend <N> <text> [options]

  Append adds text to the end of the note. Prepend inserts text right
  after the title line. Both support stdin piping.

  --no-newline     Don't add newline separator
  -f, --folder <f> Scope note index to folder

  Examples:
    cider notes append 3 "Added at the bottom"
    cider notes prepend 3 "Inserted after title"
    echo "piped text" | cider notes append 3
    cider notes append 3 "no gap" --no-newline
    cider notes prepend 3 "text" -f "Work Notes"

TEMPLATES:
  cider templates list                    List templates
  cider templates show <name>             View template content
  cider templates add                     Create new template ($EDITOR)
  cider templates delete <name>           Delete template
  cider notes add --template <name>       Create note from template

  Templates are stored as notes in the "Cider Templates" folder.
  When creating from a template, the body is pre-filled in $EDITOR.

  Examples:
    cider templates add                   Create a template in $EDITOR
    cider templates list                  List all templates
    cider templates show "Meeting Notes"  View template content
    cider notes add --template "Meeting Notes"  Create note from template
    cider notes add --template "TODO" -f Work   Template + target folder

SHARING:
  cider notes share <N>                     Show sharing status for note N
  cider notes share <N> --json              JSON share status
  cider notes shared                        List all shared notes
  cider notes shared --json                 JSON list of shared notes

  Shows iCloud collaboration status and participant count.
  Share URLs are not programmatically accessible; use Apple Notes
  Share button to create/manage collaboration links.

  Examples:
    cider notes share 5                     Show share status for note 5
    cider notes shared                      List all shared notes
    cider notes shared --json               JSON output for piping

TABLES:
  cider notes table <N>                     Show first table (aligned columns)
  cider notes table <N> --list              List all tables with row/col counts
  cider notes table <N> --index 1           Show second table (0-based)
  cider notes table <N> --json              Table as JSON array of objects
  cider notes table <N> --csv               Table as CSV
  cider notes table <N> --row 2             Specific row (0-based)
  cider notes table <N> --headers           Column headers only

  Reads native Apple Notes tables (com.apple.notes.table attachments).
  Uses ICAttachmentTableModel and ICTable to access row/column data.
  Row 0 is treated as the header row for JSON key names.

  Examples:
    cider notes table 5                     Show first table, aligned
    cider notes table 5 --list              List tables in note 5
    cider notes table 5 --json              JSON array of {header: value}
    cider notes table 5 --csv               CSV output
    cider notes table 5 --row 0             First row (headers)
    cider notes table 5 --index 1 --csv     Second table as CSV
    cider notes table 5 --headers           Column headers only

CHECKLISTS:
  cider notes checklist <N>                 Show checklist items with status
  cider notes checklist <N> --summary       Summary only (e.g. "3/6 complete")
  cider notes checklist <N> --json          JSON output
  cider notes checklist <N> --add "text"    Add a new checklist item
  cider notes check <N> <item#>             Check off item by number
  cider notes uncheck <N> <item#>           Uncheck item by number

  Reads native Apple Notes checklist formatting (style 103 paragraphs).
  Items are numbered sequentially (1-based). Check/uncheck toggles
  the done state via the CRDT attributed string.

  Examples:
    cider notes checklist 5                Show all items with [x]/[ ] status
    cider notes checklist 5 --summary      "3/6 items complete"
    cider notes check 5 2                  Check off item 2
    cider notes uncheck 5 2                Uncheck item 2
    cider notes checklist 5 --add "Buy milk"  Add new item
    cider notes checklist 5 --json         JSON with items array

WATCH / EVENTS:
  cider notes watch                          Stream note change events
  cider notes watch --folder <f>             Watch specific folder
  cider notes watch --interval 5             Poll interval (default 2s)
  cider notes watch --json                   JSON event stream for AI piping

  Polls for note changes and streams events: created, modified, deleted.
  Reads watch_interval from Cider Settings if no --interval flag.

  Examples:
    cider notes watch                        Watch all notes (2s poll)
    cider notes watch -f "Work Notes"         Watch specific folder
    cider notes watch --interval 10           Poll every 10 seconds
    cider notes watch --json                  JSON events for piping
    cider notes watch --json | while read e; do echo "$e" | jq; done

NOTE LINKS / BACKLINKS:
  cider notes links <N> [--json]             Show outgoing note links
  cider notes backlinks <N> [--json]         Show notes linking to note N
  cider notes backlinks --all [--json]       Full link graph
  cider notes link <N> <target title>       Create link to another note

  Links use Apple Notes native inline attachments (same as >> syntax).
  Cider can both create and read note-to-note links.

  Examples:
    cider notes links 5                Show what note 5 links to
    cider notes backlinks 5            Show notes that link to note 5
    cider notes backlinks --all        Full link graph across all notes
    cider notes link 5 Meeting Notes   Link note 5 to "Meeting Notes"
    cider notes links 5 --json         JSON output

FOLDER MANAGEMENT:
  cider notes folder create <name>           Create a new folder
  cider notes folder create <name> --parent <p>  Nested folder
  cider notes folder delete <name>           Delete empty folder
  cider notes folder rename <old> <new>      Rename folder

  Delete requires the folder to be empty (move/delete notes first).
  Rename checks that the new name doesn't already exist.

  Examples:
    cider notes folder create "Work Notes"
    cider notes folder create "Meetings" --parent "Work Notes"
    cider notes folder delete "Old Stuff"
    cider notes folder rename "Work" "Work Notes"

TAGS:
  cider notes tag <N> <tag>           Add #tag to end of note
  cider notes untag <N> <tag>         Remove all occurrences of #tag
  cider notes tags [--count] [--json] List all unique tags across all notes
  cider notes list --tag <tag>        Filter notes containing #tag
  cider notes search <q> --tag <tag>  Combine search + tag filter

  Tags are #word patterns in note text (Apple Notes native hashtags).
  Auto-prepends # if omitted. Case-insensitive matching.

  Examples:
    cider notes tag 3 "project-x"         Add #project-x to note 3
    cider notes untag 3 "#project-x"      Remove #project-x from note 3
    cider notes tags --count              Show tags with note counts
    cider notes list --tag project-x      List notes with #project-x
    cider notes search "meeting" --tag work  Search + tag filter

PIN / UNPIN:
  cider notes pin <N> [-f <folder>]
  cider notes unpin <N> [-f <folder>]

  Pin or unpin a note. Pinned notes appear at the top in Apple Notes.
  Use --pinned with list to show only pinned notes.

  Examples:
    cider notes pin 3
    cider notes unpin 3
    cider notes list --pinned
    cider notes pin 1 -f Work

DEBUG:
  cider notes debug <N> [-f <folder>]

  Dumps all attributed string attribute keys and values for a note.
  Useful for discovering how Apple Notes stores checklists, tables,
  links, and other rich formatting internally.

LIST (date filtering & sorting):
  cider notes list [options]

  --after <date>              Notes modified after date
  --before <date>             Notes modified before date
  --sort created|modified|title  Sort order (default: title)
  --pinned                   Show only pinned notes
  --tag <tag>                Filter notes containing #tag
  -f, --folder <f>           Filter by folder
  --json                     JSON output (includes created/modified dates)

  Date formats:
    ISO 8601:   2024-01-15, 2024-01-15T10:30:00
    Relative:   today, yesterday, "3 days ago", "1 week ago", "2 months ago"

  Examples:
    cider notes list --after today
    cider notes list --before 2024-06-01
    cider notes list --after yesterday --sort modified
    cider notes list --sort created --json
    cider notes list --after "1 week ago" -f Work
    cider notes search "meeting" --after today

SEARCH:
  cider notes search <query> [options]

  Searches note title AND body by default (case-insensitive).

  --regex          Treat query as ICU regular expression
  --title          Search title only (mutually exclusive with --body)
  --body           Search body only (mutually exclusive with --title)
  -f, --folder <f> Scope search to a specific folder
  --after <date>   Only notes modified after date
  --before <date>  Only notes modified before date
  --json           Output results as JSON

  Examples:
    cider notes search "meeting"                  Literal search (title + body)
    cider notes search "\\d{3}-\\d{4}" --regex     Find phone numbers
    cider notes search "TODO" --title              Search titles only
    cider notes search "important" --body -f Work  Search body in Work folder
    cider notes search "meeting" --after today     Search with date filter

REPLACE (single note):
  cider notes replace <N> --find <s> --replace <s> [options]

  Replaces text in the full content (title is the first line) of note N.
  Operates on a single note. Attachments are never touched.

  --regex          Treat --find as ICU regex; --replace supports $1, $2 backrefs
  -i, --case-insensitive   Case-insensitive matching

  Examples:
    cider notes replace 3 --find old --replace new
    cider notes replace 3 --find "(\\w+)@(\\w+)" --replace "[$1 at $2]" --regex
    cider notes replace 3 --find "todo" --replace "DONE" -i

REPLACE (multiple notes):
  cider notes replace --all --find <s> --replace <s> [options]

  Replaces across ALL notes (or folder-scoped). Shows a summary and asks
  for confirmation before applying. Skips notes where attachments would change.

  --all             Required: enables multi-note mode
  --folder <f>, -f  Scope to a specific folder
  --dry-run         Preview changes without applying
  --regex           ICU regex (--replace supports $1, $2)
  -i, --case-insensitive   Case-insensitive matching

  Examples:
    cider notes replace --all --find old --replace new --dry-run
    cider notes replace --all --find old --replace new -f Work
    cider notes replace --all --find "http://" --replace "https://" --folder Work

OPTIONS:
  --json    Output as JSON (for list, show, search, folders)
  -f, --folder <name>   Filter by folder (for list, search, replace --all)

Interactive mode: if <N> is omitted from edit/delete/move/show/replace/attach,
you'll be prompted to enter it (when stdin is a terminal).
```

### Test 127: Missing replace arguments

```
$ ./cider notes replace 1 --find x
Usage: cider notes replace <N> --find <text> --replace <text> [--regex] [-i]
```

---

## Section 23: Backward Compatibility


### Test 128: Legacy `-fl` (folders)

```
$ ./cider notes -fl
Folders:
  Agendas
  Archive
  Art
  Cider Templates
  Cider Tests
  CiderSync Tests
  CiderSync_Tests
  Documents
  Drafts
  Finance
  Gg
  Gifts
  Groceries
  Health
  Hobbies
  Home
  Ideas
  Misc
  New Smart Folder
  Notes
  Passwords
  Phone Numbers
  Places
  Recently Deleted
  Recipes
  Relationship
  TODO
  Wedding
  Work

Total: 29 folder(s)
```

### Test 129: Legacy `-v` (view)

```
$ ./cider notes -v 9
╔══════════════════════════════════════════╗
  CiderTest Alpha
  Folder: Cider Tests
╚══════════════════════════════════════════╝

CiderTest Alpha
This is the alpha note with some searchable content.
This line was appended. (suffix) [📎 attachment]
```

### Test 130: Legacy `-s` (search)

```
$ ./cider notes -s CiderTest Beta
Found 1 note(s) matching "CiderTest Beta":

  # Title                                      Folder                
--- ------------------------------------------ ----------------------
  1 CiderTest Beta                             Cider Tests           
```

### Test 131: Legacy `-f` (folder filter)

```
$ ./cider notes -f Cider Tests
  # Title                                      Folder                 Attachments
--- ------------------------------------------ ---------------------- -----------
  1 CiderTest Beta                             Cider Tests            
  2 CiderTest Piped                            Cider Tests            
  3 CiderTest CaseTest                         Cider Tests            
  4 CiderTest ReplAll2                         Cider Tests            
  5 CiderTest ReplAll1                         Cider Tests            
  6 CiderTest Regex                            Cider Tests            
  7 CiderTest Attach                           Cider Tests            
  8 CiderTest Gamma                            Cider Tests            
  9 CiderTest Alpha                            Cider Tests            
 10 Untag Test                                 Cider Tests            
 11 CiderTest Prepend                          Cider Tests            
 12 CiderTest Append                           Cider Tests            
 13 Live Refresh Test                          Cider Tests            
 14 AS Created Note                            Cider Tests            
 15 Serialize Test                             Cider Tests            
 16 New Note                                   Cider Tests            
 17 New Note                                   Cider Tests            
 18 New Note                                   Cider Tests            
 19 New Note                                   Cider Tests            

Total: 19 note(s)
```
Delete note "CiderTest Alpha"? (y/N) Deleted: "CiderTest Alpha"
Delete note "CiderTest Beta"? (y/N) Deleted: "CiderTest Beta"
Delete note "CiderTest Gamma"? (y/N) Deleted: "CiderTest Gamma"
Delete note "CiderTest Attach"? (y/N) Deleted: "CiderTest Attach"
Delete note "CiderTest Regex"? (y/N) Deleted: "CiderTest Regex"
Delete note "CiderTest ReplAll1"? (y/N) Deleted: "CiderTest ReplAll1"
Delete note "CiderTest ReplAll2"? (y/N) Deleted: "CiderTest ReplAll2"
Delete note "CiderTest CaseTest"? (y/N) Deleted: "CiderTest CaseTest"
Delete note "CiderTest Piped"? (y/N) Deleted: "CiderTest Piped"

---

*Report complete — 131 test cases demonstrated. All test notes cleaned up.*
