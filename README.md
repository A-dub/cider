# ✏️ Jotty

> The only Apple Notes CLI that doesn't destroy your images.

**Jotty** is a fast, native command-line interface for Apple Notes and Reminders on macOS. Unlike every other Notes CLI, Jotty uses Apple's internal CRDT engine to edit notes — meaning your images, attachments, and drawings stay exactly where you put them.

## The Problem

Every existing Notes CLI uses AppleScript's `set body` to edit notes. This **destroys all images and attachments**. The [memo](https://github.com/antoniorodr/memo) CLI even warns you about it:

> ⚠️ Be careful when using --edit and --move flags with notes that include images/attachments.

Jotty doesn't have that problem.

## How It Works

Apple Notes stores text as a CRDT (Conflict-free Replicated Data Type) using a private framework called `NotesShared.framework`. Jotty loads this framework at runtime and calls the same editing API that Notes.app uses internally:

```
ICTTMergeableString → beginEditing → replaceCharactersInRange:withString: → endEditing
```

Attachments are `U+FFFC` characters in the CRDT string. By editing text around them at the character level, Jotty never touches the attachment markers — they stay in their original position.

## Install

```bash
git clone https://github.com/A-dub/jotty
cd jotty
make
make install   # copies to /usr/local/bin
```

Or manually:
```bash
clang -framework Foundation -framework CoreData -o jotty jotty.m
cp jotty /usr/local/bin/
```

**Requirements:** macOS 12+ (Monterey or later). No Python, no pip, no Homebrew dependencies. Just `clang`.

## Usage

### Notes

```bash
# List all notes
jotty notes

# Filter by folder
jotty notes -f "Work"

# List all folders
jotty notes -fl

# View note #3 (shows attachment positions)
jotty notes -v 3

# Add a new note (opens $EDITOR)
jotty notes -a -f "Personal"

# Add from stdin
echo "Quick thought" | jotty notes -a -f "Notes"

# Edit note #3 — attachments stay in place! ✨
jotty notes -e 3

# Delete note #3
jotty notes -d 3

# Move note #3 to Archive
jotty notes -m 3 -f "Archive"

# Search notes
jotty notes -s "meeting"

# Export all notes to HTML
jotty notes --export ~/Desktop/notes-backup

# Attach a file to note #3
jotty notes --attach 3 ~/Photos/vacation.jpg
```

### Reminders

```bash
# List incomplete reminders
jotty rem

# Add a reminder
jotty rem -a "Buy groceries"

# Add with due date
jotty rem -a "Doctor" "March 15, 2026 9:00 AM"

# Edit reminder #2
jotty rem -e 2 "Updated title"

# Complete reminder #1
jotty rem -c 1

# Delete reminder #2
jotty rem -d 2
```

## How Editing Works

When you run `jotty notes -e 3`:

1. Jotty reads the note's CRDT string from the Notes database
2. Attachment markers (`U+FFFC`) become visible placeholders:
   ```
   My vacation photos

   %%ATTACHMENT_0_beach.jpg%%

   What a great trip!
   ```
3. Your `$EDITOR` opens with the text
4. You edit the text — leave placeholders intact
5. On save, Jotty computes the minimal diff and applies it via the CRDT API
6. Attachments remain in their original position. iCloud syncs normally.

## Architecture

| Component | How |
|-----------|-----|
| **Edit** | `ICTTMergeableString` CRDT API (preserves attachments) |
| **List / View / Search** | Core Data fetch via `ICNoteContext` (fast, no AppleScript) |
| **Add / Delete / Move** | `NSAppleScript` (reliable, handles iCloud sync) |
| **Attach** | `NSAppleScript` (`make new attachment`) |
| **Reminders** | `NSAppleScript` (Reminders.app) |

Single Objective-C file. No external dependencies. Compiles in under a second.

## Private Framework Details

Jotty uses `NotesShared.framework`, loaded via `dlopen()` at runtime. If the framework isn't available (wrong macOS version, changes in a future update), Jotty fails gracefully with a clear error message.

Key classes used:

| Class | Purpose |
|-------|---------|
| `ICNoteContext` | Opens the Notes Core Data store |
| `ICNote` | Note entity (title, body, attachments) |
| `ICFolder` | Folder entity |
| `ICTTMergeableString` | CRDT string — the magic that preserves attachments |

See [Reverse Engineering Notes](https://github.com/A-dub/jotty/wiki) for the full technical deep-dive on how these APIs were discovered.

## Comparison with memo

| Feature | [memo](https://github.com/antoniorodr/memo) | Jotty |
|---------|------|-------|
| List notes | ✅ | ✅ |
| View notes | ✅ (Markdown) | ✅ (plain text + attachment markers) |
| Add notes | ✅ | ✅ |
| **Edit notes** | ⚠️ **destroys attachments** | ✅ **CRDT-safe** |
| Delete notes | ✅ | ✅ |
| Move notes | ⚠️ recreates note | ✅ native move |
| Search | ✅ (fzf) | ✅ (Core Data) |
| Export | ✅ HTML+MD | ✅ HTML |
| **Attach files** | ❌ | ✅ |
| **Preserve images on edit** | ❌ | ✅ |
| Dependencies | Python, Click, mistune, html2text | **None** |
| Language | Python | Objective-C |
| Speed | Slow (AppleScript for everything) | Fast (Core Data for reads) |

## Troubleshooting

**"Not authorized to send Apple events"** — macOS needs permission for automation. Go to System Settings → Privacy & Security → Automation and allow your terminal app to control Notes and Reminders.

**"Failed to load NotesShared.framework"** — You're on an unsupported macOS version, or Apple changed the framework location. Check the [troubleshooting guide](https://github.com/A-dub/jotty/wiki).

**Reminders not working** — Reminders requires a one-time automation approval. Run any `jotty rem` command from Terminal.app (not over SSH) the first time to trigger the permission dialog.

## License

MIT

## Credits

- Inspired by [`memo`](https://github.com/antoniorodr/memo) by Antonio Rodriguez
- Built by reverse-engineering Apple's `NotesShared.framework` CRDT engine
