# Disable Git Sync — Design Spec

**Date:** 2026-05-16  
**Status:** Approved

## Goal

Disable all git/sync functionality in the Frame Art Manager add-on while keeping the code in place for easy re-enablement. Remove git tooling from the Docker image and startup scripts to keep things lean.

## Approach

Feature flag via `SYNC_ENABLED` env var. Default is `true` (opt-in disable) so the flag only needs to be set explicitly to turn sync off. `run.sh` exports `SYNC_ENABLED=false`.

---

## Section 1 — Backend flag & route gating

**File: `frame_art_manager/app/server.js`**
- Add `const SYNC_ENABLED = process.env.SYNC_ENABLED !== 'false';` near the top
- Add a new `GET /api/config` endpoint returning `{ syncEnabled: SYNC_ENABLED }`
- Gate the sync router mount: `if (SYNC_ENABLED) app.use('/api/sync', syncRouter);`

**File: `frame_art_manager/run.sh`**
- Export `SYNC_ENABLED=false` before `exec node server.js`

---

## Section 2 — Frontend hide

**File: `frame_art_manager/app/public/js/app.js`**
- On `DOMContentLoaded`, fetch `/api/config` before any other sync calls
- If `syncEnabled === false`:
  - Set `#sync-btn` to `display:none`
  - Set the `[data-tab="sync"]` button to `display:none`
  - Skip calling `checkSyncOnLoad()` and `autoPushLocalChanges()`
- All existing sync functions remain in the file — they just never get invoked

---

## Section 3 — Dockerfile & run.sh cleanup

**File: `frame_art_manager/Dockerfile`**
- Remove `git`, `git-lfs`, `openssh-client` from the `apk add` line
- Remove `&& git lfs install`

**File: `frame_art_manager/run.sh`**
- Remove SSH key setup block (currently lines 18–71)
- Remove Git LFS SSH configuration block (currently lines 85–136)
- Add `export SYNC_ENABLED=false` just before `exec node server.js`

**File: `frame_art_manager/config.yaml`**
- Remove `ssh_private_key` and `git_remote_host_alias` from `options` and `schema`

---

## Re-enabling sync

Set `SYNC_ENABLED=true` in `run.sh` (or remove the export entirely). Git/LFS/SSH tooling would need to be added back to the Dockerfile and run.sh manually.

## Out of scope

- Deleting `git_helper.js`, `routes/sync.js`, or sync-related tests
- Any changes to image upload, metadata, or tag functionality
