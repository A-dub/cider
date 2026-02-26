/**
 * notes.m — All Apple Notes commands
 */

#import "cider.h"

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

    // Tag filter
    if (tagFilter) {
        NSString *normalizedTag = [tagFilter hasPrefix:@"#"]
            ? [tagFilter lowercaseString]
            : [[@"#" stringByAppendingString:tagFilter] lowercaseString];
        NSMutableArray *tagFiltered = [NSMutableArray array];
        for (id note in notes) {
            NSString *raw = noteRawText(note);
            if (!raw) continue;
            NSArray *tags = extractTags(raw);
            for (NSString *t in tags) {
                if ([[t lowercaseString] isEqualToString:normalizedTag]) {
                    [tagFiltered addObject:note];
                    break;
                }
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
                   (unsigned long)(i + 1),
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

    // Normalize tag filter
    NSString *normalizedTag = nil;
    if (tagFilter) {
        normalizedTag = [tagFilter hasPrefix:@"#"]
            ? [tagFilter lowercaseString]
            : [[@"#" stringByAppendingString:tagFilter] lowercaseString];
    }

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

            // Tag filter
            if (normalizedTag) {
                NSArray *tags = extractTags(body);
                BOOL hasTag = NO;
                for (NSString *t in tags) {
                    if ([[t lowercaseString] isEqualToString:normalizedTag]) {
                        hasTag = YES; break;
                    }
                }
                if (!hasTag) continue;
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
                   (unsigned long)(i + 1),
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

int cmdNotesTag(NSUInteger idx, NSString *tag, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    // Normalize tag
    NSString *normalized = [tag hasPrefix:@"#"] ? tag : [@"#" stringByAppendingString:tag];

    // Check if tag already exists (case-insensitive)
    NSString *raw = noteRawText(note);
    NSArray *existing = extractTags(raw);
    for (NSString *t in existing) {
        if ([[t lowercaseString] isEqualToString:[normalized lowercaseString]]) {
            printf("Note %lu already has tag %s\n", (unsigned long)idx,
                   [t UTF8String]);
            return 0;
        }
    }

    // Append tag to end of note
    NSString *newText = [NSString stringWithFormat:@"%@ %@", raw, normalized];
    if (!applyCRDTEdit(note, raw, newText)) return 1;
    if (!saveContext()) return 1;
    printf("Added %s to note %lu\n", [normalized UTF8String], (unsigned long)idx);
    return 0;
}

int cmdNotesUntag(NSUInteger idx, NSString *tag, NSString *folder) {
    id note = noteAtIndex(idx, folder);
    if (!note) {
        fprintf(stderr, "Error: Note %lu not found\n", (unsigned long)idx);
        return 1;
    }

    NSString *normalized = [tag hasPrefix:@"#"] ? tag : [@"#" stringByAppendingString:tag];
    NSString *raw = noteRawText(note);

    // Build regex to find all occurrences (with optional leading space)
    NSString *escapedTag = [NSRegularExpression escapedPatternForString:normalized];
    NSString *pattern = [NSString stringWithFormat:@" ?%@(?=[^A-Za-z0-9_-]|$)", escapedTag];
    NSError *err = nil;
    NSRegularExpression *re = [NSRegularExpression
        regularExpressionWithPattern:pattern
        options:NSRegularExpressionCaseInsensitive
        error:&err];
    if (err) {
        fprintf(stderr, "Error: Internal regex error\n");
        return 1;
    }

    NSString *newText = [re stringByReplacingMatchesInString:raw options:0
                         range:NSMakeRange(0, raw.length) withTemplate:@""];
    if ([newText isEqualToString:raw]) {
        printf("Tag %s not found in note %lu\n", [normalized UTF8String],
               (unsigned long)idx);
        return 0;
    }

    if (!applyCRDTEdit(note, raw, newText)) return 1;
    if (!saveContext()) return 1;
    printf("Removed %s from note %lu\n", [normalized UTF8String],
           (unsigned long)idx);
    return 0;
}

void cmdNotesTags(BOOL withCounts, BOOL jsonOutput) {
    NSArray *notes = fetchAllNotes();
    NSMutableDictionary *tagCounts = [NSMutableDictionary dictionary];

    for (id note in notes) {
        NSString *raw = noteRawText(note);
        if (!raw) continue;
        NSArray *tags = extractTags(raw);
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
