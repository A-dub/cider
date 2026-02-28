/**
 * notes.m — All Apple Notes commands
 */

#import "cider.h"

// Forward declarations for static helpers
static NSArray *extractAllTags(id note);
static BOOL noteHasTag(id note, NSString *tag);
static NSArray *outgoingLinks(id note);
static NSArray *collectChecklistItems(id note);
static NSArray *tableAttachmentsForNote(id note);
static BOOL noteIsShared(id note);
static NSUInteger noteParticipantCount(id note);
static NSString *uuidFromTokenContentIdentifier(NSString *tci);

// ─────────────────────────────────────────────────────────────────────────────
// Interactive prompt helper
// ─────────────────────────────────────────────────────────────────────────────

NSUInteger promptNoteIndex(NSString *verb, NSString *folder) {
    if (!isatty(STDIN_FILENO)) {
        fprintf(stderr, "Error: note number required (stdin is not a tty)\n");
        return 0;
    }

    cmdNotesList(folder, NO, nil, nil, nil, NO, nil);

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
// COMMANDS: notes
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesList(NSString *folder, BOOL jsonOutput,
                  NSString *afterStr, NSString *beforeStr, NSString *sortMode,
                  BOOL pinnedOnly, NSString *tagFilter) {
    NSArray *notes = filteredNotes(folder);

    // Tag filter (checks both plain-text and native inline attachment tags)
    if (tagFilter) {
        NSMutableArray *tagFiltered = [NSMutableArray array];
        for (id note in notes) {
            if (noteHasTag(note, tagFilter)) {
                [tagFiltered addObject:note];
            }
        }
        notes = tagFiltered;
    }

    // Pinned filter
    if (pinnedOnly) {
        NSMutableArray *pinned = [NSMutableArray array];
        for (id note in notes) {
            BOOL isPinned = ((BOOL (*)(id, SEL))objc_msgSend)(
                note, NSSelectorFromString(@"isPinned"));
            if (isPinned) [pinned addObject:note];
        }
        notes = pinned;
    }

    // Date filtering
    NSDate *afterDate = afterStr ? parseDateString(afterStr) : nil;
    NSDate *beforeDate = beforeStr ? parseDateString(beforeStr) : nil;

    if (afterStr && !afterDate) {
        fprintf(stderr, "Error: Invalid date '%s'. Use ISO 8601 (2024-01-15) or relative (today, yesterday, \"3 days ago\").\n",
                [afterStr UTF8String]);
        return;
    }
    if (beforeStr && !beforeDate) {
        fprintf(stderr, "Error: Invalid date '%s'. Use ISO 8601 (2024-01-15) or relative (today, yesterday, \"3 days ago\").\n",
                [beforeStr UTF8String]);
        return;
    }

    if (afterDate || beforeDate) {
        NSMutableArray *filtered = [NSMutableArray array];
        for (id note in notes) {
            NSDate *mod = [note valueForKey:@"modificationDate"];
            if (!mod) continue;
            if (afterDate && [mod compare:afterDate] == NSOrderedAscending) continue;
            if (beforeDate && [mod compare:beforeDate] == NSOrderedDescending) continue;
            [filtered addObject:note];
        }
        notes = filtered;
    }

    // Sorting
    if (sortMode) {
        if ([sortMode isEqualToString:@"modified"]) {
            notes = [notes sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                NSDate *da = [a valueForKey:@"modificationDate"];
                NSDate *db = [b valueForKey:@"modificationDate"];
                if (!da) return NSOrderedAscending;
                if (!db) return NSOrderedDescending;
                return [db compare:da]; // newest first
            }];
        } else if ([sortMode isEqualToString:@"created"]) {
            notes = [notes sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
                NSDate *da = [a valueForKey:@"creationDate"];
                NSDate *db = [b valueForKey:@"creationDate"];
                if (!da) return NSOrderedAscending;
                if (!db) return NSOrderedDescending;
                return [db compare:da]; // newest first
            }];
        }
        // "title" sort is the default from filteredNotes(), so no-op
    }

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < notes.count; i++) {
            id note = notes[i];
            NSString *t = jsonEscapeString(noteTitle(note));
            NSString *f = jsonEscapeString(folderName(note));
            NSUInteger ac = noteAttachmentCount(note);
            NSDate *created = [note valueForKey:@"creationDate"];
            NSDate *modified = [note valueForKey:@"modificationDate"];
            printf("  {\"index\":%lu,\"title\":\"%s\",\"folder\":\"%s\","
                   "\"attachments\":%lu,\"created\":\"%s\",\"modified\":\"%s\"}%s\n",
                   (unsigned long)noteIntPK(note),
                   [t UTF8String],
                   [f UTF8String],
                   (unsigned long)ac,
                   [isoDateString(created) UTF8String],
                   [isoDateString(modified) UTF8String],
                   (i + 1 < notes.count) ? "," : "");
        }
        printf("]\n");
        return;
    }

    printf("%6s %-42s %-22s %s\n",
           "#", "Title", "Folder", "Attachments");
    printf("------ %-42s %-22s %s\n",
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

    for (id note in notes) {
        NSString *t = truncStr(noteTitle(note), 42);
        NSString *f = truncStr(folderName(note), 22);
        NSUInteger ac = noteAttachmentCount(note);
        NSString *atts = ac > 0 ? [NSString stringWithFormat:@"📎 %lu", ac] : @"";

        printf("%6lu %-42s %-22s %s\n",
               (unsigned long)noteIntPK(note),
               [padRight(t, 42) UTF8String],
               [padRight(f, 22) UTF8String],
               [atts UTF8String]);
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

int cmdNotesInspect(NSUInteger idx, NSString *folder, BOOL jsonOutput) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *title = noteTitle(note);
    NSString *fName = folderName(note);
    NSInteger pk = noteIntPK(note);
    NSString *uri = noteURIString(note);
    NSString *identifier = noteIdentifier(note);
    NSDate *created = [note valueForKey:@"creationDate"];
    NSDate *modified = [note valueForKey:@"modificationDate"];
    NSString *raw = noteRawText(note);
    NSString *body = noteTextForDisplay(note);
    NSUInteger charCount = raw ? raw.length : 0;
    NSUInteger wordCount = 0;
    if (raw && raw.length > 0) {
        NSArray *words = [raw componentsSeparatedByCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        for (NSString *w in words) {
            if (w.length > 0) wordCount++;
        }
    }
    BOOL isPinned = ((BOOL (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"isPinned"));
    BOOL isShared = noteIsShared(note);
    NSUInteger partCount = noteParticipantCount(note);

    // Attachments
    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
    NSUInteger attCount = orderedIDs ? orderedIDs.count : 0;
    // Tags
    NSArray *tags = extractAllTags(note);

    // Links
    NSArray *links = outgoingLinks(note);

    // Backlinks
    NSString *myIdentifier = noteIdentifier(note);
    NSArray *allNotes = fetchAllNotes();
    NSMutableArray *backlinks = [NSMutableArray array];
    for (id other in allNotes) {
        if (other == note) continue;
        @try {
            SEL sel = NSSelectorFromString(@"allNoteTextInlineAttachments");
            if (![other respondsToSelector:sel]) continue;
            id inlineAtts = ((id (*)(id, SEL))objc_msgSend)(other, sel);
            for (id att in inlineAtts) {
                BOOL isLink = (BOOL)((NSInteger (*)(id, SEL))objc_msgSend)(
                    att, NSSelectorFromString(@"isLinkAttachment"));
                if (!isLink) continue;
                NSString *tci = ((id (*)(id, SEL))objc_msgSend)(
                    att, NSSelectorFromString(@"tokenContentIdentifier"));
                if (!tci) continue;
                NSRange noteRange = [tci rangeOfString:@"applenotes:note/"];
                if (noteRange.location == NSNotFound) continue;
                NSString *rest = [tci substringFromIndex:noteRange.location + 16];
                NSRange qRange = [rest rangeOfString:@"?"];
                NSString *targetUUID = qRange.location != NSNotFound
                    ? [rest substringToIndex:qRange.location] : rest;
                if ([targetUUID caseInsensitiveCompare:myIdentifier] == NSOrderedSame) {
                    [backlinks addObject:@{
                        @"title": noteTitle(other),
                        @"pk": @(noteIntPK(other))
                    }];
                    break;
                }
            }
        } @catch (NSException *e) {}
    }

    // Checklist items
    NSArray *checkItems = collectChecklistItems(note);
    int checkDone = 0;
    for (NSDictionary *item in checkItems) {
        if ([item[@"done"] boolValue]) checkDone++;
    }

    // Tables
    NSArray *tableAtts = tableAttachmentsForNote(note);

    if (jsonOutput) {
        printf("{\n");
        printf("  \"id\": %ld,\n", (long)pk);
        printf("  \"title\": \"%s\",\n", [jsonEscapeString(title) UTF8String]);
        printf("  \"folder\": \"%s\",\n", [jsonEscapeString(fName) UTF8String]);
        printf("  \"identifier\": \"%s\",\n", [jsonEscapeString(identifier ?: @"") UTF8String]);
        printf("  \"uri\": \"%s\",\n", [jsonEscapeString(uri) UTF8String]);
        printf("  \"created\": \"%s\",\n", [isoDateString(created) UTF8String]);
        printf("  \"modified\": \"%s\",\n", [isoDateString(modified) UTF8String]);
        printf("  \"characters\": %lu,\n", (unsigned long)charCount);
        printf("  \"words\": %lu,\n", (unsigned long)wordCount);
        printf("  \"pinned\": %s,\n", isPinned ? "true" : "false");
        printf("  \"shared\": %s,\n", isShared ? "true" : "false");
        printf("  \"participants\": %lu,\n", (unsigned long)partCount);

        // Tags
        printf("  \"tags\": [");
        for (NSUInteger i = 0; i < tags.count; i++) {
            printf("%s\"%s\"", i > 0 ? ", " : "", [jsonEscapeString(tags[i]) UTF8String]);
        }
        printf("],\n");

        // Attachments
        printf("  \"attachments\": [");
        for (NSUInteger i = 0; i < attCount; i++) {
            id val = orderedIDs[i];
            NSString *attID = (val != [NSNull null]) ? val : nil;
            NSString *name = attID ? attachmentNameByID(atts, attID) : @"attachment";
            NSString *uti = @"unknown";
            if (attID) {
                for (id a in atts) {
                    NSString *ident = ((id (*)(id, SEL))objc_msgSend)(
                        a, NSSelectorFromString(@"identifier"));
                    if ([ident isEqualToString:attID]) {
                        id u = [a valueForKey:@"typeUTI"];
                        if (u) uti = u;
                        break;
                    }
                }
            }
            printf("%s{\"name\":\"%s\",\"type\":\"%s\",\"id\":\"%s\"}",
                   i > 0 ? ", " : "",
                   [jsonEscapeString(name) UTF8String],
                   [jsonEscapeString(uti) UTF8String],
                   attID ? [jsonEscapeString(attID) UTF8String] : "");
        }
        printf("],\n");

        // Links
        printf("  \"links\": [");
        for (NSUInteger i = 0; i < links.count; i++) {
            NSDictionary *l = links[i];
            printf("%s{\"text\":\"%s\",\"target\":\"%s\"}",
                   i > 0 ? ", " : "",
                   [jsonEscapeString(l[@"displayText"]) UTF8String],
                   [jsonEscapeString(l[@"targetTitle"] ?: @"") UTF8String]);
        }
        printf("],\n");

        // Backlinks
        printf("  \"backlinks\": [");
        for (NSUInteger i = 0; i < backlinks.count; i++) {
            NSDictionary *bl = backlinks[i];
            printf("%s{\"title\":\"%s\",\"id\":%ld}",
                   i > 0 ? ", " : "",
                   [jsonEscapeString(bl[@"title"]) UTF8String],
                   (long)[bl[@"pk"] integerValue]);
        }
        printf("],\n");

        // Checklist
        printf("  \"checklist\": {\"total\":%lu,\"checked\":%d,\"items\":[",
               (unsigned long)checkItems.count, checkDone);
        for (NSUInteger i = 0; i < checkItems.count; i++) {
            NSDictionary *item = checkItems[i];
            printf("%s{\"text\":\"%s\",\"done\":%s}",
                   i > 0 ? ", " : "",
                   [jsonEscapeString(item[@"text"]) UTF8String],
                   [item[@"done"] boolValue] ? "true" : "false");
        }
        printf("]},\n");

        // Tables
        printf("  \"tables\": [");
        for (NSUInteger i = 0; i < tableAtts.count; i++) {
            id tAtt = tableAtts[i];
            id tm = ((id (*)(id, SEL))objc_msgSend)(tAtt, NSSelectorFromString(@"tableModel"));
            id tbl = ((id (*)(id, SEL))objc_msgSend)(tm, NSSelectorFromString(@"table"));
            NSUInteger rows = ((NSUInteger (*)(id, SEL))objc_msgSend)(tbl, NSSelectorFromString(@"rowCount"));
            NSUInteger cols = ((NSUInteger (*)(id, SEL))objc_msgSend)(tbl, NSSelectorFromString(@"columnCount"));
            printf("%s{\"rows\":%lu,\"columns\":%lu,\"data\":[",
                   i > 0 ? ", " : "", (unsigned long)rows, (unsigned long)cols);
            for (NSUInteger r = 0; r < rows; r++) {
                @try {
                    NSArray *strings = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                        tm, NSSelectorFromString(@"stringsAtRow:"), r);
                    printf("%s[", r > 0 ? ", " : "");
                    NSUInteger sc = strings ? strings.count : 0;
                    for (NSUInteger c = 0; c < cols; c++) {
                        NSString *cell = (c < sc) ? strings[c] : @"";
                        printf("%s\"%s\"", c > 0 ? ", " : "", [jsonEscapeString(cell) UTF8String]);
                    }
                    printf("]");
                } @catch (NSException *e) {}
            }
            printf("]}");
        }
        printf("],\n");

        // Body
        printf("  \"body\": \"%s\"\n", [jsonEscapeString(body) UTF8String]);
        printf("}\n");
        return 0;
    }

    // ── Text output (document order) ──

    printf("╔══════════════════════════════════════════════════════════════╗\n");
    printf("  %s\n", [title UTF8String]);
    printf("╚══════════════════════════════════════════════════════════════╝\n\n");

    // Metadata
    printf("── Metadata ──────────────────────────────────────────────────\n");
    printf("  ID:           %ld\n", (long)pk);
    printf("  Folder:       %s\n", [fName UTF8String]);
    printf("  Created:      %s\n", [isoDateString(created) UTF8String]);
    printf("  Modified:     %s\n", [isoDateString(modified) UTF8String]);
    printf("  Characters:   %lu\n", (unsigned long)charCount);
    printf("  Words:        %lu\n", (unsigned long)wordCount);
    printf("  Pinned:       %s\n", isPinned ? "Yes" : "No");
    printf("  Shared:       %s\n", isShared ? "Yes" : "No");
    if (partCount > 0)
        printf("  Participants: %lu\n", (unsigned long)partCount);
    if (tags.count > 0)
        printf("  Tags:         %lu\n", (unsigned long)tags.count);
    if (attCount > 0)
        printf("  Attachments:  %lu\n", (unsigned long)attCount);
    if (links.count > 0)
        printf("  Links:        %lu\n", (unsigned long)links.count);
    if (backlinks.count > 0)
        printf("  Backlinks:    %lu\n", (unsigned long)backlinks.count);
    if (checkItems.count > 0)
        printf("  Checklist:    %d/%lu\n", checkDone, (unsigned long)checkItems.count);
    if (tableAtts.count > 0)
        printf("  Tables:       %lu\n", (unsigned long)tableAtts.count);
    printf("  Identifier:   %s\n", [identifier UTF8String]);
    printf("  URI:          %s\n", [uri UTF8String]);

    // Backlinks (external references, not part of note content)
    if (backlinks.count > 0) {
        printf("\n── Backlinks (%lu) ────────────────────────────────────────────\n",
               (unsigned long)backlinks.count);
        for (NSUInteger i = 0; i < backlinks.count; i++) {
            NSDictionary *bl = backlinks[i];
            printf("  %lu. \"%s\" (#%ld)\n",
                   (unsigned long)(i + 1),
                   [bl[@"title"] UTF8String],
                   (long)[bl[@"pk"] integerValue]);
        }
    }

    // ── Content (document order) ──
    printf("\n── Content ───────────────────────────────────────────────────\n");

    // Get attributed string for inline walking
    id inspectMergeStr = noteMergeableString(note);
    NSAttributedString *inspectAttrStr = nil;
    if (inspectMergeStr) {
        @try {
            inspectAttrStr = ((id (*)(id, SEL))objc_msgSend)(
                inspectMergeStr, NSSelectorFromString(@"attributedString"));
        } @catch (NSException *e) {}
    }

    if (!inspectAttrStr) {
        // Fallback: plain body text
        printf("%s\n", [body UTF8String]);
        return 0;
    }

    // Build inline attachment lookup: identifier → info dict
    NSMutableDictionary *inlineLookup = [NSMutableDictionary dictionary];
    @try {
        SEL inlineSel = NSSelectorFromString(@"allNoteTextInlineAttachments");
        if ([note respondsToSelector:inlineSel]) {
            id inspectInlineAtts = ((id (*)(id, SEL))objc_msgSend)(note, inlineSel);
            for (id iAtt in inspectInlineAtts) {
                NSString *iIdent = ((id (*)(id, SEL))objc_msgSend)(
                    iAtt, NSSelectorFromString(@"identifier"));
                if (!iIdent) continue;
                NSString *iUTI = ((id (*)(id, SEL))objc_msgSend)(
                    iAtt, NSSelectorFromString(@"typeUTI"));
                NSString *iAlt = ((id (*)(id, SEL))objc_msgSend)(
                    iAtt, NSSelectorFromString(@"altText"));
                NSString *iTCI = ((id (*)(id, SEL))objc_msgSend)(
                    iAtt, NSSelectorFromString(@"tokenContentIdentifier"));

                NSMutableDictionary *iInfo = [NSMutableDictionary dictionary];
                iInfo[@"altText"] = iAlt ?: @"";

                if ([iUTI isEqualToString:@"com.apple.notes.inlinetextattachment.hashtag"]) {
                    iInfo[@"type"] = @"tag";
                } else if ([iUTI isEqualToString:@"com.apple.notes.inlinetextattachment.link"]) {
                    iInfo[@"type"] = @"link";
                    NSString *targetUUID = uuidFromTokenContentIdentifier(iTCI);
                    if (targetUUID) {
                        id target = findNoteByIdentifier(targetUUID);
                        if (target) {
                            iInfo[@"targetTitle"] = noteTitle(target);
                            iInfo[@"targetPK"] = @(noteIntPK(target));
                        }
                    }
                }
                inlineLookup[iIdent] = iInfo;
            }
        }
    } @catch (NSException *e) {}

    // Build table attachment lookup: identifier → ICAttachment
    NSMutableDictionary *tableLookup = [NSMutableDictionary dictionary];
    for (id tblAtt in tableAtts) {
        NSString *tblIdent = ((id (*)(id, SEL))objc_msgSend)(
            tblAtt, NSSelectorFromString(@"identifier"));
        if (tblIdent) tableLookup[tblIdent] = tblAtt;
    }

    // Walk attributed string paragraph by paragraph
    NSString *inspectFullText = [(NSAttributedString *)inspectAttrStr string];
    NSUInteger inspectLen = inspectFullText.length;
    NSUInteger inspectParaStart = 0;
    BOOL skipTitle = YES;

    while (inspectParaStart < inspectLen) {
        NSRange inspNLRange = [inspectFullText rangeOfString:@"\n"
            options:0 range:NSMakeRange(inspectParaStart, inspectLen - inspectParaStart)];
        NSUInteger inspectParaEnd = (inspNLRange.location != NSNotFound)
            ? inspNLRange.location + 1 : inspectLen;

        // Skip title (first paragraph)
        if (skipTitle) {
            skipTitle = NO;
            inspectParaStart = inspectParaEnd;
            continue;
        }

        // Check if this paragraph is a checklist item
        NSDictionary *pAttrs = [(NSAttributedString *)inspectAttrStr
            attributesAtIndex:inspectParaStart effectiveRange:NULL];
        id pStyle = pAttrs[@"TTStyle"];
        BOOL isCL = NO;
        BOOL clDone = NO;
        if (pStyle) {
            NSInteger sNum = ((NSInteger (*)(id, SEL))objc_msgSend)(
                pStyle, NSSelectorFromString(@"style"));
            if (sNum == 103) {
                isCL = YES;
                id pTodo = ((id (*)(id, SEL))objc_msgSend)(
                    pStyle, NSSelectorFromString(@"todo"));
                NSInteger dRaw = pTodo
                    ? ((NSInteger (*)(id, SEL))objc_msgSend)(pTodo, NSSelectorFromString(@"done"))
                    : 0;
                clDone = (dRaw != 0);
            }
        }
        if (isCL) printf("[%s] ", clDone ? "x" : " ");

        // Walk characters in this paragraph
        NSUInteger ci = inspectParaStart;
        while (ci < inspectParaEnd) {
            unichar cc = [inspectFullText characterAtIndex:ci];

            if (cc == ATTACHMENT_MARKER) {
                NSRange cEffRange;
                NSDictionary *cAttrs = [(NSAttributedString *)inspectAttrStr
                    attributesAtIndex:ci effectiveRange:&cEffRange];
                id cTTAtt = cAttrs[@"NSAttachment"];

                if (cTTAtt) {
                    NSString *cAttId = ((id (*)(id, SEL))objc_msgSend)(
                        cTTAtt, NSSelectorFromString(@"attachmentIdentifier"));
                    NSString *cAttUTI = ((id (*)(id, SEL))objc_msgSend)(
                        cTTAtt, NSSelectorFromString(@"attachmentUTI"));

                    NSDictionary *cInfo = inlineLookup[cAttId];
                    if (cInfo && [@"tag" isEqualToString:cInfo[@"type"]]) {
                        // Native tag — show altText (e.g. "#cider")
                        printf("%s", [cInfo[@"altText"] UTF8String]);
                    } else if (cInfo && [@"link" isEqualToString:cInfo[@"type"]]) {
                        // Note link
                        NSString *cTarget = cInfo[@"targetTitle"];
                        NSNumber *cTPK = cInfo[@"targetPK"];
                        if (cTarget && cTPK)
                            printf("[-> \"%s\" #%ld]",
                                   [cTarget UTF8String], (long)[cTPK integerValue]);
                        else if (cTarget)
                            printf("[-> \"%s\"]", [cTarget UTF8String]);
                        else
                            printf("[-> %s]", [cInfo[@"altText"] UTF8String]);
                    } else if (cAttUTI &&
                               [cAttUTI isEqualToString:@"com.apple.notes.table"]) {
                        // Table — render inline with aligned columns
                        id cTblAtt = tableLookup[cAttId];
                        if (cTblAtt) {
                            @try {
                                id cTM = ((id (*)(id, SEL))objc_msgSend)(
                                    cTblAtt, NSSelectorFromString(@"tableModel"));
                                id cTbl = ((id (*)(id, SEL))objc_msgSend)(
                                    cTM, NSSelectorFromString(@"table"));
                                NSUInteger tRows = ((NSUInteger (*)(id, SEL))objc_msgSend)(
                                    cTbl, NSSelectorFromString(@"rowCount"));
                                NSUInteger tCols = ((NSUInteger (*)(id, SEL))objc_msgSend)(
                                    cTbl, NSSelectorFromString(@"columnCount"));

                                NSMutableArray *tAllRows = [NSMutableArray array];
                                NSMutableArray *tColW = [NSMutableArray array];
                                for (NSUInteger tc = 0; tc < tCols; tc++)
                                    [tColW addObject:@(0)];

                                for (NSUInteger tr = 0; tr < tRows; tr++) {
                                    @try {
                                        NSArray *tStrings =
                                            ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                                                cTM, NSSelectorFromString(@"stringsAtRow:"), tr);
                                        NSMutableArray *tRow = [NSMutableArray array];
                                        for (NSUInteger tc = 0; tc < tCols; tc++) {
                                            NSString *tCell =
                                                (tStrings && tc < tStrings.count)
                                                    ? tStrings[tc] : @"";
                                            [tRow addObject:tCell];
                                            NSUInteger tw = [tCell length];
                                            if (tw > [tColW[tc] unsignedIntegerValue])
                                                tColW[tc] = @(tw);
                                        }
                                        [tAllRows addObject:tRow];
                                    } @catch (NSException *e) {}
                                }

                                for (NSUInteger tr = 0; tr < tAllRows.count; tr++) {
                                    NSArray *tRow = tAllRows[tr];
                                    printf("  |");
                                    for (NSUInteger tc = 0; tc < tCols; tc++) {
                                        NSUInteger tw =
                                            [tColW[tc] unsignedIntegerValue];
                                        if (tw < 3) tw = 3;
                                        printf(" %-*s |", (int)tw,
                                               [tRow[tc] UTF8String]);
                                    }
                                    printf("\n");
                                    if (tr == 0) {
                                        printf("  |");
                                        for (NSUInteger tc = 0; tc < tCols; tc++) {
                                            NSUInteger tw =
                                                [tColW[tc] unsignedIntegerValue];
                                            if (tw < 3) tw = 3;
                                            for (NSUInteger td = 0; td < tw + 2; td++)
                                                printf("-");
                                            printf("|");
                                        }
                                        printf("\n");
                                    }
                                }
                            } @catch (NSException *e) {
                                printf("[table: error]\n");
                            }
                        }
                    } else {
                        // File/image attachment
                        NSString *cName = attachmentNameByID(atts, cAttId);
                        printf("[attachment: %s (%s)]", [cName UTF8String],
                               cAttUTI ? [cAttUTI UTF8String] : "unknown");
                    }
                }
                ci++;
            } else {
                // Regular text — accumulate run until next marker
                NSUInteger runStart = ci;
                while (ci < inspectParaEnd &&
                       [inspectFullText characterAtIndex:ci] != ATTACHMENT_MARKER)
                    ci++;
                NSString *textRun = [inspectFullText substringWithRange:
                    NSMakeRange(runStart, ci - runStart)];
                printf("%s", [textRun UTF8String]);
            }
        }

        inspectParaStart = inspectParaEnd;
    }

    return 0;
}

void cmdNotesAdd(NSString *folderArg) {
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

    id folder = folderArg
        ? findOrCreateFolder(folderArg, YES)
        : defaultFolder();
    if (!folder) {
        fprintf(stderr, "Error: Could not find or create folder\n");
        return;
    }
    id account = [folder valueForKey:@"account"];

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

    id noteDataEntity = [NSEntityDescription
        insertNewObjectForEntityForName:@"ICNoteData"
                 inManagedObjectContext:g_moc];
    [newNote setValue:noteDataEntity forKey:@"noteData"];

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

    ((void (*)(id, SEL))objc_msgSend)(
        newNote, NSSelectorFromString(@"saveNoteData"));
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

    if (!isatty(STDIN_FILENO)) {
        NSData *data = [[NSFileHandle fileHandleWithStandardInput]
                        readDataToEndOfFile];
        NSString *piped = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!piped || [[piped stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
            printf("Aborted: empty input.\n");
            return;
        }
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

int cmdNotesReplace(NSUInteger idx, NSString *findStr, NSString *replaceStr,
                    BOOL useRegex, BOOL caseInsensitive) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *rawText = noteRawText(note);
    NSString *newRaw = nil;

    if (useRegex) {
        NSRegularExpressionOptions opts = 0;
        if (caseInsensitive) opts |= NSRegularExpressionCaseInsensitive;
        NSError *regexErr = nil;
        NSRegularExpression *regex = [NSRegularExpression
            regularExpressionWithPattern:findStr options:opts error:&regexErr];
        if (regexErr) {
            fprintf(stderr, "Error: Invalid regex: %s\n",
                    [[regexErr localizedDescription] UTF8String]);
            return 1;
        }
        NSUInteger matches = [regex numberOfMatchesInString:rawText options:0
                              range:NSMakeRange(0, rawText.length)];
        if (matches == 0) {
            fprintf(stderr, "Error: Pattern not found in note %lu: \"%s\"\n",
                    (unsigned long)idx, [findStr UTF8String]);
            return 1;
        }
        newRaw = [regex stringByReplacingMatchesInString:rawText options:0
                  range:NSMakeRange(0, rawText.length) withTemplate:replaceStr];
    } else {
        NSStringCompareOptions opts = 0;
        if (caseInsensitive) opts |= NSCaseInsensitiveSearch;
        NSRange found = [rawText rangeOfString:findStr options:opts];
        if (found.location == NSNotFound) {
            fprintf(stderr, "Error: Text not found in note %lu: \"%s\"\n",
                    (unsigned long)idx, [findStr UTF8String]);
            return 1;
        }
        if (caseInsensitive) {
            // Replace all occurrences case-insensitively
            newRaw = [rawText stringByReplacingOccurrencesOfString:findStr
                      withString:replaceStr options:NSCaseInsensitiveSearch
                      range:NSMakeRange(0, rawText.length)];
        } else {
            newRaw = [rawText stringByReplacingOccurrencesOfString:findStr
                      withString:replaceStr];
        }
    }

    // Attachment safety check
    NSUInteger origCount = 0, newCount = 0;
    for (NSUInteger i = 0; i < rawText.length; i++)
        if ([rawText characterAtIndex:i] == ATTACHMENT_MARKER) origCount++;
    for (NSUInteger i = 0; i < newRaw.length; i++)
        if ([newRaw characterAtIndex:i] == ATTACHMENT_MARKER) newCount++;
    if (origCount != newCount) {
        fprintf(stderr, "Error: Replace would change attachment count (%lu → %lu). Aborting.\n",
                (unsigned long)origCount, (unsigned long)newCount);
        return 1;
    }

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

int cmdNotesReplaceAll(NSString *findStr, NSString *replaceStr, NSString *folder,
                       BOOL useRegex, BOOL caseInsensitive, BOOL dryRun) {
    NSArray *notes = filteredNotes(folder);
    if (!notes || notes.count == 0) {
        printf("No notes%s.\n", folder ? [[NSString stringWithFormat:@" in folder \"%@\"", folder] UTF8String] : "");
        return 0;
    }

    // Compile regex once if needed
    NSRegularExpression *regex = nil;
    if (useRegex) {
        NSRegularExpressionOptions opts = 0;
        if (caseInsensitive) opts |= NSRegularExpressionCaseInsensitive;
        NSError *regexErr = nil;
        regex = [NSRegularExpression regularExpressionWithPattern:findStr
                 options:opts error:&regexErr];
        if (regexErr) {
            fprintf(stderr, "Error: Invalid regex: %s\n",
                    [[regexErr localizedDescription] UTF8String]);
            return 1;
        }
    }

    NSStringCompareOptions strOpts = 0;
    if (caseInsensitive) strOpts |= NSCaseInsensitiveSearch;

    // Scan all notes for matches
    NSMutableArray *matchedNotes = [NSMutableArray array];
    NSMutableArray *matchCounts = [NSMutableArray array];
    NSUInteger totalMatches = 0;

    for (id note in notes) {
        NSString *rawText = noteRawText(note);
        if (!rawText || rawText.length == 0) continue;

        NSUInteger count = 0;
        if (useRegex) {
            count = [regex numberOfMatchesInString:rawText options:0
                     range:NSMakeRange(0, rawText.length)];
        } else {
            NSRange searchRange = NSMakeRange(0, rawText.length);
            while (searchRange.location < rawText.length) {
                NSRange found = [rawText rangeOfString:findStr options:strOpts
                                 range:searchRange];
                if (found.location == NSNotFound) break;
                count++;
                searchRange.location = found.location + found.length;
                searchRange.length = rawText.length - searchRange.location;
            }
        }

        if (count > 0) {
            [matchedNotes addObject:note];
            [matchCounts addObject:@(count)];
            totalMatches += count;
        }
    }

    if (matchedNotes.count == 0) {
        printf("No matches found for \"%s\"%s.\n",
               [findStr UTF8String],
               folder ? [[NSString stringWithFormat:@" in folder \"%@\"", folder] UTF8String] : "");
        return 0;
    }

    // Print summary
    printf("Found %lu match(es) in %lu note(s)%s:\n\n",
           (unsigned long)totalMatches,
           (unsigned long)matchedNotes.count,
           folder ? [[NSString stringWithFormat:@" in \"%@\"", folder] UTF8String] : "");

    for (NSUInteger i = 0; i < matchedNotes.count; i++) {
        NSString *t = noteTitle(matchedNotes[i]);
        NSString *f = folderName(matchedNotes[i]);
        printf("  %s (%s) — %lu match(es)\n",
               [t UTF8String], [f UTF8String],
               (unsigned long)[matchCounts[i] unsignedIntegerValue]);
    }

    if (dryRun) {
        printf("\n[dry-run] No changes made.\n");
        return 0;
    }

    // Confirm
    printf("\nReplace \"%s\" → \"%s\" in all %lu note(s)? (y/N) ",
           [findStr UTF8String], [replaceStr UTF8String],
           (unsigned long)matchedNotes.count);
    fflush(stdout);

    char buf[8] = {0};
    if (fgets(buf, sizeof(buf), stdin) == NULL || (buf[0] != 'y' && buf[0] != 'Y')) {
        printf("Cancelled.\n");
        return 0;
    }

    // Apply replacements
    NSUInteger replaced = 0, skipped = 0;
    for (id note in matchedNotes) {
        NSString *rawText = noteRawText(note);
        NSString *newRaw = nil;

        if (useRegex) {
            newRaw = [regex stringByReplacingMatchesInString:rawText options:0
                      range:NSMakeRange(0, rawText.length) withTemplate:replaceStr];
        } else if (caseInsensitive) {
            newRaw = [rawText stringByReplacingOccurrencesOfString:findStr
                      withString:replaceStr options:NSCaseInsensitiveSearch
                      range:NSMakeRange(0, rawText.length)];
        } else {
            newRaw = [rawText stringByReplacingOccurrencesOfString:findStr
                      withString:replaceStr];
        }

        // Attachment safety check per note
        NSUInteger origAtt = 0, newAtt = 0;
        for (NSUInteger i = 0; i < rawText.length; i++)
            if ([rawText characterAtIndex:i] == ATTACHMENT_MARKER) origAtt++;
        for (NSUInteger i = 0; i < newRaw.length; i++)
            if ([newRaw characterAtIndex:i] == ATTACHMENT_MARKER) newAtt++;
        if (origAtt != newAtt) {
            NSString *t = noteTitle(note);
            fprintf(stderr, "  Skipped \"%s\": would change attachment count (%lu → %lu)\n",
                    [t UTF8String], (unsigned long)origAtt, (unsigned long)newAtt);
            skipped++;
            continue;
        }

        if (applyCRDTEdit(note, rawText, newRaw)) {
            replaced++;
        } else {
            NSString *t = noteTitle(note);
            fprintf(stderr, "  Skipped \"%s\": CRDT edit failed\n", [t UTF8String]);
            skipped++;
        }
    }

    if (replaced > 0 && !saveContext()) {
        fprintf(stderr, "Error: save failed\n");
        return 1;
    }

    printf("✓ Replaced in %lu note(s)", (unsigned long)replaced);
    if (skipped > 0) printf(", skipped %lu", (unsigned long)skipped);
    printf(".\n");
    return 0;
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

    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"delete");
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
    id oldFolder = ((id (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"folder"));

    // Skip if already in the target folder
    if (oldFolder == folder) {
        printf("Note \"%s\" is already in \"%s\"\n", [t UTF8String],
               [targetFolderName UTF8String]);
        return;
    }

    // 1. Change the Core Data folder relationship
    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"setFolder:"), folder);

    // 2. Mark note dirty so CloudKit knows to push
    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"move");

    // 3. Update the CKRecord's parent reference to point to the new folder
    ((void (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"updateParentReferenceIfNecessary"));

    // 4. Record move activity event
    @try {
        ((id (*)(id, SEL, id, id, id))objc_msgSend)(
            note,
            NSSelectorFromString(@"persistMoveActivityEventForObject:fromParentObject:toParentObject:"),
            note, oldFolder, folder);
    } @catch (NSException *e) {}

    // 5. Persist all pending changes
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"persistPendingChanges"));

    if (saveContext()) {
        printf("Moved \"%s\" → \"%s\"\n", [t UTF8String],
               [targetFolderName UTF8String]);
    } else {
        fprintf(stderr, "Error: Failed to move note\n");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: append / prepend
// ─────────────────────────────────────────────────────────────────────────────

int cmdNotesAppend(NSUInteger idx, NSString *text, NSString *folder, BOOL noNewline) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *raw = noteRawText(note);
    NSString *newText;
    if (noNewline) {
        newText = [raw stringByAppendingString:text];
    } else {
        newText = [NSString stringWithFormat:@"%@\n%@", raw, text];
    }

    if (!applyCRDTEdit(note, raw, newText)) {
        fprintf(stderr, "Error: Failed to append to note\n");
        return 1;
    }
    if (!saveContext()) {
        fprintf(stderr, "Error: Failed to save after append\n");
        return 1;
    }
    printf("✓ Appended to note %lu\n", (unsigned long)idx);
    return 0;
}

int cmdNotesPrepend(NSUInteger idx, NSString *text, NSString *folder, BOOL noNewline) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *raw = noteRawText(note);
    NSRange nlRange = [raw rangeOfString:@"\n"];
    NSString *newText;

    if (nlRange.location == NSNotFound) {
        // Note has only a title line (no body)
        if (noNewline) {
            newText = [NSString stringWithFormat:@"%@%@", raw, text];
        } else {
            newText = [NSString stringWithFormat:@"%@\n%@", raw, text];
        }
    } else {
        NSString *title = [raw substringToIndex:nlRange.location];
        NSString *rest = [raw substringFromIndex:nlRange.location + 1];
        if (noNewline) {
            newText = [NSString stringWithFormat:@"%@\n%@%@", title, text, rest];
        } else {
            newText = [NSString stringWithFormat:@"%@\n%@\n%@", title, text, rest];
        }
    }

    if (!applyCRDTEdit(note, raw, newText)) {
        fprintf(stderr, "Error: Failed to prepend to note\n");
        return 1;
    }
    if (!saveContext()) {
        fprintf(stderr, "Error: Failed to save after prepend\n");
        return 1;
    }
    printf("✓ Prepended to note %lu\n", (unsigned long)idx);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMAND: debug (dump attributed string attributes)
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesDebug(NSUInteger idx, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *title = noteTitle(note);
    printf("Debug: \"%s\" (note %lu)\n\n", [title UTF8String], (unsigned long)idx);

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        printf("  (no mergeableString)\n");
        return;
    }

    NSString *raw = noteRawText(note);
    printf("Raw text length: %lu characters\n\n", (unsigned long)[raw length]);

    // Get the full attributed string
    id attrString = nil;
    @try {
        attrString = ((id (*)(id, SEL))objc_msgSend)(
            mergeStr, NSSelectorFromString(@"attributedString"));
    }
    @catch (NSException *e) {
        printf("  (attributedString not available: %s)\n",
               [[e reason] UTF8String]);
        return;
    }
    if (!attrString || ![attrString isKindOfClass:[NSAttributedString class]]) {
        printf("  (attributedString returned nil or non-NSAttributedString)\n");
        return;
    }

    // Collect unique attribute keys across all ranges
    NSMutableDictionary *attrSummary = [NSMutableDictionary dictionary];
    NSUInteger len = [(NSAttributedString *)attrString length];
    NSUInteger pos = 0;

    while (pos < len) {
        NSRange effRange;
        NSDictionary *attrs = [(NSAttributedString *)attrString
            attributesAtIndex:pos effectiveRange:&effRange];

        for (NSString *key in attrs) {
            id val = attrs[key];
            NSString *valDesc = [NSString stringWithFormat:@"%@ (%@)",
                [val description], NSStringFromClass([val class])];

            // Track ranges per key
            NSMutableArray *ranges = attrSummary[key];
            if (!ranges) {
                ranges = [NSMutableArray array];
                attrSummary[key] = ranges;
            }
            [ranges addObject:@{
                @"range": NSStringFromRange(effRange),
                @"value": valDesc,
                @"char": (effRange.location < [raw length])
                    ? [NSString stringWithFormat:@"%C",
                       [raw characterAtIndex:effRange.location]]
                    : @"?"
            }];
        }
        pos = effRange.location + effRange.length;
    }

    // Print summary
    printf("Attributed string attribute keys found: %lu\n\n",
           (unsigned long)[attrSummary count]);

    for (NSString *key in [[attrSummary allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        NSArray *ranges = attrSummary[key];
        printf("  Key: \"%s\" (%lu occurrence(s))\n",
               [key UTF8String], (unsigned long)ranges.count);
        for (NSDictionary *info in ranges) {
            printf("    Range: %s  Char: '%s'\n",
                   [info[@"range"] UTF8String],
                   [info[@"char"] UTF8String]);
            // Truncate long value descriptions
            NSString *valStr = info[@"value"];
            if ([valStr length] > 200) {
                valStr = [[valStr substringToIndex:200] stringByAppendingString:@"..."];
            }
            printf("    Value: %s\n", [valStr UTF8String]);
        }
        printf("\n");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: history (CRDT edit timeline)
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesHistory(NSUInteger idx, NSString *folder, BOOL jsonOutput, BOOL raw) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *title = noteTitle(note);
    id ms = noteMergeableString(note);
    if (!ms) {
        fprintf(stderr, "Error: No CRDT data for note %lu\n", (unsigned long)idx);
        return;
    }

    // Get edits array (ICTTTextEdit objects with timestamp, replicaID, range)
    NSArray *edits = nil;
    @try {
        edits = ((id (*)(id, SEL))objc_msgSend)(ms, NSSelectorFromString(@"edits"));
    } @catch (NSException *e) {}
    if (!edits || [edits count] == 0) {
        if (jsonOutput) {
            printf("{\"note\":%lu,\"title\":\"%s\",\"edits\":0,\"sessions\":[]}\n",
                   (unsigned long)idx, [jsonEscapeString(title) UTF8String]);
        } else {
            printf("No edit history for \"%s\"\n", [title UTF8String]);
        }
        return;
    }

    // Get the current text for previewing what each edit region contains
    id strObj = ((id (*)(id, SEL))objc_msgSend)(ms, NSSelectorFromString(@"string"));
    NSString *fullStr = nil;
    if ([strObj isKindOfClass:[NSAttributedString class]])
        fullStr = [(NSAttributedString *)strObj string];
    else if ([strObj isKindOfClass:[NSString class]])
        fullStr = (NSString *)strObj;
    NSUInteger textLen = fullStr ? fullStr.length : 0;

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    fmt.timeZone = [NSTimeZone localTimeZone];

    NSDateFormatter *isoFmt = [[NSDateFormatter alloc] init];
    isoFmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZZZZZ";
    isoFmt.timeZone = [NSTimeZone localTimeZone];

    // Build sorted edit list with extracted data
    NSMutableArray *editData = [NSMutableArray arrayWithCapacity:[edits count]];
    for (id edit in edits) {
        NSDate *ts = nil;
        NSUUID *rid = nil;
        NSRange range = NSMakeRange(0, 0);
        @try {
            ts = ((id (*)(id, SEL))objc_msgSend)(edit, NSSelectorFromString(@"timestamp"));
            rid = ((id (*)(id, SEL))objc_msgSend)(edit, NSSelectorFromString(@"replicaID"));
            range = ((NSRange (*)(id, SEL))objc_msgSend)(edit, NSSelectorFromString(@"range"));
        } @catch (NSException *e) { continue; }
        if (!ts) continue;

        NSString *text = @"";
        if (fullStr && range.location < textLen && range.location + range.length <= textLen) {
            text = [fullStr substringWithRange:range];
        }

        [editData addObject:@{
            @"timestamp": ts,
            @"replicaID": rid ? [rid UUIDString] : @"unknown",
            @"range": [NSValue valueWithRange:range],
            @"text": text
        }];
    }

    // Sort by timestamp
    [editData sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"timestamp"] compare:b[@"timestamp"]];
    }];

    // Collect unique replicas and assign short labels
    NSMutableOrderedSet *replicaIDs = [NSMutableOrderedSet orderedSet];
    for (NSDictionary *ed in editData) {
        [replicaIDs addObject:ed[@"replicaID"]];
    }

    // Build replica UUID → person name mapping
    NSMutableDictionary *replicaNames = [NSMutableDictionary dictionary];

    // 1. Decode replicaIDToUserIDDictData via ICMergeableDictionary → {replicaUUID: userRecordID}
    NSMutableDictionary *replicaToUserID = [NSMutableDictionary dictionary];
    @try {
        NSData *dictData = [note valueForKey:@"replicaIDToUserIDDictData"];
        if (dictData.length > 0) {
            Class mdClass = NSClassFromString(@"ICMergeableDictionary");
            if (mdClass) {
                id md = ((id (*)(id, SEL, id, id))objc_msgSend)(
                    [mdClass alloc], NSSelectorFromString(@"initWithData:replicaID:"),
                    dictData, [NSUUID UUID]);
                if (md) {
                    NSArray *keys = ((id (*)(id, SEL))objc_msgSend)(md, NSSelectorFromString(@"allKeys"));
                    for (id key in keys) {
                        id val = ((id (*)(id, SEL, id))objc_msgSend)(md, NSSelectorFromString(@"objectForKey:"), key);
                        if (val) replicaToUserID[[key description]] = [val description];
                    }
                }
            }
        }
    } @catch (NSException *e) {}

    // 2. Get CKShare participants → {userRecordID: name}
    NSMutableDictionary *userIDToName = [NSMutableDictionary dictionary];
    NSString *currentUserName = nil;
    NSMutableSet *knownRecordNames = [NSMutableSet set];
    @try {
        id share = [note valueForKey:@"serverShare"];
        if (share) {
            id participants = ((id (*)(id, SEL))objc_msgSend)(share, NSSelectorFromString(@"participants"));
            for (id part in (NSArray *)participants) {
                id identity = ((id (*)(id, SEL))objc_msgSend)(part, NSSelectorFromString(@"userIdentity"));
                if (!identity) continue;
                id nameComp = ((id (*)(id, SEL))objc_msgSend)(identity, NSSelectorFromString(@"nameComponents"));
                id userRecordID = ((id (*)(id, SEL))objc_msgSend)(identity, NSSelectorFromString(@"userRecordID"));
                NSString *recordName = userRecordID ?
                    ((id (*)(id, SEL))objc_msgSend)(userRecordID, NSSelectorFromString(@"recordName")) : nil;
                BOOL isCurrent = ((BOOL (*)(id, SEL))objc_msgSend)(part, NSSelectorFromString(@"isCurrentUser"));

                NSString *given = nameComp ? [nameComp valueForKey:@"givenName"] : nil;
                NSString *family = nameComp ? [nameComp valueForKey:@"familyName"] : nil;
                NSString *name = nil;
                if (given.length > 0 && family.length > 0)
                    name = [NSString stringWithFormat:@"%@ %@", given, family];
                else if (given.length > 0)
                    name = given;

                if (name && recordName) {
                    userIDToName[recordName] = name;
                    [knownRecordNames addObject:recordName];
                }
                if (name && isCurrent)
                    currentUserName = name;
            }
        }
    } @catch (NSException *e) {}

    // 3. For current user: CKShare uses __defaultOwner__ as recordName,
    //    but replica mapping uses the real CloudKit record ID.
    //    Map any unmatched userIDs to the current user's name.
    if (currentUserName) {
        NSMutableSet *allUserIDs = [NSMutableSet set];
        for (NSString *uid in [replicaToUserID allValues])
            [allUserIDs addObject:uid];
        for (NSString *uid in allUserIDs) {
            if (![knownRecordNames containsObject:uid])
                userIDToName[uid] = currentUserName;
        }
    }

    // 4. Cross-reference: for each replica in this note's edits, look up user → name
    for (NSString *rid in replicaIDs) {
        NSString *userID = replicaToUserID[rid] ?: replicaToUserID[[rid uppercaseString]];
        if (userID && userIDToName[userID])
            replicaNames[rid] = userIDToName[userID];
    }

    // Group into sessions (gap > 60 seconds = new session)
    NSMutableArray *sessions = [NSMutableArray array];
    NSMutableArray *currentSession = nil;
    NSDate *lastTs = nil;

    for (NSDictionary *ed in editData) {
        NSDate *ts = ed[@"timestamp"];
        if (!lastTs || [ts timeIntervalSinceDate:lastTs] > 60.0) {
            currentSession = [NSMutableArray array];
            [sessions addObject:currentSession];
        }
        [currentSession addObject:ed];
        lastTs = ts;
    }

    // === JSON Output ===
    if (jsonOutput) {
        printf("{\"note\":%lu,\"title\":\"%s\",\"edits\":%lu,\"devices\":[",
               (unsigned long)idx, [jsonEscapeString(title) UTF8String],
               (unsigned long)[editData count]);

        for (NSUInteger i = 0; i < [replicaIDs count]; i++) {
            if (i > 0) printf(",");
            NSString *rid = [replicaIDs objectAtIndex:i];
            NSString *shortID = [[rid substringToIndex:MIN([(NSString *)rid length], (NSUInteger)4)] uppercaseString];
            NSString *name = replicaNames[rid];
            if (name)
                printf("{\"id\":\"%s\",\"uuid\":\"%s\",\"name\":\"%s\"}", [shortID UTF8String], [rid UTF8String], [jsonEscapeString(name) UTF8String]);
            else
                printf("{\"id\":\"%s\",\"uuid\":\"%s\"}", [shortID UTF8String], [rid UTF8String]);
        }
        printf("],\"sessions\":[");

        for (NSUInteger si = 0; si < sessions.count; si++) {
            NSArray *sess = sessions[si];
            if (si > 0) printf(",");

            NSDate *startTs = sess[0][@"timestamp"];
            NSDate *endTs = [sess lastObject][@"timestamp"];
            NSUInteger totalChars = 0;
            NSMutableString *preview = [NSMutableString string];
            NSMutableSet *sessReplicas = [NSMutableSet set];

            for (NSDictionary *ed in sess) {
                NSRange r = [ed[@"range"] rangeValue];
                totalChars += r.length;
                [sessReplicas addObject:ed[@"replicaID"]];
                if (preview.length < 120) {
                    NSString *t = ed[@"text"];
                    t = [t stringByReplacingOccurrencesOfString:@"\n" withString:@"\\n"];
                    [preview appendString:t];
                }
            }
            if (preview.length > 120) {
                preview = [[preview substringToIndex:117] mutableCopy];
                [preview appendString:@"..."];
            }

            printf("{\"start\":\"%s\",\"end\":\"%s\",\"edits\":%lu,\"chars\":%lu,\"preview\":\"%s\",\"replicas\":[",
                   [[isoFmt stringFromDate:startTs] UTF8String],
                   [[isoFmt stringFromDate:endTs] UTF8String],
                   (unsigned long)sess.count,
                   (unsigned long)totalChars,
                   [jsonEscapeString(preview) UTF8String]);

            NSArray *sr = [[sessReplicas allObjects] sortedArrayUsingSelector:@selector(compare:)];
            for (NSUInteger ri = 0; ri < sr.count; ri++) {
                if (ri > 0) printf(",");
                printf("\"%s\"", [sr[ri] UTF8String]);
            }
            printf("]}");
        }
        printf("]}\n");
        return;
    }

    // === Text Output ===

    // Build device labels: use person name if available, else short hex ID
    NSMutableDictionary *deviceLabels = [NSMutableDictionary dictionary];
    for (NSString *rid in replicaIDs) {
        NSString *name = replicaNames[rid];
        if (name)
            deviceLabels[rid] = name;
        else {
            NSString *shortID = [[rid substringToIndex:MIN(rid.length, (NSUInteger)4)] uppercaseString];
            deviceLabels[rid] = shortID;
        }
    }

    printf("History: \"%s\" (#%lu)\n", [title UTF8String], (unsigned long)idx);
    printf("  %lu edits, %lu sessions, %lu device(s)\n",
           (unsigned long)[editData count],
           (unsigned long)sessions.count,
           (unsigned long)[replicaIDs count]);

    // Show device legend
    if ([replicaIDs count] > 1) {
        printf("  Devices:");
        for (NSUInteger i = 0; i < [replicaIDs count]; i++) {
            NSString *rid = [replicaIDs objectAtIndex:i];
            printf(" %s", [deviceLabels[rid] UTF8String]);
        }
        printf("\n");
    }
    printf("\n");

    if (raw) {
        // Raw mode: show every edit region
        for (NSDictionary *ed in editData) {
            NSDate *ts = ed[@"timestamp"];
            NSString *text = ed[@"text"];
            NSString *rid = ed[@"replicaID"];
            NSString *devLabel = deviceLabels[rid];

            NSString *display = [text stringByReplacingOccurrencesOfString:@"\n" withString:@"\u21b5"];
            if (display.length > 70) {
                display = [[display substringToIndex:67] stringByAppendingString:@"..."];
            }

            printf("  %s  %-4s  + \"%s\"\n",
                   [[fmt stringFromDate:ts] UTF8String],
                   [devLabel UTF8String],
                   [display UTF8String]);
        }
    } else {
        // Session mode: group edits into editing sessions
        for (NSUInteger si = 0; si < sessions.count; si++) {
            NSArray *sess = sessions[si];
            NSDate *startTs = sess[0][@"timestamp"];
            NSDate *endTs = [sess lastObject][@"timestamp"];
            NSTimeInterval dur = [endTs timeIntervalSinceDate:startTs];
            NSUInteger totalChars = 0;

            // Build person-attributed chunks: [{person, text}]
            // Merge adjacent edits from the same person into one chunk
            NSMutableArray *personChunks = [NSMutableArray array];
            NSString *currentPerson = nil;
            NSMutableString *currentChunk = nil;
            NSUInteger lastEnd = NSNotFound;

            for (NSDictionary *ed in sess) {
                NSRange r = [ed[@"range"] rangeValue];
                totalChars += r.length;
                NSString *person = deviceLabels[ed[@"replicaID"]];
                NSString *t = ed[@"text"];
                if (t.length == 0) continue;

                BOOL samePerson = [person isEqualToString:currentPerson ?: @""];
                BOOL adjacent = (lastEnd != NSNotFound && r.location == lastEnd);

                if (samePerson && adjacent && currentChunk) {
                    [currentChunk appendString:t];
                } else {
                    if (currentChunk && currentChunk.length > 0) {
                        [personChunks addObject:@{@"person": currentPerson, @"text": [currentChunk copy]}];
                    }
                    currentPerson = person;
                    currentChunk = [t mutableCopy];
                }
                lastEnd = r.location + r.length;
            }
            if (currentChunk && currentChunk.length > 0) {
                [personChunks addObject:@{@"person": currentPerson ?: @"?", @"text": [currentChunk copy]}];
            }

            // Time gap since previous session
            NSString *gapStr = @"";
            if (si > 0) {
                NSDate *prevEnd = [sessions[si-1] lastObject][@"timestamp"];
                NSTimeInterval gap = [startTs timeIntervalSinceDate:prevEnd];
                if (gap < 3600)
                    gapStr = [NSString stringWithFormat:@"  (%.0fm later)", gap/60];
                else if (gap < 86400)
                    gapStr = [NSString stringWithFormat:@"  (%.1fh later)", gap/3600];
                else
                    gapStr = [NSString stringWithFormat:@"  (%.0fd later)", gap/86400];
            }

            // Duration string
            NSString *durStr = @"";
            if (dur >= 1.0 && dur < 60.0)
                durStr = [NSString stringWithFormat:@", %.0fs", dur];
            else if (dur >= 60.0 && dur < 3600.0)
                durStr = [NSString stringWithFormat:@", %dm%ds", (int)(dur/60), (int)fmod(dur,60)];
            else if (dur >= 3600.0)
                durStr = [NSString stringWithFormat:@", %dh%dm", (int)(dur/3600), (int)fmod(dur/60,60)];

            printf("  %s  %lu chars%s%s\n",
                   [[fmt stringFromDate:startTs] UTF8String],
                   (unsigned long)totalChars,
                   [durStr UTF8String],
                   [gapStr UTF8String]);

            // Merge consecutive chunks from the same person
            NSMutableArray *mergedChunks = [NSMutableArray array];
            for (NSDictionary *pc in personChunks) {
                NSDictionary *last = [mergedChunks lastObject];
                if (last && [last[@"person"] isEqualToString:pc[@"person"]]) {
                    NSString *merged = [NSString stringWithFormat:@"%@\n%@", last[@"text"], pc[@"text"]];
                    [mergedChunks removeLastObject];
                    [mergedChunks addObject:@{@"person": pc[@"person"], @"text": merged}];
                } else {
                    [mergedChunks addObject:pc];
                }
            }

            // Show person-attributed content
            for (NSDictionary *pc in mergedChunks) {
                NSString *person = pc[@"person"];
                NSString *text = pc[@"text"];

                // Collapse into non-empty lines
                NSArray *lines = [text componentsSeparatedByString:@"\n"];
                NSMutableArray *nonEmpty = [NSMutableArray array];
                for (NSString *line in lines) {
                    NSString *trimmed = [line stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
                    if (trimmed.length > 0) [nonEmpty addObject:trimmed];
                }

                if (nonEmpty.count == 0) continue;

                // Show person label, then all their lines indented
                printf("    %s:\n", [person UTF8String]);
                for (NSUInteger li = 0; li < nonEmpty.count && li < 12; li++) {
                    NSString *line = nonEmpty[li];
                    if (line.length > 120)
                        line = [[line substringToIndex:117] stringByAppendingString:@"..."];
                    printf("      %s\n", [line UTF8String]);
                }
                if (nonEmpty.count > 12) {
                    printf("      ... (%lu more lines)\n",
                           (unsigned long)(nonEmpty.count - 12));
                }
            }
            printf("\n");
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: getdate / setdate
// ─────────────────────────────────────────────────────────────────────────────

int cmdNotesGetdate(NSUInteger idx, NSString *folder, BOOL jsonOutput) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *title = noteTitle(note);
    NSDate *modified = [note valueForKey:@"modificationDate"];
    NSDate *created = [note valueForKey:@"creationDate"];
    NSString *ident = noteIdentifier(note);

    if (jsonOutput) {
        printf("{\"index\":%lu,\"title\":\"%s\",\"modified\":\"%s\","
               "\"created\":\"%s\",\"identifier\":\"%s\"}\n",
               (unsigned long)idx,
               [jsonEscapeString(title) UTF8String],
               [isoDateString(modified) UTF8String],
               [isoDateString(created) UTF8String],
               [jsonEscapeString(ident ?: @"") UTF8String]);
    } else {
        printf("%lu  \"%s\"  modified: %s  created: %s  id: %s\n",
               (unsigned long)idx,
               [title UTF8String],
               [isoDateString(modified) UTF8String],
               [isoDateString(created) UTF8String],
               [ident ?: @"(none)" UTF8String]);
    }
    return 0;
}

int cmdNotesSetdate(NSUInteger idx, NSString *dateStr, NSString *folder, BOOL dryRun) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSDate *newDate = parseDateString(dateStr);
    if (!newDate) {
        fprintf(stderr, "Error: Invalid date '%s'. Use ISO 8601 (2024-01-15T14:30:00 or 2024-01-15).\n",
                [dateStr UTF8String]);
        return 1;
    }

    NSString *title = noteTitle(note);
    NSDate *oldDate = [note valueForKey:@"modificationDate"];

    if (dryRun) {
        printf("[dry-run] %lu  \"%s\"  %s → %s\n",
               (unsigned long)idx,
               [title UTF8String],
               [isoDateString(oldDate) UTF8String],
               [isoDateString(newDate) UTF8String]);
        return 0;
    }

    [note setValue:newDate forKey:@"modificationDate"];
    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"setdate");

    if (!saveContext()) {
        fprintf(stderr, "Error: Failed to save\n");
        return 1;
    }

    printf("Updated %lu  \"%s\"  %s → %s\n",
           (unsigned long)idx,
           [title UTF8String],
           [isoDateString(oldDate) UTF8String],
           [isoDateString(newDate) UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// COMMANDS: search
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesSearch(NSString *query, BOOL jsonOutput, BOOL useRegex,
                    BOOL titleOnly, BOOL bodyOnly, NSString *folder,
                    NSString *afterStr, NSString *beforeStr, NSString *tagFilter) {
    NSArray *results = nil;

    // Date filtering setup
    NSDate *afterDate = afterStr ? parseDateString(afterStr) : nil;
    NSDate *beforeDate = beforeStr ? parseDateString(beforeStr) : nil;
    if (afterStr && !afterDate) {
        fprintf(stderr, "Error: Invalid date '%s'.\n", [afterStr UTF8String]);
        return;
    }
    if (beforeStr && !beforeDate) {
        fprintf(stderr, "Error: Invalid date '%s'.\n", [beforeStr UTF8String]);
        return;
    }
    BOOL hasDateFilter = (afterDate || beforeDate);

    if (!useRegex && !bodyOnly && !folder && !hasDateFilter && !tagFilter) {
        // Fast path: Core Data predicate (existing behavior)
        NSPredicate *pred;
        if (titleOnly) {
            pred = [NSPredicate predicateWithFormat:@"title CONTAINS[cd] %@", query];
        } else {
            pred = [NSPredicate predicateWithFormat:
                @"(title CONTAINS[cd] %@) OR (snippet CONTAINS[cd] %@)",
                query, query];
        }
        results = fetchNotes(pred);
    } else {
        // Client-side filtering: regex, body-only, folder-scoped, or date-filtered
        NSArray *candidates = filteredNotes(folder);
        NSRegularExpression *regex = nil;
        if (useRegex) {
            NSError *regexErr = nil;
            regex = [NSRegularExpression
                regularExpressionWithPattern:query
                options:NSRegularExpressionCaseInsensitive
                error:&regexErr];
            if (regexErr) {
                fprintf(stderr, "Error: Invalid regex: %s\n",
                        [[regexErr localizedDescription] UTF8String]);
                return;
            }
        }

        NSMutableArray *matched = [NSMutableArray array];
        for (id note in candidates) {
            // Date filter
            if (hasDateFilter) {
                NSDate *mod = [note valueForKey:@"modificationDate"];
                if (!mod) continue;
                if (afterDate && [mod compare:afterDate] == NSOrderedAscending) continue;
                if (beforeDate && [mod compare:beforeDate] == NSOrderedDescending) continue;
            }

            BOOL found = NO;
            NSString *title = noteTitle(note);
            NSString *body = noteRawText(note);

            // Tag filter (checks both plain-text and native tags)
            if (tagFilter) {
                if (!noteHasTag(note, tagFilter)) continue;
            }

            if (!bodyOnly) {
                // Check title
                if (useRegex) {
                    if ([regex numberOfMatchesInString:title options:0
                         range:NSMakeRange(0, title.length)] > 0)
                        found = YES;
                } else {
                    if ([title rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
                        found = YES;
                }
            }
            if (!found && !titleOnly) {
                // Check body
                if (body) {
                    if (useRegex) {
                        if ([regex numberOfMatchesInString:body options:0
                             range:NSMakeRange(0, body.length)] > 0)
                            found = YES;
                    } else {
                        if ([body rangeOfString:query options:NSCaseInsensitiveSearch].location != NSNotFound)
                            found = YES;
                    }
                }
            }
            if (found) [matched addObject:note];
        }
        results = matched;
    }

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
            NSDate *created = [note valueForKey:@"creationDate"];
            NSDate *modified = [note valueForKey:@"modificationDate"];
            printf("  {\"index\":%lu,\"title\":\"%s\",\"folder\":\"%s\","
                   "\"attachments\":%lu,\"created\":\"%s\",\"modified\":\"%s\"}%s\n",
                   (unsigned long)noteIntPK(note),
                   [t UTF8String],
                   [f UTF8String],
                   (unsigned long)ac,
                   [isoDateString(created) UTF8String],
                   [isoDateString(modified) UTF8String],
                   (i + 1 < results.count) ? "," : "");
        }
        printf("]\n");
        return;
    }

    printf("Found %lu note(s) matching \"%s\":\n\n",
           (unsigned long)results.count, [query UTF8String]);
    printf("%6s %-42s %-22s\n", "#", "Title", "Folder");
    printf("------ %-42s %-22s\n",
           "------------------------------------------",
           "----------------------");

    for (id note in results) {
        NSString *t = truncStr(noteTitle(note), 42);
        NSString *f = truncStr(folderName(note), 22);
        printf("%6lu %-42s %-22s\n",
               (unsigned long)noteIntPK(note),
               [padRight(t, 42) UTF8String],
               [padRight(f, 22) UTF8String]);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings commands
// ─────────────────────────────────────────────────────────────────────────────

void cmdSettings(BOOL jsonOutput) {
    NSDictionary *settings = loadCiderSettings();

    if (jsonOutput) {
        printf("{\n");
        NSArray *keys = [[settings allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSUInteger i = 0; i < keys.count; i++) {
            printf("  \"%s\":\"%s\"%s\n",
                   [jsonEscapeString(keys[i]) UTF8String],
                   [jsonEscapeString(settings[keys[i]]) UTF8String],
                   (i + 1 < keys.count) ? "," : "");
        }
        printf("}\n");
        return;
    }

    if (settings.count == 0) {
        printf("No settings configured.\n");
        printf("Set one with: cider settings set <key> <value>\n");
        return;
    }

    printf("Cider Settings:\n\n");
    NSArray *keys = [[settings allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in keys) {
        printf("  %-25s %s\n", [key UTF8String], [settings[key] UTF8String]);
    }
}

int cmdSettingsGet(NSString *key) {
    NSString *value = getCiderSetting(key);
    if (!value) {
        fprintf(stderr, "Setting '%s' not found.\n", [key UTF8String]);
        return 1;
    }
    printf("%s\n", [value UTF8String]);
    return 0;
}

int cmdSettingsSet(NSString *key, NSString *value) {
    if (setCiderSetting(key, value) != 0) {
        fprintf(stderr, "Error: Failed to set '%s'\n", [key UTF8String]);
        return 1;
    }
    printf("Set %s = %s\n", [[key lowercaseString] UTF8String], [value UTF8String]);
    return 0;
}

int cmdSettingsReset(void) {
    NSDictionary *settings = loadCiderSettings();
    if (settings.count == 0) {
        printf("No settings to reset.\n");
        return 0;
    }

    // Find and delete the settings note
    NSArray *notes = filteredNotes(@"Cider Templates");
    for (id note in notes) {
        if ([noteTitle(note) isEqualToString:@"Cider Settings"]) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"delete");
            ((void (*)(id, SEL, BOOL))objc_msgSend)(
                note, NSSelectorFromString(@"setMarkedForDeletion:"), YES);
            if (!saveContext()) return 1;
            printf("Settings reset to defaults.\n");
            return 0;
        }
    }
    return 0;
}

int cmdNotesPin(NSUInteger idx, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    BOOL isPinned = ((BOOL (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"isPinned"));
    if (isPinned) {
        printf("Note %lu is already pinned.\n", (unsigned long)idx);
        return 0;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        note, NSSelectorFromString(@"setIsPinned:"), YES);
    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"pin");

    if (!saveContext()) return 1;
    printf("📌 Pinned note %lu: \"%s\"\n", (unsigned long)idx,
           [noteTitle(note) UTF8String]);
    return 0;
}

int cmdNotesUnpin(NSUInteger idx, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    BOOL isPinned = ((BOOL (*)(id, SEL))objc_msgSend)(
        note, NSSelectorFromString(@"isPinned"));
    if (!isPinned) {
        printf("Note %lu is not pinned.\n", (unsigned long)idx);
        return 0;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        note, NSSelectorFromString(@"setIsPinned:"), NO);
    ((void (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"unpin");

    if (!saveContext()) return 1;
    printf("📌 Unpinned note %lu: \"%s\"\n", (unsigned long)idx,
           [noteTitle(note) UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tag helpers
// ─────────────────────────────────────────────────────────────────────────────

NSArray *extractTags(NSString *text) {
    if (!text) return @[];
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:@"#[A-Za-z][A-Za-z0-9_-]*"
        options:0 error:&err];
    if (err) return @[];
    NSArray *matches = [re matchesInString:text options:0
                       range:NSMakeRange(0, text.length)];
    NSMutableOrderedSet *tags = [NSMutableOrderedSet orderedSet];
    for (NSTextCheckingResult *m in matches) {
        [tags addObject:[text substringWithRange:m.range]];
    }
    return [tags array];
}

// Extract tags from a note including native inline attachment hashtags
static NSArray *extractAllTags(id note) {
    NSMutableOrderedSet *tags = [NSMutableOrderedSet orderedSet];

    // 1. Plain text tags from raw text
    NSString *raw = noteRawText(note);
    if (raw) {
        NSArray *plainTags = extractTags(raw);
        [tags addObjectsFromArray:plainTags];
    }

    // 2. Native inline attachment hashtags
    @try {
        SEL sel = NSSelectorFromString(@"allNoteTextInlineAttachments");
        if ([note respondsToSelector:sel]) {
            id inlineAtts = ((id (*)(id, SEL))objc_msgSend)(note, sel);
            for (id att in inlineAtts) {
                NSString *uti = ((id (*)(id, SEL))objc_msgSend)(
                    att, NSSelectorFromString(@"typeUTI"));
                if ([uti isEqualToString:@"com.apple.notes.inlinetextattachment.hashtag"]) {
                    NSString *altText = ((id (*)(id, SEL))objc_msgSend)(
                        att, NSSelectorFromString(@"altText"));
                    if (altText) [tags addObject:altText];
                }
            }
        }
    } @catch (NSException *e) {}

    return [tags array];
}

// Check if a note has a specific tag (plain text or native)
static BOOL noteHasTag(id note, NSString *tag) {
    NSString *normalized = [tag hasPrefix:@"#"] ? tag : [@"#" stringByAppendingString:tag];
    NSArray *allTags = extractAllTags(note);
    for (NSString *t in allTags) {
        if ([[t lowercaseString] isEqualToString:[normalized lowercaseString]])
            return YES;
    }
    return NO;
}

int cmdNotesTag(NSUInteger idx, NSString *tag, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    // Normalize tag (strip # prefix for internal use, keep for display)
    NSString *displayTag = [tag hasPrefix:@"#"] ? tag : [@"#" stringByAppendingString:tag];
    NSString *bareTag = [tag hasPrefix:@"#"] ? [tag substringFromIndex:1] : tag;

    // Check if tag already exists via inline attachments
    NSFetchRequest *existReq = [NSFetchRequest fetchRequestWithEntityName:@"ICInlineAttachment"];
    existReq.predicate = [NSPredicate predicateWithFormat:
        @"typeUTI == 'com.apple.notes.inlinetextattachment.hashtag' AND note == %@ AND tokenContentIdentifier ==[c] %@",
        note, [bareTag uppercaseString]];
    NSArray *existingTags = [g_moc executeFetchRequest:existReq error:nil];
    if (existingTags.count > 0) {
        printf("Note %lu already has tag %s\n", (unsigned long)idx,
               [displayTag UTF8String]);
        return 0;
    }

    // Also check plain-text tags
    NSString *raw = noteRawText(note);
    NSArray *existing = extractTags(raw);
    for (NSString *t in existing) {
        if ([[t lowercaseString] isEqualToString:[displayTag lowercaseString]]) {
            printf("Note %lu already has tag %s\n", (unsigned long)idx,
                   [t UTF8String]);
            return 0;
        }
    }

    // Create ICHashtag (global entity) if needed
    @try {
        Class hashtagClass = NSClassFromString(@"ICHashtag");
        if (hashtagClass) {
            id account = [note valueForKey:@"account"];
            SEL hashSel = NSSelectorFromString(@"hashtagWithDisplayText:account:createIfNecessary:");
            ((id (*)(Class, SEL, id, id, BOOL))objc_msgSend)(
                hashtagClass, hashSel, bareTag, account, YES);
        }
    } @catch (NSException *e) {}

    // Create ICInlineAttachment for the tag
    NSString *attID = [[NSUUID UUID] UUIDString];
    @try {
        Class inlineClass = NSClassFromString(@"ICInlineAttachment");
        SEL newAttSel = NSSelectorFromString(
            @"newAttachmentWithIdentifier:typeUTI:altText:tokenContentIdentifier:note:parentAttachment:");
        ((id (*)(Class, SEL, id, id, id, id, id, id))objc_msgSend)(
            inlineClass, newAttSel,
            attID,
            @"com.apple.notes.inlinetextattachment.hashtag",
            displayTag,
            [bareTag uppercaseString],
            note,
            nil);
    } @catch (NSException *e) {
        fprintf(stderr, "Error creating inline attachment: %s\n", [[e reason] UTF8String]);
        return 1;
    }

    // Insert U+FFFC with NSAttachment attribute into mergeableString
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return 1;
    }

    // Create ICTTAttachment for the attributed string
    id ttAtt = [[NSClassFromString(@"ICTTAttachment") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(
        ttAtt, NSSelectorFromString(@"setAttachmentIdentifier:"), attID);
    ((void (*)(id, SEL, id))objc_msgSend)(
        ttAtt, NSSelectorFromString(@"setAttachmentUTI:"),
        @"com.apple.notes.inlinetextattachment.hashtag");

    // Build the attributed string: space + U+FFFC (tag marker)
    unichar fffc = 0xFFFC;
    NSString *marker = [NSString stringWithFormat:@" %C", fffc];
    NSAttributedString *tagStr = [[NSAttributedString alloc]
        initWithString:marker attributes:@{@"NSAttachment": ttAtt}];

    // Get insertion point (end of text)
    NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"attributedString"));
    NSUInteger insertPos = [(NSAttributedString *)attrStr length];

    // Insert
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"insertAttributedString:atIndex:"),
        tagStr, insertPos);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    if (!saveContext()) return 1;
    printf("Added %s to note %lu\n", [displayTag UTF8String], (unsigned long)idx);
    return 0;
}

int cmdNotesUntag(NSUInteger idx, NSString *tag, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *normalized = [tag hasPrefix:@"#"] ? tag : [@"#" stringByAppendingString:tag];
    NSString *bareTag = [tag hasPrefix:@"#"] ? [tag substringFromIndex:1] : tag;
    BOOL removed = NO;

    // 1. Try to remove native inline attachment tags
    @try {
        NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICInlineAttachment"];
        req.predicate = [NSPredicate predicateWithFormat:
            @"typeUTI == 'com.apple.notes.inlinetextattachment.hashtag' AND note == %@ AND tokenContentIdentifier ==[c] %@",
            note, [bareTag uppercaseString]];
        NSArray *atts = [g_moc executeFetchRequest:req error:nil];
        if (atts.count > 0) {
            // Collect attachment identifiers to remove from CRDT
            NSMutableSet *idsToRemove = [NSMutableSet set];
            for (id att in atts) {
                NSString *attId = ((id (*)(id, SEL))objc_msgSend)(
                    att, NSSelectorFromString(@"identifier"));
                if (attId) [idsToRemove addObject:attId];
            }

            // Use applyCRDTEdit to remove the U+FFFC markers:
            // Get raw text, find U+FFFC positions that match our tag attachments,
            // and remove them along with any leading space
            id mergeStr = noteMergeableString(note);
            NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
                mergeStr, NSSelectorFromString(@"attributedString"));
            NSString *fullText = [(NSAttributedString *)attrStr string];
            NSUInteger len = fullText.length;

            // Build new text with matching U+FFFC markers removed
            NSMutableString *newText = [NSMutableString string];
            NSRange effRange;
            for (NSUInteger i = 0; i < len; i = NSMaxRange(effRange)) {
                NSDictionary *attrs = [(NSAttributedString *)attrStr
                    attributesAtIndex:i effectiveRange:&effRange];
                id ttAtt = attrs[@"NSAttachment"];
                BOOL skip = NO;
                if (ttAtt) {
                    NSString *attId = ((id (*)(id, SEL))objc_msgSend)(
                        ttAtt, NSSelectorFromString(@"attachmentIdentifier"));
                    if ([idsToRemove containsObject:attId]) {
                        skip = YES;
                        // Also remove leading space if present
                        if (newText.length > 0 &&
                            [newText characterAtIndex:newText.length - 1] == ' ') {
                            [newText deleteCharactersInRange:
                                NSMakeRange(newText.length - 1, 1)];
                        }
                    }
                }
                if (!skip) {
                    [newText appendString:[fullText substringWithRange:effRange]];
                }
            }

            // Apply the edit via CRDT: old text has U+FFFC, new text doesn't
            NSString *oldRaw = noteRawText(note);
            if (![newText isEqualToString:fullText]) {
                applyCRDTEdit(note, oldRaw, newText);
            }

            // Delete the inline attachment entities
            for (id att in atts) {
                [g_moc deleteObject:att];
            }

            ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
            ((void (*)(id, SEL))objc_msgSend)(note,
                NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
            removed = YES;
        }
    } @catch (NSException *e) {}

    // 2. Also try to remove plain-text tags
    NSString *raw = noteRawText(note);
    NSString *escapedTag = [NSRegularExpression escapedPatternForString:normalized];
    NSString *pattern = [NSString stringWithFormat:@" ?%@(?=[^A-Za-z0-9_-]|$)", escapedTag];
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:pattern
        options:NSRegularExpressionCaseInsensitive
        error:&err];
    if (!err) {
        NSString *newText = [re stringByReplacingMatchesInString:raw options:0
                             range:NSMakeRange(0, raw.length) withTemplate:@""];
        if (![newText isEqualToString:raw]) {
            applyCRDTEdit(note, raw, newText);
            removed = YES;
        }
    }

    if (!removed) {
        printf("Tag %s not found in note %lu\n", [normalized UTF8String],
               (unsigned long)idx);
        return 0;
    }

    if (!saveContext()) return 1;
    printf("Removed %s from note %lu\n", [normalized UTF8String],
           (unsigned long)idx);
    return 0;
}

void cmdNotesTags(BOOL withCounts, BOOL jsonOutput) {
    NSArray *notes = fetchAllNotes();
    NSMutableDictionary *tagCounts = [NSMutableDictionary dictionary];

    for (id note in notes) {
        NSArray *tags = extractAllTags(note);
        NSMutableSet *seen = [NSMutableSet set]; // unique per note
        for (NSString *tag in tags) {
            NSString *lower = [tag lowercaseString];
            if ([seen containsObject:lower]) continue;
            [seen addObject:lower];
            NSNumber *count = tagCounts[lower] ?: @0;
            tagCounts[lower] = @([count integerValue] + 1);
        }
    }

    NSArray *sortedTags = [[tagCounts allKeys]
        sortedArrayUsingSelector:@selector(compare:)];

    if (jsonOutput) {
        printf("[\n");
        for (NSUInteger i = 0; i < sortedTags.count; i++) {
            NSString *tag = sortedTags[i];
            NSNumber *count = tagCounts[tag];
            printf("  {\"tag\":\"%s\",\"count\":%ld}%s\n",
                   [jsonEscapeString(tag) UTF8String],
                   (long)[count integerValue],
                   (i + 1 < sortedTags.count) ? "," : "");
        }
        printf("]\n");
        return;
    }

    if (sortedTags.count == 0) {
        printf("No tags found.\n");
        return;
    }

    for (NSString *tag in sortedTags) {
        if (withCounts) {
            printf("  %-30s %ld note(s)\n", [tag UTF8String],
                   (long)[tagCounts[tag] integerValue]);
        } else {
            printf("  %s\n", [tag UTF8String]);
        }
    }
    printf("\nTotal: %lu unique tag(s)\n", (unsigned long)sortedTags.count);
}

int cmdTagsClean(void) {
    // Find all ICHashtag entities
    NSFetchRequest *hashReq = [NSFetchRequest fetchRequestWithEntityName:@"ICHashtag"];
    NSArray *allHashtags = [g_moc executeFetchRequest:hashReq error:nil];
    if (!allHashtags || allHashtags.count == 0) {
        printf("No hashtag entities found.\n");
        return 0;
    }

    // Build set of tags that are actually used in notes (via ICInlineAttachment)
    NSFetchRequest *attReq = [NSFetchRequest fetchRequestWithEntityName:@"ICInlineAttachment"];
    attReq.predicate = [NSPredicate predicateWithFormat:
        @"typeUTI == 'com.apple.notes.inlinetextattachment.hashtag' AND note != nil AND note.markedForDeletion != YES"];
    NSArray *liveAtts = [g_moc executeFetchRequest:attReq error:nil];

    NSMutableSet *liveTags = [NSMutableSet set];
    for (id att in liveAtts) {
        NSString *token = ((id (*)(id, SEL))objc_msgSend)(
            att, NSSelectorFromString(@"tokenContentIdentifier"));
        if (token) [liveTags addObject:[token uppercaseString]];
    }

    // Delete ICHashtag entities whose tag isn't referenced by any live note
    NSUInteger cleaned = 0;
    for (id hashtag in allHashtags) {
        NSString *name = ((id (*)(id, SEL))objc_msgSend)(
            hashtag, NSSelectorFromString(@"displayText"));
        NSString *upper = [name uppercaseString];
        if (![liveTags containsObject:upper]) {
            printf("  Removing orphaned tag: #%s\n", [name UTF8String]);
            [g_moc deleteObject:hashtag];
            cleaned++;
        }
    }

    // Also delete orphaned ICInlineAttachment hashtag entities (note is nil or deleted)
    NSFetchRequest *orphanReq = [NSFetchRequest fetchRequestWithEntityName:@"ICInlineAttachment"];
    orphanReq.predicate = [NSPredicate predicateWithFormat:
        @"typeUTI == 'com.apple.notes.inlinetextattachment.hashtag' AND (note == nil OR note.markedForDeletion == YES)"];
    NSArray *orphanAtts = [g_moc executeFetchRequest:orphanReq error:nil];
    for (id att in orphanAtts) {
        [g_moc deleteObject:att];
        cleaned++;
    }

    if (cleaned == 0) {
        printf("No orphaned tags found.\n");
        return 0;
    }

    if (!saveContext()) return 1;
    printf("Cleaned %lu orphaned tag(s).\n", (unsigned long)cleaned);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Folder commands
// ─────────────────────────────────────────────────────────────────────────────

int cmdFolderCreate(NSString *name, NSString *parentName) {
    // Check if folder already exists
    id existing = findOrCreateFolder(name, NO);
    if (existing) {
        printf("Folder \"%s\" already exists.\n", [name UTF8String]);
        return 0;
    }

    id folder = findOrCreateFolder(name, YES);
    if (!folder) {
        fprintf(stderr, "Error: Could not create folder \"%s\"\n", [name UTF8String]);
        return 1;
    }

    // Set parent if specified
    if (parentName) {
        id parent = findOrCreateFolder(parentName, NO);
        if (!parent) {
            fprintf(stderr, "Error: Parent folder \"%s\" not found\n",
                    [parentName UTF8String]);
            [g_moc rollback];
            return 1;
        }
        ((void (*)(id, SEL, id))objc_msgSend)(
            folder, NSSelectorFromString(@"setParent:"), parent);
    }

    if (!saveContext()) return 1;
    printf("Created folder: \"%s\"", [name UTF8String]);
    if (parentName) printf(" (in \"%s\")", [parentName UTF8String]);
    printf("\n");
    return 0;
}

int cmdFolderDelete(NSString *name) {
    id folder = findOrCreateFolder(name, NO);
    if (!folder) {
        fprintf(stderr, "Error: Folder \"%s\" not found\n", [name UTF8String]);
        return 1;
    }

    // Check if folder has notes
    NSUInteger noteCount = 0;
    SEL countSel = NSSelectorFromString(@"visibleNotesCount");
    if ([folder respondsToSelector:countSel]) {
        noteCount = ((NSUInteger (*)(id, SEL))objc_msgSend)(folder, countSel);
    }
    if (noteCount > 0) {
        fprintf(stderr, "Error: Folder \"%s\" has %lu note(s). Move or delete them first.\n",
                [name UTF8String], (unsigned long)noteCount);
        return 1;
    }

    ((void (*)(id, SEL, BOOL))objc_msgSend)(
        folder, NSSelectorFromString(@"setMarkedForDeletion:"), YES);
    ((void (*)(id, SEL, id))objc_msgSend)(
        folder, NSSelectorFromString(@"updateChangeCountWithReason:"), @"delete");

    if (!saveContext()) return 1;
    printf("Deleted folder: \"%s\"\n", [name UTF8String]);
    return 0;
}

int cmdFolderRename(NSString *oldName, NSString *newName) {
    id folder = findOrCreateFolder(oldName, NO);
    if (!folder) {
        fprintf(stderr, "Error: Folder \"%s\" not found\n", [oldName UTF8String]);
        return 1;
    }

    // Check if new name already exists
    id existing = findOrCreateFolder(newName, NO);
    if (existing) {
        fprintf(stderr, "Error: Folder \"%s\" already exists\n", [newName UTF8String]);
        return 1;
    }

    ((void (*)(id, SEL, id))objc_msgSend)(
        folder, NSSelectorFromString(@"setTitle:"), newName);
    ((void (*)(id, SEL, id))objc_msgSend)(
        folder, NSSelectorFromString(@"updateChangeCountWithReason:"), @"rename");

    if (!saveContext()) return 1;
    printf("Renamed folder: \"%s\" → \"%s\"\n", [oldName UTF8String],
           [newName UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Template commands
// ─────────────────────────────────────────────────────────────────────────────

static NSString *kTemplateFolder = @"Cider Templates";

void cmdTemplatesList(void) {
    NSArray *notes = filteredNotes(kTemplateFolder);
    if (notes.count == 0) {
        printf("No templates found. Create one with: cider templates add\n");
        return;
    }
    printf("Templates (in \"%s\" folder):\n\n", [kTemplateFolder UTF8String]);
    NSUInteger i = 1;
    for (id note in notes) {
        printf("  %lu. %s\n", (unsigned long)i, [noteTitle(note) UTF8String]);
        i++;
    }
    printf("\nTotal: %lu template(s)\n", (unsigned long)notes.count);
}

int cmdTemplatesShow(NSString *name) {
    NSArray *notes = filteredNotes(kTemplateFolder);
    for (id note in notes) {
        NSString *title = noteTitle(note);
        if ([title caseInsensitiveCompare:name] == NSOrderedSame) {
            NSString *raw = noteRawText(note);
            // Skip the title (first line)
            NSRange nlRange = [raw rangeOfString:@"\n"];
            if (nlRange.location != NSNotFound) {
                printf("%s\n", [[raw substringFromIndex:nlRange.location + 1] UTF8String]);
            } else {
                printf("(empty template body)\n");
            }
            return 0;
        }
    }
    fprintf(stderr, "Error: Template \"%s\" not found\n", [name UTF8String]);
    return 1;
}

void cmdTemplatesAdd(void) {
    // Ensure template folder exists
    findOrCreateFolder(kTemplateFolder, YES);
    saveContext();

    cmdNotesAdd(kTemplateFolder);
}

int cmdTemplatesDelete(NSString *name) {
    NSArray *notes = filteredNotes(kTemplateFolder);
    for (id note in notes) {
        NSString *title = noteTitle(note);
        if ([title caseInsensitiveCompare:name] == NSOrderedSame) {
            ((void (*)(id, SEL, id))objc_msgSend)(
                note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"delete");
            ((void (*)(id, SEL, BOOL))objc_msgSend)(
                note, NSSelectorFromString(@"setMarkedForDeletion:"), YES);
            if (!saveContext()) return 1;
            printf("Deleted template: \"%s\"\n", [title UTF8String]);
            return 0;
        }
    }
    fprintf(stderr, "Error: Template \"%s\" not found\n", [name UTF8String]);
    return 1;
}

int cmdNotesAddFromTemplate(NSString *templateName, NSString *targetFolder) {
    // Find the template
    NSArray *templates = filteredNotes(kTemplateFolder);
    id templateNote = nil;
    for (id note in templates) {
        if ([noteTitle(note) caseInsensitiveCompare:templateName] == NSOrderedSame) {
            templateNote = note;
            break;
        }
    }
    if (!templateNote) {
        fprintf(stderr, "Error: Template \"%s\" not found\n", [templateName UTF8String]);
        return 1;
    }

    // Get template body (skip title line)
    NSString *raw = noteRawText(templateNote);
    NSString *body = @"";
    NSRange nlRange = [raw rangeOfString:@"\n"];
    if (nlRange.location != NSNotFound) {
        body = [raw substringFromIndex:nlRange.location + 1];
    }

    // Open in $EDITOR with template content pre-filled
    NSString *tmp = [NSTemporaryDirectory()
                     stringByAppendingPathComponent:@"cider_template.txt"];
    [body writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];

    if (isatty(STDIN_FILENO)) {
        NSString *editor = [[[NSProcessInfo processInfo] environment]
                            objectForKey:@"EDITOR"] ?: @"vi";
        system([[NSString stringWithFormat:@"%@ %@", editor, tmp] UTF8String]);
    }

    NSError *err = nil;
    NSString *content = [NSString stringWithContentsOfFile:tmp
                                                 encoding:NSUTF8StringEncoding
                                                    error:&err];
    [[NSFileManager defaultManager] removeItemAtPath:tmp error:nil];

    if (!content || [[content stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]] length] == 0) {
        printf("Aborted: empty note.\n");
        return 1;
    }

    id folder = targetFolder
        ? findOrCreateFolder(targetFolder, YES)
        : defaultFolder();
    if (!folder) {
        fprintf(stderr, "Error: Could not find or create folder\n");
        return 1;
    }
    id account = [folder valueForKey:@"account"];

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

    id noteDataEntity = [NSEntityDescription
        insertNewObjectForEntityForName:@"ICNoteData"
                 inManagedObjectContext:g_moc];
    [newNote setValue:noteDataEntity forKey:@"noteData"];

    id mergeStr = noteMergeableString(newNote);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string for new note\n");
        [g_moc rollback];
        return 1;
    }
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"insertString:atIndex:"),
        content, (NSUInteger)0);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(
        newNote, NSSelectorFromString(@"saveNoteData"));
    ((void (*)(id, SEL))objc_msgSend)(
        newNote, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    if (saveContext()) {
        printf("Created note from template \"%s\": \"%s\"\n",
               [templateName UTF8String],
               [noteTitle(newNote) UTF8String]);
        return 0;
    }
    fprintf(stderr, "Error: Failed to save new note\n");
    return 1;
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

// ─────────────────────────────────────────────────────────────────────────────
// Attachment helpers
// ─────────────────────────────────────────────────────────────────────────────

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
        [ordered addObject:attID ?: (id)[NSNull null]];
    }
    return ordered;
}

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

// ─────────────────────────────────────────────────────────────────────────────
// Attachment commands
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesAttachments(NSUInteger idx, BOOL jsonOut) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));
    NSString *raw = noteRawText(note);

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

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string for note\n");
        return;
    }
    NSUInteger textLen = ((NSUInteger (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"length"));

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

    NSURL *fileURL = [NSURL fileURLWithPath:absPath];
    id attachment = ((id (*)(id, SEL, id))objc_msgSend)(
        note, NSSelectorFromString(@"addAttachmentWithFileURL:"), fileURL);
    if (!attachment) {
        fprintf(stderr, "Error: addAttachmentWithFileURL: returned nil\n");
        return;
    }

    NSString *attID = ((id (*)(id, SEL))objc_msgSend)(
        attachment, NSSelectorFromString(@"identifier"));
    NSString *attUTI = ((id (*)(id, SEL))objc_msgSend)(
        attachment, NSSelectorFromString(@"typeUTI"));

    Class TTAttClass = NSClassFromString(@"ICTTAttachment");
    id ttAtt = [[TTAttClass alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(ttAtt, NSSelectorFromString(@"setAttachmentIdentifier:"), attID);
    ((void (*)(id, SEL, id))objc_msgSend)(ttAtt, NSSelectorFromString(@"setAttachmentUTI:"), attUTI);

    unichar marker = ATTACHMENT_MARKER;
    NSString *markerStr = [NSString stringWithCharacters:&marker length:1];
    NSDictionary *attrs = @{@"NSAttachment": ttAtt};
    NSAttributedString *attAttrStr = [[NSAttributedString alloc] initWithString:markerStr attributes:attrs];

    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"insertAttributedString:atIndex:"), attAttrStr, position);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
    if (!saveContext()) {
        fprintf(stderr, "Error: Failed to save attachment\n");
        return;
    }

    NSString *t = noteTitle(note);
    printf("✓ Attachment inserted at position %lu in \"%s\" (id: %s)\n",
           (unsigned long)position, [t UTF8String], [attID UTF8String]);
}

void cmdNotesDetach(NSUInteger idx, NSUInteger attIdx) {
    id note = noteAtIndex(idx, nil);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

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

    if (attIdx >= markerPositions.count) {
        fprintf(stderr, "Error: Attachment index %lu out of range (note has %lu inline attachment(s))\n",
                (unsigned long)(attIdx + 1), (unsigned long)markerPositions.count);
        return;
    }

    NSUInteger charPos = [markerPositions[attIdx] unsignedIntegerValue];

    NSArray *orderedIDs = attachmentOrderFromCRDT(note);
    NSString *targetAttID = nil;
    if (orderedIDs && attIdx < orderedIDs.count) {
        id val = orderedIDs[attIdx];
        if (val != [NSNull null]) targetAttID = val;
    }

    NSArray *atts = attachmentsAsArray(noteVisibleAttachments(note));

    NSString *removedName = targetAttID
        ? attachmentNameByID(atts, targetAttID) : @"attachment";

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return;
    }

    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, NSRange))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"deleteCharactersInRange:"),
        NSMakeRange(charPos, 1));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

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

    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
    if (!saveContext()) {
        fprintf(stderr, "Error: Failed to save detachment\n");
        return;
    }

    NSString *t = noteTitle(note);
    printf("✓ Removed attachment %lu (%s) from \"%s\"\n",
           (unsigned long)(attIdx + 1), [removedName UTF8String], [t UTF8String]);
}

// ─────────────────────────────────────────────────────────────────────────────
// Note Links / Backlinks
// ─────────────────────────────────────────────────────────────────────────────

// Extract UUID from tokenContentIdentifier like:
//   applenotes:note/UUID?ownerIdentifier=...
static NSString *uuidFromTokenContentIdentifier(NSString *tci) {
    if (!tci) return nil;
    NSRange noteSlash = [tci rangeOfString:@"applenotes:note/"];
    if (noteSlash.location == NSNotFound) return nil;
    NSString *rest = [tci substringFromIndex:noteSlash.location + noteSlash.length];
    NSRange q = [rest rangeOfString:@"?"];
    if (q.location != NSNotFound) rest = [rest substringToIndex:q.location];
    return [rest uppercaseString];
}

// Get outgoing link info for a note: returns array of dicts
// Each dict: {displayText, targetIdentifier, targetTitle, targetIndex}
static NSArray *outgoingLinks(id note) {
    SEL sel = NSSelectorFromString(@"allNoteTextInlineAttachments");
    if (![note respondsToSelector:sel]) return @[];
    id inlineAtts = ((id (*)(id, SEL))objc_msgSend)(note, sel);
    if (!inlineAtts || [inlineAtts count] == 0) return @[];

    NSMutableArray *links = [NSMutableArray array];
    for (id att in inlineAtts) {
        BOOL isLink = (BOOL)((NSInteger (*)(id, SEL))objc_msgSend)(
            att, NSSelectorFromString(@"isLinkAttachment"));
        if (!isLink) continue;

        NSString *displayText = ((id (*)(id, SEL))objc_msgSend)(
            att, NSSelectorFromString(@"altText"));
        NSString *tci = ((id (*)(id, SEL))objc_msgSend)(
            att, NSSelectorFromString(@"tokenContentIdentifier"));
        NSString *targetUUID = uuidFromTokenContentIdentifier(tci);

        NSMutableDictionary *info = [NSMutableDictionary dictionary];
        info[@"displayText"] = displayText ?: @"(unknown)";
        info[@"targetIdentifier"] = targetUUID ?: @"";

        if (targetUUID) {
            id target = findNoteByIdentifier(targetUUID);
            if (target) {
                info[@"targetTitle"] = noteTitle(target);
                // Find index in global list
                NSArray *all = filteredNotes(nil);
                for (NSUInteger i = 0; i < all.count; i++) {
                    if (all[i] == target) {
                        info[@"targetIndex"] = @(i + 1);
                        break;
                    }
                }
            } else {
                info[@"targetTitle"] = @"(deleted or inaccessible)";
            }
        }
        [links addObject:info];
    }
    return links;
}

void cmdNotesLinks(NSUInteger idx, NSString *folder, BOOL jsonOut) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found.\n", (unsigned long)idx);
        return;
    }

    NSArray *links = outgoingLinks(note);

    if (jsonOut) {
        printf("[");
        for (NSUInteger i = 0; i < links.count; i++) {
            NSDictionary *l = links[i];
            printf("%s{\"displayText\":\"%s\",\"targetTitle\":\"%s\"",
                   i > 0 ? "," : "",
                   [jsonEscapeString(l[@"displayText"]) UTF8String],
                   [jsonEscapeString(l[@"targetTitle"] ?: @"") UTF8String]);
            if (l[@"targetIndex"])
                printf(",\"targetIndex\":%ld", (long)[l[@"targetIndex"] integerValue]);
            if ([l[@"targetIdentifier"] length] > 0)
                printf(",\"targetIdentifier\":\"%s\"",
                       [jsonEscapeString(l[@"targetIdentifier"]) UTF8String]);
            printf("}");
        }
        printf("]\n");
        return;
    }

    NSString *title = noteTitle(note);
    if (links.count == 0) {
        printf("No outgoing links in \"%s\".\n", [title UTF8String]);
        return;
    }

    printf("Outgoing links from \"%s\":\n\n", [title UTF8String]);
    for (NSUInteger i = 0; i < links.count; i++) {
        NSDictionary *l = links[i];
        NSString *display = l[@"displayText"];
        NSString *target = l[@"targetTitle"];
        NSNumber *tIdx = l[@"targetIndex"];
        if (tIdx) {
            printf("  %lu. \"%s\" → \"%s\" (#%ld)\n",
                   (unsigned long)(i + 1), [display UTF8String],
                   [target UTF8String], (long)[tIdx integerValue]);
        } else if (target) {
            printf("  %lu. \"%s\" → %s\n",
                   (unsigned long)(i + 1), [display UTF8String],
                   [target UTF8String]);
        } else {
            printf("  %lu. \"%s\" → (unresolved)\n",
                   (unsigned long)(i + 1), [display UTF8String]);
        }
    }
    printf("\nTotal: %lu link(s)\n", (unsigned long)links.count);
}

void cmdNotesBacklinks(NSUInteger idx, NSString *folder, BOOL jsonOut) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found.\n", (unsigned long)idx);
        return;
    }

    NSString *myIdentifier = noteIdentifier(note);
    if (!myIdentifier) {
        fprintf(stderr, "Error: Could not get identifier for note %lu.\n", (unsigned long)idx);
        return;
    }

    NSString *title = noteTitle(note);
    NSArray *all = fetchAllNotes();
    NSMutableArray *backlinks = [NSMutableArray array];

    for (id other in all) {
        if (other == note) continue;
        SEL sel = NSSelectorFromString(@"allNoteTextInlineAttachments");
        if (![other respondsToSelector:sel]) continue;
        id inlineAtts = ((id (*)(id, SEL))objc_msgSend)(other, sel);
        if (!inlineAtts || [inlineAtts count] == 0) continue;

        for (id att in inlineAtts) {
            BOOL isLink = (BOOL)((NSInteger (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"isLinkAttachment"));
            if (!isLink) continue;

            NSString *tci = ((id (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"tokenContentIdentifier"));
            NSString *targetUUID = uuidFromTokenContentIdentifier(tci);
            if (targetUUID && [targetUUID caseInsensitiveCompare:myIdentifier] == NSOrderedSame) {
                NSString *otherTitle = noteTitle(other);
                // Find index
                NSArray *listed = filteredNotes(nil);
                NSNumber *otherIdx = nil;
                for (NSUInteger i = 0; i < listed.count; i++) {
                    if (listed[i] == other) {
                        otherIdx = @(i + 1);
                        break;
                    }
                }
                [backlinks addObject:@{
                    @"title": otherTitle,
                    @"index": otherIdx ?: [NSNull null],
                    @"identifier": noteIdentifier(other) ?: @""
                }];
                break; // one backlink per note
            }
        }
    }

    if (jsonOut) {
        printf("[");
        for (NSUInteger i = 0; i < backlinks.count; i++) {
            NSDictionary *bl = backlinks[i];
            printf("%s{\"title\":\"%s\"",
                   i > 0 ? "," : "",
                   [jsonEscapeString(bl[@"title"]) UTF8String]);
            if (bl[@"index"] != [NSNull null])
                printf(",\"index\":%ld", (long)[bl[@"index"] integerValue]);
            printf("}");
        }
        printf("]\n");
        return;
    }

    if (backlinks.count == 0) {
        printf("No notes link to \"%s\".\n", [title UTF8String]);
        return;
    }

    printf("Notes linking to \"%s\":\n\n", [title UTF8String]);
    for (NSUInteger i = 0; i < backlinks.count; i++) {
        NSDictionary *bl = backlinks[i];
        if (bl[@"index"] != [NSNull null]) {
            printf("  %lu. \"%s\" (#%ld)\n",
                   (unsigned long)(i + 1),
                   [bl[@"title"] UTF8String],
                   (long)[bl[@"index"] integerValue]);
        } else {
            printf("  %lu. \"%s\"\n",
                   (unsigned long)(i + 1), [bl[@"title"] UTF8String]);
        }
    }
    printf("\nTotal: %lu note(s) link here\n", (unsigned long)backlinks.count);
}

void cmdNotesBacklinksAll(BOOL jsonOut) {
    NSArray *all = fetchAllNotes();
    // Build a map: noteIdentifier → {title, outgoing links}
    NSMutableDictionary *linkMap = [NSMutableDictionary dictionary];

    for (id note in all) {
        SEL sel = NSSelectorFromString(@"allNoteTextInlineAttachments");
        if (![note respondsToSelector:sel]) continue;
        id inlineAtts = ((id (*)(id, SEL))objc_msgSend)(note, sel);
        if (!inlineAtts || [inlineAtts count] == 0) continue;

        NSString *srcId = noteIdentifier(note);
        NSString *srcTitle = noteTitle(note);
        if (!srcId) continue;

        for (id att in inlineAtts) {
            BOOL isLink = (BOOL)((NSInteger (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"isLinkAttachment"));
            if (!isLink) continue;

            NSString *tci = ((id (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"tokenContentIdentifier"));
            NSString *targetUUID = uuidFromTokenContentIdentifier(tci);
            if (!targetUUID) continue;

            NSString *displayText = ((id (*)(id, SEL))objc_msgSend)(
                att, NSSelectorFromString(@"altText"));

            if (!linkMap[srcId]) {
                linkMap[srcId] = [@{@"title": srcTitle, @"links": [NSMutableArray array]} mutableCopy];
            }
            [linkMap[srcId][@"links"] addObject:@{
                @"displayText": displayText ?: @"(unknown)",
                @"targetIdentifier": targetUUID
            }];
        }
    }

    if (jsonOut) {
        printf("{");
        BOOL first = YES;
        for (NSString *srcId in linkMap) {
            NSDictionary *info = linkMap[srcId];
            if (!first) printf(",");
            first = NO;
            printf("\"%s\":{\"title\":\"%s\",\"links\":[",
                   [jsonEscapeString(info[@"title"]) UTF8String],
                   [jsonEscapeString(info[@"title"]) UTF8String]);
            NSArray *links = info[@"links"];
            for (NSUInteger i = 0; i < links.count; i++) {
                NSDictionary *l = links[i];
                id target = findNoteByIdentifier(l[@"targetIdentifier"]);
                NSString *targetTitle = target ? noteTitle(target) : @"(unresolved)";
                printf("%s{\"displayText\":\"%s\",\"targetTitle\":\"%s\"}",
                       i > 0 ? "," : "",
                       [jsonEscapeString(l[@"displayText"]) UTF8String],
                       [jsonEscapeString(targetTitle) UTF8String]);
            }
            printf("]}");
        }
        printf("}\n");
        return;
    }

    if (linkMap.count == 0) {
        printf("No note-to-note links found.\n");
        return;
    }

    printf("Note link graph (%lu notes with links):\n\n",
           (unsigned long)linkMap.count);
    for (NSString *srcId in linkMap) {
        NSDictionary *info = linkMap[srcId];
        printf("  \"%s\":\n", [info[@"title"] UTF8String]);
        for (NSDictionary *l in info[@"links"]) {
            id target = findNoteByIdentifier(l[@"targetIdentifier"]);
            NSString *targetTitle = target ? noteTitle(target) : @"(unresolved)";
            printf("    → \"%s\" (as \"%s\")\n",
                   [targetTitle UTF8String],
                   [l[@"displayText"] UTF8String]);
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Create Note Link
// ─────────────────────────────────────────────────────────────────────────────

int cmdNotesLink(NSUInteger idx, NSString *targetTitle, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found.\n", (unsigned long)idx);
        return 1;
    }

    // Find the target note by title
    NSArray *all = fetchAllNotes();
    id targetNote = nil;
    for (id n in all) {
        NSString *t = noteTitle(n);
        if ([t caseInsensitiveCompare:targetTitle] == NSOrderedSame) {
            targetNote = n;
            break;
        }
    }
    if (!targetNote) {
        fprintf(stderr, "Error: Target note \"%s\" not found\n", [targetTitle UTF8String]);
        return 1;
    }
    if (targetNote == note) {
        fprintf(stderr, "Error: Cannot link a note to itself\n");
        return 1;
    }

    // Create ICInlineAttachment for the link
    NSString *attID = [[NSUUID UUID] UUIDString];
    NSString *targetID = noteIdentifier(targetNote);
    id account = [note valueForKey:@"account"];
    NSString *ownerID = @"";
    @try {
        ownerID = ((id (*)(id, SEL))objc_msgSend)(account,
            NSSelectorFromString(@"userRecordName")) ?: @"";
    } @catch (NSException *e) {}
    NSString *tokenContent = [NSString stringWithFormat:@"applenotes:note/%@?ownerIdentifier=%@",
                              [targetID lowercaseString], ownerID];
    NSString *displayText = noteTitle(targetNote);

    @try {
        Class inlineClass = NSClassFromString(@"ICInlineAttachment");
        SEL newAttSel = NSSelectorFromString(
            @"newAttachmentWithIdentifier:typeUTI:altText:tokenContentIdentifier:note:parentAttachment:");
        ((id (*)(Class, SEL, id, id, id, id, id, id))objc_msgSend)(
            inlineClass, newAttSel,
            attID,
            @"com.apple.notes.inlinetextattachment.link",
            displayText,
            tokenContent,
            note,
            nil);
    } @catch (NSException *e) {
        fprintf(stderr, "Error creating link attachment: %s\n", [[e reason] UTF8String]);
        return 1;
    }

    // Insert U+FFFC with NSAttachment into mergeableString
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return 1;
    }

    // Create ICTTAttachment for the link
    id ttAtt = [[NSClassFromString(@"ICTTAttachment") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(
        ttAtt, NSSelectorFromString(@"setAttachmentIdentifier:"), attID);
    ((void (*)(id, SEL, id))objc_msgSend)(
        ttAtt, NSSelectorFromString(@"setAttachmentUTI:"),
        @"com.apple.notes.inlinetextattachment.link");

    // Build: newline + U+FFFC (link marker)
    unichar fffc = 0xFFFC;
    NSString *marker = [NSString stringWithFormat:@"\n%C", fffc];
    NSAttributedString *linkStr = [[NSAttributedString alloc]
        initWithString:marker attributes:@{@"NSAttachment": ttAtt}];

    // Insert at end
    NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"attributedString"));
    NSUInteger insertPos = [(NSAttributedString *)attrStr length];

    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"insertAttributedString:atIndex:"),
        linkStr, insertPos);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    if (!saveContext()) return 1;
    printf("Linked note %lu → \"%s\"\n", (unsigned long)idx, [displayText UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Watch / Events
// ─────────────────────────────────────────────────────────────────────────────

void cmdNotesWatch(NSString *folder, NSTimeInterval interval, BOOL jsonOutput) {
    // Handle SIGINT gracefully
    signal(SIGINT, SIG_DFL);

    printf("Watching for note changes");
    if (folder) printf(" in \"%s\"", [folder UTF8String]);
    printf(" (interval: %.0fs, Ctrl-C to stop)\n\n", interval);
    fflush(stdout);

    // Build initial snapshot: {noteURI → {title, modDate}}
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    NSArray *notes = filteredNotes(folder);
    for (id note in notes) {
        NSString *uri = noteURIString(note);
        NSDate *mod = [note valueForKey:@"modificationDate"];
        NSString *title = noteTitle(note);
        snapshot[uri] = @{@"title": title, @"modified": mod ?: [NSDate date]};
    }

    while (1) {
        [NSThread sleepForTimeInterval:interval];

        // Re-fetch notes (need to refresh the context)
        @try {
            [g_moc refreshAllObjects];
        } @catch (NSException *e) {
            // refreshAllObjects may not be available
        }

        NSArray *current = filteredNotes(folder);
        NSMutableDictionary *newSnapshot = [NSMutableDictionary dictionary];
        NSMutableSet *seenURIs = [NSMutableSet set];

        NSDateFormatter *timeFmt = [[NSDateFormatter alloc] init];
        timeFmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";

        for (id note in current) {
            NSString *uri = noteURIString(note);
            NSDate *mod = [note valueForKey:@"modificationDate"];
            NSString *title = noteTitle(note);
            [seenURIs addObject:uri];
            newSnapshot[uri] = @{@"title": title, @"modified": mod ?: [NSDate date]};

            NSDictionary *prev = snapshot[uri];
            if (!prev) {
                // New note
                NSString *time = [timeFmt stringFromDate:mod ?: [NSDate date]];
                if (jsonOutput) {
                    printf("{\"event\":\"created\",\"title\":\"%s\",\"time\":\"%s\"}\n",
                           [jsonEscapeString(title) UTF8String],
                           [time UTF8String]);
                } else {
                    printf("[%s] created: \"%s\"\n", [time UTF8String], [title UTF8String]);
                }
                fflush(stdout);
            } else {
                NSDate *prevMod = prev[@"modified"];
                if (mod && prevMod && [mod compare:prevMod] != NSOrderedSame) {
                    // Modified note
                    NSString *time = [timeFmt stringFromDate:mod];
                    if (jsonOutput) {
                        printf("{\"event\":\"modified\",\"title\":\"%s\",\"time\":\"%s\"}\n",
                               [jsonEscapeString(title) UTF8String],
                               [time UTF8String]);
                    } else {
                        printf("[%s] modified: \"%s\"\n", [time UTF8String], [title UTF8String]);
                    }
                    fflush(stdout);
                }
            }
        }

        // Check for deleted notes
        for (NSString *uri in snapshot) {
            if (![seenURIs containsObject:uri]) {
                NSDictionary *prev = snapshot[uri];
                NSString *title = prev[@"title"];
                NSString *time = [timeFmt stringFromDate:[NSDate date]];
                if (jsonOutput) {
                    printf("{\"event\":\"deleted\",\"title\":\"%s\",\"time\":\"%s\"}\n",
                           [jsonEscapeString(title) UTF8String],
                           [time UTF8String]);
                } else {
                    printf("[%s] deleted: \"%s\"\n", [time UTF8String], [title UTF8String]);
                }
                fflush(stdout);
            }
        }

        snapshot = newSnapshot;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Checklists
// ─────────────────────────────────────────────────────────────────────────────

// Walk the attributed string and collect checklist items by paragraph.
// Each item: {text, done (BOOL as NSNumber), index (1-based NSNumber), range (NSValue of NSRange)}
// We walk by paragraph (newline-delimited) to avoid splitting items across attribute runs.
static NSArray *collectChecklistItems(id note) {
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) return @[];

    NSAttributedString *attrStr = nil;
    @try {
        attrStr = ((id (*)(id, SEL))objc_msgSend)(
            mergeStr, NSSelectorFromString(@"attributedString"));
    }
    @catch (NSException *e) { return @[]; }
    if (!attrStr) return @[];

    NSMutableArray *items = [NSMutableArray array];
    NSString *fullStr = [attrStr string];
    NSUInteger len = [fullStr length];
    int itemNum = 0;

    // Walk paragraph by paragraph
    NSUInteger paraStart = 0;
    while (paraStart < len) {
        NSRange nlRange = [fullStr rangeOfString:@"\n"
                           options:0 range:NSMakeRange(paraStart, len - paraStart)];
        NSUInteger paraEnd = (nlRange.location != NSNotFound)
            ? nlRange.location + 1 : len;
        NSRange paraRange = NSMakeRange(paraStart, paraEnd - paraStart);

        // Check if this paragraph is a checklist item by examining its first character
        NSDictionary *attrs = [attrStr attributesAtIndex:paraStart effectiveRange:NULL];
        id style = attrs[@"TTStyle"];
        if (style) {
            NSInteger styleNum = ((NSInteger (*)(id, SEL))objc_msgSend)(
                style, NSSelectorFromString(@"style"));
            if (styleNum == 103) {
                NSString *text = [fullStr substringWithRange:paraRange];
                if ([text hasSuffix:@"\n"])
                    text = [text substringToIndex:text.length - 1];

                id todo = ((id (*)(id, SEL))objc_msgSend)(
                    style, NSSelectorFromString(@"todo"));
                NSInteger doneRaw = todo
                    ? ((NSInteger (*)(id, SEL))objc_msgSend)(todo, NSSelectorFromString(@"done"))
                    : 0;
                BOOL done = (doneRaw != 0);

                itemNum++;
                [items addObject:@{
                    @"text": text,
                    @"done": @(done),
                    @"index": @(itemNum),
                    @"range": [NSValue valueWithRange:paraRange]
                }];
            }
        }
        paraStart = paraEnd;
    }
    return items;
}

void cmdNotesChecklist(NSUInteger idx, NSString *folder, BOOL jsonOut, BOOL summary,
                       NSString *addText) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    // Handle --add: append a native checklist item with paragraph style 103
    if (addText) {
        id mergeStr = noteMergeableString(note);
        if (!mergeStr) {
            fprintf(stderr, "Error: Could not get mergeable string\n");
            return;
        }

        // Create ICTTTodo with NSUUID
        NSUUID *todoUUID = [NSUUID UUID];
        id newTodo = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(
            [NSClassFromString(@"ICTTTodo") alloc],
            NSSelectorFromString(@"initWithIdentifier:done:"),
            todoUUID, (NSInteger)0);

        // Create ICTTParagraphStyle with style=103
        id paraStyle = [[NSClassFromString(@"ICTTParagraphStyle") alloc] init];
        ((void (*)(id, SEL, NSInteger))objc_msgSend)(
            paraStyle, NSSelectorFromString(@"setStyle:"), (NSInteger)103);
        ((void (*)(id, SEL, id))objc_msgSend)(
            paraStyle, NSSelectorFromString(@"setTodo:"), newTodo);
        ((void (*)(id, SEL, id))objc_msgSend)(
            paraStyle, NSSelectorFromString(@"setUuid:"), [NSUUID UUID]);

        // Build attributed string with TTStyle for the checklist item
        NSString *itemStr = [NSString stringWithFormat:@"%@\n", addText];
        NSAttributedString *styledStr = [[NSAttributedString alloc]
            initWithString:itemStr attributes:@{@"TTStyle": paraStyle}];

        // Get insertion point (end of text)
        NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
            mergeStr, NSSelectorFromString(@"attributedString"));
        NSUInteger insertPos = [(NSAttributedString *)attrStr length];

        // Insert via mergeableString
        ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
        ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
            mergeStr, NSSelectorFromString(@"insertAttributedString:atIndex:"),
            styledStr, insertPos);
        ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
        ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

        ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
        ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

        if (!saveContext()) return;
        printf("Added checklist item: \"%s\"\n", [addText UTF8String]);
        return;
    }

    NSArray *items = collectChecklistItems(note);
    NSString *title = noteTitle(note);

    if (items.count == 0) {
        if (summary) {
            if (jsonOut) {
                printf("{\"title\":\"%s\",\"checked\":0,\"total\":0}\n",
                       [jsonEscapeString(title) UTF8String]);
            } else {
                printf("0/0 items complete\n");
            }
        } else if (jsonOut) {
            printf("{\"title\":\"%s\",\"items\":[],\"checked\":0,\"total\":0}\n",
                   [jsonEscapeString(title) UTF8String]);
        } else {
            printf("No checklist items in \"%s\".\n", [title UTF8String]);
        }
        return;
    }

    int checked = 0, total = (int)items.count;
    for (NSDictionary *item in items) {
        if ([item[@"done"] boolValue]) checked++;
    }

    if (summary) {
        if (jsonOut) {
            printf("{\"title\":\"%s\",\"checked\":%d,\"total\":%d}\n",
                   [jsonEscapeString(title) UTF8String], checked, total);
        } else {
            printf("%d/%d items complete\n", checked, total);
        }
        return;
    }

    if (jsonOut) {
        printf("{\"title\":\"%s\",\"items\":[", [jsonEscapeString(title) UTF8String]);
        for (NSUInteger i = 0; i < items.count; i++) {
            NSDictionary *item = items[i];
            printf("%s{\"index\":%d,\"text\":\"%s\",\"done\":%s}",
                   i > 0 ? "," : "",
                   [item[@"index"] intValue],
                   [jsonEscapeString(item[@"text"]) UTF8String],
                   [item[@"done"] boolValue] ? "true" : "false");
        }
        printf("],\"checked\":%d,\"total\":%d}\n", checked, total);
        return;
    }

    printf("Checklist items in \"%s\":\n\n", [title UTF8String]);
    for (NSDictionary *item in items) {
        BOOL done = [item[@"done"] boolValue];
        printf("  %d. [%s] %s\n",
               [item[@"index"] intValue],
               done ? "x" : " ",
               [item[@"text"] UTF8String]);
    }
    printf("\nSummary: %d/%d complete\n", checked, total);
}

int cmdNotesCheck(NSUInteger idx, NSUInteger itemNum, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSArray *items = collectChecklistItems(note);
    if (items.count == 0) {
        fprintf(stderr, "Error: No checklist items in note %lu\n", (unsigned long)idx);
        return 1;
    }

    // Find item by 1-based number
    NSDictionary *target = nil;
    for (NSDictionary *item in items) {
        if ([item[@"index"] unsignedIntegerValue] == itemNum) {
            target = item;
            break;
        }
    }
    if (!target) {
        fprintf(stderr, "Error: Checklist item %lu not found (note has %lu items)\n",
                (unsigned long)itemNum, (unsigned long)items.count);
        return 1;
    }

    if ([target[@"done"] boolValue]) {
        printf("Item %lu is already checked.\n", (unsigned long)itemNum);
        return 0;
    }

    // Toggle the done state via the mergeableString
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return 1;
    }

    NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"attributedString"));
    NSRange range = [target[@"range"] rangeValue];

    // Get the current style and create a new todo with done=1
    NSDictionary *attrs = [attrStr attributesAtIndex:range.location effectiveRange:NULL];
    id style = attrs[@"TTStyle"];
    id todo = ((id (*)(id, SEL))objc_msgSend)(style, NSSelectorFromString(@"todo"));
    NSString *uuid = ((id (*)(id, SEL))objc_msgSend)(todo, NSSelectorFromString(@"uuid"));

    // Create new todo with done=YES
    Class todoClass = [todo class];
    id newTodo = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(
        [todoClass alloc], NSSelectorFromString(@"initWithIdentifier:done:"),
        uuid, (NSInteger)1);

    // Create new style with the updated todo
    Class styleClass = [style class];
    id newStyle = [[styleClass alloc] init];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(
        newStyle, NSSelectorFromString(@"setStyle:"), (NSInteger)103);
    ((void (*)(id, SEL, id))objc_msgSend)(
        newStyle, NSSelectorFromString(@"setTodo:"), newTodo);

    // Give the new style a UUID
    ((void (*)(id, SEL, id))objc_msgSend)(
        newStyle, NSSelectorFromString(@"setUuid:"), [NSUUID UUID]);

    // Apply the new style attribute (setAttributes:range: — NOT addAttribute:)
    NSDictionary *attrDict = @{ @"TTStyle": newStyle };
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSRange))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"setAttributes:range:"),
        attrDict, range);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    if (!saveContext()) return 1;
    printf("Checked item %lu: \"%s\"\n", (unsigned long)itemNum,
           [target[@"text"] UTF8String]);
    return 0;
}

int cmdNotesUncheck(NSUInteger idx, NSUInteger itemNum, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSArray *items = collectChecklistItems(note);
    if (items.count == 0) {
        fprintf(stderr, "Error: No checklist items in note %lu\n", (unsigned long)idx);
        return 1;
    }

    NSDictionary *target = nil;
    for (NSDictionary *item in items) {
        if ([item[@"index"] unsignedIntegerValue] == itemNum) {
            target = item;
            break;
        }
    }
    if (!target) {
        fprintf(stderr, "Error: Checklist item %lu not found (note has %lu items)\n",
                (unsigned long)itemNum, (unsigned long)items.count);
        return 1;
    }

    if (![target[@"done"] boolValue]) {
        printf("Item %lu is already unchecked.\n", (unsigned long)itemNum);
        return 0;
    }

    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return 1;
    }

    NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"attributedString"));
    NSRange range = [target[@"range"] rangeValue];

    NSDictionary *attrs = [attrStr attributesAtIndex:range.location effectiveRange:NULL];
    id style = attrs[@"TTStyle"];
    id todo = ((id (*)(id, SEL))objc_msgSend)(style, NSSelectorFromString(@"todo"));
    NSString *uuid = ((id (*)(id, SEL))objc_msgSend)(todo, NSSelectorFromString(@"uuid"));

    // Create new todo with done=NO
    Class todoClass = [todo class];
    id newTodo = ((id (*)(id, SEL, id, NSInteger))objc_msgSend)(
        [todoClass alloc], NSSelectorFromString(@"initWithIdentifier:done:"),
        uuid, (NSInteger)0);

    Class styleClass = [style class];
    id newStyle = [[styleClass alloc] init];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(
        newStyle, NSSelectorFromString(@"setStyle:"), (NSInteger)103);
    ((void (*)(id, SEL, id))objc_msgSend)(
        newStyle, NSSelectorFromString(@"setTodo:"), newTodo);

    // Give the new style a UUID
    ((void (*)(id, SEL, id))objc_msgSend)(
        newStyle, NSSelectorFromString(@"setUuid:"), [NSUUID UUID]);

    // Apply the new style attribute (setAttributes:range: — NOT addAttribute:)
    NSDictionary *uncheckAttrDict = @{ @"TTStyle": newStyle };
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSRange))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"setAttributes:range:"),
        uncheckAttrDict, range);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr, NSSelectorFromString(@"generateIdsForLocalChanges"));

    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"saveNoteData"));
    ((void (*)(id, SEL))objc_msgSend)(note, NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));

    if (!saveContext()) return 1;
    printf("Unchecked item %lu: \"%s\"\n", (unsigned long)itemNum,
           [target[@"text"] UTF8String]);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Tables
// ─────────────────────────────────────────────────────────────────────────────

// Find table attachments for a note
static NSArray *tableAttachmentsForNote(id note) {
    NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICAttachment"];
    req.predicate = [NSPredicate predicateWithFormat:
        @"typeUTI == 'com.apple.notes.table' AND note == %@", note];
    NSArray *results = [g_moc executeFetchRequest:req error:nil];
    return results ?: @[];
}

void cmdNotesTable(NSUInteger idx, NSString *folder, NSUInteger tableIdx,
                   BOOL jsonOut, BOOL csvOut, BOOL listTables, BOOL headersOnly,
                   NSInteger rowNum) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSArray *tableAtts = tableAttachmentsForNote(note);
    NSString *title = noteTitle(note);

    if (tableAtts.count == 0) {
        if (jsonOut) {
            printf("{\"error\":\"No tables in note\"}\n");
        } else {
            printf("No tables in \"%s\".\n", [title UTF8String]);
        }
        return;
    }

    // --list: show all tables with row/col counts
    if (listTables) {
        if (jsonOut) {
            printf("[");
            for (NSUInteger i = 0; i < tableAtts.count; i++) {
                id att = tableAtts[i];
                id tm = ((id (*)(id, SEL))objc_msgSend)(att, NSSelectorFromString(@"tableModel"));
                id tbl = ((id (*)(id, SEL))objc_msgSend)(tm, NSSelectorFromString(@"table"));
                NSUInteger rows = ((NSUInteger (*)(id, SEL))objc_msgSend)(tbl, NSSelectorFromString(@"rowCount"));
                NSUInteger cols = ((NSUInteger (*)(id, SEL))objc_msgSend)(tbl, NSSelectorFromString(@"columnCount"));
                printf("%s{\"index\":%lu,\"rows\":%lu,\"columns\":%lu}",
                       i > 0 ? "," : "",
                       (unsigned long)i, (unsigned long)rows, (unsigned long)cols);
            }
            printf("]\n");
        } else {
            printf("Tables in \"%s\":\n\n", [title UTF8String]);
            for (NSUInteger i = 0; i < tableAtts.count; i++) {
                id att = tableAtts[i];
                id tm = ((id (*)(id, SEL))objc_msgSend)(att, NSSelectorFromString(@"tableModel"));
                id tbl = ((id (*)(id, SEL))objc_msgSend)(tm, NSSelectorFromString(@"table"));
                NSUInteger rows = ((NSUInteger (*)(id, SEL))objc_msgSend)(tbl, NSSelectorFromString(@"rowCount"));
                NSUInteger cols = ((NSUInteger (*)(id, SEL))objc_msgSend)(tbl, NSSelectorFromString(@"columnCount"));
                printf("  %lu. %lu rows x %lu columns\n",
                       (unsigned long)i, (unsigned long)rows, (unsigned long)cols);
            }
            printf("\nTotal: %lu table(s)\n", (unsigned long)tableAtts.count);
        }
        return;
    }

    // Select table by index
    if (tableIdx >= tableAtts.count) {
        fprintf(stderr, "Error: Table index %lu out of range (note has %lu table(s))\n",
                (unsigned long)tableIdx, (unsigned long)tableAtts.count);
        return;
    }

    id att = tableAtts[tableIdx];
    id tableModel = ((id (*)(id, SEL))objc_msgSend)(att, NSSelectorFromString(@"tableModel"));
    if (!tableModel) {
        fprintf(stderr, "Error: Could not get table model\n");
        return;
    }
    id table = ((id (*)(id, SEL))objc_msgSend)(tableModel, NSSelectorFromString(@"table"));
    if (!table) {
        fprintf(stderr, "Error: Could not get table data\n");
        return;
    }

    NSUInteger rowCount = ((NSUInteger (*)(id, SEL))objc_msgSend)(table, NSSelectorFromString(@"rowCount"));
    NSUInteger colCount = ((NSUInteger (*)(id, SEL))objc_msgSend)(table, NSSelectorFromString(@"columnCount"));

    if (rowCount == 0 || colCount == 0) {
        printf("Table is empty.\n");
        return;
    }

    // Collect all rows
    NSMutableArray *allRows = [NSMutableArray array];
    for (NSUInteger r = 0; r < rowCount; r++) {
        @try {
            NSArray *strings = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(
                tableModel, NSSelectorFromString(@"stringsAtRow:"), r);
            if (strings) {
                // Pad to colCount
                NSMutableArray *row = [NSMutableArray arrayWithArray:strings];
                while (row.count < colCount) [row addObject:@""];
                [allRows addObject:row];
            }
        } @catch (NSException *e) {
            // Skip bad rows
        }
    }

    if (allRows.count == 0) {
        printf("Table has no readable data.\n");
        return;
    }

    // --headers: just first row
    if (headersOnly) {
        NSArray *headers = allRows[0];
        if (jsonOut) {
            printf("[");
            for (NSUInteger c = 0; c < headers.count; c++) {
                printf("%s\"%s\"", c > 0 ? "," : "",
                       [jsonEscapeString(headers[c]) UTF8String]);
            }
            printf("]\n");
        } else if (csvOut) {
            for (NSUInteger c = 0; c < headers.count; c++) {
                if (c > 0) printf(",");
                NSString *h = headers[c];
                if ([h rangeOfString:@","].location != NSNotFound ||
                    [h rangeOfString:@"\""].location != NSNotFound) {
                    h = [h stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
                    printf("\"%s\"", [h UTF8String]);
                } else {
                    printf("%s", [h UTF8String]);
                }
            }
            printf("\n");
        } else {
            for (NSUInteger c = 0; c < headers.count; c++) {
                printf("%s%s", c > 0 ? " | " : "", [headers[c] UTF8String]);
            }
            printf("\n");
        }
        return;
    }

    // --row N: specific row
    if (rowNum >= 0) {
        if ((NSUInteger)rowNum >= allRows.count) {
            fprintf(stderr, "Error: Row %ld out of range (table has %lu rows)\n",
                    (long)rowNum, (unsigned long)allRows.count);
            return;
        }
        NSArray *row = allRows[(NSUInteger)rowNum];
        if (jsonOut) {
            // Use headers as keys if row 0 exists
            if (rowNum > 0 && allRows.count > 0) {
                NSArray *headers = allRows[0];
                printf("{");
                for (NSUInteger c = 0; c < row.count; c++) {
                    NSString *key = (c < headers.count) ? headers[c] : [NSString stringWithFormat:@"col%lu", (unsigned long)c];
                    printf("%s\"%s\":\"%s\"", c > 0 ? "," : "",
                           [jsonEscapeString(key) UTF8String],
                           [jsonEscapeString(row[c]) UTF8String]);
                }
                printf("}\n");
            } else {
                printf("[");
                for (NSUInteger c = 0; c < row.count; c++) {
                    printf("%s\"%s\"", c > 0 ? "," : "",
                           [jsonEscapeString(row[c]) UTF8String]);
                }
                printf("]\n");
            }
        } else if (csvOut) {
            for (NSUInteger c = 0; c < row.count; c++) {
                if (c > 0) printf(",");
                NSString *val = row[c];
                if ([val rangeOfString:@","].location != NSNotFound ||
                    [val rangeOfString:@"\""].location != NSNotFound) {
                    val = [val stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
                    printf("\"%s\"", [val UTF8String]);
                } else {
                    printf("%s", [val UTF8String]);
                }
            }
            printf("\n");
        } else {
            for (NSUInteger c = 0; c < row.count; c++) {
                printf("%s%s", c > 0 ? " | " : "", [row[c] UTF8String]);
            }
            printf("\n");
        }
        return;
    }

    // Full table output
    if (jsonOut) {
        // Array of objects using row 0 as headers
        NSArray *headers = allRows[0];
        printf("[");
        for (NSUInteger r = 1; r < allRows.count; r++) {
            NSArray *row = allRows[r];
            printf("%s{", r > 1 ? "," : "");
            for (NSUInteger c = 0; c < colCount; c++) {
                NSString *key = (c < headers.count) ? headers[c] : [NSString stringWithFormat:@"col%lu", (unsigned long)c];
                NSString *val = (c < row.count) ? row[c] : @"";
                printf("%s\"%s\":\"%s\"", c > 0 ? "," : "",
                       [jsonEscapeString(key) UTF8String],
                       [jsonEscapeString(val) UTF8String]);
            }
            printf("}");
        }
        printf("]\n");
        return;
    }

    if (csvOut) {
        for (NSUInteger r = 0; r < allRows.count; r++) {
            NSArray *row = allRows[r];
            for (NSUInteger c = 0; c < colCount; c++) {
                if (c > 0) printf(",");
                NSString *val = (c < row.count) ? row[c] : @"";
                if ([val rangeOfString:@","].location != NSNotFound ||
                    [val rangeOfString:@"\""].location != NSNotFound ||
                    [val rangeOfString:@"\n"].location != NSNotFound) {
                    val = [val stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
                    printf("\"%s\"", [val UTF8String]);
                } else {
                    printf("%s", [val UTF8String]);
                }
            }
            printf("\n");
        }
        return;
    }

    // Default: aligned columns with | separators
    // Calculate column widths
    NSMutableArray *widths = [NSMutableArray array];
    for (NSUInteger c = 0; c < colCount; c++) {
        NSUInteger maxW = 0;
        for (NSArray *row in allRows) {
            NSString *val = (c < row.count) ? row[c] : @"";
            if ([val length] > maxW) maxW = [val length];
        }
        if (maxW < 3) maxW = 3;
        [widths addObject:@(maxW)];
    }

    // Print header row
    printf("| ");
    for (NSUInteger c = 0; c < colCount; c++) {
        NSString *val = (c < [allRows[0] count]) ? allRows[0][c] : @"";
        printf("%-*s", (int)[widths[c] unsignedIntegerValue], [val UTF8String]);
        if (c + 1 < colCount) printf(" | ");
    }
    printf(" |\n");

    // Separator
    printf("|");
    for (NSUInteger c = 0; c < colCount; c++) {
        printf("-");
        for (NSUInteger i = 0; i < [widths[c] unsignedIntegerValue]; i++) printf("-");
        printf("-|");
    }
    printf("\n");

    // Data rows
    for (NSUInteger r = 1; r < allRows.count; r++) {
        NSArray *row = allRows[r];
        printf("| ");
        for (NSUInteger c = 0; c < colCount; c++) {
            NSString *val = (c < row.count) ? row[c] : @"";
            printf("%-*s", (int)[widths[c] unsignedIntegerValue], [val UTF8String]);
            if (c + 1 < colCount) printf(" | ");
        }
        printf(" |\n");
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Table creation
// ─────────────────────────────────────────────────────────────────────────────

int cmdNotesTableAdd(NSUInteger idx, NSString *folder, NSArray *rows) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }
    if (rows.count == 0) {
        fprintf(stderr, "Error: No rows provided\n");
        return 1;
    }

    // Parse rows into arrays of cells (pipe-separated)
    NSMutableArray *parsedRows = [NSMutableArray array];
    NSUInteger colCount = 0;
    for (NSString *row in rows) {
        NSArray *cells = [row componentsSeparatedByString:@"|"];
        [parsedRows addObject:cells];
        if (cells.count > colCount) colCount = cells.count;
    }

    // Check if note already has a table — if so, add rows to it
    NSArray *existingTables = tableAttachmentsForNote(note);
    if (existingTables.count > 0) {
        // Add rows to the first existing table
        id att = existingTables[0];
        id tableModel = ((id (*)(id, SEL))objc_msgSend)(att,
            NSSelectorFromString(@"tableModel"));
        id table = ((id (*)(id, SEL))objc_msgSend)(tableModel,
            NSSelectorFromString(@"table"));
        NSUInteger existingRows = ((NSUInteger (*)(id, SEL))objc_msgSend)(table,
            NSSelectorFromString(@"rowCount"));
        NSUInteger existingCols = ((NSUInteger (*)(id, SEL))objc_msgSend)(table,
            NSSelectorFromString(@"columnCount"));

        // Add extra columns if needed
        for (NSUInteger c = existingCols; c < colCount; c++) {
            ((id (*)(id, SEL, NSUInteger))objc_msgSend)(table,
                NSSelectorFromString(@"insertColumnAtIndex:"), c);
        }
        if (colCount < existingCols) colCount = existingCols;

        // Add and populate new rows
        for (NSUInteger r = 0; r < parsedRows.count; r++) {
            NSUInteger newRowIdx = existingRows + r;
            ((id (*)(id, SEL, NSUInteger))objc_msgSend)(table,
                NSSelectorFromString(@"insertRowAtIndex:"), newRowIdx);
            NSArray *cells = parsedRows[r];
            for (NSUInteger c = 0; c < colCount && c < cells.count; c++) {
                NSString *val = [cells[c] stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
                NSAttributedString *cellStr = [[NSAttributedString alloc]
                    initWithString:val];
                ((void (*)(id, SEL, id, NSUInteger, NSUInteger))objc_msgSend)(table,
                    NSSelectorFromString(@"setAttributedString:columnIndex:rowIndex:"),
                    cellStr, c, newRowIdx);
            }
        }

        // Persist
        ((void (*)(id, SEL))objc_msgSend)(tableModel,
            NSSelectorFromString(@"writeMergeableData"));
        ((void (*)(id, SEL))objc_msgSend)(tableModel,
            NSSelectorFromString(@"persistPendingChanges"));
        ((void (*)(id, SEL))objc_msgSend)(note,
            NSSelectorFromString(@"saveNoteData"));
        ((void (*)(id, SEL))objc_msgSend)(note,
            NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
        ((void (*)(id, SEL, id))objc_msgSend)(
            note, NSSelectorFromString(@"updateChangeCountWithReason:"), @"tableEdit");
        if (!saveContext()) return 1;

        printf("Added %lu row(s) to existing table in note %lu\n",
               (unsigned long)parsedRows.count, (unsigned long)idx);
        return 0;
    }

    // Create new table attachment
    id tableAtt = ((id (*)(id, SEL))objc_msgSend)(note,
        NSSelectorFromString(@"addTableAttachment"));
    if (!tableAtt) {
        fprintf(stderr, "Error: Failed to create table attachment\n");
        return 1;
    }

    NSString *tableId = ((id (*)(id, SEL))objc_msgSend)(tableAtt,
        NSSelectorFromString(@"identifier"));
    id tableModel = ((id (*)(id, SEL))objc_msgSend)(tableAtt,
        NSSelectorFromString(@"tableModel"));
    id table = ((id (*)(id, SEL))objc_msgSend)(tableModel,
        NSSelectorFromString(@"table"));

    // Default is 2x2, resize to match our data
    NSUInteger targetRows = parsedRows.count;
    NSUInteger targetCols = colCount;

    // Add rows beyond the default 2
    for (NSUInteger r = 2; r < targetRows; r++) {
        ((id (*)(id, SEL, NSUInteger))objc_msgSend)(table,
            NSSelectorFromString(@"insertRowAtIndex:"), r);
    }
    // Remove extra rows if we need fewer than 2
    if (targetRows < 2) {
        for (NSUInteger r = 2; r > targetRows; r--) {
            ((void (*)(id, SEL, NSUInteger))objc_msgSend)(table,
                NSSelectorFromString(@"removeRowAtIndex:"), r - 1);
        }
    }
    // Add columns beyond the default 2
    for (NSUInteger c = 2; c < targetCols; c++) {
        ((id (*)(id, SEL, NSUInteger))objc_msgSend)(table,
            NSSelectorFromString(@"insertColumnAtIndex:"), c);
    }
    // Remove extra columns if we need fewer than 2
    if (targetCols < 2) {
        for (NSUInteger c = 2; c > targetCols; c--) {
            ((void (*)(id, SEL, NSUInteger))objc_msgSend)(table,
                NSSelectorFromString(@"removeColumnAtIndex:"), c - 1);
        }
    }

    // Populate cells
    for (NSUInteger r = 0; r < targetRows; r++) {
        NSArray *cells = parsedRows[r];
        for (NSUInteger c = 0; c < targetCols && c < cells.count; c++) {
            NSString *val = [cells[c] stringByTrimmingCharactersInSet:
                [NSCharacterSet whitespaceCharacterSet]];
            NSAttributedString *cellStr = [[NSAttributedString alloc]
                initWithString:val];
            ((void (*)(id, SEL, id, NSUInteger, NSUInteger))objc_msgSend)(table,
                NSSelectorFromString(@"setAttributedString:columnIndex:rowIndex:"),
                cellStr, c, r);
        }
    }

    // Persist table CRDT data
    ((void (*)(id, SEL))objc_msgSend)(tableModel,
        NSSelectorFromString(@"writeMergeableData"));
    ((void (*)(id, SEL))objc_msgSend)(tableModel,
        NSSelectorFromString(@"persistPendingChanges"));

    // Insert U+FFFC into the mergeableString with table attachment attributes
    id mergeStr = noteMergeableString(note);
    if (!mergeStr) {
        fprintf(stderr, "Error: Could not get mergeable string\n");
        return 1;
    }

    // Create ICTTAttachment for the FFFC
    id ttAtt = [[NSClassFromString(@"ICTTAttachment") alloc] init];
    ((void (*)(id, SEL, id))objc_msgSend)(
        ttAtt, NSSelectorFromString(@"setAttachmentIdentifier:"), tableId);
    ((void (*)(id, SEL, id))objc_msgSend)(
        ttAtt, NSSelectorFromString(@"setAttachmentUTI:"),
        @"com.apple.notes.table");

    // Paragraph style for table: style=3 (body)
    id paraStyle = [[NSClassFromString(@"ICTTParagraphStyle") alloc] init];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(
        paraStyle, NSSelectorFromString(@"setStyle:"), (NSInteger)3);
    ((void (*)(id, SEL, id))objc_msgSend)(
        paraStyle, NSSelectorFromString(@"setUuid:"), [NSUUID UUID]);

    // Build: newline + U+FFFC + newline
    unichar fffc = 0xFFFC;
    NSString *fffcStr = [NSString stringWithFormat:@"%C", fffc];
    NSAttributedString *tableMarker = [[NSAttributedString alloc]
        initWithString:fffcStr
        attributes:@{@"NSAttachment": ttAtt, @"TTStyle": paraStyle}];

    // Get insertion point (end of text)
    NSAttributedString *attrStr = ((id (*)(id, SEL))objc_msgSend)(
        mergeStr, NSSelectorFromString(@"attributedString"));
    NSUInteger insertPos = [(NSAttributedString *)attrStr length];

    // Insert newline + table marker + newline
    NSAttributedString *nlStr = [[NSAttributedString alloc]
        initWithString:@"\n"];

    ((void (*)(id, SEL))objc_msgSend)(mergeStr,
        NSSelectorFromString(@"beginEditing"));
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(mergeStr,
        NSSelectorFromString(@"insertAttributedString:atIndex:"),
        nlStr, insertPos);
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(mergeStr,
        NSSelectorFromString(@"insertAttributedString:atIndex:"),
        tableMarker, insertPos + 1);
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(mergeStr,
        NSSelectorFromString(@"insertAttributedString:atIndex:"),
        nlStr, insertPos + 2);
    ((void (*)(id, SEL))objc_msgSend)(mergeStr,
        NSSelectorFromString(@"endEditing"));
    ((void (*)(id, SEL))objc_msgSend)(mergeStr,
        NSSelectorFromString(@"generateIdsForLocalChanges"));

    // Save
    ((void (*)(id, SEL))objc_msgSend)(note,
        NSSelectorFromString(@"saveNoteData"));
    ((void (*)(id, SEL))objc_msgSend)(note,
        NSSelectorFromString(@"updateDerivedAttributesIfNeeded"));
    if (!saveContext()) return 1;

    printf("Created %lux%lu table in note %lu\n",
           (unsigned long)targetRows, (unsigned long)targetCols,
           (unsigned long)idx);
    return 0;
}

// ─────────────────────────────────────────────────────────────────────────────
// Collaborative Sharing
// ─────────────────────────────────────────────────────────────────────────────

static BOOL noteIsShared(id note) {
    @try {
        return ((BOOL (*)(id, SEL))objc_msgSend)(
            note, NSSelectorFromString(@"isSharedViaICloud"));
    } @catch (NSException *e) {
        return NO;
    }
}

static NSUInteger noteParticipantCount(id note) {
    @try {
        id parts = [note valueForKey:@"participants"];
        if ([parts isKindOfClass:[NSSet class]]) return [(NSSet *)parts count];
    } @catch (NSException *e) {}
    return 0;
}

void cmdNotesShare(NSUInteger idx, NSString *folder, BOOL jsonOut) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return;
    }

    NSString *title = noteTitle(note);
    BOOL shared = noteIsShared(note);
    NSUInteger partCount = noteParticipantCount(note);

    if (jsonOut) {
        printf("{\"title\":\"%s\",\"shared\":%s,\"participants\":%lu",
               [jsonEscapeString(title) UTF8String],
               shared ? "true" : "false",
               (unsigned long)partCount);

        // Include participant IDs
        if (partCount > 0) {
            printf(",\"participantDetails\":[");
            @try {
                id parts = [note valueForKey:@"participants"];
                BOOL first = YES;
                for (id p in (NSSet *)parts) {
                    NSString *pid = [p valueForKey:@"participantID"];
                    NSString *uid = [p valueForKey:@"userID"];
                    BOOL isOwner = [uid isEqualToString:@"__defaultOwner__"];
                    if (!first) printf(",");
                    first = NO;
                    printf("{\"participantID\":\"%s\",\"isOwner\":%s}",
                           pid ? [jsonEscapeString(pid) UTF8String] : "",
                           isOwner ? "true" : "false");
                }
            } @catch (NSException *e) {}
            printf("]");
        }
        printf("}\n");
        return;
    }

    printf("Share status for \"%s\":\n\n", [title UTF8String]);
    printf("  Shared: %s\n", shared ? "Yes (via iCloud)" : "No");

    if (partCount > 0) {
        printf("  Participants: %lu\n", (unsigned long)partCount);
        @try {
            id parts = [note valueForKey:@"participants"];
            int i = 1;
            for (id p in (NSSet *)parts) {
                NSString *uid = [p valueForKey:@"userID"];
                BOOL isOwner = [uid isEqualToString:@"__defaultOwner__"];
                printf("    %d. %s%s\n", i,
                       isOwner ? "You (owner)" : [uid UTF8String],
                       isOwner ? "" : "");
                i++;
            }
        } @catch (NSException *e) {}
    } else if (shared) {
        printf("  Participants: (details not available)\n");
    }

    if (!shared) {
        printf("\n  Note is not currently shared.\n");
        printf("  To share, use the Share button in Apple Notes.\n");
    }
}

void cmdNotesShared(BOOL jsonOut) {
    NSArray *all = fetchAllNotes();
    NSMutableArray *sharedNotes = [NSMutableArray array];

    for (id note in all) {
        if (noteIsShared(note)) {
            [sharedNotes addObject:note];
        }
    }

    if (jsonOut) {
        printf("[");
        for (NSUInteger i = 0; i < sharedNotes.count; i++) {
            id note = sharedNotes[i];
            NSString *t = jsonEscapeString(noteTitle(note));
            NSString *f = jsonEscapeString(folderName(note));
            NSUInteger parts = noteParticipantCount(note);
            printf("%s{\"title\":\"%s\",\"folder\":\"%s\",\"participants\":%lu}",
                   i > 0 ? "," : "",
                   [t UTF8String], [f UTF8String], (unsigned long)parts);
        }
        printf("]\n");
        return;
    }

    if (sharedNotes.count == 0) {
        printf("No shared notes found.\n");
        return;
    }

    printf("Shared notes:\n\n");
    printf("  # %-42s %-22s %s\n", "Title", "Folder", "Participants");
    printf("--- %-42s %-22s %s\n",
           "------------------------------------------",
           "----------------------",
           "------------");

    NSUInteger i = 1;
    for (id note in sharedNotes) {
        NSString *t = truncStr(noteTitle(note), 42);
        NSString *f = truncStr(folderName(note), 22);
        NSUInteger parts = noteParticipantCount(note);
        printf("%3lu %-42s %-22s %lu\n",
               (unsigned long)i,
               [padRight(t, 42) UTF8String],
               [padRight(f, 22) UTF8String],
               (unsigned long)parts);
        i++;
    }
    printf("\nTotal: %lu shared note(s)\n", (unsigned long)sharedNotes.count);
}
