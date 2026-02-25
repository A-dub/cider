# Disaster Recovery — Cider Sync

This document describes how to recover your Apple Notes data if something goes wrong during sync.

## Backups

Cider Sync creates automatic backups before every first-run initialization. You can also create manual backups:

```bash
cider sync backup                    # backup to ~/CiderSync/.cider-backups/
cider sync backup --dir ~/my-sync    # backup to ~/my-sync/.cider-backups/
```

Each backup contains:
- `NoteStore.sqlite` — the full Notes database
- `NoteStore.sqlite-wal` — write-ahead log (if present)
- `NoteStore.sqlite-shm` — shared memory file (if present)
- `Media/` — all attachment files
- `backup-manifest.json` — file sizes, SHA-256 hashes, timestamp

Backups are stored in `.cider-backups/backup-YYYYMMDD-HHMMSS/` within the sync directory.

## Verifying a Backup

Each backup includes a SHA-256 hash of the database verified via `PRAGMA integrity_check`. The manifest records:

```json
{
  "timestamp": "2026-02-25T10:00:00Z",
  "database_sha256": "abc123...",
  "integrity_check": "ok",
  "files": [
    {"path": "NoteStore.sqlite", "size": 1048576},
    {"path": "Media/...", "size": 204800}
  ]
}
```

## Restoring from Backup

**WARNING:** Restoration replaces your current Notes database. All changes since the backup will be lost.

### Step 1: Quit Notes.app

```bash
osascript -e 'tell application "Notes" to quit'
```

### Step 2: Locate your backup

```bash
ls ~/CiderSync/.cider-backups/
# Choose the backup you want to restore from
```

### Step 3: Replace the database

```bash
NOTES_DIR="$HOME/Library/Group Containers/group.com.apple.notes"
BACKUP_DIR="$HOME/CiderSync/.cider-backups/backup-XXXXXXXX-XXXXXX"

# Remove current database files
rm -f "$NOTES_DIR/NoteStore.sqlite"
rm -f "$NOTES_DIR/NoteStore.sqlite-wal"
rm -f "$NOTES_DIR/NoteStore.sqlite-shm"

# Copy backup database
cp "$BACKUP_DIR/NoteStore.sqlite" "$NOTES_DIR/"
cp "$BACKUP_DIR/NoteStore.sqlite-wal" "$NOTES_DIR/" 2>/dev/null
cp "$BACKUP_DIR/NoteStore.sqlite-shm" "$NOTES_DIR/" 2>/dev/null
```

### Step 4: Restore attachments (if needed)

```bash
# Only needed if attachments were corrupted
ACCOUNTS_DIR="$NOTES_DIR/Accounts"
cp -R "$BACKUP_DIR/Media/"* "$ACCOUNTS_DIR/" 2>/dev/null
```

### Step 5: Reopen Notes.app

```bash
open -a Notes
```

Notes.app will re-sync with iCloud. Local-only notes will be restored from the backup. iCloud notes may re-download from the server.

## Safety Guarantees

Cider Sync is designed with these safety rules:

1. **Pre-existing notes are never modified** — Notes created in Apple Notes are exported as read-only Markdown (`editable: false`). Local edits to these files are ignored.
2. **Notes are never deleted** — Deleting a Markdown file only untracks it; the Apple Note is never deleted.
3. **Automatic backup on first run** — The first `cider sync run` or `cider sync watch` creates a full backup automatically.
4. **Conflict resolution preserves both versions** — When both sides change, the conflict file is saved as `<file>.conflict-<timestamp>.md`.

## If Something Goes Wrong

### Notes look corrupted or empty

1. Quit Notes.app
2. Restore from the most recent backup (see above)
3. Re-open Notes.app

### A note's attachments are missing

Cider Sync never modifies attachment markers on pre-existing notes. If attachments are missing:

1. Check the `attachments/` directory in your sync folder
2. Attachments are organized by note PK: `attachments/<note_pk>/filename.ext`
3. If the original files exist in the backup's `Media/` directory, copy them back

### Sync state is confused

Delete the sync state file to force a fresh export:

```bash
rm ~/CiderSync/.cider-sync-state.json
cider sync run
```

This will re-export all notes without modifying any Apple Notes.

### A conflict file appeared

Files named `*.conflict-*.md` mean both sides changed since the last sync:

1. Open both the original `.md` and the `.conflict-*.md` file
2. Manually reconcile the differences
3. Save your changes to the original `.md` file
4. Delete the `.conflict-*.md` file
5. Run `cider sync run` to push changes
