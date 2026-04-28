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
ls ~/canonical/workspace/checkbox-provider-kprovider/units/<domain>-jobs.pxu 2>/dev/null
```

If it already exists:
- Read it to understand what jobs are already defined so you don't create duplicates.
- Record the action as **"Update"** for the pxu file.

If it does not exist:
- Record the action as **"Create"** for the pxu file.

### Step 6 — Create or update units/<domain>-jobs.pxu

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

### Step 16b — Commit and push

Once all jobs pass or skip cleanly on every target, commit and push:

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider
git add bin/<domain>_*_trace_test.py units/<domain>-jobs.pxu units/test-plan.pxu
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
  git commit -m "Create <domain> subsystem checkbox test jobs

  Import bpftrace workflow test scripts from kernel_readdoc and create
  checkbox job definitions for the <domain> subsystem.

  Jobs:
  $(git diff --cached --name-only | grep pxu | xargs grep '^id: kprovider' 2>/dev/null | sed 's/.*id: /  - /')
  "
  ```
- If **any file already existed and was updated** →
  ```bash
  git commit -m "Update <domain> subsystem checkbox test jobs

  Update bpftrace workflow test scripts and checkbox job definitions
  for the <domain> subsystem.

  Jobs:
  $(git diff --cached --name-only | grep pxu | xargs grep '^id: kprovider' 2>/dev/null | sed 's/.*id: /  - /')
  "
  ```

Then push:
```bash
git push
```

If `git push` fails because there is no upstream branch yet, run:
```bash
git push --set-upstream origin $(git branch --show-current)
```

### Step 17 — Final report

Print a summary including the git commit hash:

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

### Step D1 — Parse parameters

Parse the invocation arguments:
- `domain` = second argument (kernel subsystem: drm, sound, usb, etc.)
- `ip` = third argument (target device IP address)
- `description` = everything from the fourth argument onward, joined with spaces

Validate:
- `domain` must be non-empty
- `ip` must look like an IPv4 address (digits and dots)
- `description` may be empty (user just wants to run and debug)

Print the parsed parameters:
```
Debug mode:
  Domain:      <domain>
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
ls ~/canonical/workspace/checkbox-provider-kprovider/units/<domain>-jobs.pxu 2>/dev/null
grep "id: kprovider-<domain>" ~/canonical/workspace/checkbox-provider-kprovider/units/test-plan.pxu
```

If either is missing:
- Report: "Domain `<domain>` does not have provider jobs yet. Run `/cbprovider-domain create <domain>` first."
- Stop.

Also check that the provider is installed on the target:
```bash
timeout 30 ssh $SSH_REMOTE_OPTS ubuntu@<ip> "checkbox-cli list-bootstrapped com.canonical.certification::kprovider-<domain> 2>&1"
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
  sudo checkbox-cli run com.canonical.certification::kprovider-<domain> 2>&1
" | tee /tmp/kprovider-debug-<domain>-<ip>.txt
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
1. `~/canonical/workspace/checkbox-provider-kprovider/units/<domain>-jobs.pxu` — job definitions, guards, command wrappers
2. `~/canonical/workspace/checkbox-provider-kprovider/bin/<domain>_*_trace_test.py` — the actual test scripts

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

### Step D9 — Commit

Once all jobs pass or skip with clear hardware-absent reasons:

```bash
cd ~/canonical/workspace/checkbox-provider-kprovider
git add -A
git status
git diff --cached --stat
```

Commit with a descriptive message explaining what was debugged and fixed:
```bash
git commit -m "fix(<domain>): <concise description of what was fixed>

<Longer explanation of root cause and fix>

Tested on: <ip>

Co-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
```

Then push:
```bash
git push
```

If `git push` fails because there is no upstream branch yet:
```bash
git push --set-upstream origin $(git branch --show-current)
```

### Step D10 — Final report

Print a summary:

```
## Debug Results for domain: <domain>

### Target: <ip>
### Problem reported: <description>

### Root cause
<What was wrong and why>

### Fixes applied
| File | Change |
|---|---|
| bin/<script>.py | <what was changed> |
| units/<domain>-jobs.pxu | <what was changed, if any> |

### Final test results
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<domain>/... | PASS | |
| kprovider/<domain>/... | SKIP | <reason> |

### Unresolved issues (if any)
| Job ID | Issue | Reason |
|---|---|---|
| kprovider/<domain>/... | <issue> | environment / hardware limitation |

### Commit
<commit hash>
```
