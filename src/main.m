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
"  cider rem [subcommand]     Reminders operations\n"
"  cider sync [subcommand]    Bidirectional Notes <-> Markdown sync\n"
"  cider --version            Show version\n"
"  cider --help               Show this help\n"
"\n"
"NOTES SUBCOMMANDS:\n"
"  list [-f <folder>] [--json]         List notes (default when no subcommand)\n"
"  show <N> [--json]                   View note N  (also: cider notes <N>)\n"
"  folders [--json]                    List all folders\n"
"  add [--folder <f>]                  Add note (stdin or $EDITOR)\n"
"  edit <N>                            Edit note N (CRDT — preserves attachments!)\n"
"  delete <N>                          Delete note N\n"
"  move <N> <folder>                   Move note N to folder\n"
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
"  cider notes list [-f <folder>] [--json]  List notes (optionally filter by folder)\n"
"  cider notes <N>                          View note N\n"
"  cider notes show <N> [--json]            View note N\n"
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
"DEBUG:\n"
"  cider notes debug <N> [-f <folder>]\n"
"\n"
"  Dumps all attributed string attribute keys and values for a note.\n"
"  Useful for discovering how Apple Notes stores checklists, tables,\n"
"  links, and other rich formatting internally.\n"
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
"  --json           Output results as JSON\n"
"\n"
"  Examples:\n"
"    cider notes search \"meeting\"                  Literal search (title + body)\n"
"    cider notes search \"\\\\d{3}-\\\\d{4}\" --regex     Find phone numbers\n"
"    cider notes search \"TODO\" --title              Search titles only\n"
"    cider notes search \"important\" --body -f Work  Search body in Work folder\n"
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
                cmdNotesList(nil, NO);
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
                cmdNotesList(folder, jsonOut);

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

            // ── cider notes folders ──
            } else if ([sub isEqualToString:@"folders"]) {
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                cmdFoldersList(jsonOut);

            // ── cider notes add ──
            } else if ([sub isEqualToString:@"add"]) {
                NSString *folder = argValue(argc, argv, 3, "--folder", "-f");
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
                if (titleOnly && bodyOnly) {
                    fprintf(stderr, "Error: --title and --body are mutually exclusive\n");
                    return 1;
                }
                cmdNotesSearch(query, jsonOut, useRegex, titleOnly, bodyOnly, folder);

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
                cmdNotesList(folder, NO);

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
                cmdNotesSearch(query, NO, NO, NO, NO, nil);

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
