---
name: scan-and-test
description: End-to-end pipeline that analyzes a kernel subsystem domain and then generates checkbox test cases from the results. Runs analyze followed by cbprovider-domain for the specified domain.
---

# scan-and-test

Orchestrates a full documentation-to-test pipeline for a kernel subsystem domain:
1. Runs the **analyze** skill to document the domain with ASCII diagrams and bpftrace scripts
2. Runs the **cbprovider-domain** skill to create/update checkbox provider test cases from the results

## Usage

```
/scan-and-test <domain>
```

**Examples:**
```
/scan-and-test drm
/scan-and-test sound
/scan-and-test usb
/scan-and-test acpi
```

## Parameters

| Parameter | Description |
|---|---|
| `domain` | Kernel subsystem domain to process (e.g. `drm`, `sound`, `usb`, `acpi`). |

---

## Execution Instructions

Follow every step in order. Do not skip steps. Do not prompt for confirmation between phases.

### Phase 1 — Analyze the domain

Invoke the **analyze** skill for `<domain>`.

This will:
- Identify undocumented topics under `<domain>` in `~/canonical/workspace/kernel_readdoc`
- Create ASCII diagrams of the subsystem stack and workflow
- Write bpftrace verification test scripts
- Export README.md and test scripts to `~/canonical/workspace/kernel_readdoc/<domain>/`
- Commit and push the results

**Wait for Phase 1 to fully complete before proceeding.**
If analyze reports that all topics are already documented, that is fine — proceed to Phase 2
to ensure checkbox test cases exist for the documented content.

### Phase 2 — Generate checkbox test cases

Invoke the **cbprovider-domain** skill in **create** mode for `<domain>`:

```
/cbprovider-domain create <domain>
```

This will:
- Locate the Python bpftrace test scripts created in Phase 1
- Copy them into `~/canonical/workspace/checkbox-provider-kprovider/bin/`
- Create pxu job definitions in `units/<domain>-jobs.pxu`
- Update the test plan
- Validate the provider
- Deploy and run tests on all target machines (from inject.conf)
- Commit and push the results

### Phase 3 — Final summary

After all phases complete, print a combined summary:

```
## scan-and-test complete for domain: <domain>

### Phase 1 — Analysis
| Topic | README | Test Script | Status |
|---|---|---|---|
| <topic1> | ✓ | ✓ | created & committed |
| <topic2> | ✓ | ✓ | updated & committed |

### Phase 2 — Checkbox test cases
| Job ID | Result | Notes |
|---|---|---|
| kprovider/<domain>/... | PASS | |
| kprovider/<domain>/... | SKIP | module not loaded |
```
