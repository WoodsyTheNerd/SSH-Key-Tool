#!/usr/bin/env bash
set -euo pipefail

KEY_DATA='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAID7dd527MoBUDCvfobryWUEPg3QK7QQZhnR0gAmZOlAU Nerds-ed-key'
KEY_SRC="${1-}"
AUTH_FILE="$HOME/.ssh/authorized_keys"
LOCK_FILE="$HOME/.ssh/.authorized_keys.lock"

prompt_choice() 
{
  echo "Choose action for $USER:"
  echo "  1 = install key"
  echo "  0 = uninstall key"
  read -rp "Enter 1 or 0: " choice
  case "$choice" in
    1|0) echo "$choice" ;;
    *) echo "Invalid choice. Run again and enter 1 or 0." >&2; exit 1 ;;
  esac
}

have_cmd() { command -v "$1" >/dev/null 2>&1; }

get_key() 
{
  if [[ -n "$KEY_SRC" ]]; then
    if [[ "$KEY_SRC" =~ ^https?:// ]]; then
      have_cmd curl || { echo "curl not found" >&2; exit 2; }
      curl -fsSL "$KEY_SRC"
    else
      [[ -f "$KEY_SRC" ]] || { echo "Key file not found: $KEY_SRC" >&2; exit 3; }
      cat "$KEY_SRC"
    fi
  else
    if [[ "$KEY_DATA" == CHANGE_ME_* ]]; then
      echo "Embedded KEY_DATA is not set. Pass a key file path or URL as the first arg." >&2
      exit 4
    fi
    printf "%s\n" "$KEY_DATA"
  fi
}

normalize_key() 
{
  tr -d '\r' | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g' | sed -E 's/^[[:space:]]+|[[:space:]]+$//g'
}

validate_key() {
  if have_cmd ssh-keygen; then
    local tmp; tmp="$(mktemp)"
    trap 'rm -f "$tmp"' RETURN
    printf "%s\n" "$1" > "$tmp"
    ssh-keygen -lf "$tmp" >/dev/null 2>&1 || { echo "Invalid public key format" >&2; exit 5; }
  fi
}

ensure_perms() {
  mkdir -p "$HOME/.ssh"
  chmod 700 "$HOME/.ssh"
  touch "$AUTH_FILE"
  chmod 600 "$AUTH_FILE"
}

backup_auth() {
  cp "$AUTH_FILE" "${AUTH_FILE}.bak.$(date -u +%Y%m%dT%H%M%SZ)"
}

install_key() {
  local key="$1"
  ensure_perms
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "authorized_keys is locked. Try again." >&2; exit 6; }
  if grep -Fxq "$key" "$AUTH_FILE"; then
    echo "Key already present. No changes."
    return 0
  fi
  backup_auth
  printf "%s\n" "$key" >> "$AUTH_FILE"
  echo "Key added."
}

uninstall_key() {
  local key="$1"
  [[ -f "$AUTH_FILE" ]] || { echo "No authorized_keys file. Nothing to do." ; return 0; }
  exec 9>"$LOCK_FILE"
  flock -n 9 || { echo "authorized_keys is locked. Try again." >&2; exit 6; }
  if ! grep -Fxq "$key" "$AUTH_FILE"; then
    echo "Key not found. No changes."
    return 0
  fi
  backup_auth
  awk -v k="$key" '$0!=k' "$AUTH_FILE" > "${AUTH_FILE}.new"
  mv "${AUTH_FILE}.new" "$AUTH_FILE"
  echo "Key removed."
}

main() {
  choice="$(prompt_choice)"
  raw_key="$(get_key)"
  key="$(printf "%s" "$raw_key" | normalize_key)"
  validate_key "$key"

  if [[ "$choice" == "1" ]]; then
    install_key "$key"
  else
    uninstall_key "$key"
  fi
}

main "$@"
