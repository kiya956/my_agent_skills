#!/bin/bash
# install.sh - Install agent skills for Claude Code and/or GitHub Copilot
#
# Usage:
#   ./install.sh              - Install for both Claude and Copilot
#   ./install.sh --claude     - Install for Claude Code only
#   ./install.sh --copilot    - Install for GitHub Copilot only

set -e

SCRIPT_DIR=$(dirname "$(realpath "$0")")
SKILLS_DIR="$SCRIPT_DIR/skills"

print_info() { echo -e "\e[32m✓ $*\e[0m"; }
print_warn() { echo -e "\e[33m! $*\e[0m"; }
print_err()  { echo -e "\e[31mERROR: $*\e[0m" >&2; }

merge_permissions() {
    local settings_file="$HOME/.claude/settings.json"

    # Collect all permissions from skills that have permissions.json
    local all_perms=""
    for skill_dir in "$SKILLS_DIR"/*/; do
        local perm_file="$skill_dir/permissions.json"
        if [ -f "$perm_file" ]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            local perms
            perms=$(python3 -c "
import json, sys
with open('$perm_file') as f:
    data = json.load(f)
for p in data.get('allow', []):
    print(p)
" 2>/dev/null)
            if [ -n "$perms" ]; then
                all_perms="$all_perms"$'\n'"$perms"
                print_info "permissions from $skill_name"
            fi
        fi
    done

    if [ -z "$all_perms" ]; then
        return
    fi

    # Merge into settings.json
    if [ ! -f "$settings_file" ]; then
        echo '{"permissions":{"allow":[]}}' > "$settings_file"
    fi

    python3 -c "
import json, sys

settings_file = '$settings_file'
new_perms = '''$all_perms'''.strip().splitlines()
new_perms = [p.strip() for p in new_perms if p.strip()]

with open(settings_file) as f:
    settings = json.load(f)

existing = settings.setdefault('permissions', {}).setdefault('allow', [])
added = 0
for p in new_perms:
    if p not in existing:
        existing.append(p)
        added += 1

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print(f'  {added} new permission(s) merged into {settings_file}')
"
}

merge_copilot_permissions() {
    # For Copilot CLI, permissions.json files are kept per-skill in ~/.copilot/skills/<skill>/
    # This function ensures each installed skill has its permissions.json copied over.
    # It also creates a merged permissions summary at ~/.copilot/skills/permissions.json
    local dest="$HOME/.copilot/skills"
    local merged_file="$dest/permissions.json"
    local all_perms=""

    for skill_dir in "$SKILLS_DIR"/*/; do
        local perm_file="$skill_dir/permissions.json"
        if [ -f "$perm_file" ]; then
            local skill_name
            skill_name=$(basename "$skill_dir")
            local perms
            perms=$(python3 -c "
import json, sys
with open('$perm_file') as f:
    data = json.load(f)
for p in data.get('allow', []):
    print(p)
" 2>/dev/null)
            if [ -n "$perms" ]; then
                all_perms="$all_perms"$'\n'"$perms"
                print_info "copilot permissions from $skill_name"
            fi
        fi
    done

    if [ -z "$all_perms" ]; then
        return
    fi

    # Create a merged permissions.json for all skills
    python3 -c "
import json

new_perms = '''$all_perms'''.strip().splitlines()
new_perms = sorted(set(p.strip() for p in new_perms if p.strip()))

merged = {'allow': new_perms}
with open('$merged_file', 'w') as f:
    json.dump(merged, f, indent=2)
    f.write('\n')

print(f'  {len(new_perms)} permission(s) written to $merged_file')
"
}

install_copilot_cli() {
    echo ""
    echo "=== Installing skills for Copilot CLI ==="
    local dest="$HOME/.copilot/skills"
    mkdir -p "$dest"

    for skill_dir in "$SKILLS_DIR"/*/; do
        local skill_name
        skill_name=$(basename "$skill_dir")
        local target="$dest/$skill_name"

        if [ -d "$target" ]; then
            print_warn "$skill_name already exists at $target — overwriting"
        fi

        cp -r "$skill_dir" "$target"
        print_info "$skill_name → $target"
    done

    echo ""
    echo "--- Merging skill permissions (Copilot CLI) ---"
    merge_copilot_permissions
}

install_claude() {
    echo ""
    echo "=== Installing skills for Claude Code ==="
    local dest="$HOME/.claude/skills"
    mkdir -p "$dest"

    for skill_dir in "$SKILLS_DIR"/*/; do
        local skill_name
        skill_name=$(basename "$skill_dir")
        local target="$dest/$skill_name"

        if [ -d "$target" ]; then
            print_warn "$skill_name already exists at $target — overwriting"
        fi

        cp -r "$skill_dir" "$target"
        print_info "$skill_name → $target"
    done

    echo ""
    echo "--- Merging skill permissions ---"
    merge_permissions

    print_warn "crank skill: edit $dest/crank/.claude/settings.local.json to match your local kernel paths"
}

install_copilot() {
    echo ""
    echo "=== Installing skills for GitHub Copilot ==="
    local copilot_dir="$HOME/.vscode/copilot-skills"
    mkdir -p "$copilot_dir"

    local settings_entries=""
    for skill_dir in "$SKILLS_DIR"/*/; do
        local skill_name
        skill_name=$(basename "$skill_dir")
        local dest_file="$copilot_dir/$skill_name.md"

        cp "$skill_dir/SKILL.md" "$dest_file"
        print_info "$skill_name → $dest_file"
        settings_entries="$settings_entries    {\"file\": \"$dest_file\"},\n"
    done

    # Remove trailing comma from last entry
    settings_entries=$(echo -e "$settings_entries" | sed '$ s/,$//')

    local vscode_settings="$HOME/.config/Code/User/settings.json"
    echo ""
    echo "Add the following to $vscode_settings to enable in Copilot Chat:"
    echo ""
    echo "  \"github.copilot.chat.codeGeneration.instructions\": ["
    echo -e "$settings_entries"
    echo "  ]"
    echo ""
    print_warn "If settings.json already has this key, merge the entries manually."
}

# Parse args
TARGET="both"
for arg in "$@"; do
    case "$arg" in
        --claude)       TARGET="claude" ;;
        --copilot)      TARGET="copilot" ;;
        --copilot-cli)  TARGET="copilot-cli" ;;
        -h|--help)
            echo "Usage: $0 [--claude|--copilot|--copilot-cli]"
            echo "  --claude       Install for Claude Code (~/.claude/skills/)"
            echo "  --copilot      Install for VS Code Copilot (~/.vscode/copilot-skills/)"
            echo "  --copilot-cli  Install for Copilot CLI (~/.copilot/skills/)"
            echo "  (no flag)      Install for all three"
            exit 0
            ;;
        *)
            print_err "Unknown argument: $arg"
            echo "Usage: $0 [--claude|--copilot|--copilot-cli]"
            exit 1
            ;;
    esac
done

case "$TARGET" in
    claude)      install_claude ;;
    copilot)     install_copilot ;;
    copilot-cli) install_copilot_cli ;;
    both)        install_claude; install_copilot; install_copilot_cli ;;
esac

echo ""
print_info "Done."
