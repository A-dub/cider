# Building Cider: A Technical Deep Dive

## How We Reverse-Engineered Apple Notes' Private API and Built a CLI That Edits Notes Without Destroying Attachments

**Author:** Cal (AI assistant) with Addison  
**Date:** February 2026  
**Platform:** macOS 15.4 (Sequoia), Apple M4  
**Repository:** [github.com/A-dub/cider](https://github.com/A-dub/cider)

---

## Table of Contents

1. [The Problem](#the-problem)
2. [Failed Approaches (The Graveyard)](#failed-approaches-the-graveyard)
3. [The Breakthrough: NotesShared.framework](#the-breakthrough-notessharedframework)
4. [Reverse Engineering the Private API](#reverse-engineering-the-private-api)
5. [Understanding the CRDT Text Model](#understanding-the-crdt-text-model)
6. [Building the Editor](#building-the-editor)
7. [The Attachment Problem](#the-attachment-problem)
8. [Positional Attachment Insertion](#positional-attachment-insertion)
9. [The Detach Problem](#the-detach-problem)
10. [Migrating Off AppleScript Entirely](#migrating-off-applescript-entirely)
11. [The Invisible Notes Bug](#the-invisible-notes-bug)
12. [The Gzip Discovery](#the-gzip-discovery)
13. [Testing Strategy](#testing-strategy)
14. [Architecture Decisions](#architecture-decisions)
15. [API Reference (Private Framework)](#api-reference-private-framework)
16. [What Could Break (Future macOS Versions)](#what-could-break-future-macos-versions)

---

## The Problem

Apple Notes has no public API for editing note content. The AppleScript interface provides `set body of note` which accepts HTML, but it has a catastrophic flaw: **setting the body destroys all inline attachments**.

When you do:

```applescript
tell application "Notes"
    set body of note "My Note" to "<div>Updated text</div>"
end tell
```

Notes strips all `<img>` tags, marks attachment entities for deletion, and replaces the entire note body. If your note had images, PDFs, or files embedded inline between paragraphs of text — they're gone. The attachments get moved to "Recently Deleted" and the note is left with plain text.

This isn't a bug. It's a fundamental limitation of the AppleScript interface, which treats note bodies as flat HTML strings with no concept of the underlying CRDT data structure that actually stores note content.

### The Constraint

We needed a tool that could:

1. Edit note text (add, modify, find/replace) while preserving inline attachments in their exact positions
2. Work headlessly over SSH (no display, no GUI, no user interaction)
3. Work with iCloud-synced notes (changes must not corrupt sync)
4. Run as a standalone CLI (no Xcode project, no Swift packages)
5. Be installable on any Mac, not just ours

### What Existed

- **`memo`** — An existing Notes CLI (Ruby). Reads notes fine but has the same AppleScript body-replacement problem for writes. Its CONTRIBUTING.md also explicitly prohibits AI-generated PRs, so contributing upstream wasn't an option.
- **AppleScript** — Read/write access but destroys attachments on write.
- **Shortcuts.app** — Same underlying AppleScript bridge. Same limitation.
- **SQLite direct access** — The Notes database is at `~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite`. You can read it, but writing raw SQL would corrupt the CRDT version vectors and break iCloud sync.

---

## Failed Approaches (The Graveyard)

Before finding the working solution, we exhausted nearly every other approach. Each taught us something about why this problem is hard.

### 1. AppleScript Body Manipulation

**Idea:** Read the HTML body, parse it, modify just the text nodes, write it back.

**Result:** Doesn't matter how carefully you reconstruct the HTML. `set body` replaces the entire CRDT string. Attachments reference U+FFFC characters in the CRDT that get wiped. The attachment entities become orphans and Notes marks them for deletion.

**Lesson:** The AppleScript bridge is a lossy abstraction. It converts CRDT → HTML on read and HTML → CRDT on write, but the round-trip isn't lossless.

### 2. SQLite Direct Modification

**Idea:** The note content lives in `ZICNOTEDATA.ZDATA` as a binary blob. Decode it, modify the text portion, write it back.

**Result:** The blob is a serialized CRDT (specifically, a gzip-compressed protobuf encoding of an `ICTTMergeableString`). Each character has a unique ID consisting of a replica UUID and a sequence number. If you modify the blob without updating the version vectors, CRDT ID assignments, and tombstone tracking, iCloud sync will either:
- Reject the change silently
- Create a conflict copy
- Corrupt the note for all devices

**Lesson:** The data format exists to support multi-device collaborative editing. You can't treat it as a flat string.

### 3. Protobuf Decoding

**Idea:** Decode the protobuf structure, understand the schema, make surgical edits.

**Result:** We successfully decoded parts of the protobuf. The structure includes:
- A text storage string
- An array of CRDT edit operations with replica IDs and sequence numbers  
- Attributed string attributes (fonts, attachments, styles)
- Tombstones for deleted characters
- A version vector mapping replica UUIDs to their latest sequence numbers

While technically possible to modify this, the schema is undocumented, complex, and could change with any macOS update. We'd be reimplementing Apple's CRDT engine from scratch — a massive effort with fragile results.

**Lesson:** The protobuf approach is theoretically sound but practically insane for a CLI tool.

### 4. UI Scripting (Accessibility API)

**Idea:** Use macOS Accessibility API to programmatically interact with Notes.app's text editor — select text, type replacement text, like a robot user.

**Result:** Requires:
- Notes.app to be running and frontmost
- A display (or virtual display)
- Accessibility permissions granted
- The correct note to be open and visible

This fundamentally can't work over SSH without a display. We tried with a virtual framebuffer but Notes.app's text view doesn't properly initialize without a real or virtual GPU context.

**Addison's verdict:** "UI scripting is explicitly not acceptable."

**Lesson:** Automating the GUI is fragile, slow, requires a display, and is the wrong abstraction level.

### 5. Accessibility API (AX) Direct Access

**Idea:** Use the AX API to access Notes.app's text storage directly, without simulating clicks/keypresses.

**Result:** `AXUIElementCopyAttributeValue` can read text from Notes.app's text view, but writing requires the app to be running and the note to be open. The AX API is designed for assistive technology, not programmatic editing. It also requires TCC (Transparency, Consent, and Control) permissions that can't be granted over SSH.

**Lesson:** AX is read-focused. Write access is limited and requires the full GUI stack.

### 6. VNC / Screen Sharing

**Idea:** Use macOS Screen Sharing to get a virtual display, then UI-script Notes.app.

**Result:** Works in theory but is incredibly slow, fragile, and complex. Each operation requires: wake Mac → start screen sharing → launch Notes → navigate to note → select text → type → close. Latency is measured in seconds per operation. Not viable for a CLI tool.

**Lesson:** Remote GUI automation is always the last resort, and it's always terrible.

### 7. XPC / NotesHelper

**Idea:** Notes.app might expose an XPC service that accepts edit commands.

**Result:** Notes does use XPC internally (between the app and its various extensions), but the XPC interfaces are private, undocumented, and protected by entitlements that third-party code can't claim. There's no `com.apple.notes.editing` service waiting for us to call it.

**Lesson:** Apple's inter-process communication is locked down by entitlements. Private XPC services aren't usable without Apple-signed entitlements.

---

## The Breakthrough: NotesShared.framework

After exhausting public APIs and automation approaches, we turned to Apple's private frameworks. The key insight: **Notes.app itself must have an API for editing text while preserving attachments — it does it every time you type.**

### Finding the Framework

```bash
find /System/Library/PrivateFrameworks -name "Notes*" -maxdepth 1
```

This reveals several frameworks. `NotesShared.framework` is the one that contains the data model and editing primitives. It's shared between Notes.app, the Notes widget, Siri integration, and other system components.

### The Shared Cache Problem

On modern macOS (Big Sur+), private framework binaries aren't on disk — they live in the **dyld shared cache** (`/System/Volumes/Preboot/.../dyld_shared_cache_arm64e`). The framework paths on disk are broken symlinks. This means:

```bash
strings /System/Library/PrivateFrameworks/NotesShared.framework/NotesShared
# → "broken symbolic link" error

nm /System/Library/PrivateFrameworks/NotesShared.framework/NotesShared  
# → same error

otool -oV /System/Library/PrivateFrameworks/NotesShared.framework/NotesShared
# → same error
```

**You cannot use static analysis tools on the framework.** All introspection must happen at runtime by loading the framework with `dlopen` and using the Objective-C runtime.

### Loading the Framework

```c
#include <dlfcn.h>

void *handle = dlopen(
    "/System/Library/PrivateFrameworks/NotesShared.framework/NotesShared",
    RTLD_NOW
);
// handle is non-NULL → framework loaded from shared cache
```

Despite the broken symlink, `dlopen` works because the dynamic linker resolves the path through the shared cache. This is a standard macOS mechanism — the symlinks exist so that `dlopen` paths remain stable across versions.

---

## Reverse Engineering the Private API

With the framework loaded, we used the Objective-C runtime to discover every class, method, property, and relationship.

### Step 1: Enumerate Classes

```objc
unsigned int count = 0;
Class *classes = objc_copyClassList(&count);
for (unsigned int i = 0; i < count; i++) {
    NSString *name = NSStringFromClass(classes[i]);
    if ([name hasPrefix:@"IC"]) {
        printf("%s\n", [name UTF8String]);
    }
}
```

The `IC` prefix stands for "iCloud" — Apple's internal naming convention for Notes-related classes. There are hundreds, but the important ones are:

| Class | Purpose |
|-------|---------|
| `ICNoteContext` | Singleton database context. Manages Core Data stack. |
| `ICNote` | Core Data entity representing a note. |
| `ICNoteData` | Stores the serialized CRDT blob for a note. |
| `ICFolder` | Core Data entity for folders. Uses `title` not `name`. |
| `ICAttachment` | Core Data entity for an attachment. |
| `ICTTMergeableString` | **The CRDT string.** This is the core editing primitive. |
| `ICTTMergeableAttributedString` | CRDT string with attributes (fonts, attachments). |
| `ICTTAttachment` | CRDT attribute for an attachment marker. |
| `ICCRDocument` | Container for the CRDT document. |

### Step 2: Dump Methods

For each class, enumerate instance and class methods:

```objc
unsigned int mc = 0;
Method *methods = class_copyMethodList(cls, &mc);
for (unsigned int i = 0; i < mc; i++) {
    SEL sel = method_getName(methods[i]);
    const char *types = method_getTypeEncoding(methods[i]);
    printf("  - %s  (%s)\n", sel_getName(sel), types);
}
```

The type encoding tells you parameter types:
- `v` = void return, `@` = object, `Q` = NSUInteger, `B` = BOOL
- `{_NSRange=QQ}` = NSRange struct
- Pattern: `return_type size self_offset :_offset param1_offset param2_offset ...`

### Step 3: Dump Core Data Entity Relationships

```objc
NSEntityDescription *entity = [NSEntityDescription 
    entityForName:@"ICNote" inManagedObjectContext:moc];

// Attributes
for (NSString *key in [entity attributesByName]) {
    NSAttributeDescription *attr = entity.attributesByName[key];
    printf("  attr: %s (%ld)\n", [key UTF8String], (long)attr.attributeType);
}

// Relationships
for (NSString *key in [entity relationshipsByName]) {
    NSRelationshipDescription *rel = entity.relationshipsByName[key];
    printf("  rel: %s -> %s (%s)\n", 
        [key UTF8String],
        [rel.destinationEntity.name UTF8String],
        rel.isToMany ? "to-many" : "to-one");
}
```

Key relationships discovered:
- `ICNote.folder` → `ICFolder` (to-one)
- `ICNote.account` → `ICAccount` (to-one)
- `ICNote.noteData` → `ICNoteData` (to-one)
- `ICNote.attachments` → `ICAttachment` (to-many, **returns NSSet — unordered!**)
- `ICNote.cloudState` → `ICCloudState` (to-one)

### Step 4: Initialize the Context

The framework provides a singleton context that reads the same SQLite database as Notes.app:

```objc
Class NoteContext = NSClassFromString(@"ICNoteContext");

// Initialize with options=0 (read-write)
((void (*)(id, SEL, NSUInteger))objc_msgSend)(
    NoteContext, 
    NSSelectorFromString(@"startSharedContextWithOptions:"), 
    0
);

// Get the shared singleton
id ctx = ((id (*)(id, SEL))objc_msgSend)(
    NoteContext, 
    NSSelectorFromString(@"sharedContext")
);

// Get the Core Data managed object context
id moc = ((id (*)(id, SEL))objc_msgSend)(
    ctx, 
    NSSelectorFromString(@"managedObjectContext")
);
```

This `moc` is a standard `NSManagedObjectContext`. You can use regular Core Data fetch requests:

```objc
NSFetchRequest *req = [NSFetchRequest fetchRequestWithEntityName:@"ICNote"];
req.predicate = [NSPredicate predicateWithFormat:@"markedForDeletion == NO"];
req.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"modificationDate" ascending:NO]];
NSArray *notes = [moc executeFetchRequest:req error:nil];
```

---

## Understanding the CRDT Text Model

Apple Notes uses a custom CRDT (Conflict-free Replicated Data Type) for its text storage. This is the same technology that powers real-time collaboration in Notes (sharing a note with another person and editing simultaneously).

### What is a CRDT?

A CRDT is a data structure where concurrent edits by different devices can always be merged deterministically without conflicts. Each character in the text has a globally unique identity:

```
Character ID = (Replica UUID, Sequence Number)
```

- **Replica UUID**: Identifies the device/process that created the character
- **Sequence Number**: Monotonically increasing counter per replica

When you type "Hello" on your iPhone:
```
H → (iPhone-UUID, 1)
e → (iPhone-UUID, 2)
l → (iPhone-UUID, 3)
l → (iPhone-UUID, 4)
o → (iPhone-UUID, 5)
```

If you simultaneously type " World" on your Mac:
```
  → (Mac-UUID, 1)
W → (Mac-UUID, 2)
o → (Mac-UUID, 3)
r → (Mac-UUID, 4)
l → (Mac-UUID, 5)
d → (Mac-UUID, 6)
```

The CRDT merge algorithm deterministically combines these into "Hello World" (or " WorldHello" depending on insertion positions) — no conflict resolution needed.

### How Notes Uses It

The text content of every note is stored as an `ICTTMergeableString`, which wraps:
- The current text content
- The full edit history (inserts and deletes with their CRDT IDs)
- A version vector mapping each replica UUID to its latest sequence number
- Tombstones for deleted characters (they're marked deleted, not removed)
- Attributed string attributes (fonts, paragraph styles, **attachment markers**)

### The U+FFFC Convention

Attachments in the text are represented by `U+FFFC` (Object Replacement Character). This is a standard Unicode convention used by `NSAttributedString` for embedded objects. In the CRDT string:

```
"Meeting Notes\n￼\nAction items:\n￼\n"
                ^                ^
                |                |
           Photo of           PDF of
           whiteboard         agenda
```

Each `U+FFFC` has an attributed string attribute (`NSAttachment`) that contains an `ICTTAttachment` with:
- `attachmentIdentifier`: UUID linking to the `ICAttachment` Core Data entity
- `attachmentUTI`: Uniform Type Identifier (e.g., `public.jpeg`, `com.adobe.pdf`)

Because the `U+FFFC` characters are regular CRDT characters with unique IDs, they participate in the merge algorithm just like text characters. This is why inserting or deleting text around them doesn't disturb their positions — the CRDT maintains the relative ordering of all characters by their IDs.

### The Edit Protocol

To edit a note's text:

```objc
// 1. Get the CRDT string
id mergeStr = [note performSelector:@selector(mergeableString)];

// 2. Begin an edit transaction
[mergeStr performSelector:@selector(beginEditing)];

// 3. Make changes (these are CRDT-aware operations)
//    - insertString:atIndex:
//    - deleteCharactersInRange:
//    - replaceCharactersInRange:withString:
//    - insertAttributedString:atIndex: (for attachments)

// 4. End the transaction
[mergeStr performSelector:@selector(endEditing)];

// 5. Assign CRDT IDs to new characters
[mergeStr performSelector:@selector(generateIdsForLocalChanges)];

// 6. Save to database
[note performSelector:@selector(saveNoteData)];  // gzip + write to noteData.data
[note performSelector:@selector(updateDerivedAttributesIfNeeded)];  // title, snippet
[context performSelector:@selector(save)];  // persist to SQLite
```

Step 5 (`generateIdsForLocalChanges`) is critical. Without it, new characters have no CRDT identity and will be lost or cause corruption on the next sync. This was one of the early mistakes we made — edits would appear to work but then vanish after iCloud sync.

---

## Building the Editor

The first working version was a standalone Objective-C program that could find/replace text in a note while preserving all attachments. The key architecture decisions:

### Why Objective-C?

The private framework is Objective-C. Using it requires:
- `dlopen` to load the framework from the shared cache
- `objc_msgSend` to call methods on classes discovered at runtime
- `NSSelectorFromString` to construct selectors from strings
- `NSClassFromString` to get class objects

While Swift can call Objective-C, the dynamic dispatch pattern (`objc_msgSend` with runtime-constructed selectors) is more natural in Objective-C. Swift would require extensive bridging and `@objc` annotations that add complexity without benefit.

### Why Single-File?

`cider.m` compiles with a single `clang` invocation:

```bash
clang -framework Foundation -framework CoreData \
    -fobjc-arc -O2 -o cider cider.m
```

No Xcode project. No Swift Package Manager. No CocoaPods. No build system beyond `make`. This means:
- Anyone with Xcode Command Line Tools can build it
- CI builds are trivial (one compile command)
- No dependency management
- The entire tool is readable in one file

### The `objc_msgSend` Pattern

Every call to a private API method follows this pattern:

```objc
// Typed cast of objc_msgSend for the specific signature
((return_type (*)(id, SEL, param_types...))objc_msgSend)(
    target_object,
    NSSelectorFromString(@"methodName:"),
    param_values...
);
```

For example, to call `insertString:atIndex:` on the CRDT string:

```objc
((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
    mergeStr,
    NSSelectorFromString(@"insertString:atIndex:"),
    @"Hello",
    (NSUInteger)0
);
```

The cast is necessary because `objc_msgSend` has a generic signature (`id objc_msgSend(id, SEL, ...)`) but the actual calling convention depends on the parameter types. Getting the cast wrong causes subtle ABI bugs — especially with struct returns (which require `objc_msgSend_stret` on some architectures).

### Global State

The tool initializes the Notes context once at startup and stores the managed object context in a global:

```objc
static id g_moc = nil;  // NSManagedObjectContext

void initContext(void) {
    Class NoteContext = NSClassFromString(@"ICNoteContext");
    ((void (*)(id, SEL, NSUInteger))objc_msgSend)(
        NoteContext, 
        NSSelectorFromString(@"startSharedContextWithOptions:"), 
        0);
    id ctx = ((id (*)(id, SEL))objc_msgSend)(
        NoteContext, 
        NSSelectorFromString(@"sharedContext"));
    g_moc = ((id (*)(id, SEL))objc_msgSend)(
        ctx, 
        NSSelectorFromString(@"managedObjectContext"));
}
```

All subsequent operations (fetch, edit, save) use this single context. This mirrors how Notes.app itself works — one context per process.

---

## The Attachment Problem

With text editing working, the next challenge was **attachment manipulation**: adding, removing, and repositioning attachments.

### Why `visibleAttachments` Is Insufficient

`ICNote.visibleAttachments` returns an `NSSet` — an **unordered** collection. If a note has three images, you get all three attachment objects but have no idea which one is first, second, or third in the note text.

```objc
NSSet *attachments = [note valueForKey:@"visibleAttachments"];
NSArray *all = [attachments allObjects];
// all[0] might be the third image in the note
// all[1] might be the first
// No ordering guarantee
```

This made it impossible to implement "remove the second attachment" or "show attachments in order."

### The Solution: `attachmentOrderFromCRDT()`

The CRDT attributed string knows exactly where each attachment is in the text, because each `U+FFFC` character has an `NSAttachment` attribute containing the attachment's identifier.

```objc
NSArray *attachmentOrderFromCRDT(id note) {
    id mergeStr = [note performSelector:@selector(mergeableString)];
    id attrStr = [mergeStr performSelector:@selector(string)];
    // attrStr is an NSAttributedString
    
    NSString *text = [attrStr string];
    NSMutableArray *ordered = [NSMutableArray array];
    
    for (NSUInteger i = 0; i < text.length; i++) {
        if ([text characterAtIndex:i] == 0xFFFC) {
            // Found an attachment marker — get its identifier
            NSDictionary *attrs = [attrStr attributesAtIndex:i effectiveRange:NULL];
            id attachment = attrs[@"NSAttachment"];
            // attachment is an ICTTAttachment with:
            //   - attachmentIdentifier (UUID string)
            //   - attachmentUTI (type identifier)
            
            NSString *identifier = [attachment valueForKey:@"attachmentIdentifier"];
            if (identifier) {
                [ordered addObject:@{
                    @"identifier": identifier,
                    @"position": @(i),
                    @"uti": [attachment valueForKey:@"attachmentUTI"] ?: @"unknown"
                }];
            }
        }
    }
    
    return ordered;  // Attachments in text order
}
```

This walks the CRDT string character by character, finds every `U+FFFC`, reads its attribute, and builds an ordered array. Now we can say "attachment 1 is a JPEG at position 15, attachment 2 is a PDF at position 42."

### Resolving Attachment Names

The `ICTTAttachment` CRDT attribute has the identifier but not the human-readable filename. That lives on the `ICAttachment` Core Data entity, accessible through the note's `visibleAttachments` relationship:

```objc
NSString *attachmentNameByID(NSSet *attachments, NSString *targetID) {
    for (id att in attachments) {
        NSString *attID = [att valueForKey:@"identifier"];
        if ([attID isEqualToString:targetID]) {
            // ICAttachment uses 'userTitle' for user-given names,
            // falling back to a generated title
            NSString *name = [att valueForKey:@"userTitle"];
            if (!name || name.length == 0) {
                name = [att valueForKey:@"title"];
            }
            return name ?: @"Untitled";
        }
    }
    return nil;
}
```

**API quirk:** `ICAttachment` has no `filename` property. It uses `userTitle` (user-assigned name) and `title` (system-generated name). Neither corresponds directly to the original filename of the attached file.

---

## Positional Attachment Insertion

Adding an attachment at a specific position in the note (e.g., "insert this image after paragraph 2") was one of the more complex operations.

### The Recipe

```objc
void attachAtPosition(id note, NSString *filePath, NSUInteger position) {
    // 1. Create the Core Data attachment entity
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    id attachment = ((id (*)(id, SEL, id))objc_msgSend)(
        note,
        NSSelectorFromString(@"addAttachmentWithFileURL:"),
        fileURL
    );
    // This creates the ICAttachment entity and copies the file
    // into Notes' internal storage, but does NOT insert it into
    // the CRDT string.
    
    // 2. Get the attachment identifier and UTI
    NSString *identifier = [attachment valueForKey:@"identifier"];
    NSString *uti = /* determine UTI from file extension */;
    
    // 3. Create the CRDT attachment attribute
    Class ICTTAttachment = NSClassFromString(@"ICTTAttachment");
    id ttAttachment = [[ICTTAttachment alloc] init];
    [ttAttachment setValue:identifier forKey:@"attachmentIdentifier"];
    [ttAttachment setValue:uti forKey:@"attachmentUTI"];
    
    // 4. Build an attributed string with U+FFFC and the attachment attribute
    NSString *placeholder = [NSString stringWithFormat:@"%C", (unichar)0xFFFC];
    NSAttributedString *attrStr = [[NSAttributedString alloc]
        initWithString:placeholder
        attributes:@{@"NSAttachment": ttAttachment}];
    
    // 5. Insert into the CRDT at the desired position
    id mergeStr = [note performSelector:@selector(mergeableString)];
    [mergeStr performSelector:@selector(beginEditing)];
    
    ((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
        mergeStr,
        NSSelectorFromString(@"insertAttributedString:atIndex:"),
        attrStr,
        position
    );
    
    [mergeStr performSelector:@selector(endEditing)];
    [mergeStr performSelector:@selector(generateIdsForLocalChanges)];
    
    // 6. Save
    [note performSelector:@selector(saveNoteData)];
    [note performSelector:@selector(updateDerivedAttributesIfNeeded)];
    [context performSelector:@selector(save)];
}
```

### Critical Detail: `addAttachmentWithFileURL:` Is Not Enough

Calling `addAttachmentWithFileURL:` on an `ICNote` creates the Core Data entity (the `ICAttachment` row in SQLite) and copies the file into Notes' internal file storage. But it does **not** insert the `U+FFFC` character into the CRDT string. If you stop here, the attachment exists in the database but is invisible — it's not referenced by any character in the note text.

You must manually:
1. Create an `ICTTAttachment` with the identifier and UTI
2. Build an `NSAttributedString` with `U+FFFC` + the attachment attribute
3. Insert it into the CRDT string at the desired position
4. Generate CRDT IDs for the new character

This two-step process (entity creation + CRDT insertion) is how Notes.app does it internally. When you drag an image into a note, Notes calls `addAttachmentWithFileURL:` then separately modifies the CRDT string.

---

## The Detach Problem

Removing an attachment requires the reverse operation: remove the `U+FFFC` from the CRDT string AND delete the Core Data entity.

### Why Both Steps Matter

If you only remove the `U+FFFC`:
- The attachment entity remains in the database (orphan)
- Notes.app may still show it in some contexts
- iCloud sync carries the orphaned entity to all devices
- Storage is never reclaimed

If you only delete the Core Data entity:
- The `U+FFFC` remains in the text
- Notes.app shows a blank/broken placeholder where the attachment was
- The CRDT string references a non-existent attachment

### The Implementation

```objc
void detachAttachment(id note, NSUInteger attachmentIndex) {
    // 1. Get ordered attachments from CRDT
    NSArray *ordered = attachmentOrderFromCRDT(note);
    NSDictionary *target = ordered[attachmentIndex - 1];  // 1-indexed
    
    NSString *targetID = target[@"identifier"];
    NSUInteger position = [target[@"position"] unsignedIntegerValue];
    
    // 2. Remove U+FFFC from CRDT string
    id mergeStr = [note performSelector:@selector(mergeableString)];
    [mergeStr performSelector:@selector(beginEditing)];
    
    ((void (*)(id, SEL, NSRange))objc_msgSend)(
        mergeStr,
        NSSelectorFromString(@"deleteCharactersInRange:"),
        NSMakeRange(position, 1)
    );
    
    [mergeStr performSelector:@selector(endEditing)];
    [mergeStr performSelector:@selector(generateIdsForLocalChanges)];
    
    // 3. Delete Core Data entity
    NSSet *attachments = [note valueForKey:@"visibleAttachments"];
    for (id att in attachments) {
        if ([[att valueForKey:@"identifier"] isEqualToString:targetID]) {
            [g_moc deleteObject:att];
            break;
        }
    }
    
    // 4. Save
    [note performSelector:@selector(saveNoteData)];
    [note performSelector:@selector(updateDerivedAttributesIfNeeded)];
    [context performSelector:@selector(save)];
}
```

### No Positional Fallback

If the CRDT identifier matching fails (e.g., the attachment entity has a different identifier format than what the CRDT stores), cider warns and refuses to proceed rather than guessing. Deleting the wrong attachment is worse than failing to delete.

---

## Migrating Off AppleScript Entirely

The initial version of cider used a hybrid approach:
- **Edit/Replace/Attach/Detach**: Private framework CRDT API
- **List/View/Search**: Core Data fetch requests
- **Add/Delete/Move**: AppleScript (delegated to Notes.app)

This worked but had drawbacks:
1. **Async race conditions**: AppleScript tells Notes.app to create a note, but the SQLite database isn't immediately updated. Tests that create via AppleScript then verify via Core Data had to include arbitrary `sleep` calls.
2. **File type restrictions**: AppleScript `attach` only works with certain UTIs.
3. **Requires Notes.app**: Any operation using AppleScript launches Notes.app if it's not running.
4. **Test instability**: 3 tests had to be skipped due to AppleScript → SQLite sync timing.

### Add (Creating Notes)

Creating a note via the framework requires inserting two Core Data entities and writing CRDT text:

```objc
// 1. Create ICNote entity
id newNote = [NSEntityDescription 
    insertNewObjectForEntityForName:@"ICNote" 
             inManagedObjectContext:g_moc];

// 2. Set relationships
[newNote setValue:folder forKey:@"folder"];
[newNote setValue:account forKey:@"account"];
[newNote setValue:[NSDate date] forKey:@"creationDate"];
[newNote setValue:[NSDate date] forKey:@"modificationDate"];

// 3. Create ICNoteData entity (stores the CRDT blob)
id noteDataEntity = [NSEntityDescription
    insertNewObjectForEntityForName:@"ICNoteData"
             inManagedObjectContext:g_moc];
[newNote setValue:noteDataEntity forKey:@"noteData"];

// 4. Write text via CRDT
id mergeStr = [newNote performSelector:@selector(mergeableString)];
[mergeStr performSelector:@selector(beginEditing)];
((void (*)(id, SEL, id, NSUInteger))objc_msgSend)(
    mergeStr,
    NSSelectorFromString(@"insertString:atIndex:"),
    noteText,
    (NSUInteger)0
);
[mergeStr performSelector:@selector(endEditing)];
[mergeStr performSelector:@selector(generateIdsForLocalChanges)];

// 5. Serialize (this is where saveNoteData is critical)
[newNote performSelector:@selector(saveNoteData)];

// 6. Update derived attributes
[newNote performSelector:@selector(updateDerivedAttributesIfNeeded)];

// 7. Save
[g_moc save:nil];
```

**Critical:** Step 5 uses `saveNoteData`, not `mergeableString.serialize`. See [The Gzip Discovery](#the-gzip-discovery) for why.

### Delete

```objc
((void (*)(id, SEL))objc_msgSend)(
    note, 
    NSSelectorFromString(@"deleteFromLocalDatabase")
);
[g_moc save:nil];
```

This marks the note for deletion and removes it from the local database. iCloud sync propagates the deletion to other devices.

### Move

```objc
((void (*)(id, SEL, id))objc_msgSend)(
    note,
    NSSelectorFromString(@"setFolder:"),
    targetFolder
);
[note setValue:[NSDate date] forKey:@"modificationDate"];
[g_moc save:nil];
```

### Results

After migration:
- All 53 tests pass with 0 skips
- No `sleep` calls needed for synchronization
- Notes.app doesn't need to be running
- All file types work for attachments
- Works completely headlessly over SSH

---

## The Invisible Notes Bug

After migrating add/delete/move to the framework, we discovered that notes created by cider were invisible in Notes.app — even after restarting Notes.app.

### Symptoms

- `cider notes list` showed the note (reads from SQLite directly)
- `cider notes show` displayed full content
- Notes.app showed nothing — the note didn't appear in any folder
- Even `osascript -e 'tell application "Notes" to count of every note'` didn't include it

### Investigation

We compared the SQLite rows for a cider-created note vs an AppleScript-created note. Both had:
- Same entity type (`Z_ENT=11`)
- Same persistent store
- Same relationships (account, folder, noteData, cloudState)
- Same `markedForDeletion = 0`

The difference was the **folder**:

```sql
SELECT Z_PK, ZTITLE2, ZMARKEDFORDELETION 
FROM ZICCLOUDSYNCINGOBJECT 
WHERE ZTITLE2 = 'Cider Tests';

-- Result:
-- 1711 | Cider Tests | 1    ← MARKED FOR DELETION
-- 1789 | Cider Tests | 0    ← the real folder
```

Two folders with the same name "Cider Tests"! Folder 1711 was created by an earlier cider run, then later marked for deletion (probably when a test cleanup deleted all notes in it). But `findOrCreateFolder()` didn't filter deleted folders, so it found folder 1711 first and put new notes there.

Notes.app filters out notes in deleted folders. That's why they were invisible.

### The Fix

```objc
// Before (broken):
req.predicate = [NSPredicate predicateWithFormat:@"title == %@", title];

// After (fixed):
req.predicate = [NSPredicate predicateWithFormat:
    @"title == %@ AND markedForDeletion == NO", title];
```

Applied the same `markedForDeletion == NO` filter to:
- `fetchNotes()` — all note queries
- `fetchFolders()` — all folder queries
- `findOrCreateFolder()` — folder lookup/creation
- Account lookup for new folder creation

### Verification

After the fix, notes created by cider appear in Notes.app immediately — even while Notes.app is running. Notes.app's Core Data coordinator detects new rows via SQLite WAL (Write-Ahead Log) tracking and refreshes its display.

---

## The Gzip Discovery

Notes created by the initial framework migration had a subtle bug: the body content was empty when read back by a new cider process.

### Symptoms

```bash
$ printf 'Test Note\nBody content' | cider notes add
Created note: "Test Note"

$ cider notes 1
╔══════════════════════════════════════════╗
  Test Note
  Folder: Notes
╚══════════════════════════════════════════╝
# Body is empty!
```

The title was derived correctly (from the CRDT string in memory during creation), but when a new process read the note, the body was gone.

### Investigation

We compared the raw `noteData.data` bytes for a framework-created note vs a Notes.app-created note:

```
Notes.app note:  1f 8b 08 00 ...  (starts with 0x1f 0x8b)
Framework note:  12 2c 63 61 ...  (starts with 0x12 0x2c)
```

`0x1f 0x8b` is the **gzip magic number**. Notes.app stores the CRDT protobuf as gzip-compressed data in `noteData.data`. Our code was using `mergeableString.serialize` which produces **raw protobuf** — no compression.

When cider (or Notes.app) reads a note, it expects `noteData.data` to be gzip-compressed. The raw protobuf starts with `0x12` (a protobuf field tag), which isn't valid gzip, so decompression fails silently and returns nil. The CRDT string is empty.

### The Fix

```objc
// Before (broken — writes raw protobuf):
NSData *serialized = [mergeStr performSelector:@selector(serialize)];
[noteDataEntity setValue:serialized forKey:@"data"];

// After (fixed — saveNoteData handles gzip compression):
[note performSelector:@selector(saveNoteData)];
```

`saveNoteData` is a method on `ICNote` that:
1. Calls `serialize` on the mergeable string to get raw protobuf
2. Gzip-compresses the protobuf
3. Writes the compressed data to `noteData.data`

We never needed to call `serialize` directly. `saveNoteData` does everything.

### How We Found It

A diagnostic program that compared the first 20 bytes of existing notes' `noteData.data` with the output of `mergeableString.serialize`. The gzip magic number (`1f 8b`) immediately identified the compression layer.

---

## Testing Strategy

### Test Suite Design

The test suite (`test.sh`) runs 53 tests covering every cider command. It's a bash script that:

1. Creates test notes in a "Cider Tests" folder
2. Exercises each command and checks output
3. Cleans up all test notes
4. Reports pass/fail/skip counts

### Key Design Decisions

**Self-bootstrapping:** Tests create their own notes using `cider notes add` (framework-based), not AppleScript. This means the test suite only depends on cider itself — no external tools.

**Two modes:**
- **Full mode** (macOS with Notes database): All 53 tests run
- **Limited mode** (CI without Notes access): Framework access check fails, runs only error handling and compilation tests

**No sleep hacks:** Because all operations are synchronous (framework-based), there are no `sleep` calls to wait for AppleScript → SQLite sync. Tests verify state immediately after operations.

**Output filtering:** The `run()` helper captures stdout+stderr and filters benign framework warnings (like `ERROR: inflate failed` which occurs when reading notes created by older Notes versions with a different compression format):

```bash
run() {
    local tmpfile="/tmp/cider_run_$$.txt"
    set +e
    "$@" > "$tmpfile" 2>&1
    RC=$?
    set -e
    OUT=$(grep -v "ERROR: inflate failed" "$tmpfile" || true)
    rm -f "$tmpfile"
}
```

### CI Integration

GitHub Actions runs the test suite on every push and PR:

```yaml
- name: Build
  run: make
- name: Test
  run: make test
```

In CI, the Notes database isn't available, so the test drops into limited mode automatically. Full mode runs on local macOS development machines.

---

## Architecture Decisions

### Single File vs. Multiple Files

`cider.m` is ~2000 lines in a single file. This was intentional:
- **Compilation simplicity**: One `clang` invocation, no build system beyond `make`
- **Readability**: Everything is in one place, greppable
- **No header management**: Forward declarations at the top handle dependency ordering
- **Distribution**: The source is one file you can copy and compile

The tradeoff is that the file is long. But for a tool of this scope, one file is manageable.

### Objective-C vs. Swift

Objective-C was chosen for:
- Natural `objc_msgSend` / `dlopen` / `NSSelectorFromString` patterns
- No Swift runtime dependency (binary is smaller, more portable)
- Easier to construct dynamic dispatch at runtime
- Core Data and Foundation are Objective-C frameworks

### CLI Design: Subcommands Over Flags

```bash
# Subcommand style (v1.1.0+)
cider notes edit 3
cider notes search "query"
cider notes attach 5 photo.jpg --at 42

# Flag style (v1.0.0, still supported for compatibility)
cider notes -e 3
cider notes -s "query"
```

Subcommands read better, are more discoverable (`cider notes help`), and allow for future expansion (`cider cal`, `cider contacts`).

### Note Indexing: 1-Based Display Index

Notes are displayed with 1-based indices sorted by modification date (newest first). The index is ephemeral — it changes as notes are modified. This matches user expectations ("edit the first note in the list") and avoids exposing Core Data primary keys.

```bash
$ cider notes list
  # Title                        Folder
--- ----------------------------- --------
  1 Meeting Notes                 Work
  2 Grocery List                  Personal
  3 Project Ideas                 Work
```

The index-to-note mapping is reconstructed on every command invocation by fetching all notes and sorting. This is fast (milliseconds for thousands of notes) and ensures consistency.

---

## API Reference (Private Framework)

### ICNoteContext

The database context singleton.

| Method | Type | Description |
|--------|------|-------------|
| `+startSharedContextWithOptions:` | Class | Initialize with options (use 0 for read-write) |
| `+sharedContext` | Class | Get the singleton context |
| `-managedObjectContext` | Instance | Get the Core Data MOC |
| `-save` | Instance | Persist changes to SQLite |
| `-saveImmediately` | Instance | Force immediate save |
| `-refreshAll` | Instance | Refresh in-memory objects from store |

### ICNote

A note entity (Core Data `NSManagedObject` subclass).

| Method / Property | Description |
|-------------------|-------------|
| `mergeableString` | Get the CRDT string (`ICTTMergeableString`) |
| `visibleAttachments` | Get attachments (`NSSet` — **unordered!**) |
| `title` | Derived title (first line of text) |
| `snippet` | Derived snippet (first ~100 chars) |
| `folder` | The containing `ICFolder` |
| `account` | The owning `ICAccount` |
| `noteData` | The `ICNoteData` entity (holds serialized blob) |
| `creationDate` / `modificationDate` | Timestamps |
| `markedForDeletion` | Soft-delete flag (filter this!) |
| `identifier` | UUID string |
| `addAttachmentWithFileURL:` | Create attachment entity (does NOT insert into CRDT) |
| `deleteFromLocalDatabase` | Soft-delete the note |
| `setFolder:` | Move to a different folder |
| `saveNoteData` | Serialize CRDT → gzip → noteData.data |
| `updateDerivedAttributesIfNeeded` | Recompute title, snippet, etc. |
| `beginEditing` / `endEditing` | Bracket edit transactions |

### ICFolder

| Property | Description |
|----------|-------------|
| `title` | Folder name (not `name`!) |
| `account` | Owning account |
| `markedForDeletion` | Soft-delete flag |

### ICNoteData

| Property | Description |
|----------|-------------|
| `data` | Gzip-compressed protobuf of the CRDT string |

### ICTTMergeableString

The CRDT editing API.

| Method | Description |
|--------|-------------|
| `string` | Get current text as `NSAttributedString` |
| `beginEditing` | Start edit transaction |
| `endEditing` | End edit transaction |
| `insertString:atIndex:` | Insert plain text |
| `insertAttributedString:atIndex:` | Insert attributed text (for attachments) |
| `deleteCharactersInRange:` | Delete a range |
| `replaceCharactersInRange:withString:` | Replace a range |
| `generateIdsForLocalChanges` | Assign CRDT IDs to new characters |
| `serialize` | Serialize to raw protobuf (not gzipped!) |

### ICTTAttachment

CRDT attribute for attachment markers.

| Property | Description |
|----------|-------------|
| `attachmentIdentifier` | UUID linking to `ICAttachment` entity |
| `attachmentUTI` | Uniform Type Identifier (e.g., `public.jpeg`) |

### ICAttachment

Core Data entity for an attachment.

| Property | Description |
|----------|-------------|
| `identifier` | UUID string |
| `userTitle` | User-assigned name |
| `title` | System-generated name |
| (no `filename`) | There is no filename property |

---

## What Could Break (Future macOS Versions)

This tool uses private APIs that Apple can change at any time. Here's what to watch for and how to diagnose issues.

### Risk Assessment

| Risk | Likelihood | Impact | Detection |
|------|-----------|--------|-----------|
| Framework path changes | Low | Fatal | `dlopen` returns NULL |
| Class renamed | Low | Fatal | `NSClassFromString` returns nil |
| Method renamed/removed | Medium | Per-feature | `class_getInstanceMethod` returns NULL |
| New required init params | Medium | Fatal | Crash on `startSharedContextWithOptions:` |
| Core Data schema change | Medium | Per-feature | Fetch requests fail |
| Serialization format change | Low | Data corruption | Notes unreadable after edit |
| Entitlement requirement added | Medium | Fatal | Framework refuses to initialize |

### Diagnostic Steps

1. **Check if framework loads**: `dlopen` returns non-NULL
2. **Check if classes exist**: `NSClassFromString` for each key class
3. **Check if methods exist**: `class_getInstanceMethod` for each key selector
4. **Check if context initializes**: `startSharedContextWithOptions:` doesn't crash
5. **Check if fetch works**: `executeFetchRequest:` returns results
6. **Check if edit works**: Create a test note, edit it, read it back

If something breaks, re-run the class and method dump (Steps 2-3 from the RE guide) and look for:
- Renamed classes (search for similar names)
- Moved methods (check superclasses)
- New initialization requirements (check method type encodings)

### The Database Path

```
~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite
```

This path has been stable since macOS 10.11 (El Capitan). If it changes, the `ICNoteContext` initialization will fail. Check for new `group.com.apple.notes*` containers.

### SIP and Entitlements

Currently, loading `NotesShared.framework` doesn't require special entitlements. If Apple adds an entitlement check (like they did for some HealthKit and PassKit frameworks), the framework will either refuse to load or refuse to initialize. The diagnostic would be `dlopen` succeeding but `startSharedContextWithOptions:` returning nil or crashing.

---

## Summary

Cider exists because Apple provides no public API for editing Notes content without destroying attachments. The private `NotesShared.framework` exposes the CRDT editing primitives that Notes.app itself uses, enabling text modification that preserves inline attachments in their exact positions.

The journey from "AppleScript destroys images" to "53 tests, 0 skips, pure framework" involved:
- 7 failed approaches (AppleScript, SQLite, protobuf, UI scripting, AX, VNC, XPC)
- Runtime introspection of ~1000 private Objective-C classes
- Reverse engineering a CRDT text model
- Discovering that `noteData.data` is gzip-compressed (not raw protobuf)
- Discovering that `visibleAttachments` returns an unordered `NSSet`
- Discovering that `addAttachmentWithFileURL:` doesn't insert into the CRDT
- Discovering that `markedForDeletion` must be filtered on all queries
- Building a complete CLI with add, edit, delete, move, search, attach, detach, export

The result is a single Objective-C file that compiles in under a second, runs headlessly over SSH, and does something Apple's own AppleScript bridge cannot.

---

*Last updated: February 19, 2026*  
*macOS 15.4 (Sequoia), Apple M4*  
*Cider v2.0.0*
