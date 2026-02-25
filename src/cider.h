/**
 * cider.h — Shared declarations for the cider CLI
 *
 * All source files (#import this header):
 *   core.m       — Framework init, Core Data, CRDT, helpers
 *   notes.m      — Notes commands
 *   reminders.m  — Reminders commands
 *   sync.m       — Bidirectional Notes <-> Markdown sync
 *   main.m       — Help text, arg parsing, main()
 */

#ifndef CIDER_H
#define CIDER_H

#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <dlfcn.h>
#include <sys/stat.h>
#include <unistd.h>

#define VERSION "3.1.0"
#define ATTACHMENT_MARKER ((unichar)0xFFFC)

// ─────────────────────────────────────────────────────────────────────────────
// Global state (defined in core.m)
// ─────────────────────────────────────────────────────────────────────────────

extern id g_ctx;
extern id g_moc;

// ─────────────────────────────────────────────────────────────────────────────
// Framework init (core.m)
// ─────────────────────────────────────────────────────────────────────────────

BOOL initNotesContext(void);

// ─────────────────────────────────────────────────────────────────────────────
// Core Data helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSArray *fetchNotes(NSPredicate *predicate);
NSArray *fetchAllNotes(void);
NSArray *fetchFolders(void);
id findOrCreateFolder(NSString *title, BOOL create);
id defaultFolder(void);

// ─────────────────────────────────────────────────────────────────────────────
// Note access helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSString *noteURIString(id note);
NSInteger noteIntPK(id note);
NSString *noteTitle(id note);
NSString *folderName(id note);
id noteVisibleAttachments(id note);
NSUInteger noteAttachmentCount(id note);
NSArray *attachmentsAsArray(id attsObj);
NSArray *noteAttachmentNames(id note);

// ─────────────────────────────────────────────────────────────────────────────
// CRDT / mergeableString helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

id noteMergeableString(id note);
NSString *noteRawText(id note);
NSString *noteTextForDisplay(id note);
NSString *rawTextToEditable(NSString *raw, NSArray *names);
NSString *editableToRawText(NSString *edited);
BOOL saveContext(void);
BOOL applyCRDTEdit(id note, NSString *oldText, NSString *newText);

// ─────────────────────────────────────────────────────────────────────────────
// Note listing helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSArray *filteredNotes(NSString *filterFolder);
id noteAtIndex(NSUInteger idx, NSString *folder);

// ─────────────────────────────────────────────────────────────────────────────
// JSON / formatting / utility helpers (core.m)
// ─────────────────────────────────────────────────────────────────────────────

NSString *jsonEscapeString(NSString *s);
NSString *truncStr(NSString *s, NSUInteger maxLen);
NSString *padRight(NSString *s, NSUInteger width);
NSAppleEventDescriptor *runAppleScript(NSString *src, NSString **errMsg);

// ─────────────────────────────────────────────────────────────────────────────
// Notes commands (notes.m)
// ─────────────────────────────────────────────────────────────────────────────

NSUInteger promptNoteIndex(NSString *verb, NSString *folder);
void cmdNotesList(NSString *folder, BOOL jsonOutput);
void cmdFoldersList(BOOL jsonOutput);
int  cmdNotesView(NSUInteger idx, NSString *folder, BOOL jsonOutput);
void cmdNotesAdd(NSString *folderName);
void cmdNotesEdit(NSUInteger idx);
int  cmdNotesReplace(NSUInteger idx, NSString *findStr, NSString *replaceStr);
void cmdNotesDelete(NSUInteger idx);
void cmdNotesMove(NSUInteger idx, NSString *targetFolderName);
void cmdNotesSearch(NSString *query, BOOL jsonOutput);
void cmdNotesExport(NSString *exportPath);
void cmdNotesAttachments(NSUInteger idx, BOOL jsonOut);
void cmdNotesAttach(NSUInteger idx, NSString *filePath);
void cmdNotesAttachAt(NSUInteger idx, NSString *filePath, NSUInteger position);
NSArray *attachmentOrderFromCRDT(id note);
NSString *attachmentNameByID(NSArray *atts, NSString *attID);
void cmdNotesDetach(NSUInteger idx, NSUInteger attIdx);

// ─────────────────────────────────────────────────────────────────────────────
// Reminders commands (reminders.m)
// ─────────────────────────────────────────────────────────────────────────────

BOOL initRemindersContext(void);
void cmdRemList(void);
void cmdRemAdd(NSString *title, NSString *dueDate);
void cmdRemEdit(NSUInteger idx, NSString *newTitle);
void cmdRemDelete(NSUInteger idx);
void cmdRemComplete(NSUInteger idx);

// ─────────────────────────────────────────────────────────────────────────────
// Sync commands (sync.m)
// ─────────────────────────────────────────────────────────────────────────────

int cmdSyncBackup(NSString *syncDir);
int cmdSyncRun(NSString *syncDir);
int cmdSyncWatch(NSString *syncDir, NSTimeInterval interval);
void printSyncHelp(void);
NSString *syncDefaultDir(void);

// ─────────────────────────────────────────────────────────────────────────────
// Help text & arg parsing (main.m)
// ─────────────────────────────────────────────────────────────────────────────

void printHelp(void);
void printNotesHelp(void);
void printRemHelp(void);
NSString *argValue(int argc, char *argv[], int startIdx,
                   const char *flag1, const char *flag2);
BOOL argHasFlag(int argc, char *argv[], int startIdx,
                const char *flag1, const char *flag2);

#endif /* CIDER_H */
