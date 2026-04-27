---
name: cbprovider-domain
description: Create checkbox test cases from kernel_readdoc for a specific kernel subsystem domain (e.g. drm, sound, usb, acpi). Pass the domain name as the argument.
---

# cbprovider-domain

Generates checkbox provider test jobs for a specific kernel subsystem by
importing Python bpftrace test scripts from `~/canonical/workspace/kernel_readdoc`
into `~/canonical/workspace/checkbox-provider-kprovider`.

## Usage

```
/cbprovider-domain <domain>
```

**Examples:**
```
/cbprovider-domain drm
/cbprovider-domain sound
/cbprovider-domain usb
/cbprovider-domain acpi
```

## Parameters

| Parameter | Description |
|---|---|
| `domain` | Kernel subsystem name to generate test cases for (e.g. `drm`, `sound`, `usb`) |

---

## Execution Instructions

Follow every step in order. Do not skip steps. Stop and report clearly if any step fails.

### Step 1 — Locate test scripts for the domain

Search `~/canonical/workspace/kernel_readdoc` for Python test files related to `<domain>`:

```bash
find ~/canonical/workspace/kernel_readdoc -type f -name "*.py" | grep -i "<domain>"
```

Also try a broader search in case the domain maps to a subdirectory:
```bash
find ~/canonical/workspace/kernel_readdoc -type d | grep -i "<domain>"
```

Collect the full list of `.py` files found. If none are found, report that no
test scripts exist for this domain and stop.

For each found file, read its header docstring to understand:
- What kernel subsystem/driver it tests
- What steps it verifies
- What hardware or kernel module it requires

### Step 2 — Determine job IDs and script names

For each script, derive:
- A **bin script name**: `<domain>_<subdriver>_trace_test.py` (e.g. `drm_core_trace_test.py`)
  - If there is only one script for the domain, use `<domain>_trace_test.py`
  - If scripts are in subdirectories, use the subdirectory name as `<subdriver>`
- A **job ID**: `kprovider/<domain>/<subdriver>` (e.g. `kprovider/drm/core`)
  - If only one script, use `kprovider/<domain>`

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

```bash
cp <source_script> ~/canonical/workspace/checkbox-provider-kprovider/bin/<bin_script_name>
chmod +x ~/canonical/workspace/checkbox-provider-kprovider/bin/<bin_script_name>
```

Repeat for every script found.

### Step 5 — Check for an existing pxu file for this domain

```bash
ls ~/canonical/workspace/checkbox-provider-kprovider/units/<domain>-jobs.pxu 2>/dev/null
```

If it already exists, read it to understand what jobs are already defined so
you don't create duplicates.

### Step 6 — Create units/<domain>-jobs.pxu

Create `~/canonical/workspace/checkbox-provider-kprovider/units/<domain>-jobs.pxu`.

**Rules for pxu files (enforce all of these):**

1. Start with a category unit:
   ```
   unit: category
   id: kprovider/<domain>
   _name: <Domain> Subsystem
   ```

2. For each job:
   ```
   id: kprovider/<domain>/<subdriver>
   _summary: <One-line description>
   _description:
    <What the test traces>
    <What hardware/module is required>
   plugin: shell
   category_id: kprovider/<domain>
   user: root
   estimated_duration: <120.0 for generic, 180.0 for driver-specific>
   command:
    command -v bpftrace >/dev/null 2>&1 || { echo "bpftrace not found — install with: sudo apt install bpftrace"; exit 1; }
    <module check if driver-specific, e.g.: grep -q '^i915 ' /proc/modules || { echo "i915 module not loaded — skipping"; exit 1; }>
    <bin_script_name>
   ```

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

Add the new jobs to the `kprovider-full` include list.

Also add a new focused test plan for the domain if one doesn't already exist:
```
unit: test plan
id: kprovider-<domain>
_name: kprovider <Domain> Subsystem
_description: <Domain> subsystem bpftrace workflow tests
include:
 kprovider/<domain>/<subdriver1>
 kprovider/<domain>/<subdriver2>
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
  sudo checkbox-cli run kprovider-<domain> 2>&1 | tee /tmp/kprovider-<domain>-results.txt
"
```

If `timeout` kills the command (exit code 124), report which target timed out
and continue with remaining targets — do not hang waiting.

Fetch the results back (timeout 60s):
```bash
timeout 60 scp -o ConnectTimeout=15 -o StrictHostKeyChecking=no ubuntu@<resolved_ip>:/tmp/kprovider-<domain>-results.txt /tmp/kprovider-<domain>-<resolved_ip>-results.txt
cat /tmp/kprovider-<domain>-<resolved_ip>-results.txt
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
1. Read the corresponding `bin/<domain>_*_trace_test.py` script.
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

Once all jobs pass or skip cleanly on every target, create a feature branch,
commit the changes, push, and open a pull request to `main`.

1. **Switch to a new branch** (from `main`):
   ```bash
   cd ~/canonical/workspace/checkbox-provider-kprovider
   git checkout main
   git pull origin main
   BRANCH_NAME="add-<domain>-kprovider-jobs"
   git checkout -b "$BRANCH_NAME"
   ```

2. **Stage the new/modified files**:
   ```bash
   git add bin/<domain>_*_trace_test.py units/<domain>-jobs.pxu units/test-plan.pxu
   ```

3. **Review what is staged**:
   ```bash
   git status
   git diff --cached --stat
   ```

4. **Commit with a descriptive message**:
   ```bash
   git commit -m "Add <domain> subsystem checkbox test jobs

   Import bpftrace workflow test scripts from kernel_readdoc and create
   checkbox job definitions for the <domain> subsystem.

   Jobs added:
   $(git diff --cached --name-only | grep pxu | xargs grep '^id: kprovider' 2>/dev/null | sed 's/.*id: /  - /')
   "
   ```

5. **Push the branch**:
   ```bash
   git push --set-upstream origin "$BRANCH_NAME"
   ```

6. **Create a pull request** to `main`:
   ```bash
   gh pr create \
     --base main \
     --title "Add <domain> subsystem checkbox test jobs" \
     --body "Import bpftrace workflow test scripts from kernel_readdoc and create checkbox job definitions for the <domain> subsystem.

   ## Jobs added
   $(grep '^id: kprovider' ~/canonical/workspace/checkbox-provider-kprovider/units/<domain>-jobs.pxu | sed 's/^id: /- /')

   ## Test results
   All jobs PASS or SKIP (hardware-absent) on target machines.
   See Step 17 final report for per-target breakdown."
   ```

   Print the PR URL so the user can review it.

### Step 17 — Final report

Print a summary including the git commit hash and PR URL:

```
## Results for domain: <domain>

### bin/ scripts
| Script | Source |
|---|---|
| <domain>_*_trace_test.py | kernel_readdoc/... |

### Test plans updated
- kprovider-full (added N jobs)
- kprovider-<domain> (new)

### Test results per target
#### <resolved_ip1>
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<domain>/... | PASS | |
| kprovider/<domain>/... | SKIP | module not loaded |

#### <resolved_ip2>
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<domain>/... | PASS | |
...
```

Note any hardware requirements (e.g. "i915 job requires Intel GPU with i915 module").

Include the PR URL from Step 16b so the user can review and merge.
