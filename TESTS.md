# Test Results

Tests run on macOS 15.4 (Sequoia), Apple M4.

## Build

```bash
clang -framework Foundation -framework CoreData -o cider cider.m
# → Compiles with no errors, no external dependencies
```

## Infrastructure

| Test | Command | Result |
|------|---------|--------|
| Version | `cider --version` | ✅ `cider v1.0.0` |
| Help | `cider --help` | ✅ Shows usage |
| Notes help | `cider notes --help` | ✅ Shows notes options |
| Rem help | `cider rem --help` | ✅ Shows reminders options |
| Framework load | (implicit) | ✅ NotesShared.framework loaded from dyld shared cache |

## Notes — Read Operations

| Test | Command | Result |
|------|---------|--------|
| List all notes | `cider notes` | ✅ 545+ notes listed (title, folder, attachment count) |
| Filter by folder | `cider notes -f Work` | ✅ Correct subset returned |
| List folders | `cider notes -fl` | ✅ 20 folders with parent/child structure |
| View note | `cider notes -v 16` | ✅ Body displayed with 📎 attachment markers |
| Search | `cider notes -s "meeting"` | ✅ Matching notes by title/snippet |
| Export HTML | `cider notes --export /tmp/export` | ✅ 546 HTML files + index.html |

## Notes — Write Operations

| Test | Command | Result |
|------|---------|--------|
| Add note (stdin) | `echo "test" \| cider notes -a -f Notes` | ✅ Note created |
| Add note ($EDITOR) | `cider notes -a -f Notes` | ✅ Opens editor, creates on save |
| Delete note | `cider notes -d 1` | ✅ Note moved to trash |
| Move note | `cider notes -m 3 -f Archive` | ✅ Note moved to target folder |
| Attach file | `cider notes --attach 3 photo.jpg` | ✅ Attachment added to note |

## CRDT Edit — Core Feature

| Test | Result |
|------|--------|
| Edit note title via CRDT | ✅ Title changed, save successful |
| Attachment preserved after edit | ✅ Confirmed: attachment count unchanged, image still inline |
| Edit text before attachment | ✅ Attachment position unchanged |
| Edit text after attachment | ✅ Attachment position unchanged |
| iCloud sync after CRDT edit | ✅ Edit persisted, no revert after 45+ seconds |
| Placeholder roundtrip (`%%ATTACHMENT_N%%`) | ✅ Markers survive editor save/load |

## Reminders

| Test | Command | Result |
|------|---------|--------|
| List reminders | `cider rem` | ✅ Lists incomplete reminders with due dates |
| Add reminder | `cider rem -a "Test"` | ✅ Created |
| Complete reminder | `cider rem -c 1` | ✅ Marked complete |

**Note:** Reminders operations require macOS automation permission for the Reminders app. On first run, macOS will prompt you to allow access in System Settings → Privacy & Security → Automation.

## Known Behaviors

- **`ICFolder` uses `title` not `name`** — discovered via runtime introspection of the private framework
- **`visibleAttachments` returns `NSSet`** — converted via `allObjects` for consistent ordering
- **`ICAttachment` has no `filename`** — uses `userTitle`/`title` attributes; falls back to `typeUTI` (e.g., `public.jpeg`)
- **Reminders automation** — requires interactive macOS session to approve the first time

## Private Framework API

```
ICNoteContext       → startSharedContextWithOptions:, sharedContext, managedObjectContext, save
ICNote              → mergeableString, visibleAttachments, updateDerivedAttributesIfNeeded
ICFolder            → title (via KVC), isTrashFolder
ICTTMergeableString → beginEditing, replaceCharactersInRange:withString:, endEditing, generateIdsForLocalChanges
```

Tested on macOS 15.4 Sequoia. These APIs have been stable across macOS 12–15 based on class hierarchy analysis.
