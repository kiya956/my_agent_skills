---
name: crank
description: auto crank kernel
---

# start_crank

Guides the user through the full Ubuntu kernel crank workflow step by step, running each command and waiting for confirmation where needed.

## Usage

```
/crank <handle> <cycle> <rebase-base> <sru-cycle> <version> [builder]
```

**Example:**
```
/start_crank noble:linux-gke s2025.10.13 Ubuntu-6.8.0-91.92 s2025.10.13 6.8.0-1041.46 balboa
```

## Parameters

| Parameter | Example | Description |
|---|---|---|
| handle | `noble:linux-gke` | Kernel series:package identifier |
| cycle | `s2025.10.13` | SRU cycle for checkout |
| rebase-base | `Ubuntu-6.8.0-91.92` | Parent kernel base tag to rebase onto |
| sru-cycle | `s2025.10.13` | SRU cycle for link-tb and push-review |
| version | `6.8.0-1041.46` | Previous release version for pull-source |
| builder | `balboa` | Remote build host for push-review |

## Execution instructions

1. Ask the user for any missing parameters before starting.
2. Confirm the full parameter set.
3. Run each step in order. Print the command before running it. Wait for it to succeed before proceeding.
4. Steps marked **[CONFIRM]** require explicit user confirmation before running.
5. Step 7 is read-only output — pause and ask the user if they have reviewed it before continuing.
6. If any step fails, stop and report the error with suggested next actions.

---

## Steps

### Phase 1 — Environment Setup

```
cranky chroot create-base <handle>
cranky chroot create-session <handle>
cranky checkout <handle> --cycle <cycle>
```

### Phase 2 — Prepare the Tree (cd linux-main/)

```
cranky fix
cranky rebase -b <rebase-base>
cranky open
cranky review-master-changes
```
→ **Pause here.** Ask user to review the output, then confirm before continuing.

### Phase 3 — Finalize Changes (cd linux-main/)

```
cranky link-tb --sru-cycle <sru-cycle> --dry-run
```
→ Ask user to confirm the dry-run output, then re-run without `--dry-run`.

```
cranky update-dkms-versions
cranky close
cranky update-dependents
cranky tags -f        [CONFIRM]
cranky verify-release-ready
```
→ Fix any issues reported by verify-release-ready before continuing.

### Phase 4 — Build and Review

```
# Run from the series dir (e.g. noble/linux-gke/)
cranky pull-source linux-gke '<version>'
cranky pull-source linux-signed-gke '<version>'
cranky pull-source linux-meta-gke '<version>'

# Run from linux-main/
cranky build-sources

# Run from the series dir
cranky review *.changes
```
→ Ask user to review the generated debdiff files before continuing.

```
cranky push-review -s <sru-cycle> <builder>    [CONFIRM]
```
