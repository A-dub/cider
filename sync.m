/**
 * sync.m — Bidirectional Apple Notes <-> Markdown sync
 *
 * Mirrors Apple Notes to local Markdown files (with images) and syncs
 * edits back. Pre-existing Apple Notes are never modified or deleted.
 *
 * Commands:
 *   cider sync backup [--dir <path>]
 *   cider sync run [--dir <path>]
 *   cider sync watch [--dir <path>] [--interval <secs>]
 */

#import "cider.h"
#include <signal.h>
#include <CommonCrypto/CommonDigest.h>

// ─────────────────────────────────────────────────────────────────────────────
// Sync globals
// ─────────────────────────────────────────────────────────────────────────────

static volatile sig_atomic_t g_syncRunning = 1;
static NSString *g_defaultSyncDir = nil;

NSString *syncDefaultDir(void) {
    if (g_defaultSyncDir) return g_defaultSyncDir;
    return [NSHomeDirectory() stringByAppendingPathComponent:@"CiderSync"];
}

static void syncSignalHandler(int sig) {
    (void)sig;
    g_syncRunning = 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers: hashing, filenames, dates
// ─────────────────────────────────────────────────────────────────────────────

static NSString *sha256File(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", hash[i]];
    return hex;
}

static NSString *sha256String(NSString *str) {
    NSData *data = [str dataUsingEncoding:NSUTF8StringEncoding];
    if (!data) return @"";
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, hash);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++)
        [hex appendFormat:@"%02x", hash[i]];
    return hex;
}

static NSString *sanitizeFilename(NSString *name, NSInteger pk) {
    if (!name || name.length == 0) name = @"untitled";
    NSCharacterSet *unsafe = [NSCharacterSet characterSetWithCharactersInString:@"/\\:*?\"<>|"];
    NSArray *parts = [name componentsSeparatedByCharactersInSet:unsafe];
    NSMutableString *safe = [NSMutableString stringWithString:[parts componentsJoinedByString:@"_"]];
    [safe replaceOccurrencesOfString:@" " withString:@"_" options:0 range:NSMakeRange(0, safe.length)];
    if (safe.length > 100) [safe deleteCharactersInRange:NSMakeRange(100, safe.length - 100)];
    while (safe.length > 0) {
        unichar last = [safe characterAtIndex:safe.length - 1];
        if (last == '.' || last == ' ' || last == '_')
            [safe deleteCharactersInRange:NSMakeRange(safe.length - 1, 1)];
        else break;
    }
    if (safe.length == 0) safe = [NSMutableString stringWithFormat:@"note_%ld", (long)pk];
    return safe;
}

static NSString *isoDateString(NSDate *date) {
    if (!date) return @"";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
    fmt.timeZone = [NSTimeZone timeZoneWithAbbreviation:@"UTC"];
    return [fmt stringFromDate:date];
}

// ─────────────────────────────────────────────────────────────────────────────
// Backup
// ─────────────────────────────────────────────────────────────────────────────

int cmdSyncBackup(NSString *syncDir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *notesContainer = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Group Containers/group.com.apple.notes"];
    NSString *dbPath = [notesContainer stringByAppendingPathComponent:@"NoteStore.sqlite"];

    if (![fm fileExistsAtPath:dbPath]) {
        fprintf(stderr, "Error: Notes database not found at %s\n", [dbPath UTF8String]);
        return 1;
    }

    // Create timestamped backup directory
    NSDateFormatter *tsFmt = [[NSDateFormatter alloc] init];
    tsFmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *ts = [tsFmt stringFromDate:[NSDate date]];
    NSString *backupDir = [[syncDir stringByAppendingPathComponent:@".cider-backups"]
                           stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"backup-%@", ts]];

    NSError *err = nil;
    [fm createDirectoryAtPath:backupDir withIntermediateDirectories:YES attributes:nil error:&err];
    if (err) {
        fprintf(stderr, "Error creating backup dir: %s\n", [[err localizedDescription] UTF8String]);
        return 1;
    }

    printf("Backing up Notes database...\n");

    // Copy database files
    NSArray *dbFiles = @[@"NoteStore.sqlite", @"NoteStore.sqlite-wal", @"NoteStore.sqlite-shm"];
    NSMutableArray *manifestFiles = [NSMutableArray array];

    for (NSString *name in dbFiles) {
        NSString *src = [notesContainer stringByAppendingPathComponent:name];
        NSString *dst = [backupDir stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:src]) {
            NSError *cpErr = nil;
            [fm copyItemAtPath:src toPath:dst error:&cpErr];
            if (cpErr) {
                fprintf(stderr, "Warning: Could not copy %s: %s\n",
                        [name UTF8String], [[cpErr localizedDescription] UTF8String]);
            } else {
                NSDictionary *attrs = [fm attributesOfItemAtPath:dst error:nil];
                unsigned long long sz = [attrs fileSize];
                [manifestFiles addObject:@{@"path": name, @"size": @(sz)}];
                printf("  Copied %s (%llu bytes)\n", [name UTF8String], sz);
            }
        }
    }

    // Copy Media directories from all accounts
    NSString *accountsDir = [notesContainer stringByAppendingPathComponent:@"Accounts"];
    NSString *mediaBackupDir = [backupDir stringByAppendingPathComponent:@"Media"];
    if ([fm fileExistsAtPath:accountsDir]) {
        NSArray *accounts = [fm contentsOfDirectoryAtPath:accountsDir error:nil];
        for (NSString *acct in accounts) {
            NSString *mediaDir = [[accountsDir stringByAppendingPathComponent:acct]
                                  stringByAppendingPathComponent:@"Media"];
            if ([fm fileExistsAtPath:mediaDir]) {
                NSString *dstMedia = [mediaBackupDir stringByAppendingPathComponent:acct];
                [fm createDirectoryAtPath:dstMedia withIntermediateDirectories:YES attributes:nil error:nil];
                NSArray *mediaItems = [fm contentsOfDirectoryAtPath:mediaDir error:nil];
                for (NSString *item in mediaItems) {
                    NSString *srcItem = [mediaDir stringByAppendingPathComponent:item];
                    NSString *dstItem = [dstMedia stringByAppendingPathComponent:item];
                    [fm copyItemAtPath:srcItem toPath:dstItem error:nil];
                }
                printf("  Copied Media from account %s\n", [acct UTF8String]);
            }
        }
    }

    // SHA-256 of the database copy
    NSString *dbHash = sha256File([backupDir stringByAppendingPathComponent:@"NoteStore.sqlite"]);

    // Verify integrity via sqlite3 PRAGMA
    NSString *backupDbPath = [backupDir stringByAppendingPathComponent:@"NoteStore.sqlite"];
    NSString *integrityResult = @"skipped";
    NSString *checkCmd = [NSString stringWithFormat:
        @"sqlite3 '%@' 'PRAGMA integrity_check;' 2>&1 | head -1", backupDbPath];
    FILE *pipe = popen([checkCmd UTF8String], "r");
    if (pipe) {
        char buf[256] = {0};
        if (fgets(buf, sizeof(buf), pipe))
            integrityResult = [[NSString stringWithUTF8String:buf]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        pclose(pipe);
    }

    // Write backup-manifest.json
    NSMutableString *manifest = [NSMutableString stringWithString:@"{\n"];
    [manifest appendFormat:@"  \"timestamp\": \"%@\",\n", isoDateString([NSDate date])];
    [manifest appendFormat:@"  \"database_sha256\": \"%@\",\n", dbHash ?: @""];
    [manifest appendFormat:@"  \"integrity_check\": \"%@\",\n",
        jsonEscapeString(integrityResult)];
    [manifest appendString:@"  \"files\": [\n"];
    for (NSUInteger i = 0; i < manifestFiles.count; i++) {
        NSDictionary *f = manifestFiles[i];
        [manifest appendFormat:@"    {\"path\": \"%@\", \"size\": %@}%s\n",
            f[@"path"], f[@"size"], (i + 1 < manifestFiles.count) ? "," : ""];
    }
    [manifest appendString:@"  ]\n}\n"];

    NSString *manifestPath = [backupDir stringByAppendingPathComponent:@"backup-manifest.json"];
    [manifest writeToFile:manifestPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    printf("\nBackup complete: %s\n", [backupDir UTF8String]);
    printf("Integrity check: %s\n", [integrityResult UTF8String]);
    printf("SHA-256: %s\n", [dbHash UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync state persistence (.cider-sync-state.json)
// ─────────────────────────────────────────────────────────────────────────────

static NSMutableDictionary *syncLoadState(NSString *syncDir) {
    NSString *path = [syncDir stringByAppendingPathComponent:@".cider-sync-state.json"];
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return [NSMutableDictionary dictionary];
    NSError *err = nil;
    id obj = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:&err];
    if (err || ![obj isKindOfClass:[NSDictionary class]]) return [NSMutableDictionary dictionary];
    return [obj mutableCopy];
}

static void syncSaveState(NSString *syncDir, NSDictionary *state) {
    NSString *path = [syncDir stringByAppendingPathComponent:@".cider-sync-state.json"];
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:state
        options:NSJSONWritingPrettyPrinted error:&err];
    if (data) [data writeToFile:path atomically:YES];
}

// ─────────────────────────────────────────────────────────────────────────────
// Attachment extraction (Notes media -> sync dir)
// ─────────────────────────────────────────────────────────────────────────────

static NSString *findAttachmentFile(id attachment) {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Try runtime introspection for fileURL-type methods
    SEL fileURLSel = NSSelectorFromString(@"fileURL");
    if ([attachment respondsToSelector:fileURLSel]) {
        NSURL *url = ((id (*)(id, SEL))objc_msgSend)(attachment, fileURLSel);
        if (url && [fm fileExistsAtPath:[url path]]) return [url path];
    }

    SEL previewURLSel = NSSelectorFromString(@"previewImageURL");
    if ([attachment respondsToSelector:previewURLSel]) {
        NSURL *url = ((id (*)(id, SEL))objc_msgSend)(attachment, previewURLSel);
        if (url && [fm fileExistsAtPath:[url path]]) return [url path];
    }

    // Search Media directories by attachment UUID
    NSString *attID = ((id (*)(id, SEL))objc_msgSend)(
        attachment, NSSelectorFromString(@"identifier"));
    if (!attID) return nil;

    NSString *notesContainer = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Group Containers/group.com.apple.notes"];
    NSString *accountsDir = [notesContainer stringByAppendingPathComponent:@"Accounts"];

    NSArray *accounts = [fm contentsOfDirectoryAtPath:accountsDir error:nil];
    for (NSString *acct in accounts) {
        NSString *mediaDir = [[accountsDir stringByAppendingPathComponent:acct]
                              stringByAppendingPathComponent:@"Media"];
        NSString *attDir = [mediaDir stringByAppendingPathComponent:attID];
        if ([fm fileExistsAtPath:attDir]) {
            NSArray *files = [fm contentsOfDirectoryAtPath:attDir error:nil];
            for (NSString *f in files) {
                if ([f hasPrefix:@"."]) continue;
                return [attDir stringByAppendingPathComponent:f];
            }
        }
    }
    return nil;
}

static void extractAttachments(id note, NSString *syncDir, NSInteger pk) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *attDir = [syncDir stringByAppendingPathComponent:
        [NSString stringWithFormat:@"attachments/%ld", (long)pk]];

    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
    if (!orderedIDs || orderedIDs.count == 0) return;

    [fm createDirectoryAtPath:attDir withIntermediateDirectories:YES attributes:nil error:nil];

    for (NSUInteger i = 0; i < orderedIDs.count; i++) {
        id val = orderedIDs[i];
        if (val == [NSNull null]) continue;
        NSString *attID = val;

        // Find the Core Data attachment entity
        id targetAtt = nil;
        for (id att in atts) {
            NSString *ident = ((id (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"identifier"));
            if ([ident isEqualToString:attID]) { targetAtt = att; break; }
        }
        if (!targetAtt) continue;

        NSString *srcPath = findAttachmentFile(targetAtt);
        if (!srcPath) continue;

        NSString *name = attachmentNameByID(atts, attID);
        if ([[name pathExtension] length] == 0) {
            NSString *srcExt = [srcPath pathExtension];
            if (srcExt.length > 0) name = [name stringByAppendingPathExtension:srcExt];
        }

        NSString *dstPath = [attDir stringByAppendingPathComponent:name];
        if (![fm fileExistsAtPath:dstPath]) {
            [fm copyItemAtPath:srcPath toPath:dstPath error:nil];
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Notes -> Markdown export
// ─────────────────────────────────────────────────────────────────────────────

static NSString *noteToMarkdown(id note, NSString *syncDir) {
    NSString *uri = noteURIString(note);
    NSString *title = noteTitle(note);
    NSString *folder = folderName(note);
    NSDate *modDate = [note valueForKey:@"modificationDate"];
    NSInteger pk = noteIntPK(note);

    NSMutableString *md = [NSMutableString string];
    [md appendString:@"---\n"];
    [md appendFormat:@"note_id: \"%@\"\n", jsonEscapeString(uri)];
    [md appendFormat:@"title: \"%@\"\n", jsonEscapeString(title)];
    [md appendFormat:@"folder: \"%@\"\n", jsonEscapeString(folder)];
    [md appendFormat:@"modified: \"%@\"\n", isoDateString(modDate)];
    [md appendString:@"editable: false\n"];
    [md appendString:@"---\n\n"];

    // Build body with attachment references
    NSString *raw = noteRawText(note);
    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
    NSUInteger attIdx = 0;

    for (NSUInteger i = 0; i < [raw length]; i++) {
        unichar c = [raw characterAtIndex:i];
        if (c == ATTACHMENT_MARKER && orderedIDs && attIdx < orderedIDs.count) {
            id val = orderedIDs[attIdx];
            NSString *attID = (val != [NSNull null]) ? val : nil;
            NSString *name = attID ? attachmentNameByID(atts, attID) : @"attachment";

            // Determine if this is an image attachment
            BOOL isImage = NO;
            if (attID) {
                for (id att in atts) {
                    NSString *ident = ((id (*)(id, SEL))objc_msgSend)(
                        att, NSSelectorFromString(@"identifier"));
                    if ([ident isEqualToString:attID]) {
                        NSString *uti = [att valueForKey:@"typeUTI"];
                        if (uti && ([uti hasPrefix:@"public.image"] ||
                                    [uti hasPrefix:@"public.jpeg"] ||
                                    [uti hasPrefix:@"public.png"] ||
                                    [uti hasPrefix:@"public.heic"])) {
                            isImage = YES;
                        }
                        break;
                    }
                }
            }

            NSString *relPath = [NSString stringWithFormat:@"../attachments/%ld/%@", (long)pk, name];
            if (isImage) {
                [md appendFormat:@"![%@](%@)", name, relPath];
            } else {
                [md appendFormat:@"[%@](%@)", name, relPath];
            }
            attIdx++;
        } else if (c == ATTACHMENT_MARKER) {
            [md appendString:@"[attachment]"];
            attIdx++;
        } else {
            [md appendFormat:@"%C", c];
        }
    }

    return md;
}

static int syncExportNotes(NSString *syncDir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *notes = fetchAllNotes();
    if (!notes || notes.count == 0) {
        printf("No notes to export.\n");
        return 0;
    }

    NSMutableDictionary *state = syncLoadState(syncDir);
    NSMutableDictionary *noteStates = [state[@"notes"] mutableCopy] ?: [NSMutableDictionary dictionary];
    NSMutableDictionary *filenameMap = [NSMutableDictionary dictionary];

    NSUInteger exported = 0;
    for (id note in notes) {
        // Skip trashed notes
        id folder = [note valueForKey:@"folder"];
        if (folder) {
            BOOL isTrash = ((BOOL (*)(id, SEL))objc_msgSend)(
                folder, NSSelectorFromString(@"isTrashFolder"));
            if (isTrash) continue;
        }

        NSString *uri = noteURIString(note);
        NSString *title = noteTitle(note);
        NSString *folderStr = folderName(note);
        NSInteger pk = noteIntPK(note);
        NSDate *modDate = [note valueForKey:@"modificationDate"];

        // Create folder directory
        NSString *folderDir = [syncDir stringByAppendingPathComponent:
            sanitizeFilename(folderStr, 0)];
        [fm createDirectoryAtPath:folderDir withIntermediateDirectories:YES attributes:nil error:nil];

        // Generate filename, handling collisions with PK suffix
        NSString *baseName = sanitizeFilename(title, pk);
        NSString *filename = [baseName stringByAppendingPathExtension:@"md"];
        NSString *key = [NSString stringWithFormat:@"%@/%@", sanitizeFilename(folderStr, 0), filename];
        if (filenameMap[key]) {
            filename = [NSString stringWithFormat:@"%@_%ld.md", baseName, (long)pk];
        }
        key = [NSString stringWithFormat:@"%@/%@", sanitizeFilename(folderStr, 0), filename];
        filenameMap[key] = @YES;

        NSString *mdPath = [folderDir stringByAppendingPathComponent:filename];

        // Skip if content unchanged since last export
        NSString *rawText = noteRawText(note);
        NSString *contentHash = sha256String(rawText);
        NSDictionary *prevState = noteStates[uri];

        if (prevState && [prevState[@"content_hash"] isEqualToString:contentHash] &&
            [fm fileExistsAtPath:mdPath]) {
            noteStates[uri] = @{
                @"content_hash": contentHash,
                @"md_path": mdPath,
                @"modified": isoDateString(modDate),
                @"editable": @(prevState[@"editable"] ? [prevState[@"editable"] boolValue] : NO),
                @"pk": @(pk),
                @"last_synced_text": rawText ?: @""
            };
            continue;
        }

        // Write markdown file
        NSString *md = noteToMarkdown(note, syncDir);
        NSError *writeErr = nil;
        [md writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:&writeErr];
        if (writeErr) {
            fprintf(stderr, "Warning: Could not write %s: %s\n",
                    [mdPath UTF8String], [[writeErr localizedDescription] UTF8String]);
            continue;
        }

        // Extract attachment files
        extractAttachments(note, syncDir, pk);

        // Update sync state
        BOOL editable = prevState ? [prevState[@"editable"] boolValue] : NO;
        noteStates[uri] = @{
            @"content_hash": contentHash,
            @"md_path": mdPath,
            @"modified": isoDateString(modDate),
            @"editable": @(editable),
            @"pk": @(pk),
            @"last_synced_text": rawText ?: @""
        };

        exported++;
        printf("  %s -> %s\n", [title UTF8String], [[mdPath lastPathComponent] UTF8String]);
    }

    state[@"notes"] = noteStates;
    syncSaveState(syncDir, state);

    if (exported > 0) printf("Exported %lu note(s).\n", (unsigned long)exported);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Markdown -> Notes import
// ─────────────────────────────────────────────────────────────────────────────

// Parse YAML frontmatter from markdown file content
static NSDictionary *parseFrontmatter(NSString *content) {
    if (![content hasPrefix:@"---\n"]) return nil;
    NSRange endRange = [content rangeOfString:@"\n---\n" options:0
        range:NSMakeRange(4, MIN(content.length - 4, 2000))];
    if (endRange.location == NSNotFound) return nil;

    NSString *yaml = [content substringWithRange:NSMakeRange(4, endRange.location - 4)];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (NSString *line in [yaml componentsSeparatedByString:@"\n"]) {
        NSRange colon = [line rangeOfString:@": "];
        if (colon.location == NSNotFound) continue;
        NSString *key = [line substringToIndex:colon.location];
        NSString *val = [line substringFromIndex:colon.location + 2];
        if ([val hasPrefix:@"\""] && [val hasSuffix:@"\""]) {
            val = [val substringWithRange:NSMakeRange(1, val.length - 2)];
            val = [val stringByReplacingOccurrencesOfString:@"\\\"" withString:@"\""];
            val = [val stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
        }
        result[key] = val;
    }
    return result;
}

// Extract body text after frontmatter
static NSString *mdBodyContent(NSString *content) {
    if (![content hasPrefix:@"---\n"]) return content;
    NSRange endRange = [content rangeOfString:@"\n---\n" options:0
        range:NSMakeRange(4, MIN(content.length - 4, 2000))];
    if (endRange.location == NSNotFound) return content;
    NSUInteger bodyStart = endRange.location + endRange.length;
    while (bodyStart < content.length && [content characterAtIndex:bodyStart] == '\n') bodyStart++;
    return [content substringFromIndex:bodyStart];
}

// Convert markdown body back to raw text (attachment refs -> U+FFFC)
static NSString *mdBodyToRawText(NSString *body) {
    NSMutableString *result = [NSMutableString stringWithString:body];
    // Replace ![name](../attachments/...) with U+FFFC
    NSRegularExpression *imgRe = [NSRegularExpression
        regularExpressionWithPattern:@"!\\[[^\\]]*\\]\\(\\.\\./attachments/[^)]+\\)"
        options:0 error:nil];
    NSArray *imgMatches = [imgRe matchesInString:result options:0 range:NSMakeRange(0, result.length)];
    for (NSInteger i = (NSInteger)imgMatches.count - 1; i >= 0; i--) {
        NSTextCheckingResult *m = imgMatches[(NSUInteger)i];
        [result replaceCharactersInRange:m.range withString:@"\uFFFC"];
    }
    // Replace [name](../attachments/...) with U+FFFC
    NSRegularExpression *linkRe = [NSRegularExpression
        regularExpressionWithPattern:@"\\[[^\\]]*\\]\\(\\.\\./attachments/[^)]+\\)"
        options:0 error:nil];
    NSArray *linkMatches = [linkRe matchesInString:result options:0 range:NSMakeRange(0, result.length)];
    for (NSInteger i = (NSInteger)linkMatches.count - 1; i >= 0; i--) {
        NSTextCheckingResult *m = linkMatches[(NSUInteger)i];
        [result replaceCharactersInRange:m.range withString:@"\uFFFC"];
    }
    return result;
}

// 3-way merge: returns merged text, or nil if conflicts overlap
static NSString *threeWayMerge(NSString *base, NSString *local, NSString *remote) {
    NSArray *baseLines = [base componentsSeparatedByString:@"\n"];
    NSArray *localLines = [local componentsSeparatedByString:@"\n"];
    NSArray *remoteLines = [remote componentsSeparatedByString:@"\n"];

    NSMutableArray *merged = [NSMutableArray array];
    NSUInteger maxLen = MAX(MAX(baseLines.count, localLines.count), remoteLines.count);
    BOOL conflict = NO;

    for (NSUInteger i = 0; i < maxLen; i++) {
        NSString *bLine = (i < baseLines.count) ? baseLines[i] : @"";
        NSString *lLine = (i < localLines.count) ? localLines[i] : @"";
        NSString *rLine = (i < remoteLines.count) ? remoteLines[i] : @"";

        if ([lLine isEqualToString:rLine]) {
            [merged addObject:lLine];
        } else if ([lLine isEqualToString:bLine]) {
            [merged addObject:rLine]; // only remote changed
        } else if ([rLine isEqualToString:bLine]) {
            [merged addObject:lLine]; // only local changed
        } else {
            conflict = YES; // both changed differently
            break;
        }
    }

    if (conflict) return nil;
    return [merged componentsJoinedByString:@"\n"];
}

// Find a note by its Core Data URI string
static id noteByURI(NSString *uri) {
    NSArray *notes = fetchAllNotes();
    for (id note in notes) {
        if ([noteURIString(note) isEqualToString:uri]) return note;
    }
    return nil;
}

static int syncImportMarkdown(NSString *syncDir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableDictionary *state = syncLoadState(syncDir);
    NSMutableDictionary *noteStates = [state[@"notes"] mutableCopy] ?: [NSMutableDictionary dictionary];

    // Scan for .md files in sync directory (one level of subdirectories)
    NSArray *topItems = [fm contentsOfDirectoryAtPath:syncDir error:nil];
    NSMutableArray *mdFiles = [NSMutableArray array];

    for (NSString *item in topItems) {
        if ([item hasPrefix:@"."]) continue;
        if ([item isEqualToString:@"attachments"]) continue;
        NSString *itemPath = [syncDir stringByAppendingPathComponent:item];
        BOOL isDir = NO;
        [fm fileExistsAtPath:itemPath isDirectory:&isDir];
        if (!isDir) {
            if ([item hasSuffix:@".md"] && ![item containsString:@".conflict-"])
                [mdFiles addObject:itemPath];
            continue;
        }
        NSArray *subItems = [fm contentsOfDirectoryAtPath:itemPath error:nil];
        for (NSString *sub in subItems) {
            if ([sub hasSuffix:@".md"] && ![sub containsString:@".conflict-"])
                [mdFiles addObject:[itemPath stringByAppendingPathComponent:sub]];
        }
    }

    NSUInteger imported = 0, updated = 0;

    for (NSString *mdPath in mdFiles) {
        NSError *readErr = nil;
        NSString *content = [NSString stringWithContentsOfFile:mdPath
            encoding:NSUTF8StringEncoding error:&readErr];
        if (!content) continue;

        NSDictionary *fmData = parseFrontmatter(content);
        NSString *body = mdBodyContent(content);
        NSString *rawText = mdBodyToRawText(body);

        if (!fmData) {
            // ── New file (no frontmatter) ── create Apple Note ──
            if ([rawText stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceAndNewlineCharacterSet]].length == 0) continue;

            NSString *parentDir = [[mdPath stringByDeletingLastPathComponent] lastPathComponent];
            NSString *targetFolder = [parentDir isEqualToString:
                [syncDir lastPathComponent]] ? @"Notes" : parentDir;

            id noteFolder = findOrCreateFolder(targetFolder, YES);
            if (!noteFolder) noteFolder = defaultFolder();
            id account = [noteFolder valueForKey:@"account"];

            id newNote = [NSEntityDescription
                insertNewObjectForEntityForName:@"ICNote"
                         inManagedObjectContext:g_moc];
            ((void (*)(id, SEL, id))objc_msgSend)(
                newNote, NSSelectorFromString(@"setFolder:"), noteFolder);
            if (account) {
                ((void (*)(id, SEL, id))objc_msgSend)(
                    newNote, NSSelectorFromString(@"setAccount:"), account);
            }
            [newNote setValue:[NSDate date] forKey:@"creationDate"];
            [newNote setValue:[NSDate date] forKey:@"modificationDate"];

            id noteDataEntity = [NSEntityDescription
                insertNewObjectForEntityForName:@"ICNoteData"
                         inManagedObjectContext:g_moc];
            [newNote setValue:noteDataEntity forKey:@"noteData"];

            id mergeStr = noteMergeableString(newNote);
            if (mergeStr) {
                ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
                ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
                    mergeStr, NSSelectorFromString(@"insertString:atIndex:"),
                    rawText, (NSUInteger)0);
                ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
                ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));
            }

            ((void (*)(id, SEL))objc_msgSend)(newNote, NSSelectorFromString(@"saveNoteData"));
            ((void (*)(id, SEL))objc_msgSend)(newNote, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

            if (saveContext()) {
                NSString *uri = noteURIString(newNote);
                NSString *title = noteTitle(newNote);
                NSInteger newPk = noteIntPK(newNote);

                // Rewrite file with frontmatter (editable: true)
                NSMutableString *newMd = [NSMutableString string];
                [newMd appendString:@"---\n"];
                [newMd appendFormat:@"note_id: \"%@\"\n", jsonEscapeString(uri)];
                [newMd appendFormat:@"title: \"%@\"\n", jsonEscapeString(title)];
                [newMd appendFormat:@"folder: \"%@\"\n", jsonEscapeString(targetFolder)];
                [newMd appendFormat:@"modified: \"%@\"\n", isoDateString([NSDate date])];
                [newMd appendString:@"editable: true\n"];
                [newMd appendString:@"---\n\n"];
                [newMd appendString:body];
                [newMd writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

                noteStates[uri] = @{
                    @"content_hash": sha256String(rawText),
                    @"md_path": mdPath,
                    @"modified": isoDateString([NSDate date]),
                    @"editable": @YES,
                    @"pk": @(newPk),
                    @"last_synced_text": rawText
                };
                printf("  + Created note: \"%s\"\n", [title UTF8String]);
                imported++;
            }
            continue;
        }

        // ── Has frontmatter ──
        NSString *noteId = fmData[@"note_id"];
        BOOL editable = [fmData[@"editable"] isEqualToString:@"true"];
        if (!noteId || noteId.length == 0) continue;

        NSDictionary *prevState = noteStates[noteId];

        if (!editable) {
            // Read-only: re-export if Apple Note changed
            if (prevState) {
                NSString *prevHash = prevState[@"content_hash"];
                id noteObj = noteByURI(noteId);
                if (noteObj) {
                    NSString *currentNoteText = noteRawText(noteObj);
                    NSString *currentHash = sha256String(currentNoteText);
                    if (![currentHash isEqualToString:prevHash]) {
                        NSString *md = noteToMarkdown(noteObj, syncDir);
                        [md writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                        NSInteger pk = noteIntPK(noteObj);
                        extractAttachments(noteObj, syncDir, pk);
                        NSDate *modDate = [noteObj valueForKey:@"modificationDate"];
                        noteStates[noteId] = @{
                            @"content_hash": currentHash,
                            @"md_path": mdPath,
                            @"modified": isoDateString(modDate),
                            @"editable": @NO,
                            @"pk": @(pk),
                            @"last_synced_text": currentNoteText ?: @""
                        };
                        updated++;
                        printf("  ~ Updated (from Notes): %s\n",
                               [[mdPath lastPathComponent] UTF8String]);
                    }
                }
            }
            continue;
        }

        // ── Editable note — bidirectional sync ──
        id noteObj = noteByURI(noteId);
        if (!noteObj) {
            fprintf(stderr, "  Warning: Note %s not found (may have been deleted)\n",
                    [noteId UTF8String]);
            continue;
        }

        NSString *currentNoteText = noteRawText(noteObj);
        NSString *noteHash = sha256String(currentNoteText);
        NSString *localHash = sha256String(rawText);
        NSString *prevHash = prevState[@"content_hash"];
        NSString *lastSyncedText = prevState[@"last_synced_text"];

        BOOL noteChanged = prevHash ? ![noteHash isEqualToString:prevHash] : NO;
        BOOL localChanged = prevHash ? ![localHash isEqualToString:prevHash] : NO;

        if (!noteChanged && !localChanged) continue;

        if (localChanged && !noteChanged) {
            // Local MD changed — push to Apple Note via CRDT
            if (!applyCRDTEdit(noteObj, currentNoteText, rawText)) {
                fprintf(stderr, "  Warning: Failed to apply edit to note\n");
                continue;
            }
            [noteObj setValue:[NSDate date] forKey:@"modificationDate"];
            if (saveContext()) {
                noteStates[noteId] = @{
                    @"content_hash": sha256String(rawText),
                    @"md_path": mdPath,
                    @"modified": isoDateString([NSDate date]),
                    @"editable": @YES,
                    @"pk": prevState[@"pk"] ?: @0,
                    @"last_synced_text": rawText
                };
                updated++;
                printf("  -> Synced to Notes: %s\n", [[mdPath lastPathComponent] UTF8String]);
            }
        } else if (noteChanged && !localChanged) {
            // Apple Note changed — update MD file
            NSString *md = noteToMarkdown(noteObj, syncDir);
            md = [md stringByReplacingOccurrencesOfString:@"editable: false"
                                               withString:@"editable: true"];
            [md writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
            NSInteger pk = noteIntPK(noteObj);
            extractAttachments(noteObj, syncDir, pk);
            NSDate *modDate = [noteObj valueForKey:@"modificationDate"];
            noteStates[noteId] = @{
                @"content_hash": noteHash,
                @"md_path": mdPath,
                @"modified": isoDateString(modDate),
                @"editable": @YES,
                @"pk": @(pk),
                @"last_synced_text": currentNoteText ?: @""
            };
            updated++;
            printf("  <- Updated from Notes: %s\n", [[mdPath lastPathComponent] UTF8String]);
        } else {
            // Both changed — attempt 3-way merge
            NSString *mergedText = nil;
            if (lastSyncedText) {
                mergedText = threeWayMerge(lastSyncedText, rawText, currentNoteText);
            }

            if (mergedText) {
                // Clean merge succeeded
                if (applyCRDTEdit(noteObj, currentNoteText, mergedText)) {
                    [noteObj setValue:[NSDate date] forKey:@"modificationDate"];
                    saveContext();
                }
                NSString *md = noteToMarkdown(noteObj, syncDir);
                md = [md stringByReplacingOccurrencesOfString:@"editable: false"
                                                   withString:@"editable: true"];
                [md writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                noteStates[noteId] = @{
                    @"content_hash": sha256String(mergedText),
                    @"md_path": mdPath,
                    @"modified": isoDateString([NSDate date]),
                    @"editable": @YES,
                    @"pk": prevState[@"pk"] ?: @0,
                    @"last_synced_text": mergedText
                };
                updated++;
                printf("  * Auto-merged: %s\n", [[mdPath lastPathComponent] UTF8String]);
            } else {
                // Conflict — save local as .conflict file, write remote to original
                NSDateFormatter *tsFmt = [[NSDateFormatter alloc] init];
                tsFmt.dateFormat = @"yyyyMMdd-HHmmss";
                NSString *conflictTs = [tsFmt stringFromDate:[NSDate date]];
                NSString *conflictPath = [NSString stringWithFormat:@"%@.conflict-%@.md",
                    [mdPath stringByDeletingPathExtension], conflictTs];
                [content writeToFile:conflictPath atomically:YES
                    encoding:NSUTF8StringEncoding error:nil];

                NSString *md = noteToMarkdown(noteObj, syncDir);
                md = [md stringByReplacingOccurrencesOfString:@"editable: false"
                                                   withString:@"editable: true"];
                [md writeToFile:mdPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
                noteStates[noteId] = @{
                    @"content_hash": noteHash,
                    @"md_path": mdPath,
                    @"modified": isoDateString([NSDate date]),
                    @"editable": @YES,
                    @"pk": prevState[@"pk"] ?: @0,
                    @"last_synced_text": currentNoteText ?: @""
                };
                fprintf(stderr, "  ! Conflict: %s (local saved as %s)\n",
                        [[mdPath lastPathComponent] UTF8String],
                        [[conflictPath lastPathComponent] UTF8String]);
            }
        }
    }

    // Check for deleted Apple Notes — archive their MD files
    for (NSString *uri in [noteStates allKeys]) {
        NSDictionary *ns = noteStates[uri];
        NSString *mdPath = ns[@"md_path"];
        if (!mdPath || ![fm fileExistsAtPath:mdPath]) continue;

        id noteObj = noteByURI(uri);
        if (!noteObj) {
            NSString *archiveDir = [syncDir stringByAppendingPathComponent:@".cider-archive"];
            [fm createDirectoryAtPath:archiveDir withIntermediateDirectories:YES attributes:nil error:nil];
            NSString *archivePath = [archiveDir stringByAppendingPathComponent:[mdPath lastPathComponent]];
            [fm moveItemAtPath:mdPath toPath:archivePath error:nil];
            [noteStates removeObjectForKey:uri];
            printf("  Archived (note deleted): %s\n", [[mdPath lastPathComponent] UTF8String]);
        }
    }

    state[@"notes"] = noteStates;
    syncSaveState(syncDir, state);

    if (imported > 0) printf("Created %lu note(s).\n", (unsigned long)imported);
    if (updated > 0) printf("Updated %lu note(s).\n", (unsigned long)updated);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Sync cycle and watch daemon
// ─────────────────────────────────────────────────────────────────────────────

int cmdSyncRun(NSString *syncDir) {
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:syncDir withIntermediateDirectories:YES attributes:nil error:nil];

    // Auto-init on first run
    NSString *statePath = [syncDir stringByAppendingPathComponent:@".cider-sync-state.json"];
    BOOL firstRun = ![fm fileExistsAtPath:statePath];

    if (firstRun) {
        printf("First run detected — creating backup...\n");
        int backupRet = cmdSyncBackup(syncDir);
        if (backupRet != 0) {
            fprintf(stderr, "Backup failed. Aborting sync.\n");
            return 1;
        }
        printf("\nPerforming initial export...\n");
    }

    // Export Notes -> Markdown
    int ret = syncExportNotes(syncDir);
    if (ret != 0) return ret;

    // Import Markdown -> Notes
    ret = syncImportMarkdown(syncDir);
    return ret;
}

int cmdSyncWatch(NSString *syncDir, NSTimeInterval interval) {
    NSFileManager *fm = [NSFileManager defaultManager];

    signal(SIGINT, syncSignalHandler);
    signal(SIGTERM, syncSignalHandler);

    printf("Cider Sync watching %s (interval: %.0fs)\n", [syncDir UTF8String], interval);
    printf("Press Ctrl+C to stop.\n\n");

    // Initial sync
    int ret = cmdSyncRun(syncDir);
    if (ret != 0) return ret;

    // Track file modification times for change detection
    NSString *notesContainer = [NSHomeDirectory()
        stringByAppendingPathComponent:@"Library/Group Containers/group.com.apple.notes"];
    NSString *walPath = [notesContainer stringByAppendingPathComponent:@"NoteStore.sqlite-wal"];

    NSDate *lastWalMod = nil;
    NSDate *lastLocalMod = nil;

    NSDictionary *walAttrs = [fm attributesOfItemAtPath:walPath error:nil];
    if (walAttrs) lastWalMod = walAttrs[NSFileModificationDate];

    while (g_syncRunning) {
        [NSThread sleepForTimeInterval:interval];
        if (!g_syncRunning) break;

        BOOL needsSync = NO;

        // Check Notes database WAL for changes
        NSDictionary *curWalAttrs = [fm attributesOfItemAtPath:walPath error:nil];
        NSDate *curWalMod = curWalAttrs[NSFileModificationDate];
        if (curWalMod && (!lastWalMod || [curWalMod compare:lastWalMod] != NSOrderedSame)) {
            needsSync = YES;
            lastWalMod = curWalMod;
        }

        // Check local MD files for modifications
        NSArray *topItems = [fm contentsOfDirectoryAtPath:syncDir error:nil];
        for (NSString *item in topItems) {
            if ([item hasPrefix:@"."]) continue;
            if ([item isEqualToString:@"attachments"]) continue;
            NSString *itemPath = [syncDir stringByAppendingPathComponent:item];
            BOOL isDir = NO;
            [fm fileExistsAtPath:itemPath isDirectory:&isDir];
            if (isDir) {
                NSArray *subItems = [fm contentsOfDirectoryAtPath:itemPath error:nil];
                for (NSString *sub in subItems) {
                    if (![sub hasSuffix:@".md"]) continue;
                    NSString *subPath = [itemPath stringByAppendingPathComponent:sub];
                    NSDictionary *attrs = [fm attributesOfItemAtPath:subPath error:nil];
                    NSDate *mod = attrs[NSFileModificationDate];
                    if (mod && (!lastLocalMod || [mod compare:lastLocalMod] == NSOrderedDescending)) {
                        needsSync = YES;
                        lastLocalMod = mod;
                    }
                }
            } else if ([item hasSuffix:@".md"]) {
                NSDictionary *attrs = [fm attributesOfItemAtPath:itemPath error:nil];
                NSDate *mod = attrs[NSFileModificationDate];
                if (mod && (!lastLocalMod || [mod compare:lastLocalMod] == NSOrderedDescending)) {
                    needsSync = YES;
                    lastLocalMod = mod;
                }
            }
        }

        if (needsSync) {
            @autoreleasepool {
                cmdSyncRun(syncDir);
            }
        }
    }

    printf("\nSync stopped.\n");
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Help text
// ─────────────────────────────────────────────────────────────────────────────

void printSyncHelp(void) {
    printf(
"cider sync v" VERSION " — Bidirectional Apple Notes <-> Markdown sync\n"
"\n"
"USAGE:\n"
"  cider sync run [--dir <path>]                  One sync cycle (both directions)\n"
"  cider sync watch [--dir <path>] [--interval N] Continuous sync daemon\n"
"  cider sync backup [--dir <path>]               Backup Notes database\n"
"\n"
"OPTIONS:\n"
"  --dir <path>      Sync directory (default: ~/CiderSync)\n"
"  --interval <secs> Poll interval for watch mode (default: 2)\n"
"\n"
"FIRST RUN:\n"
"  'sync run' and 'sync watch' auto-initialize on first run:\n"
"  1. Creates a full backup of the Notes database\n"
"  2. Exports all notes to Markdown with YAML frontmatter\n"
"  3. Subsequent runs sync changes bidirectionally\n"
"\n"
"EDITABILITY:\n"
"  editable: false  — Pre-existing notes. Read-only in sync.\n"
"  editable: true   — Sync-created notes. Bidirectional edits.\n"
"  New .md files    — Creates a new Apple Note (editable: true).\n"
"\n"
"SAFETY:\n"
"  - Pre-existing Apple Notes are NEVER modified or deleted\n"
"  - Deleting an .md file never deletes the Apple Note\n"
"  - Conflicts save local version as .conflict-<timestamp>.md\n"
"\n"
"See SYNC.md and DISASTER-RECOVERY.md for full documentation.\n"
    );
}
