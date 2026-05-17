# Disable Git Sync — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Disable all git/sync functionality behind a `SYNC_ENABLED=false` env var, hide the sync UI, and strip git tooling from the Docker image and startup script.

**Architecture:** `server.js` already has `SYNC_ENABLED` + `/api/config` + gated route mount. The frontend has a `fetchConfig()` function and `syncEnabled` variable but they have two bugs and aren't wired to actually hide UI or skip sync calls. `run.sh` already exports `SYNC_ENABLED=false` but still contains the SSH and Git LFS setup blocks. Dockerfile and `config.yaml` still reference git packages and git options.

**Tech Stack:** Node.js/Express backend, vanilla JS frontend, Bash startup script, Alpine Linux Docker image.

---

## File Map

| File | Status | Change |
|------|--------|--------|
| `frame_art_manager/app/public/js/app.js` | Partial — has `syncEnabled` var + `fetchConfig()` with two bugs | Fix bugs, await config, hide UI, gate `checkSyncOnLoad()` |
| `frame_art_manager/run.sh` | Partial — has `SYNC_ENABLED=false` but SSH+LFS blocks remain | Remove SSH key block and Git LFS block |
| `frame_art_manager/Dockerfile` | Untouched | Remove `git`, `git-lfs`, `openssh-client`, `git lfs install` |
| `frame_art_manager/config.yaml` | Untouched | Remove `ssh_private_key` + `git_remote_host_alias`, bump version to `1.26.0` |
| `frame_art_manager/app/server.js` | Complete — no changes needed | — |

---

## Task 1: Fix `fetchConfig()` and wire it into DOMContentLoaded

**Files:**
- Modify: `frame_art_manager/app/public/js/app.js` (around lines 843–859 and 1318–1374)

There are two bugs in `fetchConfig()`:
1. Extra stray `}` before the function's closing brace (syntax error)
2. `data.syncEnabled || null` converts `false` → `null` due to falsy evaluation, so sync is never actually disabled

And the `DOMContentLoaded` handler calls `fetchConfig()` without `await`, so `syncEnabled` is still `null` when the sync calls are made.

- [ ] **Step 1: Fix `fetchConfig()`**

Replace the entire `fetchConfig` function (currently lines ~843–859):

```js
async function fetchConfig() {
  try {
    const response = await fetch(`${API_BASE}/config`);
    if (!response.ok) throw new Error('Failed to fetch config.');
    const data = await response.json();
    syncEnabled = data.syncEnabled !== undefined ? data.syncEnabled : null;
    return syncEnabled;
  } catch (error) {
    console.error('Error fetching config:', error);
    syncEnabled = null;
    return null;
  }
}
```

- [ ] **Step 2: Await config and hide UI in DOMContentLoaded**

Replace the opening of the `DOMContentLoaded` handler. Find:

```js
document.addEventListener('DOMContentLoaded', async () => {
  fetchConfig();
  initTabs();
  loadLibraryPath();
  initCloudSyncButton(); // Initialize cloud sync button in toolbar - BEFORE checking sync
```

Replace with:

```js
document.addEventListener('DOMContentLoaded', async () => {
  await fetchConfig();
  if (syncEnabled === false) {
    const syncBtn = document.getElementById('sync-btn');
    if (syncBtn) syncBtn.style.display = 'none';
    const syncTabBtn = document.querySelector('.advanced-tab-btn[data-tab="sync"]');
    if (syncTabBtn) syncTabBtn.style.display = 'none';
  }
  initTabs();
  loadLibraryPath();
  initCloudSyncButton(); // Initialize cloud sync button in toolbar - BEFORE checking sync
```

- [ ] **Step 3: Gate `checkSyncOnLoad()`**

Find:

```js
  // Check for sync updates in the background (after UI is loaded)
  checkSyncOnLoad();
```

Replace with:

```js
  // Check for sync updates in the background (after UI is loaded)
  if (syncEnabled !== false) checkSyncOnLoad();
```

- [ ] **Step 4: Verify no JS syntax errors**

Run from the `frame_art_manager/app` directory:

```bash
node --check public/js/app.js
```

Expected: no output (clean parse). If you see a SyntaxError, fix it before continuing.

- [ ] **Step 5: Commit**

```bash
git add frame_art_manager/app/public/js/app.js
git commit -m "feat: gate sync UI and calls behind SYNC_ENABLED flag"
```

---

## Task 2: Strip SSH and Git LFS setup from `run.sh`

**Files:**
- Modify: `frame_art_manager/run.sh`

`SYNC_ENABLED=false` is already exported at the bottom. Remove the two blocks that are now dead code.

- [ ] **Step 1: Remove the SSH key setup block**

Find and delete this entire block (from the comment through the closing `fi`):

```bash
# Set up SSH keys for Git if provided
if bashio::config.has_value 'ssh_private_key'; then
    bashio::log.info "Setting up SSH key for Git..."

    mkdir -p /root/.ssh
    chmod 700 /root/.ssh

    KEY_PATH=/root/.ssh/id_ed25519
    rm -f "${KEY_PATH}"

    # Get SSH key from config (bashio returns it as a plain string with the array joined)
    RAW_CONFIG=$(bashio::config 'ssh_private_key' 2>&1)

    if [ $? -ne 0 ]; then
        bashio::log.error "Failed to read SSH key configuration"
        bashio::exit.nok "Cannot read SSH key configuration"
    fi

    # Write the key to file
    echo "${RAW_CONFIG}" > "${KEY_PATH}"
    chmod 600 "${KEY_PATH}"

    # Validate the SSH key
    if ! ssh-keygen -y -f "${KEY_PATH}" > /dev/null 2>&1; then
        bashio::log.error "Invalid SSH key. Please verify your key is entered correctly (one line per entry)"
        rm -f "${KEY_PATH}"
        bashio::exit.nok "Invalid SSH key"
    fi

    # Get the git remote host alias (default: github-billy)
    GIT_HOST_ALIAS=$(bashio::config 'git_remote_host_alias')
    if bashio::var.is_empty "${GIT_HOST_ALIAS}"; then
        GIT_HOST_ALIAS="github-billy"
    fi

    # Create SSH config for the git remote host
    cat > /root/.ssh/config <<EOF
Host ${GIT_HOST_ALIAS}
    HostName github.com
    User git
    IdentityFile /root/.ssh/id_ed25519
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
    chmod 600 /root/.ssh/config

    # Add GitHub to known_hosts
    ssh-keyscan github.com >> /root/.ssh/known_hosts 2>/dev/null

    bashio::log.info "✓ SSH key configured for ${GIT_HOST_ALIAS}"
else
    bashio::log.info "No SSH private key configured"
    bashio::log.warning "Git sync will not work without an SSH key"
fi
```

- [ ] **Step 2: Remove the Git LFS SSH configuration block**

Find and delete this entire block:

```bash
# Ensure Git LFS uses the SSH remote when available
if git -C "${FRAME_ART_PATH}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    remote_url=$(git -C "${FRAME_ART_PATH}" remote get-url origin 2>/dev/null || true)

    if [ -n "${remote_url}" ] && [[ ${remote_url} != http* ]]; then
        user_part=""
        host_part=""
        path_part=""
        authority=""

        if [[ "${remote_url}" =~ ^([^@]+@)?([^:]+):(.+)$ ]]; then
            user_part="${BASH_REMATCH[1]}"
            host_part="${BASH_REMATCH[2]}"
            path_part="${BASH_REMATCH[3]}"
            authority="${user_part}${host_part}"
        elif [[ "${remote_url}" == ssh://* ]]; then
            trimmed="${remote_url#ssh://}"
            authority="${trimmed%%/*}"
            path_part="${trimmed#*/}"
        fi

        if [ -n "${authority}" ] && [ -n "${path_part}" ]; then
            repo_path="${path_part%.git}"
            if [ -z "${repo_path}" ]; then
                repo_path="${path_part}"
            fi

            ssh_base_url="ssh://${authority}/${repo_path}"
            ssh_endpoint="${authority}:${repo_path}"

            current_remote_lfs=$(git -C "${FRAME_ART_PATH}" config --get remote.origin.lfsurl 2>/dev/null || true)
            if [ "${current_remote_lfs}" != "${ssh_base_url}" ]; then
                git -C "${FRAME_ART_PATH}" config remote.origin.lfsurl "${ssh_base_url}"
            fi

            current_lfs_url=$(git -C "${FRAME_ART_PATH}" config --get lfs.url 2>/dev/null || true)
            if [ "${current_lfs_url}" != "${ssh_base_url}" ]; then
                git -C "${FRAME_ART_PATH}" config lfs.url "${ssh_base_url}"
            fi

            current_endpoint=$(git -C "${FRAME_ART_PATH}" config --get lfs.ssh.endpoint 2>/dev/null || true)
            if [ "${current_endpoint}" != "${ssh_endpoint}" ]; then
                git -C "${FRAME_ART_PATH}" config lfs.ssh.endpoint "${ssh_endpoint}"
            fi

            git -C "${FRAME_ART_PATH}" config --unset "lfs.https://github.com/${repo_path}.git/info/lfs.access" 2>/dev/null || true
            git -C "${FRAME_ART_PATH}" config --unset "lfs.https://github.com/${repo_path}/info/lfs.access" 2>/dev/null || true

            bashio::log.info "Configured Git LFS to use SSH endpoint for origin remote"
        fi
    fi
fi
```

- [ ] **Step 3: Verify the final `run.sh` looks right**

The file should now contain only: config reads + logging, the `/config` mount check, the frame art directory creation, the env exports, and `exec node server.js`. Confirm by reading the file — it should be roughly 30 lines.

- [ ] **Step 4: Commit**

```bash
git add frame_art_manager/run.sh
git commit -m "chore: remove SSH and Git LFS setup from run.sh"
```

---

## Task 3: Remove git packages from Dockerfile

**Files:**
- Modify: `frame_art_manager/Dockerfile`

- [ ] **Step 1: Remove git packages**

Find:

```dockerfile
# Install Node.js, git, and git-lfs
RUN apk add --no-cache \
    nodejs \
    npm \
    git \
    git-lfs \
    openssh-client \
    python3 \
    make \
    g++ \
    jq \
    && git lfs install
```

Replace with:

```dockerfile
# Install Node.js dependencies
RUN apk add --no-cache \
    nodejs \
    npm \
    python3 \
    make \
    g++ \
    jq
```

- [ ] **Step 2: Commit**

```bash
git add frame_art_manager/Dockerfile
git commit -m "chore: remove git, git-lfs, openssh-client from Docker image"
```

---

## Task 4: Clean up `config.yaml` and bump version

**Files:**
- Modify: `frame_art_manager/config.yaml`

- [ ] **Step 1: Remove git options and bump version**

The file currently starts with `version: "1.25.11"` and contains `git_remote_host_alias` and `ssh_private_key` in both `options` and `schema`.

Make these changes:

1. Change `version: "1.25.11"` → `version: "1.26.0"`

2. Remove from `options`:
   ```yaml
     git_remote_host_alias: "github-billy"
     ssh_private_key: []
   ```

3. Remove from `schema`:
   ```yaml
     git_remote_host_alias: str?
     ssh_private_key:
       - str?
   ```

The final `options` block should be:
```yaml
options:
  frame_art_path: /config/www/frame_art
  port: 8099
```

The final `schema` block should be:
```yaml
schema:
  frame_art_path: str
  port: int
```

- [ ] **Step 2: Verify the config looks correct**

Read the file back and confirm it matches:

```yaml
# Frame Art Manager Add-on Configuration
name: Frame Art Manager
version: "1.26.0"
slug: frame_art_manager
description: Manage Frame TV artwork library
url: https://github.com/punissuer/ha-frame-art-manager
arch:
  - aarch64
  - amd64
  - armhf
  - armv7
  - i386
init: false
startup: application
boot: auto
options:
  frame_art_path: /config/www/frame_art
  port: 8099
schema:
  frame_art_path: str
  port: int
map:
  - config:rw
ports:
  8099/tcp: 8099
ports_description:
  8099/tcp: Web interface
ingress: true
ingress_port: 8099
ingress_stream: false
panel_icon: mdi:image-frame
panel_title: Frame Art Manager
webui: http://[HOST]:[PORT:8099]
homeassistant_api: true
auth_api: false
hassio_api: true
hassio_role: default
```

- [ ] **Step 3: Commit**

```bash
git add frame_art_manager/config.yaml
git commit -m "chore: remove git config options, bump version to 1.26.0"
```

---

## Task 5: Push and update in Home Assistant

- [ ] **Step 1: Push to GitHub**

```bash
git push
```

- [ ] **Step 2: Trigger update check in HA**

In Home Assistant: **Settings → Add-ons → Add-on Store → ⋮ (top right) → Check for updates**

- [ ] **Step 3: Update the add-on**

Find **Frame Art Manager** in the store — it should now show version `1.26.0` with an **Update** button. Click **Update** and wait for the rebuild (2–5 minutes).

- [ ] **Step 4: Verify**

After the add-on restarts:
- The sync button in the toolbar should not be visible
- The "Sync Detail" tab in the Advanced panel should not be visible
- The add-on log (Settings → Add-ons → Frame Art Manager → Log) should show no SSH or Git LFS messages at startup
