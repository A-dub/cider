/**
 * main.m — Help text, argument parsing, and command dispatch
 *
 * Compile: clang -framework Foundation -framework CoreData -o cider \
 *          core.m notes.m reminders.m sync.m main.m
 */

#import "cider.h"

// ─────────────────────────────────────────────────────────────────────────────
// Help text
// ─────────────────────────────────────────────────────────────────────────────

void printHelp(void) {
    printf(
"cider v" VERSION " — Apple Notes CLI with CRDT attachment support\n"
"\n"
"USAGE:\n"
"  cider notes [subcommand]   Notes operations\n"
"  cider templates [sub]      Template management\n"
"  cider settings [sub]       Cider configuration\n"
"  cider rem [subcommand]     Reminders operations\n"
"  cider sync [subcommand]    Bidirectional Notes <-> Markdown sync\n"
"  cider --version            Show version\n"
"  cider --help               Show this help\n"
"\n"
"NOTES SUBCOMMANDS:\n"
"  list [-f <folder>] [--json] [--after <date>] [--before <date>] [--sort <mode>]\n"
"       [--pinned]                      List notes (default when no subcommand)\n"
"  show <N> [--json]                   View note N  (also: cider notes <N>)\n"
"  folders [--json]                    List all folders\n"
"  add [--folder <f>] [--template <t>] Add note (stdin, $EDITOR, or template)\n"
"  edit <N>                            Edit note N (CRDT — preserves attachments!)\n"
"  delete <N>                          Delete note N\n"
"  move <N> <folder>                   Move note N to folder\n"
"  pin <N>                             Pin note N\n"
"  unpin <N>                           Unpin note N\n"
"  tag <N> <tag>                       Add #tag to note N\n"
"  untag <N> <tag>                     Remove #tag from note N\n"
"  tags [--count] [--json]             List all unique tags\n"
"  share <N> [--json]                 Show sharing status for note N\n"
"  shared [--json]                    List all shared notes\n"
"  table <N> [options]                Show table data (aligned, CSV, JSON)\n"
"  checklist <N> [--summary] [--json] Show checklist items with status\n"
"  check <N> <item#>                 Check off checklist item\n"
"  uncheck <N> <item#>               Uncheck checklist item\n"
"  watch [options]                    Stream note change events\n"
"  links <N> [--json]                 Show outgoing note links\n"
"  backlinks <N> [--json]             Show notes linking to note N\n"
"  backlinks --all [--json]           Full link graph\n"
"  link <N> <target title>            Create link to another note\n"
"  folder create <name> [--parent <p>] Create a new folder\n"
"  folder delete <name>                Delete empty folder\n"
"  folder rename <old> <new>           Rename folder\n"
"  replace <N> --find <s> --replace <s> [--regex] [-i]\n"
"                                       Find & replace in note N (full content)\n"
"  replace --all --find <s> --replace <s> [--folder <f>] [--regex] [-i] [--dry-run]\n"
"                                       Find & replace across multiple notes\n"
"  append <N> <text> [--no-newline] [-f <folder>]\n"
"                                       Append text to end of note N\n"
"  prepend <N> <text> [--no-newline] [-f <folder>]\n"
"                                       Insert text after title of note N\n"
"  search <query> [--json] [--regex] [--title] [--body] [-f <folder>]\n"
"                                       Search notes (title + body by default)\n"
"  export <path>                       Export all notes to HTML\n"
"  attachments <N> [--json]             List attachments in note N\n"
"  attach <N> <file> [--at <pos>]      Add file attachment to note N\n"
"  detach <N> [<A>]                    Remove attachment A (1-based) from note N\n"
"\n"
"REMINDERS SUBCOMMANDS:\n"
"  list                               List incomplete reminders (default)\n"
"  add <title> [due-date]             Add reminder\n"
"  edit <N> <new-title>               Edit reminder N\n"
"  delete <N>                         Delete reminder N\n"
"  complete <N>                       Complete reminder N\n"
"\n"
"SYNC SUBCOMMANDS:\n"
"  run [--dir <path>]                 One sync cycle (auto-inits on first run)\n"
"  watch [--dir <path>] [--interval N] Continuous sync daemon (default: 2s)\n"
"  backup [--dir <path>]              Backup Notes database\n"
"\n"
"  Sync mirrors Notes to local Markdown files with YAML frontmatter.\n"
"  New .md files create Apple Notes; edits to owned notes sync back.\n"
"  Pre-existing notes are NEVER modified or deleted (editable: false).\n"
"  Default sync dir: ~/CiderSync. Run 'cider sync --help' for details.\n"
"\n"
"  Examples:\n"
"    cider sync run                        First run: backup + export all notes\n"
"    cider sync run --dir ~/my-notes       Sync to a custom directory\n"
"    cider sync watch                      Continuous sync (polls every 2s)\n"
"    cider sync watch --interval 10        Poll every 10 seconds\n"
"    cider sync backup                     Manual backup of Notes database\n"
"\n"
"SETTINGS:\n"
"  cider settings                     Show current settings\n"
"  cider settings get <key>           Get a single setting\n"
"  cider settings set <key> <value>   Set a setting\n"
"  cider settings reset               Reset all settings\n"
"  cider settings --json              JSON output\n"
"\n"
"  Settings are stored in a \"Cider Settings\" note. Available keys:\n"
"    default_folder    Default folder for new notes\n"
"    default_sort      Default sort order (title|modified|created)\n"
"    editor            Preferred editor ($EDITOR override)\n"
"\n"
"  Examples:\n"
"    cider settings set default_folder \"Work Notes\"\n"
"    cider settings set default_sort modified\n"
"    cider settings get default_folder\n"
"\n"
"BACKWARDS COMPAT (old flags still work):\n"
"  cider notes -fl             →  cider notes folders\n"
"  cider notes -v N            →  cider notes show N\n"
"  cider notes -e N            →  cider notes edit N\n"
"  cider notes -d N            →  cider notes delete N\n"
"  cider notes -s query        →  cider notes search query\n"
"  cider notes --attach N file →  cider notes attach N file\n"
"  cider notes --export path   →  cider notes export path\n"
"\n"
"CRDT EDIT:\n"
"  'edit' opens the note in $EDITOR with %%ATTACHMENT_N_name%%\n"
"  markers where images/files are. Edit the text freely; do NOT remove\n"
"  or rename the markers. Changes are applied via ICTTMergeableString.\n"
"  Pipe content instead: echo 'new body' | cider notes edit N\n"
    );
}

void printNotesHelp(void) {
    printf(
"cider notes v" VERSION " — Apple Notes CLI\n"
"\n"
"USAGE:\n"
"  cider notes                              List all notes\n"
"  cider notes list [options]               List notes (filter, sort, date range)\n"
"  cider notes <N>                          View note N\n"
"  cider notes show <N> [--json]            View note N\n"
"  cider notes inspect <N> [--json]        Full note details (metadata, tags, links, tables...)\n"
"  cider notes history <N> [--raw|--json]  CRDT edit timeline (who typed what, when)\n"
"  cider notes getdate <N> [--json]        Show note's modification/creation dates\n"
"  cider notes setdate <N> <date> [--dry-run]  Set note's modification date\n"
"  cider notes folders [--json]             List all folders\n"
"  cider notes add [--folder <f>]           Add note (reads stdin or $EDITOR)\n"
"  cider notes edit <N>                     Edit note N via CRDT (preserves attachments)\n"
"                                           Pipe: echo 'content' | cider notes edit N\n"
"  cider notes delete <N>                   Delete note N\n"
"  cider notes move <N> <folder>            Move note N to folder\n"
"  cider notes export <path>                Export notes to HTML\n"
"  cider notes attachments <N> [--json]     List attachments with positions\n"
"  cider notes attach <N> <file> [--at <pos>]  Attach file at position (CRDT)\n"
"  cider notes detach <N> [<A>]             Remove attachment A from note N\n"
"\n"
"APPEND / PREPEND:\n"
"  cider notes append <N> <text> [options]\n"
"  cider notes prepend <N> <text> [options]\n"
"\n"
"  Append adds text to the end of the note. Prepend inserts text right\n"
"  after the title line. Both support stdin piping.\n"
"\n"
"  --no-newline     Don't add newline separator\n"
"  -f, --folder <f> Scope note index to folder\n"
"\n"
"  Examples:\n"
"    cider notes append 3 \"Added at the bottom\"\n"
"    cider notes prepend 3 \"Inserted after title\"\n"
"    echo \"piped text\" | cider notes append 3\n"
"    cider notes append 3 \"no gap\" --no-newline\n"
"    cider notes prepend 3 \"text\" -f \"Work Notes\"\n"
"\n"
"TEMPLATES:\n"
"  cider templates list                    List templates\n"
"  cider templates show <name>             View template content\n"
"  cider templates add                     Create new template ($EDITOR)\n"
"  cider templates delete <name>           Delete template\n"
"  cider notes add --template <name>       Create note from template\n"
"\n"
"  Templates are stored as notes in the \"Cider Templates\" folder.\n"
"  When creating from a template, the body is pre-filled in $EDITOR.\n"
"\n"
"  Examples:\n"
"    cider templates add                   Create a template in $EDITOR\n"
"    cider templates list                  List all templates\n"
"    cider templates show \"Meeting Notes\"  View template content\n"
"    cider notes add --template \"Meeting Notes\"  Create note from template\n"
"    cider notes add --template \"TODO\" -f Work   Template + target folder\n"
"\n"
"SHARING:\n"
"  cider notes share <N>                     Show sharing status for note N\n"
"  cider notes share <N> --json              JSON share status\n"
"  cider notes shared                        List all shared notes\n"
"  cider notes shared --json                 JSON list of shared notes\n"
"\n"
"  Shows iCloud collaboration status and participant count.\n"
"  Share URLs are not programmatically accessible; use Apple Notes\n"
"  Share button to create/manage collaboration links.\n"
"\n"
"  Examples:\n"
"    cider notes share 5                     Show share status for note 5\n"
"    cider notes shared                      List all shared notes\n"
"    cider notes shared --json               JSON output for piping\n"
"\n"
"TABLES:\n"
"  cider notes table <N>                     Show first table (aligned columns)\n"
"  cider notes table <N> --list              List all tables with row/col counts\n"
"  cider notes table <N> --index 1           Show second table (0-based)\n"
"  cider notes table <N> --json              Table as JSON array of objects\n"
"  cider notes table <N> --csv               Table as CSV\n"
"  cider notes table <N> --row 2             Specific row (0-based)\n"
"  cider notes table <N> --headers           Column headers only\n"
"  cider notes table <N> --add-row \"a|b|c\"  Add row (creates table if none)\n"
"\n"
"  Native Apple Notes tables (com.apple.notes.table attachments).\n"
"  Uses ICAttachmentTableModel and ICTable to access row/column data.\n"
"  Row 0 is treated as the header row for JSON key names.\n"
"  --add-row can be repeated to add multiple rows at once.\n"
"\n"
"  Examples:\n"
"    cider notes table 5                     Show first table, aligned\n"
"    cider notes table 5 --list              List tables in note 5\n"
"    cider notes table 5 --json              JSON array of {header: value}\n"
"    cider notes table 5 --csv               CSV output\n"
"    cider notes table 5 --row 0             First row (headers)\n"
"    cider notes table 5 --index 1 --csv     Second table as CSV\n"
"    cider notes table 5 --add-row \"Name|Value\"  Create table with header row\n"
"    cider notes table 5 --add-row \"Row1|Data\"   Add data row\n"
"    cider notes table 5 --headers           Column headers only\n"
"\n"
"CHECKLISTS:\n"
"  cider notes checklist <N>                 Show checklist items with status\n"
"  cider notes checklist <N> --summary       Summary only (e.g. \"3/6 complete\")\n"
"  cider notes checklist <N> --json          JSON output\n"
"  cider notes checklist <N> --add \"text\"    Add a new checklist item\n"
"  cider notes check <N> <item#>             Check off item by number\n"
"  cider notes uncheck <N> <item#>           Uncheck item by number\n"
"\n"
"  Reads native Apple Notes checklist formatting (style 103 paragraphs).\n"
"  Items are numbered sequentially (1-based). Check/uncheck toggles\n"
"  the done state via the CRDT attributed string.\n"
"\n"
"  Examples:\n"
"    cider notes checklist 5                Show all items with [x]/[ ] status\n"
"    cider notes checklist 5 --summary      \"3/6 items complete\"\n"
"    cider notes check 5 2                  Check off item 2\n"
"    cider notes uncheck 5 2                Uncheck item 2\n"
"    cider notes checklist 5 --add \"Buy milk\"  Add new item\n"
"    cider notes checklist 5 --json         JSON with items array\n"
"\n"
"WATCH / EVENTS:\n"
"  cider notes watch                          Stream note change events\n"
"  cider notes watch --folder <f>             Watch specific folder\n"
"  cider notes watch --interval 5             Poll interval (default 2s)\n"
"  cider notes watch --json                   JSON event stream for AI piping\n"
"\n"
"  Polls for note changes and streams events: created, modified, deleted.\n"
"  Reads watch_interval from Cider Settings if no --interval flag.\n"
"\n"
"  Examples:\n"
"    cider notes watch                        Watch all notes (2s poll)\n"
"    cider notes watch -f \"Work Notes\"         Watch specific folder\n"
"    cider notes watch --interval 10           Poll every 10 seconds\n"
"    cider notes watch --json                  JSON events for piping\n"
"    cider notes watch --json | while read e; do echo \"$e\" | jq; done\n"
"\n"
"NOTE LINKS / BACKLINKS:\n"
"  cider notes links <N> [--json]             Show outgoing note links\n"
"  cider notes backlinks <N> [--json]         Show notes linking to note N\n"
"  cider notes backlinks --all [--json]       Full link graph\n"
"  cider notes link <N> <target title>       Create link to another note\n"
"\n"
"  Links use Apple Notes native inline attachments (same as >> syntax).\n"
"  Cider can both create and read note-to-note links.\n"
"\n"
"  Examples:\n"
"    cider notes links 5                Show what note 5 links to\n"
"    cider notes backlinks 5            Show notes that link to note 5\n"
"    cider notes backlinks --all        Full link graph across all notes\n"
"    cider notes link 5 Meeting Notes   Link note 5 to \"Meeting Notes\"\n"
"    cider notes links 5 --json         JSON output\n"
"\n"
"FOLDER MANAGEMENT:\n"
"  cider notes folder create <name>           Create a new folder\n"
"  cider notes folder create <name> --parent <p>  Nested folder\n"
"  cider notes folder delete <name>           Delete empty folder\n"
"  cider notes folder rename <old> <new>      Rename folder\n"
"\n"
"  Delete requires the folder to be empty (move/delete notes first).\n"
"  Rename checks that the new name doesn't already exist.\n"
"\n"
"  Examples:\n"
"    cider notes folder create \"Work Notes\"\n"
"    cider notes folder create \"Meetings\" --parent \"Work Notes\"\n"
"    cider notes folder delete \"Old Stuff\"\n"
"    cider notes folder rename \"Work\" \"Work Notes\"\n"
"\n"
"TAGS:\n"
"  cider notes tag <N> <tag>           Add #tag to end of note\n"
"  cider notes untag <N> <tag>         Remove all occurrences of #tag\n"
"  cider notes tags [--count] [--json] List all unique tags across all notes\n"
"  cider notes list --tag <tag>        Filter notes containing #tag\n"
"  cider notes search <q> --tag <tag>  Combine search + tag filter\n"
"\n"
"  Tags are #word patterns in note text (Apple Notes native hashtags).\n"
"  Auto-prepends # if omitted. Case-insensitive matching.\n"
"\n"
"  Examples:\n"
"    cider notes tag 3 \"project-x\"         Add #project-x to note 3\n"
"    cider notes untag 3 \"#project-x\"      Remove #project-x from note 3\n"
"    cider notes tags --count              Show tags with note counts\n"
"    cider notes list --tag project-x      List notes with #project-x\n"
"    cider notes search \"meeting\" --tag work  Search + tag filter\n"
"\n"
"PIN / UNPIN:\n"
"  cider notes pin <N> [-f <folder>]\n"
"  cider notes unpin <N> [-f <folder>]\n"
"\n"
"  Pin or unpin a note. Pinned notes appear at the top in Apple Notes.\n"
"  Use --pinned with list to show only pinned notes.\n"
"\n"
"  Examples:\n"
"    cider notes pin 3\n"
"    cider notes unpin 3\n"
"    cider notes list --pinned\n"
"    cider notes pin 1 -f Work\n"
"\n"
"HISTORY:\n"
"  cider notes history <N>                 Show CRDT edit timeline\n"
"  cider notes history <N> --raw           Per-keystroke detail\n"
"  cider notes history <N> --json          JSON output\n"
"\n"
"  Shows when and how a note was edited, extracted from the CRDT.\n"
"  Default groups edits into sessions (>60s gap = new session).\n"
"  --raw shows every individual edit with per-second timestamps.\n"
"  Each device that edited the note gets a letter label (A, B, C...).\n"
"\n"
"  Examples:\n"
"    cider notes history 5                 Session-grouped timeline\n"
"    cider notes history 5 --raw           Every keystroke\n"
"    cider notes history 5 --json          JSON for piping\n"
"\n"
"DATES:\n"
"  cider notes getdate <N> [--json]        Show modification & creation dates\n"
"  cider notes setdate <N> <date>          Set modification date\n"
"  cider notes setdate <N> <date> --dry-run  Preview without changing\n"
"\n"
"  Date format: ISO 8601 (2024-01-15T14:30:00 or 2024-01-15)\n"
"\n"
"  Examples:\n"
"    cider notes getdate 349               Show dates for note 349\n"
"    cider notes setdate 349 2024-06-15T10:30:00  Set modification date\n"
"    cider notes setdate 349 2024-06-15 --dry-run  Preview change\n"
"\n"
"DEBUG:\n"
"  cider notes debug <N> [-f <folder>]\n"
"\n"
"  Dumps all attributed string attribute keys and values for a note.\n"
"  Useful for discovering how Apple Notes stores checklists, tables,\n"
"  links, and other rich formatting internally.\n"
"\n"
"LIST (date filtering & sorting):\n"
"  cider notes list [options]\n"
"\n"
"  --after <date>              Notes modified after date\n"
"  --before <date>             Notes modified before date\n"
"  --sort created|modified|title  Sort order (default: title)\n"
"  --pinned                   Show only pinned notes\n"
"  --tag <tag>                Filter notes containing #tag\n"
"  -f, --folder <f>           Filter by folder\n"
"  --json                     JSON output (includes created/modified dates)\n"
"\n"
"  Date formats:\n"
"    ISO 8601:   2024-01-15, 2024-01-15T10:30:00\n"
"    Relative:   today, yesterday, \"3 days ago\", \"1 week ago\", \"2 months ago\"\n"
"\n"
"  Examples:\n"
"    cider notes list --after today\n"
"    cider notes list --before 2024-06-01\n"
"    cider notes list --after yesterday --sort modified\n"
"    cider notes list --sort created --json\n"
"    cider notes list --after \"1 week ago\" -f Work\n"
"    cider notes search \"meeting\" --after today\n"
"\n"
"SEARCH:\n"
"  cider notes search <query> [options]\n"
"\n"
"  Searches note title AND body by default (case-insensitive).\n"
"\n"
"  --regex          Treat query as ICU regular expression\n"
"  --title          Search title only (mutually exclusive with --body)\n"
"  --body           Search body only (mutually exclusive with --title)\n"
"  -f, --folder <f> Scope search to a specific folder\n"
"  --after <date>   Only notes modified after date\n"
"  --before <date>  Only notes modified before date\n"
"  --json           Output results as JSON\n"
"\n"
"  Examples:\n"
"    cider notes search \"meeting\"                  Literal search (title + body)\n"
"    cider notes search \"\\\\d{3}-\\\\d{4}\" --regex     Find phone numbers\n"
"    cider notes search \"TODO\" --title              Search titles only\n"
"    cider notes search \"important\" --body -f Work  Search body in Work folder\n"
"    cider notes search \"meeting\" --after today     Search with date filter\n"
"\n"
"REPLACE (single note):\n"
"  cider notes replace <N> --find <s> --replace <s> [options]\n"
"\n"
"  Replaces text in the full content (title is the first line) of note N.\n"
"  Operates on a single note. Attachments are never touched.\n"
"\n"
"  --regex          Treat --find as ICU regex; --replace supports $1, $2 backrefs\n"
"  -i, --case-insensitive   Case-insensitive matching\n"
"\n"
"  Examples:\n"
"    cider notes replace 3 --find old --replace new\n"
"    cider notes replace 3 --find \"(\\\\w+)@(\\\\w+)\" --replace \"[$1 at $2]\" --regex\n"
"    cider notes replace 3 --find \"todo\" --replace \"DONE\" -i\n"
"\n"
"REPLACE (multiple notes):\n"
"  cider notes replace --all --find <s> --replace <s> [options]\n"
"\n"
"  Replaces across ALL notes (or folder-scoped). Shows a summary and asks\n"
"  for confirmation before applying. Skips notes where attachments would change.\n"
"\n"
"  --all             Required: enables multi-note mode\n"
"  --folder <f>, -f  Scope to a specific folder\n"
"  --dry-run         Preview changes without applying\n"
"  --regex           ICU regex (--replace supports $1, $2)\n"
"  -i, --case-insensitive   Case-insensitive matching\n"
"\n"
"  Examples:\n"
"    cider notes replace --all --find old --replace new --dry-run\n"
"    cider notes replace --all --find old --replace new -f Work\n"
"    cider notes replace --all --find \"http://\" --replace \"https://\" --folder Work\n"
"\n"
"OPTIONS:\n"
"  --json    Output as JSON (for list, show, search, folders)\n"
"  -f, --folder <name>   Filter by folder (for list, search, replace --all)\n"
"\n"
"Interactive mode: if <N> is omitted from edit/delete/move/show/replace/attach,\n"
"you'll be prompted to enter it (when stdin is a terminal).\n"
    );
}

void printRemHelp(void) {
    printf(
"cider rem v" VERSION " — Reminders CLI\n"
"\n"
"USAGE:\n"
"  cider rem                          List all incomplete reminders\n"
"  cider rem list                     List all incomplete reminders\n"
"  cider rem add <title>              Add reminder\n"
"  cider rem add <title> <due>        Add reminder with due date\n"
"  cider rem edit <N> <new-title>     Edit reminder N\n"
"  cider rem delete <N>               Delete reminder N\n"
"  cider rem complete <N>             Complete reminder N\n"
    );
}

// ─────────────────────────────────────────────────────────────────────────────
// Argument parsing helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *argValue(int argc, char *argv[], int startIdx, const char *flag1, const char *flag2) {
    for (int i = startIdx; i < argc - 1; i++) {
        if ((flag1 && strcmp(argv[i], flag1) == 0) ||
            (flag2 && strcmp(argv[i], flag2) == 0)) {
            return [NSString stringWithUTF8String:argv[i + 1]];
        }
    }
    return nil;
}

BOOL argHasFlag(int argc, char *argv[], int startIdx, const char *flag1, const char *flag2) {
    for (int i = startIdx; i < argc; i++) {
        if ((flag1 && strcmp(argv[i], flag1) == 0) ||
            (flag2 && strcmp(argv[i], flag2) == 0)) {
            return YES;
        }
    }
    return NO;
}

// ─────────────────────────────────────────────────────────────────────────────
// main
// ─────────────────────────────────────────────────────────────────────────────

int main(int argc, char *argv[]) {
    @autoreleasepool {

        if (argc < 2) {
            printHelp();
            return 0;
        }

        NSString *cmd = [NSString stringWithUTF8String:argv[1]];

        // ── top-level flags ──────────────────────────────────────────────────
        if ([cmd isEqualToString:@"--version"] ||
            [cmd isEqualToString:@"-V"]) {
            printf("cider v" VERSION "\n");
            return 0;
        }
        if ([cmd isEqualToString:@"--help"] ||
            [cmd isEqualToString:@"-h"]) {
            printHelp();
            return 0;
        }

        // ── notes ────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"notes"]) {
            if (argc >= 3 && strcmp(argv[2], "--help") == 0) {
                printNotesHelp();
                return 0;
            }
            if (argc >= 3 && strcmp(argv[2], "-h") == 0) {
                printNotesHelp();
                return 0;
            }

            if (!initNotesContext()) return 1;

            if (argc == 2) {
                cmdNotesList(nil, NO, nil, nil, nil, NO, nil);
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];

            // ── cider notes <N>  (bare number → show) ──
            if ([sub intValue] > 0 && [sub isEqualToString:
                [NSString stringWithFormat:@"%d", [sub intValue]]]) {
                NSUInteger idx = (NSUInteger)[sub intValue];
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                return cmdNotesView(idx, nil, jsonOut);
            }

            // ── cider notes list ──
            if ([sub isEqualToString:@"list"]) {
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                NSString *afterStr = argValue(argc, argv, 3, "--after", NULL);
                NSString *beforeStr = argValue(argc, argv, 3, "--before", NULL);
                NSString *sortMode = argValue(argc, argv, 3, "--sort", NULL);
                BOOL pinnedOnly = argHasFlag(argc, argv, 3, "--pinned", NULL);
                NSString *tagFilter = argValue(argc, argv, 3, "--tag", NULL);
                cmdNotesList(folder, jsonOut, afterStr, beforeStr, sortMode, pinnedOnly, tagFilter);

            // ── cider notes show ──
            } else if ([sub isEqualToString:@"show"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"show", nil);
                if (!idx) return 1;
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                return cmdNotesView(idx, nil, jsonOut);

            // ── cider notes inspect ──
            } else if ([sub isEqualToString:@"inspect"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *fldr = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"inspect", fldr);
                if (!idx) return 1;
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                return cmdNotesInspect(idx, fldr, jsonOut);

            // ── cider notes folders ──
            } else if ([sub isEqualToString:@"folders"]) {
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                cmdFoldersList(jsonOut);

            // ── cider notes add ──
            } else if ([sub isEqualToString:@"add"]) {
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                NSString *tmpl = argValue(argc, argv, 3, "--template", NULL);
                if (tmpl) {
                    return cmdNotesAddFromTemplate(tmpl, folder);
                }
                cmdNotesAdd(folder);

            // ── cider notes edit ──
            } else if ([sub isEqualToString:@"edit"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"edit", nil);
                if (!idx) return 1;
                cmdNotesEdit(idx);

            // ── cider notes delete ──
            } else if ([sub isEqualToString:@"delete"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"delete", nil);
                if (!idx) return 1;
                cmdNotesDelete(idx);

            // ── cider notes move ──
            } else if ([sub isEqualToString:@"move"]) {
                NSUInteger idx = 0;
                NSString *targetFolder = nil;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"move", nil);
                if (!idx) return 1;
                targetFolder = argValue(argc, argv, 3, "--folder", "-f");
                if (!targetFolder && argc >= 5) {
                    const char *arg4 = argv[4];
                    if (arg4[0] != '-') {
                        targetFolder = [NSString stringWithUTF8String:arg4];
                    }
                }
                if (!targetFolder) {
                    fprintf(stderr, "Usage: cider notes move <N> <folder>\n");
                    return 1;
                }
                cmdNotesMove(idx, targetFolder);

            // ── cider notes append ──
            } else if ([sub isEqualToString:@"append"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                BOOL noNewline = argHasFlag(argc, argv, 3, "--no-newline", NULL);
                if (!idx) idx = promptNoteIndex(@"append to", folder);
                if (!idx) return 1;

                // Collect non-flag arguments after index as text (priority over stdin)
                NSString *text = nil;
                NSMutableArray *parts = [NSMutableArray array];
                for (int i = 4; i < argc; i++) {
                    if (strcmp(argv[i], "--no-newline") == 0 ||
                        strcmp(argv[i], "--folder") == 0 ||
                        strcmp(argv[i], "-f") == 0) {
                        if (strcmp(argv[i], "--folder") == 0 ||
                            strcmp(argv[i], "-f") == 0) i++; // skip value
                        continue;
                    }
                    [parts addObject:[NSString stringWithUTF8String:argv[i]]];
                }
                if (parts.count > 0) {
                    text = [parts componentsJoinedByString:@" "];
                }

                // Fall back to stdin if no argument text
                if (!text && !isatty(STDIN_FILENO)) {
                    NSFileHandle *fh = [NSFileHandle fileHandleWithStandardInput];
                    NSData *data = [fh readDataToEndOfFile];
                    text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if ([text hasSuffix:@"\n"]) {
                        text = [text substringToIndex:[text length] - 1];
                    }
                }

                if (!text || [text length] == 0) {
                    fprintf(stderr, "Error: No text provided. Pass text as argument or pipe from stdin.\n");
                    return 1;
                }
                return cmdNotesAppend(idx, text, folder, noNewline);

            // ── cider notes prepend ──
            } else if ([sub isEqualToString:@"prepend"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                BOOL noNewline = argHasFlag(argc, argv, 3, "--no-newline", NULL);
                if (!idx) idx = promptNoteIndex(@"prepend to", folder);
                if (!idx) return 1;

                // Collect non-flag arguments after index as text (priority over stdin)
                NSString *text = nil;
                NSMutableArray *parts = [NSMutableArray array];
                for (int i = 4; i < argc; i++) {
                    if (strcmp(argv[i], "--no-newline") == 0 ||
                        strcmp(argv[i], "--folder") == 0 ||
                        strcmp(argv[i], "-f") == 0) {
                        if (strcmp(argv[i], "--folder") == 0 ||
                            strcmp(argv[i], "-f") == 0) i++;
                        continue;
                    }
                    [parts addObject:[NSString stringWithUTF8String:argv[i]]];
                }
                if (parts.count > 0) {
                    text = [parts componentsJoinedByString:@" "];
                }

                // Fall back to stdin if no argument text
                if (!text && !isatty(STDIN_FILENO)) {
                    NSFileHandle *fh = [NSFileHandle fileHandleWithStandardInput];
                    NSData *data = [fh readDataToEndOfFile];
                    text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                    if ([text hasSuffix:@"\n"]) {
                        text = [text substringToIndex:[text length] - 1];
                    }
                }

                if (!text || [text length] == 0) {
                    fprintf(stderr, "Error: No text provided. Pass text as argument or pipe from stdin.\n");
                    return 1;
                }
                return cmdNotesPrepend(idx, text, folder, noNewline);

            // ── cider notes debug ──
            } else if ([sub isEqualToString:@"debug"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"debug", folder);
                if (!idx) return 1;
                cmdNotesDebug(idx, folder);

            // ── cider notes history ──
            } else if ([sub isEqualToString:@"history"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"history", folder);
                if (!idx) return 1;
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                BOOL rawOut = argHasFlag(argc, argv, 3, "--raw", NULL);
                cmdNotesHistory(idx, folder, jsonOut, rawOut);

            // ── cider notes getdate ──
            } else if ([sub isEqualToString:@"getdate"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"get date of", folder);
                if (!idx) return 1;
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                return cmdNotesGetdate(idx, folder, jsonOut);

            // ── cider notes setdate ──
            } else if ([sub isEqualToString:@"setdate"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"set date on", folder);
                if (!idx) return 1;
                BOOL dryRun = argHasFlag(argc, argv, 3, "--dry-run", NULL);
                NSString *dateStr = nil;
                for (int i = 4; i < argc; i++) {
                    if (argv[i][0] != '-') {
                        dateStr = [NSString stringWithUTF8String:argv[i]];
                        break;
                    }
                }
                if (!dateStr) {
                    fprintf(stderr, "Usage: cider notes setdate <N> <ISO-date> [--dry-run]\n");
                    return 1;
                }
                return cmdNotesSetdate(idx, dateStr, folder, dryRun);

            // ── cider notes pin ──
            } else if ([sub isEqualToString:@"pin"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"pin", folder);
                if (!idx) return 1;
                return cmdNotesPin(idx, folder);

            // ── cider notes unpin ──
            } else if ([sub isEqualToString:@"unpin"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"unpin", folder);
                if (!idx) return 1;
                return cmdNotesUnpin(idx, folder);

            // ── cider notes watch ──
            } else if ([sub isEqualToString:@"watch"]) {
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                NSTimeInterval interval = 2.0;
                NSString *intStr = argValue(argc, argv, 3, "--interval", NULL);
                if (intStr) interval = [intStr doubleValue];
                if (!intStr) {
                    NSString *settingInterval = getCiderSetting(@"watch_interval");
                    if (settingInterval) interval = [settingInterval doubleValue];
                }
                if (interval < 0.5) interval = 0.5;
                cmdNotesWatch(folder, interval, jsonOut);
                return 0; // never reached (infinite loop)

            // ── cider notes links ──
            } else if ([sub isEqualToString:@"links"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                if (!idx) idx = promptNoteIndex(@"show links for", folder);
                if (!idx) return 1;
                cmdNotesLinks(idx, folder, jsonOut);

            // ── cider notes backlinks ──
            } else if ([sub isEqualToString:@"backlinks"]) {
                BOOL allLinks = argHasFlag(argc, argv, 3, "--all", NULL);
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                if (allLinks) {
                    cmdNotesBacklinksAll(jsonOut);
                } else {
                    NSUInteger idx = 0;
                    if (argc >= 4) {
                        int v = atoi(argv[3]);
                        if (v > 0) idx = (NSUInteger)v;
                    }
                    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                    if (!idx) idx = promptNoteIndex(@"show backlinks for", folder);
                    if (!idx) return 1;
                    cmdNotesBacklinks(idx, folder, jsonOut);
                }

            // ── cider notes link ──
            } else if ([sub isEqualToString:@"link"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                NSString *target = nil;
                if (argc >= 5) {
                    // Collect remaining args as target title
                    NSMutableArray *parts = [NSMutableArray array];
                    for (int i = 4; i < argc; i++) {
                        NSString *a = [NSString stringWithUTF8String:argv[i]];
                        if ([a hasPrefix:@"--"] || [a hasPrefix:@"-f"]) break;
                        [parts addObject:a];
                    }
                    if (parts.count > 0)
                        target = [parts componentsJoinedByString:@" "];
                }
                if (!idx) idx = promptNoteIndex(@"link from", folder);
                if (!idx) return 1;
                if (!target || target.length == 0) {
                    fprintf(stderr, "Usage: cider notes link <N> <target note title>\n");
                    return 1;
                }
                return cmdNotesLink(idx, target, folder);

            // ── cider notes share ──
            } else if ([sub isEqualToString:@"share"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                if (!idx) idx = promptNoteIndex(@"show share status for", folder);
                if (!idx) return 1;
                cmdNotesShare(idx, folder, jsonOut);

            // ── cider notes shared ──
            } else if ([sub isEqualToString:@"shared"]) {
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                cmdNotesShared(jsonOut);

            // ── cider notes table ──
            } else if ([sub isEqualToString:@"table"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"show table for", folder);
                if (!idx) return 1;
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                BOOL csvOut = argHasFlag(argc, argv, 3, "--csv", NULL);
                BOOL listTables = argHasFlag(argc, argv, 3, "--list", NULL);
                BOOL headersOnly = argHasFlag(argc, argv, 3, "--headers", NULL);
                NSUInteger tableIdx = 0;
                NSString *indexStr = argValue(argc, argv, 3, "--index", NULL);
                if (indexStr) tableIdx = (NSUInteger)[indexStr intValue];
                NSInteger rowNum = -1;
                NSString *rowStr = argValue(argc, argv, 3, "--row", NULL);
                if (rowStr) rowNum = [rowStr integerValue];

                // Collect --add-row arguments (can be repeated)
                NSMutableArray *addRows = [NSMutableArray array];
                for (int i = 3; i < argc; i++) {
                    if (strcmp(argv[i], "--add-row") == 0 && i + 1 < argc) {
                        [addRows addObject:[NSString stringWithUTF8String:argv[++i]]];
                    }
                }
                if (addRows.count > 0) {
                    return cmdNotesTableAdd(idx, folder, addRows);
                }

                cmdNotesTable(idx, folder, tableIdx, jsonOut, csvOut, listTables, headersOnly, rowNum);

            // ── cider notes checklist ──
            } else if ([sub isEqualToString:@"checklist"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"show checklist for", folder);
                if (!idx) return 1;
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                BOOL summary = argHasFlag(argc, argv, 3, "--summary", NULL);
                NSString *addText = argValue(argc, argv, 3, "--add", NULL);
                cmdNotesChecklist(idx, folder, jsonOut, summary, addText);

            // ── cider notes check ──
            } else if ([sub isEqualToString:@"check"]) {
                NSUInteger idx = 0;
                NSUInteger itemNum = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (argc >= 5) {
                    int v = atoi(argv[4]);
                    if (v > 0) itemNum = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"check item in", folder);
                if (!idx) return 1;
                if (!itemNum) {
                    fprintf(stderr, "Usage: cider notes check <N> <item#>\n");
                    return 1;
                }
                return cmdNotesCheck(idx, itemNum, folder);

            // ── cider notes uncheck ──
            } else if ([sub isEqualToString:@"uncheck"]) {
                NSUInteger idx = 0;
                NSUInteger itemNum = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (argc >= 5) {
                    int v = atoi(argv[4]);
                    if (v > 0) itemNum = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"uncheck item in", folder);
                if (!idx) return 1;
                if (!itemNum) {
                    fprintf(stderr, "Usage: cider notes uncheck <N> <item#>\n");
                    return 1;
                }
                return cmdNotesUncheck(idx, itemNum, folder);

            // ── cider notes folder ──
            } else if ([sub isEqualToString:@"folder"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes folder create|delete|rename ...\n");
                    return 1;
                }
                NSString *action = [NSString stringWithUTF8String:argv[3]];
                if ([action isEqualToString:@"create"]) {
                    if (argc < 5) {
                        fprintf(stderr, "Usage: cider notes folder create <name> [--parent <p>]\n");
                        return 1;
                    }
                    NSString *name = [NSString stringWithUTF8String:argv[4]];
                    NSString *parent = argValue(argc, argv, 5, "--parent", NULL);
                    return cmdFolderCreate(name, parent);
                } else if ([action isEqualToString:@"delete"]) {
                    if (argc < 5) {
                        fprintf(stderr, "Usage: cider notes folder delete <name>\n");
                        return 1;
                    }
                    NSString *name = [NSString stringWithUTF8String:argv[4]];
                    return cmdFolderDelete(name);
                } else if ([action isEqualToString:@"rename"]) {
                    if (argc < 6) {
                        fprintf(stderr, "Usage: cider notes folder rename <old> <new>\n");
                        return 1;
                    }
                    NSString *oldName = [NSString stringWithUTF8String:argv[4]];
                    NSString *newName = [NSString stringWithUTF8String:argv[5]];
                    return cmdFolderRename(oldName, newName);
                } else {
                    fprintf(stderr, "Unknown folder action: %s\n", [action UTF8String]);
                    return 1;
                }

            // ── cider notes tag ──
            } else if ([sub isEqualToString:@"tag"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"tag", folder);
                if (!idx) return 1;
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider notes tag <N> <tag>\n");
                    return 1;
                }
                // Find the tag argument (first non-flag arg after index)
                NSString *tag = nil;
                for (int i = 4; i < argc; i++) {
                    if (strcmp(argv[i], "--folder") == 0 || strcmp(argv[i], "-f") == 0) {
                        i++; continue;
                    }
                    tag = [NSString stringWithUTF8String:argv[i]];
                    break;
                }
                if (!tag) {
                    fprintf(stderr, "Usage: cider notes tag <N> <tag>\n");
                    return 1;
                }
                return cmdNotesTag(idx, tag, folder);

            // ── cider notes untag ──
            } else if ([sub isEqualToString:@"untag"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                if (!idx) idx = promptNoteIndex(@"untag", folder);
                if (!idx) return 1;
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider notes untag <N> <tag>\n");
                    return 1;
                }
                NSString *tag = nil;
                for (int i = 4; i < argc; i++) {
                    if (strcmp(argv[i], "--folder") == 0 || strcmp(argv[i], "-f") == 0) {
                        i++; continue;
                    }
                    tag = [NSString stringWithUTF8String:argv[i]];
                    break;
                }
                if (!tag) {
                    fprintf(stderr, "Usage: cider notes untag <N> <tag>\n");
                    return 1;
                }
                return cmdNotesUntag(idx, tag, folder);

            // ── cider notes tags ──
            } else if ([sub isEqualToString:@"tags"]) {
                BOOL withCounts = argHasFlag(argc, argv, 3, "--count", NULL);
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                BOOL clean = argHasFlag(argc, argv, 3, "--clean", NULL);
                if (clean) return cmdTagsClean();
                cmdNotesTags(withCounts, jsonOut);

            // ── cider notes replace ──
            } else if ([sub isEqualToString:@"replace"]) {
                BOOL useRegex = argHasFlag(argc, argv, 3, "--regex", NULL);
                BOOL caseInsensitive = argHasFlag(argc, argv, 3, "-i", "--case-insensitive");
                BOOL replaceAll = argHasFlag(argc, argv, 3, "--all", NULL);
                NSString *findStr = argValue(argc, argv, 3, "--find", NULL);
                NSString *replaceStr = argValue(argc, argv, 3, "--replace", NULL);

                if (replaceAll) {
                    if (!findStr || !replaceStr) {
                        fprintf(stderr, "Usage: cider notes replace --all --find <text> --replace <text> [--folder <f>] [--regex] [-i] [--dry-run]\n");
                        return 1;
                    }
                    NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
                    BOOL dryRun = argHasFlag(argc, argv, 3, "--dry-run", NULL);
                    return cmdNotesReplaceAll(findStr, replaceStr, folder,
                                             useRegex, caseInsensitive, dryRun);
                }

                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"replace", nil);
                if (!idx) return 1;
                if (!findStr || !replaceStr) {
                    fprintf(stderr, "Usage: cider notes replace <N> --find <text> --replace <text> [--regex] [-i]\n");
                    return 1;
                }
                return cmdNotesReplace(idx, findStr, replaceStr, useRegex, caseInsensitive);

            // ── cider notes search ──
            } else if ([sub isEqualToString:@"search"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes search <query> [--regex] [--title] [--body] [-f <folder>] [--json]\n");
                    return 1;
                }
                NSString *query = [NSString stringWithUTF8String:argv[3]];
                BOOL jsonOut = argHasFlag(argc, argv, 4, "--json", NULL);
                BOOL useRegex = argHasFlag(argc, argv, 4, "--regex", NULL);
                BOOL titleOnly = argHasFlag(argc, argv, 4, "--title", NULL);
                BOOL bodyOnly = argHasFlag(argc, argv, 4, "--body", NULL);
                NSString *folder = argValue(argc, argv, 4, "--folder", "-f");
                NSString *afterStr = argValue(argc, argv, 4, "--after", NULL);
                NSString *beforeStr = argValue(argc, argv, 4, "--before", NULL);
                NSString *tagFilter = argValue(argc, argv, 4, "--tag", NULL);
                if (titleOnly && bodyOnly) {
                    fprintf(stderr, "Error: --title and --body are mutually exclusive\n");
                    return 1;
                }
                cmdNotesSearch(query, jsonOut, useRegex, titleOnly, bodyOnly, folder, afterStr, beforeStr, tagFilter);

            // ── cider notes export ──
            } else if ([sub isEqualToString:@"export"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes export <path>\n");
                    return 1;
                }
                NSString *path = [NSString stringWithUTF8String:argv[3]];
                cmdNotesExport(path);

            // ── cider notes attachments ──
            } else if ([sub isEqualToString:@"attachments"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"list attachments for", nil);
                if (!idx) return 1;
                BOOL json = NO;
                for (int ai = 4; ai < argc; ai++) {
                    if (strcmp(argv[ai], "--json") == 0) { json = YES; break; }
                }
                cmdNotesAttachments(idx, json);

            // ── cider notes detach ──
            } else if ([sub isEqualToString:@"detach"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"detach from", nil);
                if (!idx) return 1;

                NSUInteger attIdx = 0;
                if (argc >= 5) {
                    attIdx = (NSUInteger)(atoi(argv[4]) - 1);
                } else {
                    id note = noteAtIndex(idx, nil);
                    if (note) {
                        NSArray *orderedIDs = attachmentOrderFromCRDT(note);
                        NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
                        NSUInteger inlineCount = orderedIDs ? orderedIDs.count : 0;
                        if (inlineCount == 0) {
                            fprintf(stderr, "Note %lu has no inline attachments.\n", (unsigned long)idx);
                            return 1;
                        }
                        printf("Attachments in note %lu:\n", (unsigned long)idx);
                        for (NSUInteger i = 0; i < inlineCount; i++) {
                            id val = orderedIDs[i];
                            NSString *aName = (val != [NSNull null])
                                ? attachmentNameByID(atts, val) : @"attachment";
                            printf("  %lu. %s\n", (unsigned long)(i + 1), [aName UTF8String]);
                        }
                        if (inlineCount == 1) {
                            attIdx = 0;
                            printf("Removing the only attachment.\n");
                        } else {
                            printf("Remove which attachment? [1-%lu]: ", (unsigned long)inlineCount);
                            fflush(stdout);
                            char buf[32];
                            if (fgets(buf, sizeof(buf), stdin)) {
                                int v = atoi(buf);
                                if (v < 1 || (NSUInteger)v > inlineCount) {
                                    fprintf(stderr, "Invalid selection.\n");
                                    return 1;
                                }
                                attIdx = (NSUInteger)(v - 1);
                            }
                        }
                    }
                }
                cmdNotesDetach(idx, attIdx);

            // ── cider notes attach ──
            } else if ([sub isEqualToString:@"attach"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"attach", nil);
                if (!idx) return 1;
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider notes attach <N> <file>\n");
                    return 1;
                }
                NSString *filePath = [NSString stringWithUTF8String:argv[4]];

                NSInteger atPos = -1;
                for (int ai = 5; ai < argc - 1; ai++) {
                    if (strcmp(argv[ai], "--at") == 0) {
                        atPos = (NSInteger)atoi(argv[ai + 1]);
                        break;
                    }
                }
                if (atPos >= 0) {
                    cmdNotesAttachAt(idx, filePath, (NSUInteger)atPos);
                } else {
                    cmdNotesAttach(idx, filePath);
                }

            // ── Legacy flag aliases ──────────────────────────────────────────

            } else if ([sub isEqualToString:@"-fl"]) {
                cmdFoldersList(NO);

            } else if ([sub isEqualToString:@"-f"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes -f <folder>\n");
                    return 1;
                }
                NSString *folder = [NSString stringWithUTF8String:argv[3]];
                cmdNotesList(folder, NO, nil, nil, nil, NO, nil);

            } else if ([sub isEqualToString:@"-v"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes -v <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdNotesView(idx, nil, NO);

            } else if ([sub isEqualToString:@"-a"]) {
                NSString *folder = nil;
                for (int i = 3; i < argc - 1; i++) {
                    if (strcmp(argv[i], "-f") == 0) {
                        folder = [NSString stringWithUTF8String:argv[i + 1]];
                    }
                }
                cmdNotesAdd(folder);

            } else if ([sub isEqualToString:@"-e"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes -e <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdNotesEdit(idx);

            } else if ([sub isEqualToString:@"-d"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes -d <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdNotesDelete(idx);

            } else if ([sub isEqualToString:@"-m"]) {
                if (argc < 6 || strcmp(argv[4], "-f") != 0) {
                    fprintf(stderr, "Usage: cider notes -m <N> -f <folder>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *folder = [NSString stringWithUTF8String:argv[5]];
                cmdNotesMove(idx, folder);

            } else if ([sub isEqualToString:@"-s"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes -s <query>\n");
                    return 1;
                }
                NSString *query = [NSString stringWithUTF8String:argv[3]];
                cmdNotesSearch(query, NO, NO, NO, NO, nil, nil, nil, nil);

            } else if ([sub isEqualToString:@"--export"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes --export <path>\n");
                    return 1;
                }
                NSString *path = [NSString stringWithUTF8String:argv[3]];
                cmdNotesExport(path);

            } else if ([sub isEqualToString:@"--attach"]) {
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider notes --attach <N> <file>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *filePath = [NSString stringWithUTF8String:argv[4]];

                NSInteger atPos = -1;
                for (int ai = 5; ai < argc - 1; ai++) {
                    if (strcmp(argv[ai], "--at") == 0) {
                        atPos = (NSInteger)atoi(argv[ai + 1]);
                        break;
                    }
                }
                if (atPos >= 0) {
                    cmdNotesAttachAt(idx, filePath, (NSUInteger)atPos);
                } else {
                    cmdNotesAttach(idx, filePath);
                }

            } else {
                fprintf(stderr, "Unknown notes subcommand: %s\n", argv[2]);
                printNotesHelp();
                return 1;
            }
            return 0;
        }

        // ── templates ────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"templates"]) {
            if (!initNotesContext()) return 1;

            if (argc == 2) {
                cmdTemplatesList();
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];

            if ([sub isEqualToString:@"list"]) {
                cmdTemplatesList();
            } else if ([sub isEqualToString:@"show"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider templates show <name>\n");
                    return 1;
                }
                NSString *name = [NSString stringWithUTF8String:argv[3]];
                return cmdTemplatesShow(name);
            } else if ([sub isEqualToString:@"add"]) {
                cmdTemplatesAdd();
            } else if ([sub isEqualToString:@"delete"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider templates delete <name>\n");
                    return 1;
                }
                NSString *name = [NSString stringWithUTF8String:argv[3]];
                return cmdTemplatesDelete(name);
            } else {
                fprintf(stderr, "Unknown templates subcommand: %s\n", argv[2]);
                return 1;
            }
            return 0;
        }

        // ── settings ─────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"settings"]) {
            if (!initNotesContext()) return 1;

            if (argc == 2) {
                BOOL jsonOut = argHasFlag(argc, argv, 2, "--json", NULL);
                cmdSettings(jsonOut);
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];

            if ([sub isEqualToString:@"--json"]) {
                cmdSettings(YES);
            } else if ([sub isEqualToString:@"get"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider settings get <key>\n");
                    return 1;
                }
                NSString *key = [NSString stringWithUTF8String:argv[3]];
                return cmdSettingsGet(key);
            } else if ([sub isEqualToString:@"set"]) {
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider settings set <key> <value>\n");
                    return 1;
                }
                NSString *key = [NSString stringWithUTF8String:argv[3]];
                // Join remaining args as value (allows spaces without quoting)
                NSMutableArray *valParts = [NSMutableArray array];
                for (int i = 4; i < argc; i++) {
                    [valParts addObject:[NSString stringWithUTF8String:argv[i]]];
                }
                NSString *value = [valParts componentsJoinedByString:@" "];
                return cmdSettingsSet(key, value);
            } else if ([sub isEqualToString:@"reset"]) {
                return cmdSettingsReset();
            } else {
                fprintf(stderr, "Unknown settings subcommand: %s\n", argv[2]);
                return 1;
            }
            return 0;
        }

        // ── sync ─────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"sync"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printSyncHelp();
                return 0;
            }

            if (argc == 2) {
                printSyncHelp();
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];
            NSString *syncDir = argValue(argc, argv, 3, "--dir", "-d") ?: syncDefaultDir();

            if ([sub isEqualToString:@"backup"]) {
                if (!initNotesContext()) return 1;
                NSFileManager *fm = [NSFileManager defaultManager];
                [fm createDirectoryAtPath:syncDir withIntermediateDirectories:YES attributes:nil error:nil];
                return cmdSyncBackup(syncDir);

            } else if ([sub isEqualToString:@"run"]) {
                if (!initNotesContext()) return 1;
                return cmdSyncRun(syncDir);

            } else if ([sub isEqualToString:@"watch"]) {
                if (!initNotesContext()) return 1;
                NSTimeInterval interval = 2.0;
                NSString *intStr = argValue(argc, argv, 3, "--interval", "-i");
                if (intStr) interval = [intStr doubleValue];
                if (interval < 0.5) interval = 0.5;
                return cmdSyncWatch(syncDir, interval);

            } else {
                fprintf(stderr, "Unknown sync subcommand: %s\n", argv[2]);
                printSyncHelp();
                return 1;
            }
        }

        // ── rem ──────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"rem"]) {
            if (argc >= 3 && (strcmp(argv[2], "--help") == 0 ||
                               strcmp(argv[2], "-h") == 0)) {
                printRemHelp();
                return 0;
            }

            if (argc == 2) {
                cmdRemList();
                return 0;
            }

            NSString *sub = [NSString stringWithUTF8String:argv[2]];

            if ([sub isEqualToString:@"list"]) {
                cmdRemList();

            } else if ([sub isEqualToString:@"add"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider rem add <title> [due-date]\n");
                    return 1;
                }
                NSString *title = [NSString stringWithUTF8String:argv[3]];
                NSString *due = (argc >= 5) ? [NSString stringWithUTF8String:argv[4]] : nil;
                cmdRemAdd(title, due);

            } else if ([sub isEqualToString:@"edit"]) {
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider rem edit <N> <new-title>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *title = [NSString stringWithUTF8String:argv[4]];
                cmdRemEdit(idx, title);

            } else if ([sub isEqualToString:@"delete"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider rem delete <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdRemDelete(idx);

            } else if ([sub isEqualToString:@"complete"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider rem complete <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdRemComplete(idx);

            // ── Legacy flag aliases ──────────────────────────────────────────

            } else if ([sub isEqualToString:@"-a"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider rem -a <title> [due-date]\n");
                    return 1;
                }
                NSString *title = [NSString stringWithUTF8String:argv[3]];
                NSString *due = (argc >= 5) ? [NSString stringWithUTF8String:argv[4]] : nil;
                cmdRemAdd(title, due);

            } else if ([sub isEqualToString:@"-e"]) {
                if (argc < 5) {
                    fprintf(stderr, "Usage: cider rem -e <N> <new-title>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *title = [NSString stringWithUTF8String:argv[4]];
                cmdRemEdit(idx, title);

            } else if ([sub isEqualToString:@"-d"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider rem -d <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdRemDelete(idx);

            } else if ([sub isEqualToString:@"-c"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider rem -c <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdRemComplete(idx);

            } else {
                fprintf(stderr, "Unknown rem subcommand: %s\n", argv[2]);
                printRemHelp();
                return 1;
            }
            return 0;
        }

        fprintf(stderr, "Unknown command: %s\n"
                "Run 'cider --help' for usage.\n", [cmd UTF8String]);
        return 1;
    }
}
