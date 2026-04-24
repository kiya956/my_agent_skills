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
        --claude)  TARGET="claude" ;;
        --copilot) TARGET="copilot" ;;
        -h|--help)
            echo "Usage: $0 [--claude|--copilot]"
            exit 0
            ;;
        *)
            print_err "Unknown argument: $arg"
            echo "Usage: $0 [--claude|--copilot]"
            exit 1
            ;;
    esac
done

case "$TARGET" in
    claude)  install_claude ;;
    copilot) install_copilot ;;
    both)    install_claude; install_copilot ;;
esac

echo ""
print_info "Done."
