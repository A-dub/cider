/**
 * jotty — Apple Notes CLI with CRDT attachment support
 *
 * Uses Apple's private NotesShared.framework CRDT API (ICTTMergeableString)
 * to edit notes while preserving attachments in their original position.
 *
 * Compile: clang -framework Foundation -framework CoreData -o jotty jotty.m
 */

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#define VERSION "1.0.0"
#define ATTACHMENT_MARKER ((unichar)0xFFFC)

// ─────────────────────────────────────────────────────────────────────────────
// Global state
// ─────────────────────────────────────────────────────────────────────────────

static id g_ctx = nil;
static id g_moc = nil;

// ─────────────────────────────────────────────────────────────────────────────
// Framework init
// ─────────────────────────────────────────────────────────────────────────────

BOOL initNotesContext(void) {
    void *handle = dlopen(
        "/System/Library/PrivateFrameworks/NotesShared.framework/NotesShared",
        RTLD_NOW);
    if (!handle) {
        fprintf(stderr, "Error: Could not load NotesShared.framework: %s\n",
                dlerror());
        return NO;
    }

    Class NoteContext = NSClassFromString(@"ICNoteContext");
    if (!NoteContext) {
        fprintf(stderr, "Error: ICNoteContext class not found. "
                "Is this macOS with Apple Notes?\n");
        return NO;
    }

    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(
        NoteContext,
        NSSelectorFromString(@"startSharedContextWithOptions:"),
        0);

    g_ctx = ((id (*)(id, SEL))objc_msgSend)(
        NoteContext, NSSelectorFromString(@"sharedContext"));
    if (!g_ctx) {
        fprintf(stderr, "Error: Could not get shared ICNoteContext\n");
        return NO;
    }

    g_moc = ((id (*)(id, SEL))objc_msgSend)(
        g_ctx, NSSelectorFromString(@"managedObjectContext"));
    if (!g_moc) {
        fprintf(stderr, "Error: Could not get managed object context\n");
        return NO;
    }

    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// Core Data helpers
// ─────────────────────────────────────────────────────────────────────────────

NSArray *fetchNotes(NSPredicate *predicate) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
    req.predicate = predicate;
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"modificationDate"
                                      ascending:NO]
    ];
    NSError *err = nil;
    NSArray *results = [g_moc executeFetchRequest:req error:&err];
    if (err) {
        fprintf(stderr, "Fetch error: %s\n", [[err localizedDescription] UTF8String]);
        return nil;
    }
    return results ?: @[];
}

NSArray *fetchAllNotes(void) {
    return fetchNotes(nil);
}

NSArray *fetchFolders(void) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    // ICFolder uses 'title' not 'name'
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES]
    ];
    NSError *err = nil;
    NSArray *results = [g_moc executeFetchRequest:req error:&err];
    if (err) {
        fprintf(stderr, "Fetch folders error: %s\n",
                [[err localizedDescription] UTF8String]);
        return nil;
    }
    return results ?: @[];
}

// Get the x-coredata:// URI string for a note (used by AppleScript)
NSString *noteURIString(id note) {
    id objID = ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"objectID"));
    NSURL *uri = ((NSURL *(*)(id, SEL))objc_msgSend)(
        objID, NSSelectorFromString(@"URIRepresentation"));
    return [uri absoluteString];
}

NSInteger noteIntPK(id note) {
    NSString *uri = noteURIString(note);
    NSRange pRange = [uri rangeOfString:@"/p" options:NSBackwardsSearch];
    if (pRange.location == NSNotFound) return -1;
    return [[uri substringFromIndex:pRange.location + 2] integerValue];
}

NSString *noteTitle(id note) {
    NSString *t = ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"title"));
    return t ?: @"(untitled)";
}

NSString *folderName(id note) {
    // ICFolder uses 'title' attribute, not 'name'
    id folder = [note valueForKey:@"folder"];
    if (!folder) return @"Notes";
    id title = [folder valueForKey:@"title"];
    if (title && [title isKindOfClass:[NSString class]]) return (NSString *)title;
    // Fallback: try the localizedTitle method
    id locTitle = ((id (*)(id, SEL))objc_msgSend)(
        folder, NSSelectorFromString(@"localizedTitle"));
    return (locTitle && [locTitle isKindOfClass:[NSString class]])
        ? (NSString *)locTitle : @"Notes";
}

id noteVisibleAttachments(id note) {
    return ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"visibleAttachments"));
}

NSUInteger noteAttachmentCount(id note) {
    id atts = noteVisibleAttachments(note);
    return atts ? [atts count] : 0;
}

// Convert the result of visibleAttachments (an NSSet or NSOrderedSet)
// to a sorted NSArray for stable ordering.
NSArray *attachmentsAsArray(id attsObj) {
    if (!attsObj) return @[];
    if ([attsObj isKindOfClass:[NSArray class]]) return (NSArray *)attsObj;
    // NSSet or NSOrderedSet
    if ([attsObj respondsToSelector:@selector(allObjects)]) {
        return [(NSSet *)attsObj allObjects];
    }
    if ([attsObj respondsToSelector:@selector(array)]) {
        return [(NSOrderedSet *)attsObj array];
    }
    return @[];
}

NSArray *noteAttachmentNames(id note) {
    id attsObj = noteVisibleAttachments(note);
    NSArray *atts = attachmentsAsArray(attsObj);
    if (atts.count == 0) return @[];

    NSMutableArray *names = [NSMutableArray array];
    for (id att in atts) {
        // ICAttachment has 'title' and 'userTitle' attributes (no 'filename')
        NSString *name = nil;
        id ut = [att valueForKey:@"userTitle"];
        if (ut && [ut isKindOfClass:[NSString class]] && [(NSString *)ut length] > 0) {
            name = (NSString *)ut;
        } else {
            id t = [att valueForKey:@"title"];
            if (t && [t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0) {
                name = (NSString *)t;
            }
        }
        if (!name || name.length == 0) {
            // Try typeUTI for a hint
            id uti = [att valueForKey:@"typeUTI"];
            if (uti && [uti isKindOfClass:[NSString class]]) {
                name = [NSString stringWithFormat:@"[%@]", uti];
            } else {
                name = @"attachment";
            }
        }
        [names addObject:name];
    }
    return names;
}

// ─────────────────────────────────────────────────────────────────────────────
// CRDT / mergeableString helpers
// ─────────────────────────────────────────────────────────────────────────────

id noteMergeableString(id note) {
    return ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"mergeableString"));
}

// Returns the raw NSString with U+FFFC where attachments are
NSString *noteRawText(id note) {
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) return @"";

    id attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"string"));
    if (!attrStr) return @"";

    if ([attrStr isKindOfClass:[NSAttributedString class]]) {
        return [(NSAttributedString *)attrStr string];
    }
    return (NSString *)attrStr ?: @"";
}

// Replace U+FFFC with [📎 filename] for display
NSString *noteTextForDisplay(id note) {
    NSString *raw = noteRawText(note);
    NSArray *names = noteAttachmentNames(note);
    NSMutableString *buf = [NSMutableString stringWithCapacity:[raw length]];
    NSUInteger ai = 0;

    for (NSUInteger i = 0; i < [raw length]; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == ATTACHMENT_MARKER) {
            NSString *aname = (ai < names.count) ? names[ai] : @"attachment";
            [buf appendFormat:@"[📎 %@]", aname];
            ai++;
        } else {
            [buf appendFormat:@"%C", c];
        }
    }
    return buf;
}

// Replace U+FFFC with %%ATTACHMENT_N%% markers for the editor
NSString *rawTextToEditable(NSString *raw, NSArray *names) {
    NSMutableString *buf = [NSMutableString stringWithCapacity:[raw length]];
    NSUInteger ai = 0;

    for (NSUInteger i = 0; i < [raw length]; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == ATTACHMENT_MARKER) {
            NSString *aname = (ai < names.count) ? names[ai] : @"attachment";
            [buf appendFormat:@"%%%%ATTACHMENT_%lu_%@%%%%",
             (unsigned long)ai, aname];
            ai++;
        } else {
            [buf appendFormat:@"%C", c];
        }
    }
    return buf;
}

// Replace %%ATTACHMENT_N_name%% markers back to U+FFFC
NSString *editableToRawText(NSString *edited) {
    NSMutableString *result = [NSMutableString stringWithString:edited];
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"%%ATTACHMENT_\\d+_[^%]*%%"
                             options:0
                               error:nil];
    NSArray *matches = [regex matchesInString:result
                                      options:0
                                        range:NSMakeRange(0, [result length])];
    // Process right-to-left to preserve positions
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--) {
        NSTextCheckingResult *match = matches[(NSUInteger)i];
        [result replaceCharactersInRange:match.range
                              withString:@"\uFFFC"];
    }
    return result;
}

// Save context
BOOL saveContext(void) {
    NSError *err = nil;
    BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
        g_ctx, NSSelectorFromString(@"save:"), &err);
    // Fallback: try save without error param
    if (!ok && !err) {
        ok = ((BOOL (*)(id, SEL))objc_msgSend)(
            g_ctx, NSSelectorFromString(@"save"));
    }
    if (err) {
        fprintf(stderr, "Save error: %s\n",
                [[err localizedDescription] UTF8String]);
    }
    return ok;
}

/**
 * Apply a CRDT edit to a note, preserving attachment positions.
 * Uses longest-common-prefix/suffix diff to find the minimal changed region,
 * then calls replaceCharactersInRange:withString: on the mergeableString.
 */
BOOL applyCRDTEdit(id note, NSString *oldText, NSString *newText) {
    if ([oldText isEqualToString:newText]) {
        printf("No changes detected.\n");
        return YES;
    }

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeableString for note\n");
        return NO;
    }

    NSUInteger oldLen = [oldText length];
    NSUInteger newLen = [newText length];

    // Find longest common prefix
    NSUInteger prefix = 0;
    while (prefix < oldLen && prefix < newLen &&
           [oldText characterAtIndex:prefix] ==
               [newText characterAtIndex:prefix]) {
        prefix++;
    }

    // Find longest common suffix (not overlapping with prefix)
    NSUInteger suffix = 0;
    while (suffix < (oldLen - prefix) && suffix < (newLen - prefix) &&
           [oldText characterAtIndex:oldLen - 1 - suffix] ==
               [newText characterAtIndex:newLen - 1 - suffix]) {
        suffix++;
    }

    NSRange replaceRange = NSMakeRange(prefix, oldLen - prefix - suffix);
    NSString *replaceWith = [newText substringWithRange:
                             NSMakeRange(prefix, newLen - prefix - suffix)];

    ((void (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"beginEditing"));

    ((void (*)(id, SEL, NSRange, id))objc_msgSend)(
        mergeStr,
        NSSelectorFromString(@"replaceCharactersInRange:withString:"),
        replaceRange,
        replaceWith);

    ((void (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"endEditing"));

    ((void (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// Note listing helpers
// ─────────────────────────────────────────────────────────────────────────────

// Returns a filtered list of notes (optionally by folder name), skipping
// system/trash/hidden folders unless the user explicitly asks for them.
NSArray *filteredNotes(NSString *filterFolder) {
    NSArray *all = fetchAllNotes();
    if (!all) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (id note in all) {
        // Skip notes in trash / recently deleted
        id folder = [note valueForKey:@"folder"];
        if (folder) {
            BOOL isTrash = ((BOOL (*)(id, SEL))objc_msgSend)(
                folder, NSSelectorFromString(@"isTrashFolder"));
            if (isTrash && !filterFolder) continue;
        }

        if (!filterFolder) {
            [result addObject:note];
        } else {
            NSString *fn = folderName(note);
            if ([fn caseInsensitiveCompare:filterFolder] == NSOrderedSame) {
                [result addObject:note];
            }
        }
    }
    return result;
}

// Get note by 1-based index from the (optionally filtered) list
id noteAtIndex(NSUInteger idx, NSString *folder) {
    NSArray *notes = filteredNotes(folder);
    if (idx == 0 || idx > notes.count) return nil;
    return notes[idx - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
// AppleScript helper
// ─────────────────────────────────────────────────────────────────────────────

NSAppleEventDescriptor *runAppleScript(NSString *src, NSString **errMsg) {
    NSDictionary *err = nil;
    NSAppleScript *as = [[NSAppleScript alloc] initWithSource:src];
    NSAppleEventDescriptor *res = [as executeAndReturnError:&err];
    if (!res && errMsg) {
        *errMsg = [err[@"NSAppleScriptErrorMessage"]
                   ?: [err description] ?: @"Unknown AppleScript error"
                   copy];
    }
    return res;
}

// ─────────────────────────────────────────────────────────────────────────────
// Column formatting helpers
// ─────────────────────────────────────────────────────────────────────────────

NSString *truncStr(NSString *s, NSUInteger maxLen) {
    if ([s length] <= maxLen) return s;
    return [[s substringToIndex:maxLen - 2] stringByAppendingString:@".."];
}

NSString *padRight(NSString *s, NSUInteger width) {
    if ([s length] >= width) return [s substringToIndex:width];
    NSMutableString *padded = [NSMutableString stringWithString:s];
    while ([padded length] < width) [padded appendString:@" "];
    return padded;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: notes
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesList(NSString *folder) {
    NSArray *notes = filteredNotes(folder);

    printf("  # %-42s %-22s %s\n",
           "Title", "Folder", "Attachments");
    printf("--- %-42s %-22s %s\n",
           "------------------------------------------",
           "----------------------",
           "-----------");

    if (notes.count == 0) {
        if (folder) {
            printf("  (no notes in folder \"%s\")\n", [folder UTF8String]);
        } else {
            printf("  (no notes)\n");
        }
        return;
    }

    NSUInteger i = 1;
    for (id note in notes) {
        NSString *t = truncStr(noteTitle(note), 42);
        NSString *f = truncStr(folderName(note), 22);
        NSUInteger ac = noteAttachmentCount(note);
        NSString *atts = ac > 0 ? [NSString stringWithFormat:@"📎 %lu", ac] : @"";

        printf("%3lu %-42s %-22s %s\n",
               (unsigned long)i,
               [padRight(t, 42) UTF8String],
               [padRight(f, 22) UTF8String],
               [atts UTF8String]);
        i++;
    }
    printf("\nTotal: %lu note(s)\n", (unsigned long)notes.count);
}

void cmdFoldersList(void) {
    NSArray *folders = fetchFolders();
    printf("Folders:\n");
    for (id folder in folders) {
        // ICFolder uses 'title' attribute
        id titleVal = [folder valueForKey:@"title"];
        NSString *name = (titleVal && [titleVal isKindOfClass:[NSString class]])
            ? (NSString *)titleVal : @"(unnamed)";
        // parent relationship is 'parent' on ICFolder
        id parent = [folder valueForKey:@"parent"];
        if (parent) {
            id pTitleVal = [parent valueForKey:@"title"];
            NSString *pname = (pTitleVal && [pTitleVal isKindOfClass:[NSString class]])
                ? (NSString *)pTitleVal : @"";
            printf("  %s / %s\n", [pname UTF8String], [name UTF8String]);
        } else {
            printf("  %s\n", [name UTF8String]);
        }
    }
    printf("\nTotal: %lu folder(s)\n", (unsigned long)folders.count);
}

void cmdNotesView(NSUInteger idx, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *t = noteTitle(note);
    NSString *f = folderName(note);
    NSArray *names = noteAttachmentNames(note);
    NSUInteger ac = names.count;

    // Header
    printf("╔══════════════════════════════════════════╗\n");
    printf("  %s\n", [t UTF8String]);
    printf("  Folder: %s", [f UTF8String]);
    if (ac > 0) {
        printf(" | 📎 %lu attachment(s): ", (unsigned long)ac);
        for (NSString *n in names) printf("%s ", [n UTF8String]);
    }
    printf("\n╚══════════════════════════════════════════╝\n\n");

    printf("%s\n", [noteTextForDisplay(note) UTF8String]);
}

void cmdNotesAdd(NSString *folder) {
    NSString *content = nil;

    // Detect if stdin is a pipe/file
    struct stat st;
    fstat(STDIN_FILENO, &st);
    BOOL hasPipe = S_ISFIFO(st.st_mode) || S_ISREG(st.st_mode);

    if (hasPipe) {
        NSData *data = [[NSFileHandle fileHandleWithStandardInput]
                        readDataToEndOfFile];
        content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    } else {
        NSString *tmp = [NSTemporaryDirectory()
                         stringByAppendingPathComponent:@"jotty_new.txt"];
        [@"" writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];

        NSString *editor = [[[NSProcessInfo processInfo] environment]
                            objectForKey:@"EDITOR"] ?: @"vi";
        system([[NSString stringWithFormat:@"%@ %@", editor, tmp] UTF8String]);

        NSError *err = nil;
        content = [NSString stringWithContentsOfFile:tmp
                                            encoding:NSUTF8StringEncoding
                                               error:&err];
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
    }

    if (!content || [[content stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        printf("Aborted: empty note.\n");
        return;
    }

    // Escape for AppleScript
    NSString *esc = [content stringByReplacingOccurrencesOfString:@"\\"
                                                       withString:@"\\\\"];
    esc = [esc stringByReplacingOccurrencesOfString:@"\"" withString:@"\\\""];

    NSString *script;
    if (folder) {
        script = [NSString stringWithFormat:
            @"tell application \"Notes\"\n"
            @"  if not (exists folder \"%@\") then\n"
            @"    make new folder with properties {name:\"%@\"}\n"
            @"  end if\n"
            @"  tell folder \"%@\"\n"
            @"    set newNote to make new note with properties {body:\"%@\"}\n"
            @"    return name of newNote\n"
            @"  end tell\n"
            @"end tell", folder, folder, folder, esc];
    } else {
        script = [NSString stringWithFormat:
            @"tell application \"Notes\"\n"
            @"  set newNote to make new note with properties {body:\"%@\"}\n"
            @"  return name of newNote\n"
            @"end tell", esc];
    }

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error creating note: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("Created note: \"%s\"\n",
               [[res stringValue] ?: @"(untitled)" UTF8String]);
    }
}

void cmdNotesEdit(NSUInteger idx) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *t = noteTitle(note);
    NSArray *names = noteAttachmentNames(note);
    NSString *rawText = noteRawText(note);
    NSString *editText = rawTextToEditable(rawText, names);

    printf("Editing: \"%s\"\n", [t UTF8String]);
    if (names.count > 0) {
        printf("⚠️  Note has %lu attachment(s). Do NOT remove or rename the "
               "%%%%ATTACHMENT_N_...%%%% markers.\n",
               (unsigned long)names.count);
        for (NSUInteger i = 0; i < names.count; i++) {
            printf("   [%lu] %s\n", (unsigned long)i, [names[i] UTF8String]);
        }
    }

    // Write to temp file
    NSString *tmp = [NSTemporaryDirectory()
                     stringByAppendingPathComponent:@"jotty_edit.txt"];
    NSError *writeErr = nil;
    [editText writeToFile:tmp
               atomically:YES
                 encoding:NSUTF8StringEncoding
                    error:&writeErr];
    if (writeErr) {
        fprintf(stderr, "Error writing temp file: %s\n",
                [[writeErr localizedDescription] UTF8String]);
        return;
    }

    // Open editor
    NSString *editor = [[[NSProcessInfo processInfo] environment]
                        objectForKey:@"EDITOR"] ?: @"vi";
    int ret = system([[NSString stringWithFormat:@"%@ %@", editor, tmp] UTF8String]);
    if (ret != 0) {
        fprintf(stderr, "Editor returned error (%d)\n", ret);
        [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
        return;
    }

    // Read edited content
    NSError *readErr = nil;
    NSString *edited = [NSString stringWithContentsOfFile:tmp
                                                 encoding:NSUTF8StringEncoding
                                                    error:&readErr];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];

    if (!edited) {
        fprintf(stderr, "Error reading temp file: %s\n",
                [[readErr localizedDescription] UTF8String]);
        return;
    }

    // Restore attachment markers
    NSString *newRaw = editableToRawText(edited);

    // Validate: same number of attachment markers
    NSUInteger origCount = 0, newCount = 0;
    for (NSUInteger i = 0; i < [rawText length]; i++)
        if ([rawText characterAtIndex:i] == ATTACHMENT_MARKER) origCount++;
    for (NSUInteger i = 0; i < [newRaw length]; i++)
        if ([newRaw characterAtIndex:i] == ATTACHMENT_MARKER) newCount++;

    if (origCount != newCount) {
        fprintf(stderr,
                "Warning: attachment count changed (%lu → %lu). "
                "Markers should not be added or removed.\n",
                (unsigned long)origCount, (unsigned long)newCount);
    }

    // Apply CRDT edit
    if (!applyCRDTEdit(note, rawText, newRaw)) return;

    if (saveContext()) {
        printf("✓ Note saved (CRDT, attachments preserved).\n");
    } else {
        fprintf(stderr, "Error: save failed\n");
    }
}

void cmdNotesDelete(NSUInteger idx) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *t = noteTitle(note);
    printf("Delete note \"%s\"? (y/N) ", [t UTF8String]);
    fflush(stdout);

    char buf[8] = {0};
    if (fgets(buf, sizeof(buf), stdin) == NULL || (buf[0] != 'y' && buf[0] != 'Y')) {
        printf("Cancelled.\n");
        return;
    }

    NSString *noteID = noteURIString(note);
    NSString *script = [NSString stringWithFormat:
        @"tell application \"Notes\"\n"
        @"  set n to note id \"%@\"\n"
        @"  delete n\n"
        @"end tell", noteID];

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error deleting note: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("Deleted: \"%s\"\n", [t UTF8String]);
    }
}

void cmdNotesMove(NSUInteger idx, NSString *targetFolder) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *t = noteTitle(note);
    NSString *noteID = noteURIString(note);

    NSString *script = [NSString stringWithFormat:
        @"tell application \"Notes\"\n"
        @"  set n to note id \"%@\"\n"
        @"  if not (exists folder \"%@\") then\n"
        @"    make new folder with properties {name:\"%@\"}\n"
        @"  end if\n"
        @"  move n to folder \"%@\"\n"
        @"end tell",
        noteID, targetFolder, targetFolder, targetFolder];

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error moving note: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("Moved \"%s\" → \"%s\"\n", [t UTF8String],
               [targetFolder UTF8String]);
    }
}

void cmdNotesSearch(NSString *query) {
    // Search by title and snippet (Core Data attributes on ICNote)
    NSPredicate *pred = [NSPredicate predicateWithFormat:
        @"(title CONTAINS[cd] %@) OR (snippet CONTAINS[cd] %@)",
        query, query];
    NSArray *results = fetchNotes(pred);

    if (!results || results.count == 0) {
        printf("No notes found matching \"%s\"\n", [query UTF8String]);
        return;
    }

    printf("Found %lu note(s) matching \"%s\":\n\n",
           (unsigned long)results.count, [query UTF8String]);
    printf("  # %-42s %-22s\n", "Title", "Folder");
    printf("--- %-42s %-22s\n",
           "------------------------------------------",
           "----------------------");

    NSUInteger i = 1;
    for (id note in results) {
        NSString *t = truncStr(noteTitle(note), 42);
        NSString *f = truncStr(folderName(note), 22);
        printf("%3lu %-42s %-22s\n",
               (unsigned long)i,
               [padRight(t, 42) UTF8String],
               [padRight(f, 22) UTF8String]);
        i++;
    }
}

void cmdNotesExport(NSString *exportPath) {
    NSArray *notes = fetchAllNotes();
    if (!notes || notes.count == 0) {
        printf("No notes to export.\n");
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *mkErr = nil;
    [fm createDirectoryAtPath:exportPath
  withIntermediateDirectories:YES
                   attributes:nil
                        error:&mkErr];
    if (mkErr) {
        fprintf(stderr, "Error creating export directory: %s\n",
                [[mkErr localizedDescription] UTF8String]);
        return;
    }

    NSMutableString *index = [NSMutableString stringWithFormat:
        @"<!DOCTYPE html><html><head><meta charset='utf-8'>"
        @"<title>Notes Export</title><style>"
        @"body{font-family:-apple-system,sans-serif;max-width:900px;margin:40px auto;padding:0 20px}"
        @"h1{color:#1d1d1f}a{color:#0066cc;text-decoration:none}"
        @"a:hover{text-decoration:underline}"
        @"li{margin:8px 0}.folder{color:#888;font-size:.85em}"
        @"</style></head><body><h1>📝 Notes Export</h1><ul>\n"];

    NSUInteger i = 1;
    for (id note in notes) {
        NSString *t = noteTitle(note);
        NSString *f = folderName(note);
        NSString *body = noteTextForDisplay(note);

        // Sanitize filename
        NSMutableString *safeTitle = [NSMutableString stringWithString:t];
        NSCharacterSet *unsafe = [NSCharacterSet
            characterSetWithCharactersInString:@"/\\:*?\"<>|"];
        NSArray *parts = [safeTitle componentsSeparatedByCharactersInSet:unsafe];
        safeTitle = [NSMutableString stringWithString:[parts componentsJoinedByString:@"-"]];
        if ([safeTitle length] > 50) [safeTitle deleteCharactersInRange:NSMakeRange(50, [safeTitle length] - 50)];

        NSString *filename = [NSString stringWithFormat:@"%04lu_%@.html",
                              (unsigned long)i, safeTitle];
        NSString *filePath = [exportPath stringByAppendingPathComponent:filename];

        // HTML escape helper
        NSString *(^htmlEsc)(NSString *) = ^NSString *(NSString *s) {
            s = [s stringByReplacingOccurrencesOfString:@"&" withString:@"&amp;"];
            s = [s stringByReplacingOccurrencesOfString:@"<" withString:@"&lt;"];
            s = [s stringByReplacingOccurrencesOfString:@">" withString:@"&gt;"];
            s = [s stringByReplacingOccurrencesOfString:@"\n" withString:@"<br>\n"];
            return s;
        };

        NSString *eT = htmlEsc(t);
        NSString *eF = htmlEsc(f);
        NSString *eBody = htmlEsc(body);
        NSString *html = [NSString stringWithFormat:
            @"<!DOCTYPE html><html><head><meta charset='utf-8'><title>%@</title><style>"
            @"body{font-family:-apple-system,sans-serif;max-width:900px;margin:40px auto;padding:0 20px}"
            @"h1{color:#1d1d1f}.folder{color:#888;font-size:.9em}"
            @"pre{white-space:pre-wrap;background:#f5f5f7;padding:20px;border-radius:10px;line-height:1.6}"
            @"</style></head><body>"
            @"<h1>%@</h1><p class='folder'>&#x1F4C1; %@</p><pre>%@</pre>"
            @"</body></html>",
            eT, eT, eF, eBody];

        [html writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

        [index appendFormat:@"<li><a href='%@'>%@</a> "
                            @"<span class='folder'>&#x1F4C1; %@</span></li>\n",
                            filename, t, f];
        i++;
    }

    [index appendString:@"</ul><p><em>Exported by jotty v" VERSION "</em></p></body></html>"];
    NSString *indexPath = [exportPath stringByAppendingPathComponent:@"index.html"];
    [index writeToFile:indexPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    printf("Exported %lu notes to: %s\n",
           (unsigned long)(i - 1), [exportPath UTF8String]);
    printf("Index:    %s\n", [indexPath UTF8String]);
}

void cmdNotesAttach(NSUInteger idx, NSString *filePath) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    // Resolve absolute path
    NSString *absPath = [filePath hasPrefix:@"/"]
        ? filePath
        : [[[NSFileManager defaultManager] currentDirectoryPath]
           stringByAppendingPathComponent:filePath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:absPath]) {
        fprintf(stderr, "Error: File not found: %s\n", [absPath UTF8String]);
        return;
    }

    NSString *t = noteTitle(note);
    NSString *noteID = noteURIString(note);

    NSString *script = [NSString stringWithFormat:
        @"tell application \"Notes\"\n"
        @"  set n to note id \"%@\"\n"
        @"  tell n\n"
        @"    make new attachment with properties {filename:\"%@\"} at beginning of body\n"
        @"  end tell\n"
        @"  return count of attachments of n\n"
        @"end tell", noteID, absPath];

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error adding attachment: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("✓ Attachment added to \"%s\" (now %s attachment(s))\n",
               [t UTF8String],
               [[res stringValue] ?: @"?" UTF8String]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: rem (Reminders)
// ─────────────────────────────────────────────────────────────────────────────

void cmdRemList(void) {
    NSString *script =
        @"tell application \"Reminders\"\n"
        @"  set output to \"\"\n"
        @"  set idx to 1\n"
        @"  repeat with aList in every list\n"
        @"    set rems to (every reminder of aList whose completed is false)\n"
        @"    repeat with r in rems\n"
        @"      set dueInfo to \"\"\n"
        @"      try\n"
        @"        set dueDate to due date of r\n"
        @"        set dueInfo to \"  [due \" & (dueDate as string) & \"]\"\n"
        @"      end try\n"
        @"      set listName to name of aList\n"
        @"      set output to output & idx & \". \" & (name of r) & "
        @"                    \" (\" & listName & \")\" & dueInfo & \"\n\"\n"
        @"      set idx to idx + 1\n"
        @"    end repeat\n"
        @"  end repeat\n"
        @"  if output is \"\" then return \"(no incomplete reminders)\"\n"
        @"  return output\n"
        @"end tell";

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error listing reminders: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("%s\n", [[res stringValue] UTF8String]);
    }
}

void cmdRemAdd(NSString *title, NSString *dueDate) {
    NSString *esc = [title stringByReplacingOccurrencesOfString:@"\""
                                                     withString:@"\\\""];
    NSString *script;
    if (dueDate) {
        NSString *escDate = [dueDate stringByReplacingOccurrencesOfString:@"\""
                                                               withString:@"\\\""];
        script = [NSString stringWithFormat:
            @"tell application \"Reminders\"\n"
            @"  set r to make new reminder with properties "
            @"    {name:\"%@\", due date:date \"%@\"}\n"
            @"  return name of r\n"
            @"end tell", esc, escDate];
    } else {
        script = [NSString stringWithFormat:
            @"tell application \"Reminders\"\n"
            @"  set r to make new reminder with properties {name:\"%@\"}\n"
            @"  return name of r\n"
            @"end tell", esc];
    }

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error adding reminder: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("Added reminder: \"%s\"\n",
               [[res stringValue] ?: title UTF8String]);
    }
}

// Helper: generate AppleScript to find reminder N and do an action
NSString *remScriptFindAndAct(NSUInteger idx, NSString *action) {
    return [NSString stringWithFormat:
        @"tell application \"Reminders\"\n"
        @"  set idx to 0\n"
        @"  repeat with aList in every list\n"
        @"    set rems to (every reminder of aList whose completed is false)\n"
        @"    repeat with r in rems\n"
        @"      set idx to idx + 1\n"
        @"      if idx = %lu then\n"
        @"        %@\n"
        @"      end if\n"
        @"    end repeat\n"
        @"  end repeat\n"
        @"  return \"Reminder %lu not found\"\n"
        @"end tell",
        (unsigned long)idx, action, (unsigned long)idx];
}

void cmdRemEdit(NSUInteger idx, NSString *newTitle) {
    NSString *esc = [newTitle stringByReplacingOccurrencesOfString:@"\""
                                                        withString:@"\\\""];
    NSString *action = [NSString stringWithFormat:
        @"set name of r to \"%@\"\n"
        @"        return \"Updated: \" & name of r", esc];
    NSString *script = remScriptFindAndAct(idx, action);

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error editing reminder: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("%s\n", [[res stringValue] UTF8String]);
    }
}

void cmdRemDelete(NSUInteger idx) {
    NSString *action =
        @"set rName to name of r\n"
        @"        delete r\n"
        @"        return \"Deleted: \" & rName";
    NSString *script = remScriptFindAndAct(idx, action);

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error deleting reminder: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("%s\n", [[res stringValue] UTF8String]);
    }
}

void cmdRemComplete(NSUInteger idx) {
    NSString *action =
        @"set completed of r to true\n"
        @"        return \"Completed: \" & name of r";
    NSString *script = remScriptFindAndAct(idx, action);

    NSString *errMsg = nil;
    NSAppleEventDescriptor *res = runAppleScript(script, &errMsg);
    if (!res) {
        fprintf(stderr, "Error completing reminder: %s\n",
                errMsg ? [errMsg UTF8String] : "unknown");
    } else {
        printf("%s\n", [[res stringValue] UTF8String]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Help text
// ─────────────────────────────────────────────────────────────────────────────

void printHelp(void) {
    printf(
"jotty v" VERSION " — Apple Notes CLI with CRDT attachment support\n"
"\n"
"USAGE:\n"
"  jotty notes [options]    Notes operations\n"
"  jotty rem [options]      Reminders operations\n"
"  jotty --version          Show version\n"
"  jotty --help             Show this help\n"
"\n"
"NOTES OPTIONS:\n"
"  (no args)                    List all notes\n"
"  -f <folder>                  Filter by / set folder\n"
"  -fl                          List all folders\n"
"  -v <N>                       View note N\n"
"  -a                           Add note (stdin or $EDITOR)\n"
"  -a -f <folder>               Add note to folder\n"
"  -e <N>                       Edit note N (CRDT — preserves attachments!)\n"
"  -d <N>                       Delete note N\n"
"  -m <N> -f <folder>           Move note N to folder\n"
"  -s <query>                   Search notes by text\n"
"  --export <path>              Export all notes to HTML\n"
"  --attach <N> <file>          Add file attachment to note N\n"
"\n"
"REMINDERS OPTIONS:\n"
"  (no args)                    List all incomplete reminders\n"
"  -a <title> [due-date]        Add reminder\n"
"  -e <N> <new-title>           Edit reminder N\n"
"  -d <N>                       Delete reminder N\n"
"  -c <N>                       Complete reminder N\n"
"\n"
"CRDT EDIT:\n"
"  The -e command opens the note in $EDITOR with %%ATTACHMENT_N_name%%\n"
"  markers where images/files are. Edit the text freely; do NOT remove\n"
"  or rename the markers. On save, changes are applied via\n"
"  ICTTMergeableString, so attachments stay in their original positions.\n"
    );
}

void printNotesHelp(void) {
    printf(
"jotty notes — Apple Notes CLI\n"
"\n"
"USAGE:\n"
"  jotty notes                     List all notes\n"
"  jotty notes -f <folder>         List notes in folder\n"
"  jotty notes -fl                 List all folders\n"
"  jotty notes -v <N>              View note N\n"
"  jotty notes -a                  Add note (reads stdin or $EDITOR)\n"
"  jotty notes -a -f <folder>      Add note to folder\n"
"  jotty notes -e <N>              Edit note N via CRDT (preserves attachments)\n"
"  jotty notes -d <N>              Delete note N\n"
"  jotty notes -m <N> -f <folder>  Move note N to folder\n"
"  jotty notes -s <query>          Search notes\n"
"  jotty notes --export <path>     Export notes to HTML\n"
"  jotty notes --attach <N> <file> Attach file to note N\n"
    );
}

void printRemHelp(void) {
    printf(
"jotty rem — Reminders CLI\n"
"\n"
"USAGE:\n"
"  jotty rem                       List all incomplete reminders\n"
"  jotty rem -a <title>            Add reminder\n"
"  jotty rem -a <title> <due>      Add reminder with due date\n"
"  jotty rem -e <N> <new-title>    Edit reminder N\n"
"  jotty rem -d <N>                Delete reminder N\n"
"  jotty rem -c <N>                Complete reminder N\n"
    );
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
            printf("jotty v" VERSION "\n");
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

            // Init Core Data / NotesShared for all notes sub-commands
            if (!initNotesContext()) return 1;

            if (argc == 2) {
                // jotty notes
                cmdNotesList(nil);
                return 0;
            }

            NSString *opt = [NSString stringWithUTF8String:argv[2]];

            if ([opt isEqualToString:@"-fl"]) {
                cmdFoldersList();

            } else if ([opt isEqualToString:@"-f"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty notes -f <folder>\n");
                    return 1;
                }
                NSString *folder = [NSString stringWithUTF8String:argv[3]];
                cmdNotesList(folder);

            } else if ([opt isEqualToString:@"-v"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty notes -v <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdNotesView(idx, nil);

            } else if ([opt isEqualToString:@"-a"]) {
                NSString *folder = nil;
                for (int i = 3; i < argc - 1; i++) {
                    if (strcmp(argv[i], "-f") == 0) {
                        folder = [NSString stringWithUTF8String:argv[i + 1]];
                    }
                }
                cmdNotesAdd(folder);

            } else if ([opt isEqualToString:@"-e"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty notes -e <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdNotesEdit(idx);

            } else if ([opt isEqualToString:@"-d"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty notes -d <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdNotesDelete(idx);

            } else if ([opt isEqualToString:@"-m"]) {
                if (argc < 6 || strcmp(argv[4], "-f") != 0) {
                    fprintf(stderr, "Usage: jotty notes -m <N> -f <folder>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *folder = [NSString stringWithUTF8String:argv[5]];
                cmdNotesMove(idx, folder);

            } else if ([opt isEqualToString:@"-s"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty notes -s <query>\n");
                    return 1;
                }
                NSString *query = [NSString stringWithUTF8String:argv[3]];
                cmdNotesSearch(query);

            } else if ([opt isEqualToString:@"--export"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty notes --export <path>\n");
                    return 1;
                }
                NSString *path = [NSString stringWithUTF8String:argv[3]];
                cmdNotesExport(path);

            } else if ([opt isEqualToString:@"--attach"]) {
                if (argc < 5) {
                    fprintf(stderr, "Usage: jotty notes --attach <N> <file>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *filePath = [NSString stringWithUTF8String:argv[4]];
                cmdNotesAttach(idx, filePath);

            } else {
                fprintf(stderr, "Unknown notes option: %s\n", argv[2]);
                printNotesHelp();
                return 1;
            }
            return 0;
        }

        // ── rem ──────────────────────────────────────────────────────────────
        if ([cmd isEqualToString:@"rem"]) {
            if (argc >= 3 && strcmp(argv[2], "--help") == 0) {
                printRemHelp();
                return 0;
            }

            if (argc == 2) {
                cmdRemList();
                return 0;
            }

            NSString *opt = [NSString stringWithUTF8String:argv[2]];

            if ([opt isEqualToString:@"-a"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty rem -a <title> [due-date]\n");
                    return 1;
                }
                NSString *title = [NSString stringWithUTF8String:argv[3]];
                NSString *due = (argc >= 5) ? [NSString stringWithUTF8String:argv[4]] : nil;
                cmdRemAdd(title, due);

            } else if ([opt isEqualToString:@"-e"]) {
                if (argc < 5) {
                    fprintf(stderr, "Usage: jotty rem -e <N> <new-title>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                NSString *title = [NSString stringWithUTF8String:argv[4]];
                cmdRemEdit(idx, title);

            } else if ([opt isEqualToString:@"-d"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty rem -d <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdRemDelete(idx);

            } else if ([opt isEqualToString:@"-c"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: jotty rem -c <N>\n");
                    return 1;
                }
                NSUInteger idx = (NSUInteger)atoi(argv[3]);
                cmdRemComplete(idx);

            } else {
                fprintf(stderr, "Unknown rem option: %s\n", argv[2]);
                printRemHelp();
                return 1;
            }
            return 0;
        }

        fprintf(stderr, "Unknown command: %s\n"
                "Run 'jotty --help' for usage.\n", [cmd UTF8String]);
        return 1;
    }
}
