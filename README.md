# Ubuntu-Server-setup

One-command bootstrap + interactive control panel (`svsetup`) for a fresh Ubuntu
22.04/24.04 VPS: system hardening and performance tuning, then a menu to install
whichever of your usual stack you need — **Coolify**, **3x-ui**, or your Telegram
bots — with sane defaults, firewall rules, and zero conflicts between them.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Alirewa/Ubuntu-Server-setup/main/install.sh -o svsetup-install.sh
sudo bash svsetup-install.sh
```

This clones the toolkit to `/opt/svsetup`, installs the `svsetup` command, and opens
the menu. Re-run it any time with `sudo svsetup` — every step is safe to repeat
(it skips work that's already done, and re-running a panel installer just updates it
to the latest release).

## What it does

### 1) Initial server setup (runs first, automatically)
- Full `apt update && upgrade`, base toolchain (git, curl, build-essential, ...).
- Timezone, `en_US.UTF-8` locale, NTP time sync (chrony).
- Swapfile sized to RAM, `vm.swappiness=10` (RAM preferred, but no OOM-kills under load).
- Kernel/network tuning: **TCP BBR**, larger socket backlogs, raised file-descriptor
  limits, capped journald log size (200M) — meaningfully faster page loads and no
  more disk-filling logs.
- **Security baseline** — UFW (default-deny incoming), Fail2ban on SSH, SSH hardened
  at a *safe* level (root login disabled only — your SSH port and password auth are
  left untouched so this step can never lock you out), unattended security updates.
  Want stricter SSH (custom port + key-only auth)? Run `sudo svsetup --ssh-strict`
  once you've confirmed key-based login works.
- **Docker Engine** + Compose plugin, installed early since every panel below runs in
  its own isolated container or systemd service.

### 2) Coolify — your deploy panel
Installed via Coolify's own official installer (always the latest release). Opens
ports `80, 443, 8000, 6001, 6002`. Coolify's containers are left **uncapped** —
it gets resource priority over everything else installed by this toolkit.

Also covers the "deploys feel slow" problem: BuildKit + a persistent build-cache
volume are enabled so repeat deploys reuse cached layers, and the BBR/network tuning
above speeds up first-byte time for visitors. See `/root/svsetup-README.txt` on the
server (written automatically) for the full explanation, including why a second web
server (nginx/caddy) is deliberately *not* installed — Coolify already runs Traefik
on 80/443 and a second proxy would only get in its way.

### 3) 3x-ui (MHSanaei) — personal VPN panel
Runs the project's **own official installer** (it asks you for the panel port and
credentials interactively — exactly as it normally does). svsetup then:
- Opens the port(s) you chose in UFW.
- Caps the `x-ui.service` systemd unit to ~20% CPU / 512MB RAM with a lower
  scheduling priority, so it can never compete with Coolify for resources (since
  x-ui runs natively, not in Docker, the systemd cgroup equivalent of a Docker
  resource limit is used — same underlying kernel mechanism).

### 4) Telegram bots (your repos)
Each bot ships its own production-grade `install.sh` (systemd service, isolated
Python venv / Node deps, unique service names) — svsetup just runs the official one:
- **[tg-bot-auto-sender](https://github.com/Alirewa/tg-bot-auto-sender)** — scrapes
  and validates VPN configs, auto-posts to a Telegram channel on a schedule.
- **[tg-bot-uploader-drive](https://github.com/Alirewa/tg-bot-uploader-drive)** —
  lets Telegram users upload files straight to their own Google Drive.

### 5) Extra useful packages
`htop`, `glances`, `ncdu`, `tmux`, `fzf`, `bat`, `tree`, `jq`, `net-tools`, `dnsutils`,
`rsync`, `zstd` — day-to-day server tools, none of which open a network port or
compete with the panels above. Full explanation of each is written to
`/root/svsetup-README.txt` on the server as it installs.

### 6) Firewall management
Dedicated UFW front-end: list current rules, allow a new port (tcp/udp/both, with a
label), or remove a rule by number or by port — no need to remember `ufw` syntax.

### 7) Web/Network speed boost
Standalone button that (re-)applies the BBR/sysctl network tuning and the Docker
BuildKit cache, independent of running the full initial setup, and prints what's
currently active (congestion control algorithm, swap status, BuildKit cache
presence). Safe to run any time.

### 8) Update svsetup itself
Pulls the latest version of this toolkit directly from GitHub (`git fetch` +
`reset --hard origin/main` in `/opt/svsetup`) and restarts the menu on the new
version — no need to re-run the curl one-liner.

### Per-install port prompts
Before Coolify, 3x-ui, and each Telegram bot actually installs, svsetup asks if
that specific install needs any extra firewall ports beyond what it already knows
about — so the firewall stays in sync with whatever you're deploying, without
having to remember to open ports manually afterward.

## Non-interactive flags

```bash
sudo svsetup --init        # update + security + Docker only
sudo svsetup --coolify
sudo svsetup --xui
sudo svsetup --bots
sudo svsetup --extras
sudo svsetup --firewall    # firewall management menu
sudo svsetup --speed       # re-apply network speed tuning
sudo svsetup --update      # pull latest svsetup from GitHub
sudo svsetup --all         # everything in one go
sudo svsetup --ssh-strict  # opt-in: custom SSH port + key-only auth
```

## Resilience

Every menu option runs inside an isolated subshell — if a module hits an error
(network blip, a package failing to install, etc.) you get an error message and
land back on the menu instead of the whole `svsetup` session dying. An earlier
version had a bug where SSH-port detection (`ss | grep ...`) could fail and silently
kill the entire session under `set -e`, which is exactly the class of failure this
subshell wrapping now contains.

## Firewall ports reference

| Port(s)         | Used by            | Notes                                   |
|-----------------|---------------------|------------------------------------------|
| 22 (or custom)  | SSH                 | Always kept open                         |
| 80, 443         | Coolify (Traefik)   | Public web traffic for deployed apps     |
| 8000            | Coolify             | Dashboard                                |
| 6001, 6002      | Coolify             | Realtime/websocket connections           |
| (you choose)    | 3x-ui panel/inbounds| Opened interactively during install      |
| 8081            | tg-bot-uploader-drive | Local-only Telegram Bot API container, **not** exposed publicly |

## Resource priority

Coolify is the priority workload (~80% of server resources by design):
- Coolify's Docker containers: **no** cpu/mem limits applied.
- x-ui: capped via systemd (`CPUQuota`, `MemoryMax`, `Nice`) — see
  `/etc/systemd/system/x-ui.service.d/svsetup-limits.conf` to adjust.
- Telegram bots: lightweight services with no caps needed; if you notice them
  using too many resources, they can be capped the same way via a systemd drop-in.

## On-server documentation

Every module appends a section to `/root/svsetup-README.txt` as it runs, explaining
what it installed, why, and how to manage it (service names, ports, CLIs). Logs live
in `/var/log/svsetup/svsetup.log`.
