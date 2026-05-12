# cbprovider-domain

A Copilot skill that automates the full lifecycle of checkbox kernel test jobs —
from generating test cases out of kernel documentation, all the way to running
them on real hardware and reporting the results.

---

## What it does

```
kernel_readdoc  →  checkbox provider  →  target machines  →  test results  →  pull request
```

1. Reads Python bpftrace test scripts from `~/canonical/workspace/kernel_readdoc`
2. Generates checkbox job definitions (`.pxu`) and installs scripts into the provider
3. Finds configured target machines, injects SSH credentials, and verifies VPN access
4. Rsyncs the updated provider to each target and installs it
5. Runs the test plan on each target, collects results, and reports PASS / FAIL / SKIP
6. Iterates: analyses failures, applies fixes, and re-runs until clean
7. Commits the changes on a feature branch and opens a pull request

---

## Prerequisites

| Requirement | Notes |
|---|---|
| TW VPN | Must be connected before running — the skill will attempt to bring it up automatically |
| SSH key | `~/.ssh/id_rsa.pub` must exist; `inject.sh` will push it to each target |
| `bpftrace` | Must be installed on each target machine |
| `checkbox-cli` | Must be installed on each target machine |
| `kernel_readdoc` repo | Cloned at `~/canonical/workspace/kernel_readdoc` |
| `checkbox-provider-kprovider` repo | Cloned at `~/canonical/workspace/checkbox-provider-kprovider` |

---

## Configuration — Target machines

Edit the target list before running:

```
~/.claude/skills/cbprovider-domain/references/inject.conf
```

Add one `TARGET=` line per machine. Targets can be an IP address or a Certification ID (CID):

```ini
# inject.conf - target machines for cbprovider-domain testing
# Add one TARGET per line. Comment out with # to skip.

TARGET=10.102.195.77       # direct IP
TARGET=202504-36641        # CID — resolved automatically via the hotlab API
TARGET=202512-38196
```

At least one `TARGET=` entry is required. The skill will fail early and tell you
if the file is empty or missing.

---

## Usage

```
/cbprovider-domain <domain>                               # create/update (default)
/cbprovider-domain create <domain>                        # explicit create/update
/cbprovider-domain debug <domain> <ip> <description...>   # debug a specific issue on one target
/cbprovider-domain migrate <domain>                       # migrate domain to Forgejo
```

### Mode A — Create / Update (default)

Generates checkbox test jobs for a kernel subsystem and runs them across all
configured targets.

```
/cbprovider-domain drm
/cbprovider-domain create sound
/cbprovider-domain usb
```

**What happens:**
1. Both `kernel_readdoc` and `checkbox-provider-kprovider` are synced to `main`
2. Test scripts are found under the resolved kernel path (e.g. `drivers/gpu/drm`)
3. Scripts are copied to `bin/` and a `.pxu` job file is created under `units/`
4. The provider is validated with `python3 manage.py validate`
5. SSH credentials are injected to every target in `inject.conf`
6. The updated provider is rsynced and installed on each target
7. `checkbox-cli run <TEST_PLAN_ID>` is executed on each target
8. Results are fetched and displayed per target
9. Failures are analysed and fixed (up to 3 fix/retest cycles)
10. A feature branch is created, committed, and a PR is opened

### Mode B — Debug

Debug an existing domain's test jobs on a single specific target. Use this when
you already have jobs created but something is failing.

```
/cbprovider-domain debug drm 10.102.180.54 bridge test shows all FAIL but result passes
/cbprovider-domain debug sound 10.102.195.77
```

**Arguments:**
- `domain` — kernel subsystem (e.g. `drm`, `sound`, `usb`)
- `ip` — target device IP address
- `description` — (optional) free-text description of the problem; no quotes needed

**What happens:**
1. VPN is verified and SSH credentials are injected to the specified IP
2. Prerequisites on the target are checked (`bpftrace`, `checkbox-cli`, kernel modules)
3. The provider is deployed and the test plan is run
4. Failures are cross-referenced with your description and root-causes are identified
5. Fixes are applied locally, redeployed, and retested (up to 3 cycles)
6. A fix branch is committed and a PR is opened

### Mode C — Migrate

Migrate a domain's scripts and job definitions from `checkbox-provider-kprovider`
to the Forgejo repository at `forgejo.kernel.ubuntu.com`.

```
/cbprovider-domain migrate drm
/cbprovider-domain migrate sound
```

---

## Output — Test results report

After running, the skill prints a summary like this:

```
## Results for domain: drm (kernel path: gpu/drm)

### bin/ scripts
| Script                        | Source                                      |
|-------------------------------|---------------------------------------------|
| gpu_drm_i915_trace_test.py    | kernel_readdoc/drivers/gpu/drm/i915/...     |
| gpu_drm_amd_trace_test.py     | kernel_readdoc/drivers/gpu/drm/amd/...      |

### Test results per target
#### 10.102.195.77
| Job ID                  | Result | Notes                  |
|-------------------------|--------|------------------------|
| kprovider/gpu/drm/core  | PASS   |                        |
| kprovider/gpu/drm/i915  | PASS   |                        |
| kprovider/gpu/drm/amd   | SKIP   | amdgpu module not loaded |

#### 202512-38196
| Job ID                  | Result | Notes |
|-------------------------|--------|-------|
| kprovider/gpu/drm/core  | PASS   |       |
| kprovider/gpu/drm/i915  | SKIP   | i915 module not loaded |
| kprovider/gpu/drm/amd   | PASS   |       |

### Commit
abc1234  Create gpu/drm subsystem checkbox test jobs
```

---

## Supported domains

Any kernel subsystem that has Python test scripts in `kernel_readdoc`. Common examples:

| Domain argument | Resolves to kernel path |
|---|---|
| `drm` | `drivers/gpu/drm` |
| `gpu` | `drivers/gpu` |
| `sound` | `sound` |
| `usb` | `drivers/usb` |
| `acpi` | `drivers/acpi` |
| `net` | `drivers/net` |

Run `/cbprovider-domain <domain>` with any subsystem name — the skill resolves the
correct path automatically by searching the `kernel_readdoc` directory tree.

---

## Troubleshooting

| Problem | Solution |
|---|---|
| "TW VPN is not connected" | Connect to the TW VPN manually, then re-run |
| "inject.conf has no TARGET entries" | Add `TARGET=<IP or CID>` lines to `inject.conf` |
| "bpftrace not found" on target | Run `sudo apt install bpftrace` on the target machine |
| "checkbox-cli not found" on target | Install checkbox on the target machine |
| `git pull` fails (diverged history) | Resolve the merge conflict manually before re-running |
| All targets fail injection | Check VPN and that the target machines are powered on |
