/**
 * cider — Apple Notes CLI with CRDT attachment support
 *
 * Uses Apple's private NotesShared.framework CRDT API (ICTTMergeableString)
 * to edit notes while preserving attachments in their original position.
 *
 * Compile: clang -framework Foundation -framework CoreData -o cider cider.m
 */

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#define VERSION "2.0.0"
#define ATTACHMENT_MARKER ((unichar)0xFFFC)

// Forward declarations
NSArray *attachmentOrderFromCRDT(id note);
NSString *attachmentNameByID(NSArray *atts, NSString *attID);
void cmdNotesAttachAt(NSUInteger idx, NSString *filePath, NSUInteger position);

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

    // Verify we can actually read from the store (detect Full Disk Access issues)
    NSFetchRequest *testReq = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
    testReq.fetchLimit = 1;
    NSError *testErr = nil;
    NSArray *testResult = [g_moc executeFetchRequest:testReq error:&testErr];
    if (testErr || !testResult) {
        NSString *errDesc = [testErr localizedDescription] ?: @"unknown error";
        if ([errDesc containsString:@"256"] ||
            [errDesc containsString:@"couldn't be opened"] ||
            [errDesc containsString:@"failure to access"]) {
            fprintf(stderr,
                "\n"
                "Error: Cannot access the Notes database.\n"
                "\n"
                "This is usually a macOS permissions issue. To fix it:\n"
                "\n"
                "  1. Open System Settings → Privacy & Security → Full Disk Access\n"
                "  2. Click + and add your terminal app\n"
                "     (Terminal.app, iTerm, Warp, etc.)\n"
                "  3. Restart your terminal\n"
                "\n");
        } else {
            fprintf(stderr, "Error: Failed to read Notes database: %s\n",
                    [errDesc UTF8String]);
        }
        return NO;
    }

    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// Core Data helpers
// ─────────────────────────────────────────────────────────────────────────────

NSArray *fetchNotes(NSPredicate *predicate) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
    NSPredicate *notDeleted = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
    req.predicate = predicate
        ? [NSCompoundPredicate andPredicateWithSubpredicates:@[notDeleted, predicate]]
        : notDeleted;
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
    return fetchNotes([NSPredicate predicateWithFormat:@"markedForDeletion == NO"]);
}

NSArray *fetchFolders(void) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    req.predicate = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
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

// Find a folder by title, optionally creating it if it doesn't exist
id findOrCreateFolder(NSString *title, BOOL create) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    req.predicate = [NSPredicate predicateWithFormat:@"title == %@ AND markedForDeletion == NO", title];
    NSArray *results = [g_moc executeFetchRequest:req error:nil];
    if (results.count > 0) return results.firstObject;
    if (!create) return nil;

    // Get account from an existing (non-deleted) folder
    NSFetchRequest *fReq = [NSFetchRequest fetchRequestWithEntityName:@"ICFolder"];
    fReq.predicate = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
    NSArray *allFolders = [g_moc executeFetchRequest:fReq error:nil];
    id account = nil;
    for (id f in allFolders) {
        account = [f valueForKey:@"account"];
        if (account) break;
    }
    if (!account) return nil;

    id newFolder = [NSEntityDescription
        insertNewObjectForEntityForName:@"ICFolder"
                 inManagedObjectContext:g_moc];
    ((void (*)(id, SEL, id))objc_msgSend)(
        newFolder, NSSelectorFromString(@"setTitle:"), title);
    [newFolder setValue:account forKey:@"account"];
    return newFolder;
}

// Get the default folder ("Notes") or the first available folder
id defaultFolder(void) {
    id folder = findOrCreateFolder(@"Notes", NO);
    if (folder) return folder;
    NSArray *all = fetchFolders();
    for (id f in all) {
        NSString *t = [f valueForKey:@"title"];
        if (t && t.length > 0) return f;
    }
    return nil;
}

// Get the x-coredata:// URI string for a note
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
    id folder = [note valueForKey:@"folder"];
    if (!folder) return @"Notes";
    id title = [folder valueForKey:@"title"];
    if (title && [title isKindOfClass:[NSString class]]) return (NSString *)title;
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

NSArray *attachmentsAsArray(id attsObj) {
    if (!attsObj) return @[];
    if ([attsObj isKindOfClass:[NSArray class]]) return (NSArray *)attsObj;
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

NSString *editableToRawText(NSString *edited) {
    NSMutableString *result = [NSMutableString stringWithString:edited];
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"%%ATTACHMENT_\\d+_[^%]*%%"
                             options:0
                               error:nil];
    NSArray *matches = [regex matchesInString:result
                                      options:0
                                        range:NSMakeRange(0, [result length])];
    for (NSInteger i = (NSInteger)matches.count - 1; i >= 0; i--) {
        NSTextCheckingResult *match = matches[(NSUInteger)i];
        [result replaceCharactersInRange:match.range
                              withString:@"\uFFFC"];
    }
    return result;
}

BOOL saveContext(void) {
    NSError *err = nil;
    BOOL ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(
        g_ctx, NSSelectorFromString(@"save:"), &err);
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

    NSUInteger prefix = 0;
    while (prefix < oldLen && prefix < newLen &&
           [oldText characterAtIndex:prefix] ==
               [newText characterAtIndex:prefix]) {
        prefix++;
    }

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

NSArray *filteredNotes(NSString *filterFolder) {
    NSArray *all = fetchAllNotes();
    if (!all) return @[];

    NSMutableArray *result = [NSMutableArray array];
    for (id note in all) {
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

id noteAtIndex(NSUInteger idx, NSString *folder) {
    NSArray *notes = filteredNotes(folder);
    if (idx == 0 || idx > notes.count) return nil;
    return notes[idx - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
// JSON helpers
// ─────────────────────────────────────────────────────────────────────────────

// Simple JSON string escaping
NSString *jsonEscapeString(NSString *s) {
    if (!s) return @"";
    NSMutableString *r = [NSMutableString stringWithString:s];
    [r replaceOccurrencesOfString:@"\\" withString:@"\\\\" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\"" withString:@"\\\"" options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\n" withString:@"\\n"  options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\r" withString:@"\\r"  options:0 range:NSMakeRange(0, r.length)];
    [r replaceOccurrencesOfString:@"\t" withString:@"\\t"  options:0 range:NSMakeRange(0, r.length)];
    return r;
}

// ─────────────────────────────────────────────────────────────────────────────
// Interactive prompt helper
// ─────────────────────────────────────────────────────────────────────────────

// Forward declaration (cmdNotesList is defined below)
void cmdNotesList(NSString *folder, BOOL jsonOutput);

// Prompt user for a note index when none was supplied.
// Shows the note list, then reads a number from stdin.
// Returns 0 on failure/cancel.
NSUInteger promptNoteIndex(NSString *verb, NSString *folder) {
    if (!isatty(STDIN_FILENO)) {
        fprintf(stderr, "Error: note number required (stdin is not a tty)\n");
        return 0;
    }

    cmdNotesList(folder, NO);

    printf("\nEnter note number to %s: ", verb ? [verb UTF8String] : "select");
    fflush(stdout);

    char buf[32] = {0};
    if (fgets(buf, sizeof(buf), stdin) == NULL) return 0;
    int n = atoi(buf);
    if (n <= 0) {
        printf("Cancelled.\n");
        return 0;
    }
    return (NSUInteger)n;
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

void cmdNotesList(NSString *folder, BOOL jsonOutput) {
    NSArray *notes = filteredNotes(folder);

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < notes.count; i++) {
            id note = notes[i];
            NSString *t = jsonEscapeString(noteTitle(note));
            NSString *f = jsonEscapeString(folderName(note));
            NSUInteger ac = noteAttachmentCount(note);
            printf("  {\"index\":%lu,\"title\":\"%s\",\"folder\":\"%s\",\"attachments\":%lu}%s\n",
                   (unsigned long)(i + 1),
                   [t UTF8String],
                   [f UTF8String],
                   (unsigned long)ac,
                   (i + 1 < notes.count) ? "," : "");
        }
        printf("]\n");
        return;
    }

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

void cmdFoldersList(BOOL jsonOutput) {
    NSArray *folders = fetchFolders();

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < folders.count; i++) {
            id folder = folders[i];
            id titleVal = [folder valueForKey:@"title"];
            NSString *name = (titleVal && [titleVal isKindOfClass:[NSString class]])
                ? (NSString *)titleVal : @"(unnamed)";
            id parent = [folder valueForKey:@"parent"];
            NSString *parentName = @"";
            if (parent) {
                id pTitleVal = [parent valueForKey:@"title"];
                if (pTitleVal && [pTitleVal isKindOfClass:[NSString class]])
                    parentName = (NSString *)pTitleVal;
            }
            printf("  {\"name\":\"%s\",\"parent\":\"%s\"}%s\n",
                   [jsonEscapeString(name) UTF8String],
                   [jsonEscapeString(parentName) UTF8String],
                   (i + 1 < folders.count) ? "," : "");
        }
        printf("]\n");
        return;
    }

    printf("Folders:\n");
    for (id folder in folders) {
        id titleVal = [folder valueForKey:@"title"];
        NSString *name = (titleVal && [titleVal isKindOfClass:[NSString class]])
            ? (NSString *)titleVal : @"(unnamed)";
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

int cmdNotesView(NSUInteger idx, NSString *folder, BOOL jsonOutput) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *t = noteTitle(note);
    NSString *f = folderName(note);
    NSArray *names = noteAttachmentNames(note);
    NSUInteger ac = names.count;
    NSString *body = noteTextForDisplay(note);

    if (jsonOutput) {
        NSMutableString *jsonNames = [NSMutableString stringWithString:@"["];
        for (NSUInteger i = 0; i < names.count; i++) {
            [jsonNames appendFormat:@"\"%@\"%@",
             jsonEscapeString(names[i]),
             (i + 1 < names.count) ? @"," : @""];
        }
        [jsonNames appendString:@"]"];
        printf("{\"index\":%lu,\"title\":\"%s\",\"folder\":\"%s\","
               "\"attachments\":%lu,\"attachment_names\":%s,\"body\":\"%s\"}\n",
               (unsigned long)idx,
               [jsonEscapeString(t) UTF8String],
               [jsonEscapeString(f) UTF8String],
               (unsigned long)ac,
               [jsonNames UTF8String],
               [jsonEscapeString(body) UTF8String]);
        return 0;
    }

    printf("╔══════════════════════════════════════════╗\n");
    printf("  %s\n", [t UTF8String]);
    printf("  Folder: %s", [f UTF8String]);
    if (ac > 0) {
        printf(" | 📎 %lu attachment(s): ", (unsigned long)ac);
        for (NSString *n in names) printf("%s ", [n UTF8String]);
    }
    printf("\n╚══════════════════════════════════════════╝\n\n");

    printf("%s\n", [body UTF8String]);
    return 0;
}

void cmdNotesAdd(NSString *folderName) {
    NSString *content = nil;

    if (!isatty(STDIN_FILENO)) {
        NSData *data = [[NSFileHandle fileHandleWithStandardInput]
                        readDataToEndOfFile];
        content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    } else {
        NSString *tmp = [NSTemporaryDirectory()
                         stringByAppendingPathComponent:@"cider_new.txt"];
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

    // Find or create target folder
    id folder = folderName
        ? findOrCreateFolder(folderName, YES)
        : defaultFolder();
    if (!folder) {
        fprintf(stderr, "Error: Could not find or create folder\n");
        return;
    }
    id account = [folder valueForKey:@"account"];

    // Create note entity
    id newNote = [NSEntityDescription
        insertNewObjectForEntityForName:@"ICNote"
                 inManagedObjectContext:g_moc];
    ((void (*)(id, SEL, id))objc_msgSend)(
        newNote, NSSelectorFromString(@"setFolder:"), folder);
    if (account) {
        ((void (*)(id, SEL, id))objc_msgSend)(
            newNote, NSSelectorFromString(@"setAccount:"), account);
    }
    [newNote setValue:[NSDate date] forKey:@"creationDate"];
    [newNote setValue:[NSDate date] forKey:@"modificationDate"];

    // Create ICNoteData entity and link
    id noteDataEntity = [NSEntityDescription
        insertNewObjectForEntityForName:@"ICNoteData"
                 inManagedObjectContext:g_moc];
    [newNote setValue:noteDataEntity forKey:@"noteData"];

    // Write text via CRDT
    id mergeStr = noteMergeableString(newNote);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string for new note\n");
        [g_moc rollback];
        return;
    }
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"insertString:atIndex:"),
        content, (NSUInteger)0);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    // Save CRDT data to noteData (handles compression)
    ((void (*)(id, SEL))objc_msgSend)(
        newNote, NSSelectorFromString(@"saveNoteData"));

    // Update derived attributes (title, snippet)
    ((void (*)(id, SEL))objc_msgSend)(
        newNote, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    if (saveContext()) {
        NSString *t = noteTitle(newNote);
        printf("Created note: \"%s\"\n", [t UTF8String]);
    } else {
        fprintf(stderr, "Error: Failed to save new note\n");
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

    NSString *newRaw = nil;

    // If stdin is not a tty, read content from stdin (pipe mode)
    if (!isatty(STDIN_FILENO)) {
        NSData *data = [[NSFileHandle fileHandleWithStandardInput]
                        readDataToEndOfFile];
        NSString *piped = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!piped || [[piped stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            printf("Aborted: empty input.\n");
            return;
        }
        // Piped content replaces note body; attachment markers are restored if present
        newRaw = editableToRawText(piped);
    } else {
        printf("Editing: \"%s\"\n", [t UTF8String]);
        if (names.count > 0) {
            printf("⚠️  Note has %lu attachment(s). Do NOT remove or rename the "
                   "%%%%ATTACHMENT_N_...%%%% markers.\n",
                   (unsigned long)names.count);
            for (NSUInteger i = 0; i < names.count; i++) {
                printf("   [%lu] %s\n", (unsigned long)i, [names[i] UTF8String]);
            }
        }

        NSString *tmp = [NSTemporaryDirectory()
                         stringByAppendingPathComponent:@"cider_edit.txt"];
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

        NSString *editor = [[[NSProcessInfo processInfo] environment]
                            objectForKey:@"EDITOR"] ?: @"vi";
        int ret = system([[NSString stringWithFormat:@"%@ %@", editor, tmp] UTF8String]);
        if (ret != 0) {
            fprintf(stderr, "Editor returned error (%d)\n", ret);
            [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];
            return;
        }

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

        newRaw = editableToRawText(edited);
    }

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

    if (!applyCRDTEdit(note, rawText, newRaw)) return;

    if (saveContext()) {
        printf("✓ Note saved (CRDT, attachments preserved).\n");
    } else {
        fprintf(stderr, "Error: save failed\n");
    }
}

int cmdNotesReplace(NSUInteger idx, NSString *findStr, NSString *replaceStr) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *rawText = noteRawText(note);
    NSRange found = [rawText rangeOfString:findStr];
    if (found.location == NSNotFound) {
        fprintf(stderr, "Error: Text not found in note %lu: \"%s\"\n",
                (unsigned long)idx, [findStr UTF8String]);
        return 1;
    }

    NSString *newRaw = [rawText stringByReplacingOccurrencesOfString:findStr
                                                          withString:replaceStr];

    if (!applyCRDTEdit(note, rawText, newRaw)) return 1;

    if (saveContext()) {
        printf("✓ Replaced \"%s\" → \"%s\" in note %lu.\n",
               [findStr UTF8String], [replaceStr UTF8String], (unsigned long)idx);
        return 0;
    } else {
        fprintf(stderr, "Error: save failed\n");
        return 1;
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

    ((void (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"deleteFromLocalDatabase"));

    if (saveContext()) {
        printf("Deleted: \"%s\"\n", [t UTF8String]);
    } else {
        fprintf(stderr, "Error: Failed to delete note\n");
    }
}

void cmdNotesMove(NSUInteger idx, NSString *targetFolderName) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    id folder = findOrCreateFolder(targetFolderName, YES);
    if (!folder) {
        fprintf(stderr, "Error: Could not find or create folder \"%s\"\n",
                [targetFolderName UTF8String]);
        return;
    }

    NSString *t = noteTitle(note);
    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"setFolder:"), folder);
    [note setValue:[NSDate date] forKey:@"modificationDate"];

    if (saveContext()) {
        printf("Moved \"%s\" → \"%s\"\n", [t UTF8String],
               [targetFolderName UTF8String]);
    } else {
        fprintf(stderr, "Error: Failed to move note\n");
    }
}

void cmdNotesSearch(NSString *query, BOOL jsonOutput) {
    NSPredicate *pred = [NSPredicate predicateWithFormat:
        @"(title CONTAINS[cd] %@) OR (snippet CONTAINS[cd] %@)",
        query, query];
    NSArray *results = fetchNotes(pred);

    if (!results || results.count == 0) {
        if (jsonOutput) {
            printf("[]\n");
        } else {
            printf("No notes found matching \"%s\"\n", [query UTF8String]);
        }
        return;
    }

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < results.count; i++) {
            id note = results[i];
            NSString *t = jsonEscapeString(noteTitle(note));
            NSString *f = jsonEscapeString(folderName(note));
            NSUInteger ac = noteAttachmentCount(note);
            printf("  {\"index\":%lu,\"title\":\"%s\",\"folder\":\"%s\",\"attachments\":%lu}%s\n",
                   (unsigned long)(i + 1),
                   [t UTF8String],
                   [f UTF8String],
                   (unsigned long)ac,
                   (i + 1 < results.count) ? "," : "");
        }
        printf("]\n");
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

        NSMutableString *safeTitle = [NSMutableString stringWithString:t];
        NSCharacterSet *unsafe = [NSCharacterSet
            characterSetWithCharactersInString:@"/\\:*?\"<>|"];
        NSArray *parts = [safeTitle componentsSeparatedByCharactersInSet:unsafe];
        safeTitle = [NSMutableString stringWithString:[parts componentsJoinedByString:@"-"]];
        if ([safeTitle length] > 50) [safeTitle deleteCharactersInRange:NSMakeRange(50, [safeTitle length] - 50)];

        NSString *filename = [NSString stringWithFormat:@"%04lu_%@.html",
                              (unsigned long)i, safeTitle];
        NSString *filePath = [exportPath stringByAppendingPathComponent:filename];

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

    [index appendString:@"</ul><p><em>Exported by cider v" VERSION "</em></p></body></html>"];
    NSString *indexPath = [exportPath stringByAppendingPathComponent:@"index.html"];
    [index writeToFile:indexPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    printf("Exported %lu notes to: %s\n",
           (unsigned long)(i - 1), [exportPath UTF8String]);
    printf("Index:    %s\n", [indexPath UTF8String]);
}

void cmdNotesAttachments(NSUInteger idx, BOOL jsonOut) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
    NSString *raw = noteRawText(note);

    // Find marker positions
    NSMutableArray *markerPositions = [NSMutableArray array];
    for (NSUInteger i = 0; i < [raw length]; i++) {
        if ([raw characterAtIndex:i] == ATTACHMENT_MARKER)
            [markerPositions addObject:@(i)];
    }

    NSUInteger count = orderedIDs ? orderedIDs.count : 0;

    if (jsonOut) {
        printf("[");
        for (NSUInteger i = 0; i < count; i++) {
            id val = orderedIDs[i];
            NSString *attID = (val != [NSNull null]) ? val : nil;
            NSString *name = attID ? attachmentNameByID(atts, attID) : @"attachment";
            NSString *uti = @"unknown";
            NSUInteger pos = (i < markerPositions.count)
                ? [markerPositions[i] unsignedIntegerValue] : 0;
            if (attID) {
                for (id att in atts) {
                    NSString *ident = ((id (*)(id, SEL))objc_msgSend)(
                        att, NSSelectorFromString(@"identifier"));
                    if ([ident isEqualToString:attID]) {
                        id u = [att valueForKey:@"typeUTI"];
                        if (u) uti = u;
                        break;
                    }
                }
            }
            printf("%s{\"index\":%lu,\"name\":\"%s\",\"type\":\"%s\",\"position\":%lu,\"id\":\"%s\"}",
                   i > 0 ? "," : "",
                   (unsigned long)(i + 1),
                   [name UTF8String],
                   [uti UTF8String],
                   (unsigned long)pos,
                   attID ? [attID UTF8String] : "");
        }
        printf("]\n");
    } else {
        NSString *title = noteTitle(note);
        if (count == 0) {
            printf("No attachments in \"%s\"\n", [title UTF8String]);
            return;
        }
        printf("Attachments in \"%s\":\n", [title UTF8String]);
        for (NSUInteger i = 0; i < count; i++) {
            id val = orderedIDs[i];
            NSString *attID = (val != [NSNull null]) ? val : nil;
            NSString *name = attID ? attachmentNameByID(atts, attID) : @"attachment";
            NSString *uti = @"unknown";
            NSUInteger pos = (i < markerPositions.count)
                ? [markerPositions[i] unsignedIntegerValue] : 0;
            if (attID) {
                for (id att in atts) {
                    NSString *ident = ((id (*)(id, SEL))objc_msgSend)(
                        att, NSSelectorFromString(@"identifier"));
                    if ([ident isEqualToString:attID]) {
                        id u = [att valueForKey:@"typeUTI"];
                        if (u) uti = u;
                        break;
                    }
                }
            }
            printf("  %lu. %s  (%s, position %lu)\n",
                   (unsigned long)(i + 1),
                   [name UTF8String],
                   [uti UTF8String],
                   (unsigned long)pos);
        }
    }
}

void cmdNotesAttach(NSUInteger idx, NSString *filePath) {
    // Default attach (no position): appends to end of note via CRDT
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *absPath = [filePath hasPrefix:@"/"]
        ? filePath
        : [[[NSFileManager defaultManager] currentDirectoryPath]
           stringByAppendingPathComponent:filePath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:absPath]) {
        fprintf(stderr, "Error: File not found: %s\n", [absPath UTF8String]);
        return;
    }

    // Get current text length to append at end
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string for note\n");
        return;
    }
    NSUInteger textLen = ((NSUInteger (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"length"));

    // Use the CRDT attach-at-position path (append to end)
    cmdNotesAttachAt(idx, filePath, textLen);
}

void cmdNotesAttachAt(NSUInteger idx, NSString *filePath, NSUInteger position) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *absPath = [filePath hasPrefix:@"/"]
        ? filePath
        : [[[NSFileManager defaultManager] currentDirectoryPath]
           stringByAppendingPathComponent:filePath];

    if (![[NSFileManager defaultManager] fileExistsAtPath:absPath]) {
        fprintf(stderr, "Error: File not found: %s\n", [absPath UTF8String]);
        return;
    }

    // Get mergeable string to validate position
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string for note\n");
        return;
    }

    NSUInteger textLen = ((NSUInteger (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"length"));
    if (position > textLen) {
        fprintf(stderr, "Error: Position %lu out of range (note length: %lu)\n",
                (unsigned long)position, (unsigned long)textLen);
        return;
    }

    // 1. Create ICAttachment via addAttachmentWithFileURL:
    NSURL *fileURL = [NSURL fileURLWithPath:absPath];
    id attachment = ((id (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"addAttachmentWithFileURL:"), fileURL);
    if (!attachment) {
        fprintf(stderr, "Error: addAttachmentWithFileURL: returned nil\n");
        return;
    }

    // 2. Get identifier and UTI
    NSString *attID = ((id (*)(id, SEL))objc_msgSend)(
        attachment, NSSelectorFromString(@"identifier"));
    NSString *attUTI = ((id (*)(id, SEL))objc_msgSend)(
        attachment, NSSelectorFromString(@"typeUTI"));

    // 3. Create ICTTAttachment
    Class TTAttClass = NSClassFromString(@"ICTTAttachment");
    id ttAtt = [[TTAttClass alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(ttAtt, NSSelectorFromString(@"setAttachmentIdentifier:"), attID);
    ((void (*)(id, SEL, id))objc_msgSend)(ttAtt, NSSelectorFromString(@"setAttachmentUTI:"), attUTI);

    // 4. Build attributed string with U+FFFC
    unichar marker = ATTACHMENT_MARKER;
    NSString *markerStr = [NSString stringWithCharacters:&marker length:1];
    NSDictionary *attrs = @{@"NSAttachment": ttAtt};
    NSAttributedString *attAttrStr = [[NSAttributedString alloc] initWithString:markerStr attributes:attrs];

    // 5. Insert into CRDT at position
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"insertAttributedString:atIndex:"), attAttrStr, position);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    // 6. Update derived attributes and save
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
    NSError *saveErr = nil;
    [g_moc save:&saveErr];
    if (saveErr) {
        fprintf(stderr, "Error saving: %s\n", [[saveErr localizedDescription] UTF8String]);
        return;
    }

    NSString *t = noteTitle(note);
    printf("✓ Attachment inserted at position %lu in \"%s\" (id: %s)\n",
           (unsigned long)position, [t UTF8String], [attID UTF8String]);
}

/**
 * Build a mapping from text position (U+FFFC index) to attachment identifier
 * by inspecting the CRDT attributed string attributes.
 */
NSArray *attachmentOrderFromCRDT(id note) {
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) return nil;

    NSString *raw = noteRawText(note);
    NSMutableArray *ordered = [NSMutableArray array];

    id attrString = nil;
    @try {
        attrString = ((id (*)(id, SEL))objc_msgSend)(
            mergeStr, NSSelectorFromString(@"attributedString"));
    }
    @catch (NSException *e) { return nil; }
    if (!attrString) return nil;

    for (NSUInteger i = 0; i < [raw length]; i++) {
        if ([raw characterAtIndex:i] != ATTACHMENT_MARKER) continue;
        NSString *attID = nil;
        @try {
            NSRange effRange;
            NSDictionary *attrs = [(NSAttributedString *)attrString
                attributesAtIndex:i effectiveRange:&effRange];
            id ttAtt = attrs[@"NSAttachment"];
            if (ttAtt) {
                attID = ((id (*)(id, SEL))objc_msgSend)(
                    ttAtt, NSSelectorFromString(@"attachmentIdentifier"));
            }
        }
        @catch (NSException *e) {}
        // Store identifier (or NSNull if we couldn't resolve it)
        [ordered addObject:attID ?: (id)[NSNull null]];
    }
    return ordered;
}

/**
 * Get attachment display name by identifier from the Core Data entities.
 */
NSString *attachmentNameByID(NSArray *atts, NSString *attID) {
    if (!attID || !atts) return @"attachment";
    for (id att in atts) {
        NSString *ident = ((id (*)(id, SEL))objc_msgSend)(
            att, NSSelectorFromString(@"identifier"));
        if (![ident isEqualToString:attID]) continue;
        id ut = [att valueForKey:@"userTitle"];
        if (ut && [ut isKindOfClass:[NSString class]] && [(NSString *)ut length] > 0)
            return (NSString *)ut;
        id t = [att valueForKey:@"title"];
        if (t && [t isKindOfClass:[NSString class]] && [(NSString *)t length] > 0)
            return (NSString *)t;
        id uti = [att valueForKey:@"typeUTI"];
        if (uti && [uti isKindOfClass:[NSString class]])
            return [NSString stringWithFormat:@"[%@]", uti];
        return @"attachment";
    }
    return @"attachment";
}

void cmdNotesDetach(NSUInteger idx, NSUInteger attIdx) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    // Get raw text and find the Nth U+FFFC marker position
    NSString *raw = noteRawText(note);
    NSMutableArray *markerPositions = [NSMutableArray array];
    for (NSUInteger i = 0; i < [raw length]; i++) {
        if ([raw characterAtIndex:i] == ATTACHMENT_MARKER) {
            [markerPositions addObject:@(i)];
        }
    }

    if (markerPositions.count == 0) {
        fprintf(stderr, "Error: Note has no inline attachments\n");
        return;
    }

    // attIdx is 0-based attachment index (in text order)
    if (attIdx >= markerPositions.count) {
        fprintf(stderr, "Error: Attachment index %lu out of range (note has %lu inline attachment(s))\n",
                (unsigned long)(attIdx + 1), (unsigned long)markerPositions.count);
        return;
    }

    NSUInteger charPos = [markerPositions[attIdx] unsignedIntegerValue];

    // Get ordered attachment identifiers from CRDT attributed string
    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSString *targetAttID = nil;
    if (orderedIDs && attIdx < orderedIDs.count) {
        id val = orderedIDs[attIdx];
        if (val != [NSNull null]) targetAttID = val;
    }

    // Get Core Data entities
    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));

    // Get display name before deletion
    NSString *removedName = targetAttID
        ? attachmentNameByID(atts, targetAttID) : @"attachment";

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return;
    }

    // 1. Remove the U+FFFC character from the CRDT string
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, NSRange))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"deleteCharactersInRange:"),
        NSMakeRange(charPos, 1));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    // 2. Delete the Core Data attachment entity by identifier
    BOOL deletedEntity = NO;
    if (targetAttID) {
        for (id att in atts) {
            NSString *attID = ((id (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"identifier"));
            if ([attID isEqualToString:targetAttID]) {
                [g_moc deleteObject:att];
                deletedEntity = YES;
                break;
            }
        }
    }

    if (!deletedEntity) {
        fprintf(stderr, "Warning: Could not identify attachment entity to delete "
                "(CRDT marker removed but entity may be orphaned)\n");
    }

    // 3. Save
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
    NSError *saveErr = nil;
    [g_moc save:&saveErr];
    if (saveErr) {
        fprintf(stderr, "Error saving: %s\n", [[saveErr localizedDescription] UTF8String]);
        return;
    }

    NSString *t = noteTitle(note);
    printf("✓ Removed attachment %lu (%s) from \"%s\"\n",
           (unsigned long)(attIdx + 1), [removedName UTF8String], [t UTF8String]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminders Core Data context
// ─────────────────────────────────────────────────────────────────────────────

static NSManagedObjectContext *g_remMOC = nil;
static NSPersistentStoreCoordinator *g_remPSC = nil;

BOOL initRemindersContext(void) {
    if (g_remMOC) return YES;

    // Load ReminderKit framework for its managed object model
    void *rkHandle = dlopen(
        "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit",
        RTLD_NOW);
    if (!rkHandle) {
        fprintf(stderr, "Warning: Could not load ReminderKit.framework: %s\n",
                dlerror());
    }

    // Load the managed object model
    NSString *momdPath =
        @"/System/Library/PrivateFrameworks/ReminderKit.framework"
        @"/Versions/A/Resources/ReminderData.momd";
    NSURL *momdURL = [NSURL fileURLWithPath:momdPath];
    NSManagedObjectModel *model =
        [[NSManagedObjectModel alloc] initWithContentsOfURL:momdURL];
    if (!model) {
        fprintf(stderr, "Error: Could not load Reminders model from %s\n",
                [momdPath UTF8String]);
        return NO;
    }

    g_remPSC = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:model];

    // Scan for .sqlite files in the Reminders container
    NSString *storesDir = [NSHomeDirectory() stringByAppendingPathComponent:
        @"Library/Group Containers/group.com.apple.reminders/Container_v1/Stores"];
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contents = [fm contentsOfDirectoryAtPath:storesDir error:nil];

    NSDictionary *storeOpts = @{
        NSMigratePersistentStoresAutomaticallyOption: @YES,
        NSInferMappingModelAutomaticallyOption: @YES,
        NSSQLitePragmasOption: @{@"journal_mode": @"WAL"}
    };

    NSURL *bestStore = nil;
    NSUInteger bestCount = 0;

    for (NSString *file in contents) {
        if (![file hasSuffix:@".sqlite"]) continue;
        NSString *fullPath = [storesDir stringByAppendingPathComponent:file];
        NSURL *storeURL = [NSURL fileURLWithPath:fullPath];

        // Try adding this store
        NSError *err = nil;
        NSPersistentStore *store =
            [g_remPSC addPersistentStoreWithType:NSSQLiteStoreType
                                   configuration:nil
                                             URL:storeURL
                                         options:storeOpts
                                           error:&err];
        if (!store) continue;

        // Check how many reminders it has
        NSManagedObjectContext *tmpMOC = [[NSManagedObjectContext alloc]
            initWithConcurrencyType:NSMainQueueConcurrencyType];
        [tmpMOC setPersistentStoreCoordinator:g_remPSC];

        NSFetchRequest *countReq =
            [NSFetchRequest fetchRequestWithEntityName:@"REMCDReminder"];
        NSUInteger count = [tmpMOC countForFetchRequest:countReq error:nil];

        if (count > bestCount) {
            bestCount = count;
            bestStore = storeURL;
        }

        // Remove this store so we can try others
        [g_remPSC removePersistentStore:store error:nil];
    }

    if (!bestStore) {
        // Check if the directory itself is inaccessible (Full Disk Access)
        BOOL dirExists = [fm fileExistsAtPath:storesDir isDirectory:NULL];
        if (!dirExists || !contents || [contents count] == 0) {
            fprintf(stderr,
                "\n"
                "Error: Cannot access the Reminders database.\n"
                "\n"
                "This is usually a macOS permissions issue. To fix it:\n"
                "\n"
                "  1. Open System Settings → Privacy & Security → Full Disk Access\n"
                "  2. Click + and add your terminal app\n"
                "     (Terminal.app, iTerm, Warp, etc.)\n"
                "  3. Restart your terminal\n"
                "\n");
        } else {
            fprintf(stderr, "Error: No Reminders database found in %s\n",
                    [storesDir UTF8String]);
        }
        return NO;
    }

    // Re-add the best store permanently
    NSError *err = nil;
    if (![g_remPSC addPersistentStoreWithType:NSSQLiteStoreType
                                configuration:nil
                                          URL:bestStore
                                      options:storeOpts
                                        error:&err]) {
        NSString *errDesc = [err localizedDescription] ?: @"unknown error";
        if ([errDesc containsString:@"256"] ||
            [errDesc containsString:@"couldn't be opened"] ||
            [errDesc containsString:@"failure to access"]) {
            fprintf(stderr,
                "\n"
                "Error: Cannot access the Reminders database.\n"
                "\n"
                "This is usually a macOS permissions issue. To fix it:\n"
                "\n"
                "  1. Open System Settings → Privacy & Security → Full Disk Access\n"
                "  2. Click + and add your terminal app\n"
                "     (Terminal.app, iTerm, Warp, etc.)\n"
                "  3. Restart your terminal\n"
                "\n");
        } else {
            fprintf(stderr, "Error opening Reminders store: %s\n",
                    [errDesc UTF8String]);
        }
        return NO;
    }

    g_remMOC = [[NSManagedObjectContext alloc]
        initWithConcurrencyType:NSMainQueueConcurrencyType];
    [g_remMOC setPersistentStoreCoordinator:g_remPSC];

    return YES;
}

// ─────────────────────────────────────────────────────────────────────────────
// Reminders helpers
// ─────────────────────────────────────────────────────────────────────────────

static NSArray *fetchIncompleteReminders(void) {
    NSFetchRequest *req =
        [NSFetchRequest fetchRequestWithEntityName:@"REMCDReminder"];
    req.predicate = [NSPredicate predicateWithFormat:
        @"completed == NO AND markedForDeletion == NO"];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:YES]
    ];
    NSError *err = nil;
    NSArray *results = [g_remMOC executeFetchRequest:req error:&err];
    if (err) {
        fprintf(stderr, "Error fetching reminders: %s\n",
                [[err localizedDescription] UTF8String]);
        return @[];
    }
    return results ?: @[];
}

static NSString *listNameForReminder(NSManagedObject *rem) {
    NSManagedObject *list = [rem valueForKey:@"list"];
    if (list) {
        NSString *name = [list valueForKey:@"name"];
        if (name) return name;
    }
    return @"(no list)";
}

static NSString *formatDueDate(NSDate *date) {
    if (!date) return nil;
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    [fmt setDateFormat:@"yyyy-MM-dd HH:mm"];
    return [fmt stringFromDate:date];
}

static NSDate *parseDueDate(NSString *str) {
    if (!str) return nil;
    NSArray *formats = @[
        @"yyyy-MM-dd HH:mm",
        @"yyyy-MM-dd'T'HH:mm:ss",
        @"yyyy-MM-dd'T'HH:mm",
        @"yyyy-MM-dd",
        @"MM/dd/yyyy",
        @"MM/dd/yyyy HH:mm",
        @"MMM d, yyyy",
        @"MMMM d, yyyy"
    ];
    for (NSString *f in formats) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        [fmt setDateFormat:f];
        [fmt setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"en_US_POSIX"]];
        NSDate *d = [fmt dateFromString:str];
        if (d) return d;
    }
    // Try NSDataDetector as last resort
    NSDataDetector *det = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate
                                                         error:nil];
    NSTextCheckingResult *match =
        [det firstMatchInString:str options:0 range:NSMakeRange(0, str.length)];
    if (match) return match.date;
    return nil;
}

static NSManagedObject *findDefaultList(void) {
    NSFetchRequest *req =
        [NSFetchRequest fetchRequestWithEntityName:@"REMCDBaseList"];
    req.predicate = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
    req.sortDescriptors = @[
        [NSSortDescriptor sortDescriptorWithKey:@"name" ascending:YES]
    ];
    NSArray *lists = [g_remMOC executeFetchRequest:req error:nil];
    if (!lists || lists.count == 0) return nil;

    // Prefer list named "Reminders"
    for (NSManagedObject *l in lists) {
        if ([[l valueForKey:@"name"] isEqualToString:@"Reminders"]) return l;
    }
    return lists[0];
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: rem (Reminders)
// ─────────────────────────────────────────────────────────────────────────────

void cmdRemList(void) {
    if (!initRemindersContext()) return;

    NSArray *rems = fetchIncompleteReminders();
    if (rems.count == 0) {
        printf("(no incomplete reminders)\n");
        return;
    }

    for (NSUInteger i = 0; i < rems.count; i++) {
        NSManagedObject *r = rems[i];
        NSString *title = [r valueForKey:@"title"] ?: @"(untitled)";
        NSString *listName = listNameForReminder(r);
        NSDate *due = [r valueForKey:@"dueDate"];
        NSString *dueStr = formatDueDate(due);

        if (dueStr) {
            printf("%lu. %s (%s)  [due %s]\n",
                   (unsigned long)(i + 1),
                   [title UTF8String],
                   [listName UTF8String],
                   [dueStr UTF8String]);
        } else {
            printf("%lu. %s (%s)\n",
                   (unsigned long)(i + 1),
                   [title UTF8String],
                   [listName UTF8String]);
        }
    }
}

void cmdRemAdd(NSString *title, NSString *dueDate) {
    if (!initRemindersContext()) return;

    NSManagedObject *defaultList = findDefaultList();
    if (!defaultList) {
        fprintf(stderr, "Error: No reminder lists found\n");
        return;
    }

    NSManagedObject *rem = [NSEntityDescription
        insertNewObjectForEntityForName:@"REMCDReminder"
                 inManagedObjectContext:g_remMOC];

    [rem setValue:title forKey:@"title"];
    [rem setValue:[NSDate date] forKey:@"creationDate"];
    [rem setValue:[NSDate date] forKey:@"lastModifiedDate"];
    [rem setValue:@NO forKey:@"completed"];
    [rem setValue:@NO forKey:@"markedForDeletion"];
    [rem setValue:@NO forKey:@"flagged"];
    [rem setValue:@0 forKey:@"priority"];
    [rem setValue:defaultList forKey:@"list"];

    // Copy account from the list
    NSManagedObject *account = [defaultList valueForKey:@"account"];
    if (account) {
        [rem setValue:account forKey:@"account"];
    }

    // Set due date if provided
    if (dueDate) {
        NSDate *due = parseDueDate(dueDate);
        if (due) {
            [rem setValue:due forKey:@"dueDate"];
            [rem setValue:@YES forKey:@"allDay"];
        } else {
            fprintf(stderr, "Warning: Could not parse date \"%s\", "
                    "adding without due date\n", [dueDate UTF8String]);
        }
    }

    NSError *saveErr = nil;
    [g_remMOC save:&saveErr];
    if (saveErr) {
        fprintf(stderr, "Error saving reminder: %s\n",
                [[saveErr localizedDescription] UTF8String]);
        return;
    }
    printf("Added reminder: \"%s\"\n", [title UTF8String]);
}

void cmdRemEdit(NSUInteger idx, NSString *newTitle) {
    if (!initRemindersContext()) return;

    NSArray *rems = fetchIncompleteReminders();
    if (idx < 1 || idx > rems.count) {
        fprintf(stderr, "Reminder %lu not found (have %lu)\n",
                (unsigned long)idx, (unsigned long)rems.count);
        return;
    }

    NSManagedObject *r = rems[idx - 1];
    [r setValue:newTitle forKey:@"title"];
    [r setValue:[NSDate date] forKey:@"lastModifiedDate"];

    NSError *saveErr = nil;
    [g_remMOC save:&saveErr];
    if (saveErr) {
        fprintf(stderr, "Error saving: %s\n",
                [[saveErr localizedDescription] UTF8String]);
        return;
    }
    printf("Updated: %s\n", [newTitle UTF8String]);
}

void cmdRemDelete(NSUInteger idx) {
    if (!initRemindersContext()) return;

    NSArray *rems = fetchIncompleteReminders();
    if (idx < 1 || idx > rems.count) {
        fprintf(stderr, "Reminder %lu not found (have %lu)\n",
                (unsigned long)idx, (unsigned long)rems.count);
        return;
    }

    NSManagedObject *r = rems[idx - 1];
    NSString *title = [r valueForKey:@"title"] ?: @"(untitled)";
    [r setValue:@YES forKey:@"markedForDeletion"];
    [r setValue:[NSDate date] forKey:@"lastModifiedDate"];

    NSError *saveErr = nil;
    [g_remMOC save:&saveErr];
    if (saveErr) {
        fprintf(stderr, "Error saving: %s\n",
                [[saveErr localizedDescription] UTF8String]);
        return;
    }
    printf("Deleted: %s\n", [title UTF8String]);
}

void cmdRemComplete(NSUInteger idx) {
    if (!initRemindersContext()) return;

    NSArray *rems = fetchIncompleteReminders();
    if (idx < 1 || idx > rems.count) {
        fprintf(stderr, "Reminder %lu not found (have %lu)\n",
                (unsigned long)idx, (unsigned long)rems.count);
        return;
    }

    NSManagedObject *r = rems[idx - 1];
    NSString *title = [r valueForKey:@"title"] ?: @"(untitled)";
    [r setValue:@YES forKey:@"completed"];
    [r setValue:[NSDate date] forKey:@"completionDate"];
    [r setValue:[NSDate date] forKey:@"lastModifiedDate"];

    NSError *saveErr = nil;
    [g_remMOC save:&saveErr];
    if (saveErr) {
        fprintf(stderr, "Error saving: %s\n",
                [[saveErr localizedDescription] UTF8String]);
        return;
    }
    printf("Completed: %s\n", [title UTF8String]);
}

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
"  replace <N> --find <s> --replace <s>  Find & replace text in note N\n"
"  search <query> [--json]             Search notes by text\n"
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
"  cider notes replace <N> --find <s> --replace <s>\n"
"                                           Find & replace text in note N\n"
"  cider notes search <query> [--json]      Search notes\n"
"  cider notes export <path>                Export notes to HTML\n"
"  cider notes attachments <N> [--json]        List attachments with positions\n"
"  cider notes attach <N> <file> [--at <pos>]  Attach file at position (CRDT)\n"
"  cider notes detach <N> [<A>]               Remove attachment A from note N\n"
"\n"
"OPTIONS:\n"
"  --json    Output as JSON (for list, show, search, folders)\n"
"  -f, --folder <name>   Filter by folder (for list) or set folder (for add)\n"
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

// Find a flag value in argv. Returns nil if not found.
// Looks for --flag val or -f val patterns.
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

            // No subcommand: default to list
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
                // Target folder: cider notes move N <folder> or --folder <folder>
                targetFolder = argValue(argc, argv, 3, "--folder", "-f");
                if (!targetFolder && argc >= 5) {
                    // positional: cider notes move N FolderName
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

            // ── cider notes replace ──
            } else if ([sub isEqualToString:@"replace"]) {
                NSUInteger idx = 0;
                if (argc >= 4) {
                    int v = atoi(argv[3]);
                    if (v > 0) idx = (NSUInteger)v;
                }
                if (!idx) idx = promptNoteIndex(@"replace", nil);
                if (!idx) return 1;
                NSString *findStr = argValue(argc, argv, 3, "--find", NULL);
                NSString *replaceStr = argValue(argc, argv, 3, "--replace", NULL);
                if (!findStr || !replaceStr) {
                    fprintf(stderr, "Usage: cider notes replace <N> --find <text> --replace <text>\n");
                    return 1;
                }
                return cmdNotesReplace(idx, findStr, replaceStr);

            // ── cider notes search ──
            } else if ([sub isEqualToString:@"search"]) {
                if (argc < 4) {
                    fprintf(stderr, "Usage: cider notes search <query>\n");
                    return 1;
                }
                NSString *query = [NSString stringWithUTF8String:argv[3]];
                BOOL jsonOut = argHasFlag(argc, argv, 3, "--json", NULL);
                cmdNotesSearch(query, jsonOut);

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

                // Get attachment index (0-based, or 1-based from user)
                NSUInteger attIdx = 0;
                if (argc >= 5) {
                    attIdx = (NSUInteger)(atoi(argv[4]) - 1); // User provides 1-based
                } else {
                    // Show attachments and prompt (in text order via CRDT)
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

                // Check for --at <position>
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
                cmdNotesSearch(query, NO);

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

            // ── Subcommand style ─────────────────────────────────────────────

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
