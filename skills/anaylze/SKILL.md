---
name: analyze
description: Explains code with visual diagrams and analogies. Use when explaining how code works or when the user asks how something works.
---

# analyze

Analyzes and documents a specific kernel subsystem domain with ASCII diagrams,
test cases, and bpftrace verification scripts.

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

---

## Execution Instructions

Follow every step in order. Do not skip steps. Stop and report clearly if any step fails.
**Process ONLY the specified `<domain>` — do NOT loop or continue to other domains.**

### Step 1 — Identify undocumented topics in the domain

Check `~/canonical/workspace/kernel_readdoc` and compare against the current
kernel source tree to find subsystem topics under `<domain>` that have not yet
been documented.

```bash
ls ~/canonical/workspace/kernel_readdoc/<domain>/ 2>/dev/null
```

List what exists and what is missing. Only work on topics within `<domain>`.

### Step 2 — Pick the next undocumented topic

From the undocumented topics found in Step 1, choose **one** topic to document.
If all topics under `<domain>` are already documented, report that and stop.

### Step 3 — Draw an ASCII diagram of the subsystem stack

Create a clear ASCII diagram showing the full `<domain>` subsystem stack:
- Userspace interface layer
- Kernel API / framework layer
- Driver / hardware abstraction layer

### Step 4 — Explain each layer and component

For each layer in the diagram, explain:
- What it does
- Key data structures and functions
- How it connects to adjacent layers

Keep the explanation practical and easy to follow.

### Step 5 — Draw an ASCII diagram of the workflow

Create a second ASCII diagram showing how a typical operation flows through
the subsystem (e.g. a page flip for DRM, a PCM open for sound).

### Step 6 — Export documentation to HackMD

Export the diagrams and explanations to a HackMD-formatted markdown file.

### Step 7 — Create bpftrace verification test case

Write a Python test script using bpftrace to verify the workflow step by step.
The test must:
- Attach bpftrace probes at each key function in the flow
- Run a trigger action to exercise the path
- Mark each step as PASS or FAIL
- Print a summary at the end

Export both `README.md` and the test script to
`~/canonical/workspace/kernel_readdoc/<domain>/<topic>/`
(create the directory if it does not exist).

Commit and push without prompting:
```bash
cd ~/canonical/workspace/kernel_readdoc
git add <domain>/<topic>/
git commit -m "Add <domain>/<topic> analysis and bpftrace test"
git push
```

### Step 8 — Check for remaining topics in this domain

If there are still undocumented topics **within the same `<domain>`** and you
have sufficient context/tokens remaining, repeat from Step 2 for the next topic.

**Do NOT move to a different domain.** When all topics in `<domain>` are done
(or tokens are low), print a summary and stop.

### Step 9 — Final report

Print a summary of what was documented:

```
## Analysis complete for domain: <domain>

| Topic | README | Test Script | Status |
|---|---|---|---|
| <topic1> | ✓ | ✓ | committed |
| <topic2> | ✓ | ✓ | committed |
| <topic3> | — | — | already documented |
```
