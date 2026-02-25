# Cider Sync — Bidirectional Apple Notes / Markdown Sync

Cider Sync mirrors your Apple Notes to local Markdown files and syncs changes back. Edit notes in your favorite editor, version them with git, or process them with scripts — all while keeping Apple Notes as the source of truth.

## Quick Start

```bash
# One sync cycle (auto-initializes on first run with backup + export)
cider sync run

# Continuous sync daemon (polls every 2 seconds)
cider sync watch

# Manual backup
cider sync backup
```

## Commands

### `cider sync run [--dir <path>]`

Runs a single bidirectional sync cycle. On first run, automatically creates a backup and performs initial export.

Default sync directory: `~/CiderSync`

### `cider sync watch [--dir <path>] [--interval <secs>]`

Runs continuous sync, polling for changes every N seconds (default: 2). Press Ctrl+C to stop.

### `cider sync backup [--dir <path>]`

Creates a timestamped backup of the Notes database and all attachments. Backups are stored in `<sync-dir>/.cider-backups/`.

## Directory Layout

```
~/CiderSync/
  Notes/
    My_First_Note.md
    Shopping_List.md
  Work/
    Project_Plan.md
    Meeting_Notes.md
  attachments/
    42/
      photo.jpg
      diagram.png
    87/
      document.pdf
  .cider-sync-state.json
  .cider-backups/
    backup-20260225-100000/
      NoteStore.sqlite
      backup-manifest.json
      Media/
  .cider-archive/
```

## Markdown Format

Each note becomes a Markdown file with YAML frontmatter:

```yaml
---
note_id: "x-coredata://...ICNote/p42"
title: "My Note"
folder: "Notes"
modified: "2026-02-25T10:00:00Z"
editable: false
---

Note content here...

![photo.jpg](../attachments/42/photo.jpg)

More content...

[document.pdf](../attachments/42/document.pdf)
```

## Editability Rules

### `editable: false` (Pre-existing notes)

Notes that were created in Apple Notes are **read-only** in sync. The Markdown file reflects the note's content, but local edits are ignored (with a warning). The Apple Note is authoritative.

This ensures cider never accidentally modifies notes you created by hand.

### `editable: true` (Sync-created notes)

Notes created by cider sync (either from new Markdown files or via `cider notes add`) are **bidirectional**. Edit the Markdown file and run sync — changes are applied to the Apple Note via CRDT. Edit in Apple Notes — changes appear in the Markdown file.

### New Markdown files (no frontmatter)

Drop a new `.md` file into the sync directory. On the next sync, cider creates a corresponding Apple Note and marks it `editable: true`.

## Conflict Resolution

When both the Apple Note and the Markdown file change between syncs:

1. **Auto-merge attempted** — Cider computes a 3-way diff using the last-synced version as the common ancestor. If changes are in different regions, both are applied cleanly.
2. **If merge conflicts** — The local version is saved as `<file>.conflict-<timestamp>.md`, the Apple Note version is written to the original file, and a warning is logged.

## Attachments

- **Images** in notes become `![name](../attachments/<pk>/name)` in Markdown
- **Non-image files** become `[name](../attachments/<pk>/name)`
- Adding an image reference in an `editable: true` note triggers attachment creation on sync
- Attachment files are extracted from the Notes media directory

## Safety

- Pre-existing Apple Notes are **never modified or deleted**
- Deleting a Markdown file **never** deletes the Apple Note (it's just untracked)
- Deleted Apple Notes have their Markdown moved to `.cider-archive/`
- First run always creates a full database backup
- See [DISASTER-RECOVERY.md](DISASTER-RECOVERY.md) for restoration instructions
