#!/usr/bin/env bash
# 13-domains.sh — lightweight cross-service domain registry. Coolify and
# 3x-ui each terminate TLS independently (Traefik inside Coolify, acme.sh
# inside the x-ui console) — svsetup doesn't replace either, but a domain
# pointed at the wrong one (or registered for both) just fails silently with
# no obvious reason. This tracks what's pointed where, catches that conflict
# before it happens, and verifies DNS before you waste time on a cert request.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

DOMAINS_FILE="${SVSETUP_STATE_DIR}/domains.tsv"

module_domains() {
  touch "$DOMAINS_FILE"
  while true; do
    clear
    header "Domain Management"
    domains_list
    echo
    echo "  1) Add a domain"
    echo "  2) Remove a domain"
    echo "  3) Re-check DNS for all domains"
    echo "  0) Back to main menu"
    echo
    local c
    ask c "Choose" "0"
    case "$c" in
      1) domain_add ;;
      2) domain_remove ;;
      3) domains_list_with_dns; press_enter ;;
      0) return 0 ;;
      *) warn "Invalid choice" ;;
    esac
  done
}

server_public_ip() {
  local ip
  ip="$(curl -fsSL --max-time 4 https://api.ipify.org 2>/dev/null)" || true
  if [ -z "$ip" ]; then
    ip="$(curl -fsSL --max-time 4 https://ifconfig.me 2>/dev/null)" || true
  fi
  printf '%s' "$ip"
}

domain_resolved_ip() {
  local domain="$1" resolved
  resolved="$(getent hosts "$domain" 2>/dev/null | awk '{print $1}' | head -1)" || true
  if [ -z "$resolved" ]; then
    resolved="$(curl -fsSL --max-time 4 "https://dns.google/resolve?name=${domain}&type=A" 2>/dev/null \
      | grep -oE '"data":"[0-9.]+"' | head -1 | grep -oE '[0-9.]+')" || true
  fi
  printf '%s' "$resolved"
}

domains_list() {
  if [ ! -s "$DOMAINS_FILE" ]; then
    info "No domains registered yet."
    return 0
  fi
  printf '%-32s %-10s %s\n' "DOMAIN" "TARGET" "ADDED"
  while IFS=$'\t' read -r domain target added _; do
    [ -z "$domain" ] && continue
    printf '%-32s %-10s %s\n' "$domain" "$target" "$added"
  done < "$DOMAINS_FILE"
}

domains_list_with_dns() {
  if [ ! -s "$DOMAINS_FILE" ]; then
    info "No domains registered yet."
    return 0
  fi
  info "Checking this server's public IP..."
  local server_ip; server_ip="$(server_public_ip)"
  [ -z "$server_ip" ] && warn "Could not detect this server's public IP — DNS check skipped."
  echo
  printf '%-32s %-10s %s\n' "DOMAIN" "TARGET" "DNS"
  while IFS=$'\t' read -r domain target added _; do
    [ -z "$domain" ] && continue
    local status="skipped" resolved
    if [ -n "$server_ip" ]; then
      resolved="$(domain_resolved_ip "$domain")"
      if [ -z "$resolved" ]; then
        status="not resolving"
      elif [ "$resolved" = "$server_ip" ]; then
        status="OK"
      else
        status="points elsewhere (${resolved})"
      fi
    fi
    printf '%-32s %-10s %s\n' "$domain" "$target" "$status"
  done < "$DOMAINS_FILE"
}

domain_remove_entry() {
  local domain="$1"
  sed -i "/^${domain}\t/d" "$DOMAINS_FILE"
}

domain_add() {
  local domain target target_label existing
  ask domain "Domain (e.g. app.example.com)" ""
  [ -z "$domain" ] && return 0

  existing="$(awk -F'\t' -v d="$domain" '$1==d {print $2}' "$DOMAINS_FILE" 2>/dev/null)" || true

  echo "  1) Coolify (an app you deployed there)"
  echo "  2) 3x-ui (the VPN panel)"
  ask target "Which service is this domain for" "1"
  case "$target" in
    2) target_label="x-ui" ;;
    *) target_label="coolify" ;;
  esac

  if [ -n "$existing" ] && [ "$existing" != "$target_label" ]; then
    warn "${domain} is already registered for '${existing}'."
    warn "Pointing the same domain at both Coolify and x-ui doesn't work — only one of"
    warn "them can actually terminate TLS for it; the other will just fail silently."
    confirm "Re-register ${domain} for '${target_label}' instead (drops the old entry)?" "N" || return 0
    domain_remove_entry "$domain"
  elif [ "$existing" = "$target_label" ]; then
    info "${domain} is already registered for ${target_label} — refreshing its DNS check."
    domain_remove_entry "$domain"
  fi

  info "Checking DNS for ${domain}..."
  local server_ip resolved
  server_ip="$(server_public_ip)"
  if [ -n "$server_ip" ]; then
    resolved="$(domain_resolved_ip "$domain")"
    if [ "$resolved" = "$server_ip" ]; then
      ok "${domain} already resolves to this server (${server_ip})"
    elif [ -n "$resolved" ]; then
      warn "${domain} currently resolves to ${resolved}, not this server (${server_ip})."
      warn "Update its DNS A record before requesting a certificate, or it will fail."
    else
      warn "${domain} doesn't appear to resolve anywhere yet. Point its DNS A record at"
      warn "${server_ip} before requesting a certificate, or it will fail."
    fi
  else
    warn "Could not detect this server's public IP — skipping DNS verification."
  fi

  printf '%s\t%s\t%s\n' "$domain" "$target_label" "$(date -Iseconds)" >> "$DOMAINS_FILE"
  ok "Registered ${domain} -> ${target_label}"
  echo

  if [ "$target_label" = "coolify" ]; then
    info "Finish this inside Coolify itself: dashboard -> your app -> Domains -> add"
    info "${domain} there. Coolify provisions the SSL certificate automatically via its"
    info "built-in Traefik proxy. This registry entry is local bookkeeping only — it"
    info "lets svsetup warn you about conflicts, it doesn't configure Coolify for you."
  else
    info "Finish this for x-ui in its certificate console (domain binding + Let's"
    info "Encrypt via acme.sh) — same console as the host 'x-ui' command."
    if confirm "Open it now?" "Y"; then
      if command -v xui_console >/dev/null 2>&1; then
        xui_console
      else
        info "Run it from svsetup's 3x-ui menu (option 3 -> 2), or just type: x-ui"
      fi
    fi
  fi
  press_enter
}

domain_remove() {
  domains_list
  echo
  local domain
  ask domain "Domain to remove from the registry (blank to cancel)" ""
  [ -z "$domain" ] && return 0
  if awk -F'\t' -v d="$domain" '$1==d{f=1} END{exit !f}' "$DOMAINS_FILE" 2>/dev/null; then
    domain_remove_entry "$domain"
    ok "Removed ${domain} from the registry (this does not touch any certificate or"
    ok "Coolify config — just the local tracking entry)."
  else
    warn "${domain} was not found in the registry."
  fi
  press_enter
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  require_root; require_ubuntu
  module_domains
fi
