/**
 * reminders.m — Reminders commands (Core Data + ReminderKit.framework)
 */

#import "cider.h"

// ─────────────────────────────────────────────────────────────────────────────
// Reminders Core Data context (file-local)
// ─────────────────────────────────────────────────────────────────────────────

static NSManagedObjectContext *g_remMOC = nil;
static NSPersistentStoreCoordinator *g_remPSC = nil;

BOOL initRemindersContext(void) {
    if (g_remMOC) return YES;

    void *rkHandle = dlopen(
        "/System/Library/PrivateFrameworks/ReminderKit.framework/ReminderKit",
        RTLD_NOW);
    if (!rkHandle) {
        fprintf(stderr, "Warning: Could not load ReminderKit.framework: %s\n",
                dlerror());
    }

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

        NSError *err = nil;
        NSPersistentStore *store =
            [g_remPSC addPersistentStoreWithType:NSSQLiteStoreType
                                   configuration:nil
                                             URL:storeURL
                                         options:storeOpts
                                           error:&err];
        if (!store) continue;

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

        [g_remPSC removePersistentStore:store error:nil];
    }

    if (!bestStore) {
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
// Reminders helpers (file-local)
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

    NSManagedObject *account = [defaultList valueForKey:@"account"];
    if (account) {
        [rem setValue:account forKey:@"account"];
    }

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
