# Test Results

All tests run on Mac (macOS) via SSH, using the binary compiled from `crdtnotes.m`.

## Build

```
clang -framework Foundation -framework CoreData -o crdtnotes crdtnotes.m
→ Compiled OK (no errors)
```

## Core Infrastructure

| Test | Command | Result |
|------|---------|--------|
| Version flag | `crdtnotes --version` | ✅ `crdtnotes v1.0.0` |
| Help flag | `crdtnotes --help` | ✅ Full help displayed |
| Notes help | `crdtnotes notes --help` | ✅ Notes-specific help |
| Rem help | `crdtnotes rem --help` | ✅ Rem-specific help |
| Framework load | (implicit in all notes ops) | ✅ NotesShared.framework loads |

## Notes Commands

| Test | Command | Result |
|------|---------|--------|
| List all notes | `crdtnotes notes` | ✅ 545+ notes listed with title/folder/attachment count |
| Filter by folder | `crdtnotes notes -f Work` | ✅ 26 Work notes listed |
| List folders | `crdtnotes notes -fl` | ✅ 20 folders listed with parent/child structure |
| View note | `crdtnotes notes -v 16` | ✅ Header + body displayed with attachment markers |
| Search notes | `crdtnotes notes -s "Cal Test"` | ✅ 37 matching notes found |
| Add note (stdin) | `echo "text" \| crdtnotes notes -a -f Notes` | ✅ Note created via AppleScript |
| Delete note | `echo y \| crdtnotes notes -d 1` | ✅ Note deleted |
| Export to HTML | `crdtnotes notes --export /tmp/notes_export` | ✅ 546 files + index.html created |

## CRDT Edit — The Core Feature

| Test | Command | Result |
|------|---------|--------|
| Edit note title (CRDT) | `EDITOR=/tmp/test_editor.sh crdtnotes notes -e 16` | ✅ Title changed "Cal Test CLEAN" → "crdtnotes-EDIT-TEST" |
| Attachment preserved | AppleScript verify | ✅ `1 attachment` confirmed after CRDT edit |
| Restore title | `EDITOR=/tmp/restore_editor.sh crdtnotes notes -e 16` | ✅ Title restored "Cal Test CLEAN" |
| Attachment still preserved | `crdtnotes notes -v 16` | ✅ `📎 1 attachment(s): [public.data]` |

**CRDT edit algorithm:** longest-common-prefix/suffix diff → single `replaceCharactersInRange:withString:` call on `ICTTMergeableString`.

## Known Behaviors

- **Reminders over SSH:** Returns "Not authorized to send Apple events to Reminders." — requires interactive macOS session to grant automation permission. Normal Apple behavior.
- **Attachment names:** `ICAttachment` exposes `userTitle` and `title` attributes (no `filename`). Falls back to `typeUTI` (e.g., `public.jpeg`) when no title is set.
- **visibleAttachments returns NSSet:** Properly handled with `allObjects` conversion for consistent ordering.
- **ICFolder uses `title` not `name`:** Discovered via runtime introspection; fixed in code.

## Private Framework API Used

```
ICNoteContext   → startSharedContextWithOptions:, sharedContext, managedObjectContext, save
ICNote          → mergeableString, visibleAttachments, updateDerivedAttributesIfNeeded
ICFolder        → title (via KVC), isTrashFolder
ICTTMergeableString → beginEditing, replaceCharactersInRange:withString:, endEditing, generateIdsForLocalChanges
```
