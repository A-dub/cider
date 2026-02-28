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
"cider v" VERSION " — Apple Notes CLI\n"
"\n"
"USAGE:\n"
"  cider notes [subcommand]    Notes operations\n"
"  cider templates [sub]       Template management\n"
"  cider settings [sub]        Cider configuration\n"
"  cider rem [subcommand]      Reminders operations\n"
"  cider sync [subcommand]     Notes <-> Markdown sync\n"
"  cider --version             Show version\n"
"\n"
"Run 'cider <command> --help' for details on any command.\n"
    );
}

void printNotesHelp(void) {
    printf(
"cider notes v" VERSION " — Apple Notes CLI\n"
"\n"
"SUBCOMMANDS:\n"
"  list          List notes (with filters, sorting, date range)\n"
"  show <N>      View note content\n"
"  inspect <N>   Full note details (metadata, tags, links, tables)\n"
"  folders       List all folders\n"
"  add           Add a new note (stdin, $EDITOR, or template)\n"
"  edit <N>      Edit note via CRDT (preserves attachments)\n"
"  delete <N>    Delete a note\n"
"  move <N>      Move note to a folder\n"
"  search        Search notes by text\n"
"  replace       Find & replace in one or all notes\n"
"  append <N>    Append text to end of note\n"
"  prepend <N>   Insert text after title\n"
"  pin <N>       Pin a note\n"
"  unpin <N>     Unpin a note\n"
"  tag <N>       Add a #tag to a note\n"
"  untag <N>     Remove a #tag from a note\n"
"  tags          List all unique tags\n"
"  share <N>     Show sharing status\n"
"  shared        List all shared notes\n"
"  table <N>     Show/add table data\n"
"  checklist <N> Show checklist items\n"
"  check <N>     Check off a checklist item\n"
"  uncheck <N>   Uncheck a checklist item\n"
"  links <N>     Show outgoing note links\n"
"  backlinks <N> Show notes linking to note N\n"
"  link <N>      Create a link to another note\n"
"  watch         Stream note change events\n"
"  history <N>   CRDT edit timeline (who edited, when)\n"
"  getdate <N>   Show modification/creation dates\n"
"  setdate <N>   Set modification date\n"
"  folder        Create, delete, or rename folders\n"
"  attachments   List attachments in a note\n"
"  attach <N>    Add file attachment to a note\n"
"  detach <N>    Remove an attachment\n"
"  export        Export all notes to HTML\n"
"  debug <N>     Dump CRDT attributes for a note\n"
"\n"
"Run 'cider notes <subcommand> --help' for detailed usage.\n"
    );
}

// Per-subcommand detailed help
void printNotesSubcommandHelp(const char *sub) {
    if (strcmp(sub, "list") == 0) {
        printf(
"cider notes list [options]\n"
"\n"
"  List notes with optional filtering and sorting.\n"
"\n"
"OPTIONS:\n"
"  -f, --folder <f>           Filter by folder\n"
"  --after <date>             Notes modified after date\n"
"  --before <date>            Notes modified before date\n"
"  --sort created|modified|title  Sort order (default: title)\n"
"  --pinned                   Show only pinned notes\n"
"  --tag <tag>                Filter by #tag\n"
"  --json                     JSON output\n"
"\n"
"  Date formats: 2024-01-15, 2024-01-15T10:30:00,\n"
"  today, yesterday, \"3 days ago\", \"1 week ago\"\n"
"\n"
"EXAMPLES:\n"
"  cider notes list --after today\n"
"  cider notes list --sort modified -f Work\n"
"  cider notes list --after \"1 week ago\" --json\n"
"  cider notes list --tag project-x --pinned\n"
        );
    } else if (strcmp(sub, "show") == 0) {
        printf(
"cider notes show <N> [--json] [-f <folder>]\n"
"\n"
"  View the content of note N. Also: cider notes <N>\n"
"\n"
"EXAMPLES:\n"
"  cider notes show 5\n"
"  cider notes 5\n"
"  cider notes show 5 --json\n"
        );
    } else if (strcmp(sub, "inspect") == 0) {
        printf(
"cider notes inspect <N> [--json] [-f <folder>]\n"
"\n"
"  Full note details: metadata, tags, links, tables, attachments.\n"
"\n"
"EXAMPLES:\n"
"  cider notes inspect 5\n"
"  cider notes inspect 5 --json\n"
        );
    } else if (strcmp(sub, "folders") == 0) {
        printf(
"cider notes folders [--json]\n"
"\n"
"  List all note folders.\n"
        );
    } else if (strcmp(sub, "add") == 0) {
        printf(
"cider notes add [--folder <f>] [--template <name>]\n"
"\n"
"  Add a new note. Reads from stdin (if piped) or opens $EDITOR.\n"
"  The first line becomes the title.\n"
"\n"
"OPTIONS:\n"
"  -f, --folder <f>       Target folder\n"
"  --template <name>      Pre-fill from a template\n"
"\n"
"EXAMPLES:\n"
"  cider notes add\n"
"  cider notes add -f \"Work Notes\"\n"
"  echo \"Title\\nBody\" | cider notes add\n"
"  cider notes add --template \"Meeting Notes\"\n"
        );
    } else if (strcmp(sub, "edit") == 0) {
        printf(
"cider notes edit <N>\n"
"\n"
"  Edit note N in $EDITOR using CRDT (preserves attachments).\n"
"  Attachments appear as %%%%ATTACHMENT_N_name%%%% markers.\n"
"  Edit the text freely but do NOT remove or rename markers.\n"
"  Pipe content: echo 'new body' | cider notes edit N\n"
"\n"
"EXAMPLES:\n"
"  cider notes edit 5\n"
"  echo \"new content\" | cider notes edit 5\n"
        );
    } else if (strcmp(sub, "delete") == 0) {
        printf("cider notes delete <N>\n\n  Delete note N.\n");
    } else if (strcmp(sub, "move") == 0) {
        printf(
"cider notes move <N> <folder>\n"
"\n"
"  Move note N to the specified folder.\n"
"\n"
"EXAMPLES:\n"
"  cider notes move 5 \"Work Notes\"\n"
        );
    } else if (strcmp(sub, "search") == 0) {
        printf(
"cider notes search <query> [options]\n"
"\n"
"  Search note title and body (case-insensitive).\n"
"\n"
"OPTIONS:\n"
"  --regex           Treat query as ICU regex\n"
"  --title           Search title only\n"
"  --body            Search body only\n"
"  -f, --folder <f>  Scope to folder\n"
"  --after <date>    Filter by modification date\n"
"  --before <date>   Filter by modification date\n"
"  --tag <tag>       Also filter by #tag\n"
"  --json            JSON output\n"
"\n"
"EXAMPLES:\n"
"  cider notes search \"meeting\"\n"
"  cider notes search \"TODO\" --title\n"
"  cider notes search \"\\\\d{3}-\\\\d{4}\" --regex\n"
"  cider notes search \"important\" --body -f Work\n"
        );
    } else if (strcmp(sub, "replace") == 0) {
        printf(
"cider notes replace <N> --find <s> --replace <s> [--regex] [-i]\n"
"cider notes replace --all --find <s> --replace <s> [options]\n"
"\n"
"  Find and replace text in one or all notes.\n"
"\n"
"OPTIONS:\n"
"  --all              Replace across all notes (instead of one)\n"
"  --regex            ICU regex; --replace supports $1, $2\n"
"  -i                 Case-insensitive\n"
"  -f, --folder <f>   Scope --all to a folder\n"
"  --dry-run          Preview without changing (--all mode)\n"
"\n"
"EXAMPLES:\n"
"  cider notes replace 3 --find old --replace new\n"
"  cider notes replace --all --find old --replace new --dry-run\n"
"  cider notes replace --all --find \"http://\" --replace \"https://\" -f Work\n"
        );
    } else if (strcmp(sub, "append") == 0) {
        printf(
"cider notes append <N> <text> [--no-newline] [-f <folder>]\n"
"\n"
"  Append text to the end of note N. Supports stdin piping.\n"
"\n"
"EXAMPLES:\n"
"  cider notes append 3 \"Added at the bottom\"\n"
"  echo \"piped text\" | cider notes append 3\n"
"  cider notes append 3 \"no gap\" --no-newline\n"
        );
    } else if (strcmp(sub, "prepend") == 0) {
        printf(
"cider notes prepend <N> <text> [--no-newline] [-f <folder>]\n"
"\n"
"  Insert text right after the title of note N. Supports stdin piping.\n"
"\n"
"EXAMPLES:\n"
"  cider notes prepend 3 \"Inserted after title\"\n"
"  echo \"piped text\" | cider notes prepend 3\n"
        );
    } else if (strcmp(sub, "pin") == 0 || strcmp(sub, "unpin") == 0) {
        printf(
"cider notes pin <N> [-f <folder>]\n"
"cider notes unpin <N> [-f <folder>]\n"
"\n"
"  Pin or unpin a note. Pinned notes appear at the top in Apple Notes.\n"
"\n"
"EXAMPLES:\n"
"  cider notes pin 3\n"
"  cider notes unpin 3\n"
"  cider notes list --pinned\n"
        );
    } else if (strcmp(sub, "tag") == 0 || strcmp(sub, "untag") == 0) {
        printf(
"cider notes tag <N> <tag> [-f <folder>]\n"
"cider notes untag <N> <tag> [-f <folder>]\n"
"\n"
"  Add or remove #tags. Auto-prepends # if omitted.\n"
"\n"
"EXAMPLES:\n"
"  cider notes tag 3 project-x\n"
"  cider notes untag 3 project-x\n"
        );
    } else if (strcmp(sub, "tags") == 0) {
        printf(
"cider notes tags [--count] [--json] [--clean]\n"
"\n"
"  List all unique #tags across all notes.\n"
"  --count shows how many notes use each tag.\n"
"  --clean removes orphaned tags.\n"
        );
    } else if (strcmp(sub, "share") == 0) {
        printf(
"cider notes share <N> [--json] [-f <folder>]\n"
"\n"
"  Show iCloud sharing status and participants for note N.\n"
"\n"
"EXAMPLES:\n"
"  cider notes share 5\n"
"  cider notes share 5 --json\n"
        );
    } else if (strcmp(sub, "shared") == 0) {
        printf(
"cider notes shared [--json]\n"
"\n"
"  List all shared (collaborative) notes.\n"
        );
    } else if (strcmp(sub, "table") == 0) {
        printf(
"cider notes table <N> [options]\n"
"\n"
"  Show or modify table data in note N.\n"
"\n"
"OPTIONS:\n"
"  --list              List all tables with row/col counts\n"
"  --index <i>         Select table by index (0-based)\n"
"  --json              JSON array of {header: value}\n"
"  --csv               CSV output\n"
"  --row <r>           Specific row (0-based)\n"
"  --headers           Column headers only\n"
"  --add-row \"a|b|c\"   Add row (pipe-delimited, repeatable)\n"
"\n"
"EXAMPLES:\n"
"  cider notes table 5\n"
"  cider notes table 5 --json\n"
"  cider notes table 5 --csv\n"
"  cider notes table 5 --add-row \"Name|Value\"\n"
        );
    } else if (strcmp(sub, "checklist") == 0) {
        printf(
"cider notes checklist <N> [--summary] [--json] [--add \"text\"] [-f <folder>]\n"
"\n"
"  Show checklist items with [x]/[ ] status.\n"
"\n"
"OPTIONS:\n"
"  --summary      Summary only (e.g. \"3/6 complete\")\n"
"  --json         JSON output\n"
"  --add \"text\"   Add a new checklist item\n"
"\n"
"EXAMPLES:\n"
"  cider notes checklist 5\n"
"  cider notes checklist 5 --summary\n"
"  cider notes checklist 5 --add \"Buy milk\"\n"
        );
    } else if (strcmp(sub, "check") == 0 || strcmp(sub, "uncheck") == 0) {
        printf(
"cider notes check <N> <item#> [-f <folder>]\n"
"cider notes uncheck <N> <item#> [-f <folder>]\n"
"\n"
"  Check or uncheck a checklist item by number (1-based).\n"
"\n"
"EXAMPLES:\n"
"  cider notes check 5 2\n"
"  cider notes uncheck 5 2\n"
        );
    } else if (strcmp(sub, "links") == 0) {
        printf(
"cider notes links <N> [--json] [-f <folder>]\n"
"\n"
"  Show outgoing note-to-note links in note N.\n"
"\n"
"EXAMPLES:\n"
"  cider notes links 5\n"
"  cider notes links 5 --json\n"
        );
    } else if (strcmp(sub, "backlinks") == 0) {
        printf(
"cider notes backlinks <N> [--json] [-f <folder>]\n"
"cider notes backlinks --all [--json]\n"
"\n"
"  Show notes that link to note N, or show full link graph.\n"
"\n"
"EXAMPLES:\n"
"  cider notes backlinks 5\n"
"  cider notes backlinks --all\n"
"  cider notes backlinks --all --json\n"
        );
    } else if (strcmp(sub, "link") == 0) {
        printf(
"cider notes link <N> <target title> [-f <folder>]\n"
"\n"
"  Create a link from note N to another note by title.\n"
"\n"
"EXAMPLES:\n"
"  cider notes link 5 \"Meeting Notes\"\n"
        );
    } else if (strcmp(sub, "watch") == 0) {
        printf(
"cider notes watch [--folder <f>] [--interval <s>] [--json]\n"
"\n"
"  Stream note change events (created, modified, deleted).\n"
"\n"
"OPTIONS:\n"
"  -f, --folder <f>   Watch specific folder\n"
"  --interval <s>     Poll interval in seconds (default: 2)\n"
"  --json             JSON event stream\n"
"\n"
"EXAMPLES:\n"
"  cider notes watch\n"
"  cider notes watch -f \"Work Notes\"\n"
"  cider notes watch --json --interval 10\n"
        );
    } else if (strcmp(sub, "history") == 0) {
        printf(
"cider notes history <N> [--raw] [--json] [-f <folder>]\n"
"\n"
"  Show CRDT edit timeline — who edited the note and when.\n"
"  Groups edits into sessions (>60s gap = new session).\n"
"  Shows person names for shared notes, device IDs otherwise.\n"
"\n"
"OPTIONS:\n"
"  --raw    Per-keystroke detail (every individual edit)\n"
"  --json   JSON output with devices and sessions\n"
"\n"
"EXAMPLES:\n"
"  cider notes history 5\n"
"  cider notes history 5 --raw\n"
"  cider notes history 5 --json\n"
        );
    } else if (strcmp(sub, "getdate") == 0) {
        printf(
"cider notes getdate <N> [--json] [-f <folder>]\n"
"\n"
"  Show a note's modification and creation dates.\n"
"\n"
"EXAMPLES:\n"
"  cider notes getdate 349\n"
"  cider notes getdate 349 --json\n"
        );
    } else if (strcmp(sub, "setdate") == 0) {
        printf(
"cider notes setdate <N> <date> [--dry-run] [-f <folder>]\n"
"\n"
"  Set a note's modification date.\n"
"  Date format: ISO 8601 (2024-01-15T14:30:00 or 2024-01-15)\n"
"\n"
"OPTIONS:\n"
"  --dry-run   Preview the change without writing\n"
"\n"
"EXAMPLES:\n"
"  cider notes setdate 349 2024-06-15T10:30:00\n"
"  cider notes setdate 349 2024-06-15 --dry-run\n"
        );
    } else if (strcmp(sub, "folder") == 0) {
        printf(
"cider notes folder create <name> [--parent <p>]\n"
"cider notes folder delete <name>\n"
"cider notes folder rename <old> <new>\n"
"\n"
"  Create, delete, or rename folders.\n"
"  Delete requires the folder to be empty.\n"
"\n"
"EXAMPLES:\n"
"  cider notes folder create \"Work Notes\"\n"
"  cider notes folder create \"Meetings\" --parent \"Work Notes\"\n"
"  cider notes folder delete \"Old Stuff\"\n"
"  cider notes folder rename \"Work\" \"Work Notes\"\n"
        );
    } else if (strcmp(sub, "attachments") == 0) {
        printf(
"cider notes attachments <N> [--json]\n"
"\n"
"  List attachments in note N with CRDT positions.\n"
        );
    } else if (strcmp(sub, "attach") == 0) {
        printf(
"cider notes attach <N> <file> [--at <pos>]\n"
"\n"
"  Attach a file to note N. Optionally specify position.\n"
"\n"
"EXAMPLES:\n"
"  cider notes attach 5 ~/photo.jpg\n"
"  cider notes attach 5 ~/doc.pdf --at 3\n"
        );
    } else if (strcmp(sub, "detach") == 0) {
        printf(
"cider notes detach <N> [<A>]\n"
"\n"
"  Remove attachment A (1-based index) from note N.\n"
"  Omit A to be prompted interactively.\n"
        );
    } else if (strcmp(sub, "export") == 0) {
        printf(
"cider notes export <path>\n"
"\n"
"  Export all notes to HTML files in the given directory.\n"
        );
    } else if (strcmp(sub, "debug") == 0) {
        printf(
"cider notes debug <N> [-f <folder>]\n"
"\n"
"  Dump all CRDT attributed string attributes for a note.\n"
"  Useful for understanding internal formatting.\n"
        );
    } else {
        fprintf(stderr, "No help available for '%s'. Run 'cider notes --help' for subcommand list.\n", sub);
    }
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

            // ── cider notes <subcommand> --help ──
            if (argc >= 4 && (strcmp(argv[3], "--help") == 0 || strcmp(argv[3], "-h") == 0)) {
                printNotesSubcommandHelp([sub UTF8String]);
                return 0;
            }

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
