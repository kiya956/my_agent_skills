---
name: cbprovider-domain
description: Create checkbox test cases from kernel_readdoc for a specific kernel subsystem domain (e.g. drm, sound, usb, acpi). Pass the domain name as the argument.
---

# cbprovider-domain

Generates and debugs checkbox provider test jobs for a specific kernel subsystem by
importing Python bpftrace test scripts from `~/canonical/workspace/kernel_readdoc`
into `~/canonical/workspace/checkbox-provider-kprovider`.

## Usage

```
/cbprovider-domain <domain>                              # Mode A: create/update (default)
/cbprovider-domain create <domain>                       # Mode A: explicit create/update
/cbprovider-domain debug <domain> <ip> <description...>  # Mode B: debug on target device
```

**Examples:**
```
/cbprovider-domain drm
/cbprovider-domain create sound
/cbprovider-domain debug drm 10.102.180.54 bridge test shows all FAIL but result passes
```

## Parameters

| Parameter | Description |
|---|---|
| `function` | (Optional) `create` or `debug`. Defaults to `create` if omitted. |
| `domain` | Kernel subsystem name (e.g. `drm`, `sound`, `usb`, `acpi`) |
| `ip` | (debug only) Target device IP address |
| `description` | (debug only) Free-text description of the issue — everything after the IP is joined as the description, no quotes required |

---

## Mode Dispatch

**Read the first argument to decide the mode:**

- If the first argument is `debug` → run **Mode B — Debug** (Steps D1–D10 below)
- If the first argument is `create` → run **Mode A — Create/Update** (Steps 1–17 below)
- If the first argument is neither `debug` nor `create` → treat it as `<domain>` and run **Mode A — Create/Update**

**Only run one mode per invocation. Do not mix modes.**

---

# Mode A — Create / Update

Follow every step in order. Do not skip steps. Stop and report clearly if any step fails.

### Step 0 — Sync repositories

Ensure both the provider and kernel_readdoc repos are on `main` and up-to-date
before making any changes:

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider
git checkout main
git pull --ff-only origin main
```

```bash
cd ~/canonical/workspace/kernel_readdoc
git checkout main
git pull --ff-only origin main
```

If either `git pull` fails (e.g. merge conflict, diverged history), stop and
report the error — do not proceed with stale code.

### Step 1 — Resolve kernel hierarchy path

The `kernel_readdoc` repository mirrors the Linux kernel source tree structure.
Before doing anything else, resolve the user's `<domain>` to its **kernel source path**.

```bash
find ~/canonical/workspace/kernel_readdoc -type d -name "<domain>" \
  -not -path '*/.git/*' -not -path '*__pycache__*' 2>/dev/null
```

This may return multiple matches (e.g. `net/` exists as both a top-level dir
and under `drivers/net/`). Apply these resolution rules **in order**:

1. If only one match → use it.
2. If multiple matches → prefer the one with **more `.py` test files** underneath.
3. If still tied → prefer the **deeper path** (more specific scope).

Compute these canonical variables from the resolved path (use these everywhere
in later steps instead of raw `<domain>`):

| Variable | How to compute | Example (`drm`) | Example (`sound`) |
|---|---|---|---|
| `KERNEL_SOURCE_PATH` | Path relative to `kernel_readdoc/` root | `drivers/gpu/drm` | `sound` |
| `KERNEL_PATH` | Strip leading `drivers/` if present; keep as-is for top-level dirs | `gpu/drm` | `sound` |
| `KERNEL_PATH_DASHED` | Replace `/` with `-` in KERNEL_PATH | `gpu-drm` | `sound` |
| `KERNEL_PATH_UNDERSCORED` | Replace `/` with `_` in KERNEL_PATH | `gpu_drm` | `sound` |
| `PXU_FILE` | `units/<KERNEL_PATH_DASHED>-jobs.pxu` | `units/gpu-drm-jobs.pxu` | `units/sound-jobs.pxu` |
| `TEST_PLAN_ID` | `kprovider-<KERNEL_PATH_DASHED>` | `kprovider-gpu-drm` | `kprovider-sound` |
| `LEAF_CATEGORY` | `kprovider/<KERNEL_PATH>` | `kprovider/gpu/drm` | `kprovider/sound` |

**Important: `drm` and `gpu` are NOT aliases.** They resolve to different scopes:
- `drm` → `drivers/gpu/drm` → `KERNEL_PATH=gpu/drm`
- `gpu` → `drivers/gpu` → `KERNEL_PATH=gpu`

If resolution fails (no directory found), report it and stop.

### Step 1 — Locate test scripts for the domain

Search **within** the resolved `KERNEL_SOURCE_PATH` directory for Python test files:

```bash
find ~/canonical/workspace/kernel_readdoc/<KERNEL_SOURCE_PATH> -type f -name "*.py" \
  -not -path '*__pycache__*'
```

Collect the full list of `.py` files found. If none are found, report that no
test scripts exist for this domain and stop.

For each found file, read its header docstring to understand:
- What kernel subsystem/driver it tests
- What steps it verifies
- What hardware or kernel module it requires

### Step 2 — Determine job IDs and script names

For each script, derive names from its **relative path below `KERNEL_SOURCE_PATH`**:

- The **subdirectory name** below the domain root is the `<component>`.
  If the script is directly in the domain root (not in a subdirectory),
  treat the script's stem as the component.

- A **bin script name**: `<KERNEL_PATH_UNDERSCORED>_<component>_trace_test.py`
  - Example: `drm` domain, `i915/` subdir → `gpu_drm_i915_trace_test.py`
  - Example: `sound` domain, single script → `sound_trace_test.py`
  - If there is only one script for the domain, use `<KERNEL_PATH_UNDERSCORED>_trace_test.py`

- A **job ID**: `kprovider/<KERNEL_PATH>/<component>`
  - Example: `kprovider/gpu/drm/i915`, `kprovider/gpu/drm/core`
  - If only one script, use `kprovider/<KERNEL_PATH>`

Before copying, check for **bin name collisions** with existing scripts:
```bash
ls ~/canonical/workspace/checkbox-provider-kprovider/bin/<bin_script_name> 2>/dev/null
```

### Step 3 — Fix known Python syntax issues before copying

Before copying each script, check for this known bug pattern and fix it:

**Bug**: `global PROBE_TIMEOUT` declared *after* the variable is already used in the
same function (e.g. as a `default=` argument). Python 3.12+ rejects this.

**Fix**: Move the `global PROBE_TIMEOUT` declaration to the very first line inside
`main()`, before `parser = argparse.ArgumentParser(...)`.

Check for this with:
```bash
grep -n "global PROBE_TIMEOUT\|default=PROBE_TIMEOUT" <script>
```

If the `default=PROBE_TIMEOUT` line number is lower than `global PROBE_TIMEOUT`,
fix it by moving `global PROBE_TIMEOUT` to the top of the function.

After fixing, verify syntax:
```bash
python3 -m py_compile <script>
```

### Step 4 — Copy scripts to bin/

Before copying, check whether each bin script already exists:

```bash
ls ~/canonical/workspace/checkbox-provider-kprovider/bin/<bin_script_name> 2>/dev/null
```

- **If it does not exist** → this is a new script. Record the action as **"Create"**.
- **If it already exists** → this is an update. Record the action as **"Update"**.

```bash
cp <source_script> ~/canonical/workspace/checkbox-provider-kprovider/bin/<bin_script_name>
chmod +x ~/canonical/workspace/checkbox-provider-kprovider/bin/<bin_script_name>
```

Repeat for every script found. Track the Create/Update action for each — this
determines the commit message later (Step 16b).

### Step 5 — Check for an existing pxu file for this domain

```bash
ls ~/canonical/workspace/checkbox-provider-kprovider/units/<KERNEL_PATH_DASHED>-jobs.pxu 2>/dev/null
```

If it already exists:
- Read it to understand what jobs are already defined so you don't create duplicates.
- Record the action as **"Update"** for the pxu file.

If it does not exist:
- Record the action as **"Create"** for the pxu file.

Also check **all** existing pxu files for parent category definitions to avoid
duplicates:
```bash
grep -r '^id: kprovider/' ~/canonical/workspace/checkbox-provider-kprovider/units/*.pxu 2>/dev/null
```

### Step 6 — Create or update the pxu file

Create `~/canonical/workspace/checkbox-provider-kprovider/units/<KERNEL_PATH_DASHED>-jobs.pxu`.

**Rules for pxu files (enforce all of these):**

1. **Create category units for the full hierarchy path.**
   For each level in `KERNEL_PATH`, create a category unit — but **only if it
   is NOT already defined in another existing pxu file** (checked in Step 5).

   Example for `KERNEL_PATH=gpu/drm`:
   ```
   unit: category
   id: kprovider/gpu
   _name: GPU Subsystem

   unit: category
   id: kprovider/gpu/drm
   _name: DRM GPU Drivers
   ```

   If `kprovider/gpu` is already defined in `gpu-jobs.pxu`, then only define
   `kprovider/gpu/drm` in this file.

   Example for `KERNEL_PATH=sound` (single level):
   ```
   unit: category
   id: kprovider/sound
   _name: Sound Subsystem
   ```

2. For each job, use the **leaf category** (`LEAF_CATEGORY`) and **hierarchical
   job ID**:
   ```
   id: kprovider/<KERNEL_PATH>/<component>
   _summary: <One-line description>
   _description:
    <What the test traces>
    <What hardware/module is required>
   plugin: shell
   category_id: <LEAF_CATEGORY>
   user: root
   estimated_duration: <120.0 for generic, 180.0 for driver-specific>
   command:
    command -v bpftrace >/dev/null 2>&1 || { echo "bpftrace not found — install with: sudo apt install bpftrace"; exit 1; }
    <module check if driver-specific, e.g.: grep -q '^i915 ' /proc/modules || { echo "i915 module not loaded — skipping"; exit 1; }>
    <bin_script_name>
   ```

   Example job IDs following kernel hierarchy:
   - `kprovider/gpu/drm/core` (from `drivers/gpu/drm/core/`)
   - `kprovider/gpu/drm/i915` (from `drivers/gpu/drm/i915/`)
   - `kprovider/sound/hda` (from `sound/hda/`)
   - `kprovider/usb/core` (from `drivers/usb/core/`)

3. **Do NOT use `requires:` field** — `executable` and `package` resource units
   are not available in kprovider. Put all prerequisite checks in `command:` instead.

4. **Do NOT prefix job IDs or test plan IDs with `com.canonical.certification::`** —
   the namespace is injected automatically by `manage.py`.

5. For driver-specific jobs (i915, amdgpu, nouveau, xe, etc.), add a
   `/proc/modules` guard in the command so the job skips gracefully on
   machines without that hardware.

### Step 7 — Update units/test-plan.pxu

Read the existing test plan file:
```bash
cat ~/canonical/workspace/checkbox-provider-kprovider/units/test-plan.pxu
```

Add the new jobs to the `kprovider-full` include list using their full
hierarchical IDs (e.g. `kprovider/gpu/drm/i915`, not `kprovider/drm/i915`).

Also add a new focused test plan for the domain if one doesn't already exist:
```
unit: test plan
id: <TEST_PLAN_ID>
_name: kprovider <Human-Readable Domain Name>
_description: <Domain> subsystem bpftrace workflow tests
include:
 kprovider/<KERNEL_PATH>/<component1>
 kprovider/<KERNEL_PATH>/<component2>
 ...
```

Example for `drm`:
```
unit: test plan
id: kprovider-gpu-drm
_name: kprovider DRM GPU Drivers
_description: DRM subsystem bpftrace workflow tests (core + all GPU drivers)
include:
 kprovider/gpu/drm/core
 kprovider/gpu/drm/i915
 kprovider/gpu/drm/amd
 ...
```

### Step 8 — Validate the provider

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider && python3 manage.py validate 2>&1
```

The output must end with `The provider seems to be valid`.

If there are **errors** (not warnings), fix them:
- `field 'requires'` errors → remove `requires:` field, move checks to `command:`
- `identifier cannot define a custom namespace` → remove `com.canonical.certification::` prefix from the `id:` field in test plan units
- `SyntaxError` in a script → fix the Python file (see Step 3) and re-run validate

Warnings about missing other providers (checkbox-provider-base, etc.) are
expected and can be ignored.

### Step 9 — (Reserved for final commit — see Step 16)

Do **not** commit or push yet. Proceed directly to Phase 2.

---

## Phase 2 — Inject SSH key to target machine

### Step 10 — Read target list from config

Read the config file:
```bash
cat ~/.claude/skills/cbprovider-domain/references/inject.conf
```

Parse all non-empty `TARGET=` lines (ignore comments and blank values):
```bash
TARGETS=$(grep -E '^TARGET=.+' ~/.claude/skills/cbprovider-domain/references/inject.conf | cut -d'=' -f2 | tr -d '[:space:]')
```

If the list is empty or the file does not exist, stop and tell the user:
> "`inject.conf` has no TARGET entries. Edit `~/.claude/skills/cbprovider-domain/references/inject.conf` and add one or more `TARGET=<IP or CID>` lines, then re-run."

Print the resolved list so the user can confirm:
```
Targets: <target1>, <target2>, ...
```

### Step 11 — Run inject.sh for each target

For each target in `TARGETS`, run with a timeout to prevent hangs:
```bash
timeout 120 bash ~/.claude/skills/cbprovider-domain/scripts/inject.sh <target>
```

- If a target fails or times out (exit code 124), report the error and skip it — continue with remaining targets.
- After processing all targets, report which succeeded and which failed.
- If **all** targets failed, stop and do not proceed to Phase 3.
- Note the resolved IP address printed by inject.sh for each target (used in Phase 3).

If it succeeds, note the resolved IP address printed by the script (used in Phase 3).

---

## Phase 3 — Run test cases on target machine

Repeat Steps 12–13 for **each target** that succeeded in Step 11.

### Step 12 — Install/update the provider on the target

For each `<resolved_ip>`, sync the local provider tree to the target using rsync
(the changes have not been pushed to git yet):

```bash
rsync -av --timeout=60 -e "ssh -o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no" --exclude='.git' ~/canonical/workspace/checkbox-provider-kprovider/ ubuntu@<resolved_ip>:~/checkbox-provider-kprovider/
```

If rsync hangs for more than 60 seconds on any I/O, it will timeout automatically.

### Step 13 — Run the domain test plan

**Important: All remote SSH commands MUST use timeouts to prevent hangs.**

Define SSH options for all remote commands in this step:
```bash
SSH_REMOTE_OPTS="-o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no"
```

Install the provider (timeout 120s):
```bash
timeout 120 ssh $SSH_REMOTE_OPTS ubuntu@<resolved_ip> "
  cd ~/checkbox-provider-kprovider
  sudo python3 manage.py develop
"
```

Run the test plan (timeout 600s — 10 minutes max):
```bash
timeout 600 ssh $SSH_REMOTE_OPTS ubuntu@<resolved_ip> "
  cd ~/checkbox-provider-kprovider
  sudo checkbox-cli run <TEST_PLAN_ID> 2>&1 | tee /tmp/<TEST_PLAN_ID>-results.txt
"
```

If `timeout` kills the command (exit code 124), report which target timed out
and continue with remaining targets — do not hang waiting.

Fetch the results back (timeout 60s):
```bash
timeout 60 scp -o ConnectTimeout=15 -o StrictHostKeyChecking=no ubuntu@<resolved_ip>:/tmp/<TEST_PLAN_ID>-results.txt /tmp/<TEST_PLAN_ID>-<resolved_ip>-results.txt
cat /tmp/<TEST_PLAN_ID>-<resolved_ip>-results.txt
```

Parse the output for:
- `PASS` / `FAIL` / `SKIP` per job ID
- Any Python tracebacks or bpftrace errors
- Timeout errors

Collect results from all targets before proceeding to Phase 4.

---

## Phase 4 — Fine-tune

### Step 14 — Analyse failures

For each failed or erroring job:
1. Read the corresponding `bin/<KERNEL_PATH_UNDERSCORED>_*_trace_test.py` script.
2. Identify the root cause from the test output:
   - **bpftrace probe not found** → wrong probe name; update the script's probe list.
   - **Timeout** → increase `PROBE_TIMEOUT` default or the `estimated_duration` in the pxu.
   - **Module not loaded** → tighten the `/proc/modules` guard or mark as SKIP-worthy.
   - **Python error** → fix the script (syntax, logic, missing import).
   - **bpftrace not installed** → note it; the command guard already handles this.

### Step 15 — Apply fixes

Edit the affected scripts and/or pxu jobs. After each edit:
```bash
python3 -m py_compile ~/canonical/workspace/checkbox-provider-kprovider/bin/<script>
cd ~/canonical/workspace/checkbox-provider-kprovider && python3 manage.py validate 2>&1
```

### Step 16 — Re-run until clean

Repeat Steps 12–13 (deploy+run) and 14–15 (analyse+fix) until all jobs either
PASS or SKIP with a clear hardware-absent reason. Do **not** commit during
this loop. If a target consistently times out after 2 retries, skip it and
note the timeout in the final report.

### Step 16b — Create branch, commit, push, and open PR

**Do NOT push directly to `main`.** Always work on a feature branch and open a
pull request.

Once all jobs pass or skip cleanly on every target:

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider
```

Create a feature branch from the current `main`:
```bash
git checkout -b <KERNEL_PATH_DASHED>-checkbox-jobs
```

Stage the changes:
```bash
git add bin/<KERNEL_PATH_UNDERSCORED>_*_trace_test.py units/<KERNEL_PATH_DASHED>-jobs.pxu units/test-plan.pxu
```

Check what is staged before committing:
```bash
git status
git diff --cached --stat
```

Commit with a descriptive message. Use **"Create"** or **"Update"** based on
whether the files were newly created or already existed (tracked in Steps 4–5):

- If **all bin scripts and pxu files were newly created** →
  ```bash
  git commit -m "Create <KERNEL_PATH> subsystem checkbox test jobs

  Import bpftrace workflow test scripts from kernel_readdoc and create
  checkbox job definitions for the <KERNEL_PATH> subsystem.

  Jobs:
  $(git diff --cached --name-only | grep pxu | xargs grep '^id: kprovider' 2>/dev/null | sed 's/.*id: /  - /')

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```
- If **any file already existed and was updated** →
  ```bash
  git commit -m "Update <KERNEL_PATH> subsystem checkbox test jobs

  Update bpftrace workflow test scripts and checkbox job definitions
  for the <KERNEL_PATH> subsystem.

  Jobs:
  $(git diff --cached --name-only | grep pxu | xargs grep '^id: kprovider' 2>/dev/null | sed 's/.*id: /  - /')

  Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
  ```

Push the feature branch:
```bash
git push --set-upstream origin <KERNEL_PATH_DASHED>-checkbox-jobs
```

Open a pull request using the `gh` CLI:
```bash
gh pr create \
  --base main \
  --head <KERNEL_PATH_DASHED>-checkbox-jobs \
  --title "<Create|Update> <KERNEL_PATH> subsystem checkbox test jobs" \
  --body "## Summary

<Create or Update> bpftrace workflow test scripts and checkbox job definitions
for the \`<KERNEL_PATH>\` subsystem.

## Jobs
$(git diff main --name-only | grep pxu | xargs grep '^id: kprovider' 2>/dev/null | sed 's/.*id: /- /')

## Test results per target
<Include the per-target results table from Step 17>
"
```

If `gh` is not installed or not authenticated, print the GitHub compare URL for
the user to create the PR manually:
```
https://github.com/<owner>/<repo>/compare/main...<KERNEL_PATH_DASHED>-checkbox-jobs?expand=1
```

### Step 17 — Final report

Print a summary including the git commit hash:

```
## Results for domain: <domain> (kernel path: <KERNEL_PATH>)

### bin/ scripts
| Script | Source |
|---|---|
| <KERNEL_PATH_UNDERSCORED>_*_trace_test.py | kernel_readdoc/<KERNEL_SOURCE_PATH>/... |

### Test plans updated
- kprovider-full (added N jobs)
- <TEST_PLAN_ID> (new)

### Test results per target
#### <resolved_ip1>
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<KERNEL_PATH>/... | PASS | |
| kprovider/<KERNEL_PATH>/... | SKIP | module not loaded |

#### <resolved_ip2>
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<KERNEL_PATH>/... | PASS | |
...
```

Note any hardware requirements (e.g. "i915 job requires Intel GPU with i915 module").

---

# Mode B — Debug

Debug an existing domain test on a specific target device. SSH to the target,
run tests, analyze failures against the user's description, apply fixes, and
re-test until clean.

Follow every step in order. Do not skip steps. Stop and report clearly if any step fails.

**Important: All remote SSH commands MUST use timeouts to prevent hangs.**

Define SSH options for all remote commands in this mode:
```bash
SSH_REMOTE_OPTS="-o ConnectTimeout=15 -o ServerAliveInterval=10 -o ServerAliveCountMax=3 -o StrictHostKeyChecking=no"
```

### Step D0 — Sync repository

Ensure the provider repo is on `main` and up-to-date before debugging:

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider
git checkout main
git pull --ff-only origin main
```

If `git pull` fails, stop and report the error.

### Step D1 — Parse parameters and resolve kernel hierarchy

Parse the invocation arguments:
- `domain` = second argument (kernel subsystem: drm, sound, usb, etc.)
- `ip` = third argument (target device IP address)
- `description` = everything from the fourth argument onward, joined with spaces

Validate:
- `domain` must be non-empty
- `ip` must look like an IPv4 address (digits and dots)
- `description` may be empty (user just wants to run and debug)

**Resolve the kernel hierarchy** using the same rules as Step 1 (Mode A) to
compute `KERNEL_PATH`, `KERNEL_PATH_DASHED`, `KERNEL_PATH_UNDERSCORED`,
`PXU_FILE`, `TEST_PLAN_ID`, and `LEAF_CATEGORY`.

Print the parsed parameters:
```
Debug mode:
  Domain:      <domain>
  Kernel path: <KERNEL_PATH>
  Target IP:   <ip>
  Description: <description>
```

### Step D2 — SSH connectivity and prerequisites

Test SSH connectivity with a timeout:
```bash
timeout 10 ssh $SSH_REMOTE_OPTS ubuntu@<ip> "echo ok" 2>&1
```

**If SSH auth fails** (permission denied, not key-auth connection refused):
- Attempt to inject SSH key automatically:
  ```bash
  timeout 120 bash ~/.copilot/skills/cbprovider-domain/scripts/inject.sh <ip>
  ```
- If inject succeeds, retry the SSH test.
- If inject also fails, stop and tell the user to set up SSH access manually.

**If SSH is unreachable** (timeout, connection refused): stop and report the target is offline.

Once SSH works, check generic prerequisites on the target:
```bash
timeout 30 ssh $SSH_REMOTE_OPTS ubuntu@<ip> "
  echo '=== bpftrace ==='
  which bpftrace 2>/dev/null || echo 'MISSING'
  echo '=== checkbox-cli ==='
  which checkbox-cli 2>/dev/null || echo 'MISSING'
  echo '=== kernel modules ==='
  lsmod | head -20
  echo '=== DRM devices ==='
  ls /dev/dri/ 2>/dev/null || echo 'none'
"
```

If `bpftrace` or `checkbox-cli` is missing, report and stop.

### Step D3 — Verify local provider and test plan exist

Check that the local provider has the domain:
```bash
ls ~/canonical/workspace/checkbox-provider-kprovider/units/<KERNEL_PATH_DASHED>-jobs.pxu 2>/dev/null
grep "id: <TEST_PLAN_ID>" ~/canonical/workspace/checkbox-provider-kprovider/units/test-plan.pxu
```

If either is missing:
- Report: "Domain `<domain>` (kernel path: `<KERNEL_PATH>`) does not have provider jobs yet. Run `/cbprovider-domain create <domain>` first."
- Stop.

Also check that the provider is installed on the target:
```bash
timeout 30 ssh $SSH_REMOTE_OPTS ubuntu@<ip> "checkbox-cli list-bootstrapped com.canonical.certification::<TEST_PLAN_ID> 2>&1"
```

If the test plan is not listed on the target, deploy first (jump to Step D5 deploy substep, then return here).

### Step D4 — Run the domain test plan on target

Deploy the latest local provider to the target:
```bash
rsync -av --timeout=60 -e "ssh $SSH_REMOTE_OPTS" --exclude='.git' \
  ~/canonical/workspace/checkbox-provider-kprovider/ \
  ubuntu@<ip>:~/checkbox-provider-kprovider/
```

Install/update the provider:
```bash
timeout 120 ssh $SSH_REMOTE_OPTS ubuntu@<ip> "
  cd ~/checkbox-provider-kprovider
  sudo python3 manage.py develop
"
```

Run the test plan (timeout 600s — 10 minutes max):
```bash
timeout 600 ssh $SSH_REMOTE_OPTS ubuntu@<ip> "
  sudo checkbox-cli run com.canonical.certification::<TEST_PLAN_ID> 2>&1
" | tee /tmp/kprovider-debug-<KERNEL_PATH_DASHED>-<ip>.txt
```

If `timeout` kills the command (exit code 124), report the timeout and stop.

### Step D5 — Analyze results against user description

Parse the test output for:
- Each job's **Outcome** (passed / failed / cannot be started)
- Per-step `[PASS]` / `[FAIL]` / `[SKIP]` within each job
- Python tracebacks or bpftrace errors
- Exit codes

Cross-reference with the user's `<description>`:
- Does the user's reported problem match what was observed?
- Are there additional issues not mentioned in the description?

Read the relevant local files to understand the test logic:
1. `~/canonical/workspace/checkbox-provider-kprovider/units/<KERNEL_PATH_DASHED>-jobs.pxu` — job definitions, guards, command wrappers
2. `~/canonical/workspace/checkbox-provider-kprovider/bin/<KERNEL_PATH_UNDERSCORED>_*_trace_test.py` — the actual test scripts

For each failing or suspicious job, identify:
- **Script-level issue**: exit code not matching results, missing hardware detection, wrong probe names
- **pxu-level issue**: missing resource guard, wrong command, incorrect `requires:` usage
- **Environment issue**: hardware not present, module not loaded, bpftrace version too old
- **False positive**: test prints FAIL but exits 0 (checkbox reports as pass)
- **False negative**: test skips when it should run

### Step D6 — Apply fixes locally

For each identified issue, edit the relevant files in `~/canonical/workspace/checkbox-provider-kprovider/`:

- Fix scripts in `bin/`
- Fix job definitions in `units/`
- Fix test plans in `units/test-plan.pxu` if needed

After each edit, validate:
```bash
python3 -m py_compile ~/canonical/workspace/checkbox-provider-kprovider/bin/<script>
cd ~/canonical/workspace/checkbox-provider-kprovider && python3 manage.py validate 2>&1
```

### Step D7 — Re-deploy and re-test

Repeat Step D4 (deploy + run) with the fixed code.

### Step D8 — Iterate (max 3 cycles)

If there are still failures after re-test:
1. Go back to Step D5 (analyze) → D6 (fix) → D7 (re-test)
2. Track the cycle count

**Stop after 3 fix/retest cycles.** If issues remain:
- Report the unresolved failures clearly
- Distinguish between code bugs (fixable) vs environment/hardware limitations (not fixable)
- Do NOT continue looping

### Step D9 — Create branch, commit, push, and open PR

**Do NOT push directly to `main`.** Always work on a feature branch and open a
pull request.

Once all jobs pass or skip with clear hardware-absent reasons:

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider
```

Create a feature branch from the current `main`:
```bash
git checkout -b fix/<KERNEL_PATH_DASHED>-<short-description>
```

Where `<short-description>` is a brief kebab-case summary of the fix (e.g.
`fix/gpu-drm-exit-codes`, `fix/sound-passive-steps`).

Stage and review changes:
```bash
git add -A
git status
git diff --cached --stat
```

Commit with a descriptive message explaining what was debugged and fixed:
```bash
git commit -m "fix(<KERNEL_PATH_DASHED>): <concise description of what was fixed>

<Longer explanation of root cause and fix>

Tested on: <ip>

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Push the feature branch:
```bash
git push --set-upstream origin fix/<KERNEL_PATH_DASHED>-<short-description>
```

Open a pull request using the `gh` CLI:
```bash
gh pr create \
  --base main \
  --head fix/<KERNEL_PATH_DASHED>-<short-description> \
  --title "fix(<KERNEL_PATH_DASHED>): <concise description of what was fixed>" \
  --body "## Summary

<Longer explanation of root cause and fix>

## Fixes applied
<Table of files changed and what was changed>

## Test results
<Per-target results table from Step D10>

Tested on: <ip>
"
```

If `gh` is not installed or not authenticated, print the GitHub compare URL for
the user to create the PR manually:
```
https://github.com/<owner>/<repo>/compare/main...fix/<KERNEL_PATH_DASHED>-<short-description>?expand=1
```

### Step D10 — Final report

Print a summary:

```
## Debug Results for domain: <domain> (kernel path: <KERNEL_PATH>)

### Target: <ip>
### Problem reported: <description>

### Root cause
<What was wrong and why>

### Fixes applied
| File | Change |
|---|---|
| bin/<script>.py | <what was changed> |
| units/<KERNEL_PATH_DASHED>-jobs.pxu | <what was changed, if any> |

### Final test results
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<KERNEL_PATH>/... | PASS | |
| kprovider/<KERNEL_PATH>/... | SKIP | <reason> |

### Unresolved issues (if any)
| Job ID | Issue | Reason |
|---|---|---|
| kprovider/<KERNEL_PATH>/... | <issue> | environment / hardware limitation |

### Commit
<commit hash>
```
