# ✏️ Cider

> A native CLI for Apple apps. Notes and Reminders today — more tomorrow.

**Cider** is a fast, native command-line interface for Apple apps on macOS. Currently supports **Notes** (with attachment-safe CRDT editing) and **Reminders**. Unlike every other Notes CLI, Cider uses Apple's internal CRDT engine to edit notes — meaning your images, attachments, and drawings stay exactly where you put them.

## The Problem

Every existing Notes CLI uses AppleScript's `set body` to edit notes. This **destroys all images and attachments**. The [memo](https://github.com/antoniorodr/memo) CLI even warns you about it:

> ⚠️ Be careful when using --edit and --move flags with notes that include images/attachments.

Cider doesn't have that problem.

## How It Works

Apple Notes stores text as a CRDT (Conflict-free Replicated Data Type) using a private framework called `NotesShared.framework`. Cider loads this framework at runtime and calls the same editing API that Notes.app uses internally:

```
ICTTMergeableString → beginEditing → replaceCharactersInRange:withString: → endEditing
```

Attachments are `U+FFFC` characters in the CRDT string. By editing text around them at the character level, Cider never touches the attachment markers — they stay in their original position.

## Install

### Quick install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/A-dub/cider/master/install.sh | bash
```

This downloads the latest release binary for your architecture and installs to `/usr/local/bin`.

### Download manually

Grab the latest binary from [Releases](https://github.com/A-dub/cider/releases/latest):

```bash
# Download (Apple Silicon)
curl -fsSL -o cider https://github.com/A-dub/cider/releases/latest/download/cider-arm64

# Or Intel
curl -fsSL -o cider https://github.com/A-dub/cider/releases/latest/download/cider-x86_64

# Install
chmod +x cider
sudo mv cider /usr/local/bin/
```

### Build from source

```bash
git clone https://github.com/A-dub/cider
cd cider
make
make install   # copies to /usr/local/bin
```

Or manually:
```bash
clang -framework Foundation -framework CoreData -o cider cider.m
```

**Requirements:** macOS 12+ (Monterey or later). No Python, no pip, no Homebrew dependencies. Just `clang`.

## Usage

### Notes

```bash
# List all notes (default when no subcommand)
cider notes
cider notes list

# Filter by folder
cider notes list -f "Work"
cider notes list --folder Work

# List all folders
cider notes folders

# View note #3 (shows attachment positions)
cider notes 3
cider notes show 3

# JSON output (pipe-friendly)
cider notes list --json
cider notes show 3 --json
cider notes folders --json
cider notes search "meeting" --json

# Add a new note (opens $EDITOR)
cider notes add --folder Personal

# Add from stdin
echo "Quick thought" | cider notes add --folder Notes

# Edit note #3 — attachments stay in place! ✨
cider notes edit 3

# Edit from stdin (no editor needed)
echo "new content" | cider notes edit 3

# Find & replace in note #3 (fully scriptable, no editor)
cider notes replace 3 --find "old text" --replace "new text"

# Delete note #3
cider notes delete 3

# Move note #3 to Archive
cider notes move 3 Archive
cider notes move 3 --folder Archive

# Search notes
cider notes search "meeting"

# Export all notes to HTML
cider notes export ~/Desktop/notes-backup

# List attachments in note #3 (with positions and types)
cider notes attachments 3
cider notes attachments 3 --json

# Attach a file to note #3
cider notes attach 3 ~/Photos/vacation.jpg

# Attach at a specific text position (CRDT-based)
cider notes attach 3 ~/Photos/vacation.jpg --at 42

# Remove attachment #1 from note #3
cider notes detach 3 1

# Interactive mode: omit N to get prompted (when stdin is a terminal)
cider notes edit       # shows list, prompts "Enter note number to edit: "
cider notes delete     # same for delete, show, move, replace, attach, detach
```

#### Backwards compatibility

Old flag syntax still works:

```bash
cider notes -fl          # → cider notes folders
cider notes -v 3         # → cider notes show 3
cider notes -e 3         # → cider notes edit 3
cider notes -d 3         # → cider notes delete 3
cider notes -s "query"   # → cider notes search "query"
cider notes -f Work      # → cider notes list --folder Work
cider notes -a -f Work   # → cider notes add --folder Work
cider notes -m 3 -f Arc  # → cider notes move 3 Archive
cider notes --export ~/Desktop/export  # still works
cider notes --attach 3 file.jpg        # still works
```

### Reminders

```bash
# List incomplete reminders (default)
cider rem
cider rem list

# Add a reminder
cider rem add "Buy groceries"

# Add with due date
cider rem add "Doctor" "March 15, 2026 9:00 AM"

# Edit reminder #2
cider rem edit 2 "Updated title"

# Complete reminder #1
cider rem complete 1

# Delete reminder #2
cider rem delete 2
```

## How Editing Works

When you run `cider notes edit 3`:

1. Cider reads the note's CRDT string from the Notes database
2. Attachment markers (`U+FFFC`) become visible placeholders:
   ```
   My vacation photos

   %%ATTACHMENT_0_beach.jpg%%

   What a great trip!
   ```
3. Your `$EDITOR` opens with the text
4. You edit the text — leave placeholders intact
5. On save, Cider computes the minimal diff and applies it via the CRDT API
6. Attachments remain in their original position. iCloud syncs normally.

**Pipe mode:** When stdin is not a terminal, the new content is read from stdin directly — no editor opens. The `%%ATTACHMENT_N_name%%` placeholders still work if you include them.

```bash
echo "new content" | cider notes edit 3
```

**Replace command:** For scripting, `replace` lets you do surgical find-and-replace without an editor:

```bash
cider notes replace 3 --find "old text" --replace "new text"
```

## Architecture

| Component | How |
|-----------|-----|
| **Edit / Replace** | `ICTTMergeableString` CRDT API (preserves attachments) |
| **List / View / Search** | Core Data fetch via `ICNoteContext` (fast) |
| **Add** | Core Data insert + CRDT text + `saveNoteData` |
| **Delete** | `deleteFromLocalDatabase` (framework) |
| **Move** | `setFolder:` (framework) |
| **Attach / Detach** | CRDT API (`addAttachmentWithFileURL:` + attributed string) |
| **Reminders** | `NSAppleScript` (Reminders.app — only remaining AppleScript user) |

All Notes operations use the private framework directly — no AppleScript, no Notes.app process needed. Single Objective-C file. No external dependencies. Compiles in under a second.

## Private Framework Details

Cider uses `NotesShared.framework`, loaded via `dlopen()` at runtime. If the framework isn't available (wrong macOS version, changes in a future update), Cider fails gracefully with a clear error message.

Key classes used:

| Class | Purpose |
|-------|---------|
| `ICNoteContext` | Opens the Notes Core Data store |
| `ICNote` | Note entity (title, body, attachments) |
| `ICFolder` | Folder entity |
| `ICTTMergeableString` | CRDT string — the magic that preserves attachments |

See [Reverse Engineering Notes](https://github.com/A-dub/cider/wiki) for the full technical deep-dive on how these APIs were discovered.

## Comparison with memo

| Feature | [memo](https://github.com/antoniorodr/memo) | Cider |
|---------|------|-------|
| List notes | ✅ | ✅ |
| View notes | ✅ (Markdown) | ✅ (plain text + attachment markers) |
| Add notes | ✅ | ✅ |
| **Edit notes** | ⚠️ **destroys attachments** | ✅ **CRDT-safe** |
| **Replace text** | ❌ | ✅ (scriptable, no editor) |
| Delete notes | ✅ | ✅ |
| Move notes | ⚠️ recreates note | ✅ native move |
| Search | ✅ (fzf) | ✅ (Core Data) |
| Export | ✅ HTML+MD | ✅ HTML |
| **Attach files** | ❌ | ✅ |
| **Remove attachments** | ❌ | ✅ (CRDT + entity cleanup) |
| **Preserve images on edit** | ❌ | ✅ |
| **JSON output** | ❌ | ✅ (`--json` flag) |
| **Pipe-friendly** | ❌ | ✅ (stdin edit, JSON out) |
| Dependencies | Python, Click, mistune, html2text | **None** |
| Language | Python | Objective-C |
| Speed | Slow (AppleScript for everything) | Fast (Core Data for reads) |

## Troubleshooting

**"Cannot access the Notes database"** — cider needs Full Disk Access to read the Notes and Reminders databases. Go to **System Settings → Privacy & Security → Full Disk Access** and add your terminal app (Terminal.app, iTerm, Warp, etc.). Restart your terminal after granting access.

**"Failed to load NotesShared.framework"** — You're on an unsupported macOS version, or Apple changed the framework location. Check the [troubleshooting guide](https://github.com/A-dub/cider/wiki).

**"Not authorized to send Apple events"** — Reminders still uses AppleScript as a fallback. Go to System Settings → Privacy & Security → Automation and allow your terminal app to control Reminders.

## License

MIT

## Credits

- Inspired by [`memo`](https://github.com/antoniorodr/memo) by Antonio Rodriguez
- Built by reverse-engineering Apple's `NotesShared.framework` CRDT engine
