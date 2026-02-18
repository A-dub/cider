# crdtnotes

> Apple Notes CLI with CRDT attachment support

`crdtnotes` is a command-line interface for Apple Notes that uses Apple's private `NotesShared.framework` CRDT API (`ICTTMergeableString`) to edit notes while **preserving attachments in their original positions** — something that `AppleScript set body` cannot do.

## The Problem

Every existing Notes CLI (including the Python-based [`memo`](https://github.com/antoniorodr/memo)) uses AppleScript's `set body of note to "..."` to edit note content. This **destroys all images and attachments** because it replaces the entire note body with plain HTML.

## The Solution

`crdtnotes` uses the same CRDT (Conflict-free Replicated Data Type) engine that Apple's own Notes app uses internally:

```
ICTTMergeableString → beginEditing → replaceCharactersInRange:withString: → endEditing → generateIdsForLocalChanges
```

Attachments are represented as `U+FFFC` (Object Replacement Character) markers in the CRDT string. By operating at the character level, `crdtnotes` can edit text content around attachment positions without disturbing the attachments themselves.

## Installation

### Build from source (macOS only)

```bash
git clone https://github.com/a-d-w/crdtnotes
cd crdtnotes
clang -framework Foundation -framework CoreData -o crdtnotes crdtnotes.m
sudo cp crdtnotes /usr/local/bin/
```

Or use the Makefile:

```bash
make
make install
```

### Requirements

- macOS 12+ (Monterey or later recommended)
- Apple Notes app (default macOS app)
- No external dependencies

## Usage

### Notes

```bash
# List all notes
crdtnotes notes

# List notes in a folder
crdtnotes notes -f "Work"

# List all folders
crdtnotes notes -fl

# View note 3
crdtnotes notes -v 3

# Add a new note (opens $EDITOR, or reads from stdin)
crdtnotes notes -a
echo "Hello world" | crdtnotes notes -a

# Add note to a specific folder
crdtnotes notes -a -f "Work"

# Edit note 3 — uses CRDT API, preserves attachments!
crdtnotes notes -e 3

# Delete note 3
crdtnotes notes -d 3

# Move note 3 to "Archive" folder
crdtnotes notes -m 3 -f "Archive"

# Search notes
crdtnotes notes -s "meeting notes"

# Export all notes to HTML
crdtnotes notes --export ~/Desktop/notes-export

# Add a file attachment to note 3
crdtnotes notes --attach 3 ~/Downloads/photo.jpg
```

### Reminders

```bash
# List all incomplete reminders
crdtnotes rem

# Add a reminder
crdtnotes rem -a "Buy groceries"

# Add a reminder with a due date
crdtnotes rem -a "Doctor appointment" "December 31, 2025 9:00 AM"

# Edit reminder 2
crdtnotes rem -e 2 "Grocery run"

# Delete reminder 2
crdtnotes rem -d 2

# Complete reminder 1
crdtnotes rem -c 1
```

### Other

```bash
crdtnotes --version
crdtnotes --help
crdtnotes notes --help
crdtnotes rem --help
```

## How CRDT Editing Works

When you run `crdtnotes notes -e <N>`:

1. The note's raw text (with `U+FFFC` attachment markers) is fetched from the Notes database via `ICNoteContext`
2. Each `U+FFFC` is replaced with a `%%ATTACHMENT_N_filename%%` placeholder so you can see where attachments are
3. Your `$EDITOR` opens with the editable text
4. When you save and exit, the placeholders are restored to `U+FFFC`
5. A **longest-common-prefix/suffix diff** finds the minimal changed region
6. The CRDT API (`replaceCharactersInRange:withString:`) applies the change — only touching the text you edited, leaving attachment markers untouched
7. The change is saved to the Notes database

### Example

If a note contains:
```
My vacation photos

[📎 beach.jpg]

What a great trip!
```

In the editor you see:
```
My vacation photos

%%ATTACHMENT_0_beach.jpg%%

What a great trip!
```

You can freely edit the text before and after the marker. The marker itself must be left intact. On save, the attachment stays in place.

## Architecture

Single-file Objective-C (`crdtnotes.m`), compiled with `clang`. No external dependencies.

- **Notes operations**: Use `ICNoteContext` + `ICTTMergeableString` (CoreData / NotesShared.framework)
- **Add/Delete/Move/Attach**: Use `NSAppleScript` (simpler, well-tested)
- **Edit**: Uses CRDT API for attachment-safe edits
- **Reminders**: Use `NSAppleScript` (Reminders app)
- **Search**: Core Data predicate fetch (fast, no AppleScript needed)

## Private Framework

`crdtnotes` uses `NotesShared.framework`, a private Apple framework. Key classes:

| Class | Purpose |
|-------|---------|
| `ICNoteContext` | Opens the Notes Core Data store |
| `ICNote` | Core Data entity for a note |
| `ICFolder` | Core Data entity for a folder |
| `ICTTMergeableString` | CRDT string with attachment positions |

The framework is loaded at runtime via `dlopen()`, so the binary won't crash on systems where it's unavailable — it gracefully reports an error instead.

## Comparison with memo

| Feature | memo (Python) | crdtnotes |
|---------|--------------|-----------|
| List notes | ✅ | ✅ |
| View notes | ✅ | ✅ |
| Add notes | ✅ | ✅ |
| Edit notes | ⚠️ destroys attachments | ✅ CRDT-safe |
| Delete notes | ✅ | ✅ |
| Move notes | ✅ | ✅ |
| Search | ✅ | ✅ |
| Export HTML | ❌ | ✅ |
| Attachment-safe edit | ❌ | ✅ |
| Add attachment | ❌ | ✅ |
| No Python required | ❌ | ✅ |
| Speed | Slow (AppleScript) | Fast (CoreData) |

## License

MIT

## Acknowledgements

- [`memo`](https://github.com/antoniorodr/memo) by Antonio Rodriguez — the Python CLI this was inspired by
- Apple's Notes engineering team for building a CRDT engine accessible via private frameworks
