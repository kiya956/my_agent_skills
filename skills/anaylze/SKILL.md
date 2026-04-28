---
name: analyze
description: Explains code with visual diagrams and analogies. Use when explaining how code works or when the user asks how something works.
---

# analyze

Analyzes and documents a specific kernel subsystem domain with ASCII diagrams,
test cases, and bpftrace verification scripts.

**All analysis MUST be grounded in actual kernel source code** from the local
kernel tree at `~/canonical/kernel/noble-linux-oem`. Do NOT rely on training
knowledge alone — read the real `.c` and `.h` files to extract struct definitions,
function names, call chains, and data flows.

## Usage

```
/analyze <domain>
```

**Examples:**
```
/analyze drm
/analyze sound
/analyze usb
/analyze acpi
```

## Parameters

| Parameter | Description |
|---|---|
| `domain` | Kernel subsystem domain to analyze (e.g. `drm`, `sound`, `usb`, `acpi`). Only this domain will be processed — the skill does NOT continue to other domains. |

## Source Code Location

The **sole source of truth** for kernel structures, functions, and workflows is:

```
KERNEL_SRC=~/canonical/kernel/noble-linux-oem
```

**Rules:**
- Every struct, function name, callback, and data flow mentioned in the README
  MUST come from reading files under `$KERNEL_SRC`.
- Every bpftrace probe target MUST be verified to exist in the source (grep for
  the function definition in `$KERNEL_SRC`).
- Do NOT invent or guess function names — if a function is not found in the
  source tree, do not include it.
- When listing "Key Source Files", use paths relative to `$KERNEL_SRC` and
  verify they exist with `ls`.

---

## Execution Instructions

Follow every step in order. Do not skip steps. Stop and report clearly if any step fails.
**Process ONLY the specified `<domain>` — do NOT loop or continue to other domains.**

### Step 1 — Locate the domain in the kernel source tree

Find where `<domain>` lives in the actual kernel source:

```bash
KERNEL_SRC=~/canonical/kernel/noble-linux-oem

# Find the domain directory in the kernel source tree
find "$KERNEL_SRC" -maxdepth 4 -type d -name "<domain>" 2>/dev/null | grep -v '.git' | head -10

# For GPU/DRM: the path is typically drivers/gpu/drm
# For sound: sound/
# For USB: drivers/usb/
# etc.
```

Once you find `<source_path>` (e.g. `drivers/gpu/drm`), list subdirectories
to discover topics:

```bash
ls -d "$KERNEL_SRC/<source_path>"/*/ 2>/dev/null | head -30
```

Record `<source_path>` — this is used for all subsequent steps.

### Step 2 — Identify undocumented topics

Compare the kernel source subdirectories against existing documentation:

```bash
# What topics exist in the kernel source?
ls -d "$KERNEL_SRC/<source_path>"/*/ 2>/dev/null | xargs -I{} basename {}

# What topics are already documented?
ls ~/canonical/workspace/kernel_readdoc/<source_path>/ 2>/dev/null
```

The directory hierarchy in `kernel_readdoc` **must mirror the kernel source tree**.
List what exists and what is missing. Only work on topics within `<domain>`.

### Step 3 — Pick the next undocumented topic

From the undocumented topics found in Step 2, choose **one** topic to document.
Prefer topics that are more widely used or fundamental (e.g. `core`, `scheduler`
before obscure vendor drivers).

If all topics under `<domain>` are already documented, report that and stop.

### Step 4 — Read the actual kernel source code for the topic

**This is the critical step.** Read the real source files to understand the
subsystem. Do NOT skip this — all documentation must be grounded in the code.

```bash
TOPIC_DIR="$KERNEL_SRC/<source_path>/<topic>"

# List all source files
ls "$TOPIC_DIR"/*.c "$TOPIC_DIR"/*.h 2>/dev/null

# Read key header files for struct definitions
grep -l "^struct " "$TOPIC_DIR"/*.h "$KERNEL_SRC/include/"**"/<topic>*.h" 2>/dev/null

# Find main entry points and exported functions
grep -n "EXPORT_SYMBOL\|module_init\|module_exit\|__init\|probe" "$TOPIC_DIR"/*.c 2>/dev/null | head -30

# Find key data structures
grep -n "^struct.*{" "$TOPIC_DIR"/*.c "$TOPIC_DIR"/*.h 2>/dev/null | head -30

# Find ops/callback tables (vtables)
grep -n "_ops\s*=\s*{" "$TOPIC_DIR"/*.c 2>/dev/null | head -20
```

Read the most important files (typically the main `.c` file, the primary `.h`
header) to understand:
- Key data structures and their fields
- Function call chains (init → probe → open → submit → irq → cleanup)
- Callback vtables (ops structs)
- Relationships between components

**Extract real struct definitions** by reading the header files:
```bash
# Example: read the main header to get struct definitions
grep -A 20 "^struct drm_sched_job {" "$KERNEL_SRC/include/drm/gpu_scheduler.h"
```

### Step 5 — Draw an ASCII diagram of the subsystem stack

Create a clear ASCII diagram showing the full `<domain>` subsystem stack:
- Userspace interface layer
- Kernel API / framework layer
- Driver / hardware abstraction layer

**Every component in the diagram must correspond to a real struct, file, or
function found in Step 4.** Do not include components you did not find in the
source.

### Step 6 — Explain each layer and component

For each layer in the diagram, explain:
- What it does
- Key data structures and functions (**cite the actual source file and line**)
- How it connects to adjacent layers

Keep the explanation practical and easy to follow.

### Step 7 — Draw an ASCII diagram of the workflow

Create a second ASCII diagram showing how a typical operation flows through
the subsystem (e.g. a page flip for DRM, a PCM open for sound).

**Verify the call chain** by tracing function calls in the source:
```bash
# Example: trace what drm_sched_main() calls
grep -n "drm_sched_main\|run_job\|free_job" "$TOPIC_DIR"/*.c | head -20
```

### Step 8 — Export documentation to HackMD

Export the diagrams and explanations to a HackMD-formatted markdown file.

Include a header with source tree reference:
```markdown
> **Source tree:** `<source_path>/<topic>/`
> **Kernel:** noble-linux-oem
> **Date:** <today>
> **Scanned from:** ~/canonical/kernel/noble-linux-oem
```

### Step 9 — Create bpftrace verification test case

Write a Python test script using bpftrace to verify the workflow step by step.

**Before adding any probe target**, verify the function exists in the source:
```bash
grep -rn "^.*\b<function_name>\b.*(" "$KERNEL_SRC/<source_path>/<topic>/" \
     "$KERNEL_SRC/include/" 2>/dev/null | grep -v "^Binary" | head -5
```

Only include probe targets for functions that are confirmed to exist in the
kernel source. For each probe, add an `alt_probes` list with alternative
function names found in the source in case the primary is inlined or renamed.

The test must:
- Attach bpftrace probes at each key function in the flow
- Run a trigger action to exercise the path
- Mark each step as PASS or FAIL
- Print a summary at the end

Before writing any file, check whether it already exists:

```bash
ls ~/canonical/workspace/kernel_readdoc/<source_path>/<topic>/README.md 2>/dev/null
ls ~/canonical/workspace/kernel_readdoc/<source_path>/<topic>/test_*.py 2>/dev/null
```

- **If the file does not exist** → create it. Record the action as **"Create"**.
- **If the file already exists** → update it in place (merge new content with
  existing content, preserving any manual edits where possible). Record the
  action as **"Update"**.

Track the action (Create or Update) for each file — this determines the commit
message in the next substep.

Export both `README.md` and the test script to
`~/canonical/workspace/kernel_readdoc/<source_path>/<topic>/`
(create the directory if it does not exist).

Commit and push without prompting. Use the correct verb based on whether files
were created or updated:

- If **all files were newly created** →
  ```bash
  git commit -m "Create <source_path>/<topic> analysis and bpftrace test"
  ```
- If **any file already existed and was updated** →
  ```bash
  git commit -m "Update <source_path>/<topic> analysis and bpftrace test"
  ```

```bash
cd ~/canonical/workspace/kernel_readdoc
git add <source_path>/<topic>/
git commit -m "<Create|Update> <source_path>/<topic> analysis and bpftrace test"
git push
```

### Step 10 — Check for remaining topics in this domain

If there are still undocumented topics **within the same `<domain>`** and you
have sufficient context/tokens remaining, repeat from Step 3 for the next topic.

**Do NOT move to a different domain.** When all topics in `<domain>` are done
(or tokens are low), print a summary and stop.

### Step 11 — Final report

Print a summary of what was documented:

```
## Analysis complete for domain: <domain>

Source: ~/canonical/kernel/noble-linux-oem/<source_path>/

| Topic | README | Test Script | Status |
|---|---|---|---|
| <topic1> | ✓ | ✓ | created & committed |
| <topic2> | ✓ | ✓ | updated & committed |
| <topic3> | — | — | already documented |
```
