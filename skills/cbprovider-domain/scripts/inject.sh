#!/bin/bash
#
# inject.sh - Inject SSH public key to target machine
#
# Usage:
#   inject.sh <IP>           - Inject key to IP with default ubuntu user
#   inject.sh <CID>          - Inject key to machine with CID (e.g., 202504-36641)
#
# This script sends your SSH public key (~/.ssh/id_rsa.pub) to the target
# machine and appends it to ~/.ssh/authorized_keys on the target.

set -e

SCRIPT_DIR=$(dirname "$0")
SSH_KEY="${HOME}/.ssh/id_rsa.pub"
SSH_USER="ubuntu"
SSH_PASS="insecure"
SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR"
HOTLAB_URL="http://f1.cctu.space/tel-hotlab?show_offline=1"
CERT_URL_BASE="https://certification.canonical.com/hardware"

print_err() { echo -e "\e[31mERROR: $@\e[0m" >&2; }
print_info() { echo -e "\e[32m$@\e[0m"; }

usage() {
    cat << EOF
Usage: $0 <IP|CID>

Arguments:
  IP      - Direct IP address (e.g., 10.102.195.77)
  CID     - Certification ID (e.g., 202504-36641)

Examples:
  $0 10.102.195.77
  $0 202504-36641

The script will inject your SSH public key (~/.ssh/id_rsa.pub) to the
target machine's ~/.ssh/authorized_keys file.
EOF
}

check_dependencies() {
    local missing=""
    for cmd in sshpass ssh curl; do
        if ! command -v $cmd &> /dev/null; then
            missing="$missing $cmd"
        fi
    done

    if [ -n "$missing" ]; then
        print_err "Missing required commands:$missing"
        print_err "Install with: sudo apt-get install sshpass openssh-client curl"
        exit 1
    fi
}

check_ssh_key() {
    if [ ! -f "$SSH_KEY" ]; then
        print_err "SSH public key not found: $SSH_KEY"
        print_err "Generate one with: ssh-keygen -t rsa -b 4096"
        exit 1
    fi
}

lookup_cid() {
    local cid="$1"
    local tmpfile=$(mktemp)
    trap "rm -f '$tmpfile'" EXIT

    echo "Looking up CID $cid on $HOTLAB_URL..." >&2

    if ! curl -s -o "$tmpfile" "$HOTLAB_URL"; then
        print_err "Failed to fetch hotlab page"
        rm -f "$tmpfile"
        exit 1
    fi

    local section=$(grep -A 15 "$cid" "$tmpfile")
    local ip=$(echo "$section" | grep -oP 'dut_ip.*?rdp://\K[0-9.]+' | head -1)
    local pdu=$(echo "$section" | grep -oP "show_dut_info\(\[&#39;\K[^:]+(?=:)" | head -1)

    rm -f "$tmpfile"

    if [ -z "$ip" ]; then
        print_err "CID $cid not found on hotlab page"
        echo "Please check manually at:" >&2
        echo "  Hotlab: $HOTLAB_URL" >&2
        echo "  Cert:   $CERT_URL_BASE/$cid" >&2
        exit 1
    fi

    echo "${ip}|${pdu}"
}

inject_key() {
    local target_ip="$1"
    local pub_key=$(cat "$SSH_KEY")
    local pub_key_content=$(echo "$pub_key" | awk '{print $1, $2}')

    print_info "Testing connection to $target_ip..."

    if ! timeout 5 bash -c "echo > /dev/tcp/$target_ip/22" 2>/dev/null; then
        print_err "Machine $target_ip is unreachable (may be powered off)"
        print_info "Please power on the machine and try again"
        return 1
    fi

    print_info "Checking if key already exists on $SSH_USER@$target_ip..."

    if sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$target_ip" "grep -qF '$pub_key_content' ~/.ssh/authorized_keys 2>/dev/null"; then
        print_info "✓ SSH key already exists on $target_ip"
        print_info "You can connect with: ssh $SSH_USER@$target_ip"
        return 0
    fi

    print_info "Injecting SSH key to $SSH_USER@$target_ip..."

    local remote_cmd="mkdir -p ~/.ssh && chmod 700 ~/.ssh && echo '$pub_key' >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"

    if sshpass -p "$SSH_PASS" ssh $SSH_OPTS "$SSH_USER@$target_ip" "$remote_cmd"; then
        print_info "✓ SSH key successfully injected to $target_ip"
        print_info "You can now connect with: ssh $SSH_USER@$target_ip"
        return 0
    else
        print_err "Failed to inject SSH key to $target_ip"
        return 1
    fi
}

main() {
    if [ $# -ne 1 ]; then
        usage
        exit 1
    fi

    local target="$1"

    # Show help
    if [ "$target" = "-h" ] || [ "$target" = "--help" ]; then
        usage
        exit 0
    fi

    check_dependencies
    check_ssh_key

    if [[ "$target" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        inject_key "$target"
    elif [[ "$target" =~ ^[0-9]{6}-[0-9]+$ ]]; then
        local result=$(lookup_cid "$target")
        local ip=$(echo "$result" | cut -d'|' -f1)
        local pdu=$(echo "$result" | cut -d'|' -f2)
        if [ -n "$ip" ]; then
            if [ -n "$pdu" ]; then
                print_info "CID: $target, PDU: $pdu, IP: $ip"
            else
                print_info "CID: $target, IP: $ip"
            fi
            inject_key "$ip"
        fi
    else
        print_err "Invalid argument: $target"
        print_err "Expected IP address (e.g., 10.102.195.77) or CID (e.g., 202504-36641)"
        usage
        exit 1
    fi
}

main "$@"
