# Ubuntu-Server-setup — Automated Ubuntu 22.04/24.04 VPS Setup Script

**One-command bootstrap and interactive control panel (`svsetup`) for a fresh Ubuntu
server**: automatic security hardening, firewall configuration, and network speed
tuning (TCP BBR), plus a menu to install **Coolify** (self-hosted deploy platform),
**3x-ui / Sanaei panel** (Xray VPN panel), and **Telegram bots** — all isolated from
each other, with the firewall and resource limits handled for you.

Built for anyone who spins up a fresh Ubuntu VPS and wants a repeatable, scripted way
to go from a blank server to a hardened, production-ready box in minutes instead of
manually running the same fifteen commands every time.

## Features

- **One-line install** — a single `curl | bash` command sets up everything and drops
  you into an interactive menu (`svsetup`), reusable any time afterward.
- **Security hardening** — UFW firewall (default-deny), Fail2ban for SSH
  brute-force protection, safe SSH hardening (no lockout risk), automatic security
  updates.
- **Performance tuning** — TCP BBR congestion control, sysctl/network tuning, swap
  configuration, and Docker BuildKit caching to speed up page loads and deploys.
- **Coolify installer** — official latest release, firewall ports opened
  automatically, configured to get resource priority over everything else.
- **3x-ui (Sanaei) submenu** — built and run via Docker (official `docker-compose.yml`
  from the 3x-ui repo itself), with install/update, domain & SSL certificate setup
  (the real native console, restored as a host `x-ui` command too), login settings,
  status, and removal — fixed credentials/port/path and CPU/RAM limits so it never
  competes with Coolify for resources.
- **Docker container management menu** — see every container svsetup (or anything
  else) started, its state and published ports, with start/stop/restart/logs/remove.
- **Telegram bot deployment** — one-command install for
  [tg-bot-auto-sender](https://github.com/Alirewa/tg-bot-auto-sender) and
  [tg-bot-uploader-drive](https://github.com/Alirewa/tg-bot-uploader-drive).
- **Firewall management menu** — list, add, or remove UFW rules without memorizing
  `ufw` syntax.
- **Self-update** — pulls the latest version of this toolkit straight from GitHub.
- **Full reset/uninstall** — undo everything svsetup installed without ever needing
  to reinstall the server's OS.

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

### 3) 3x-ui (MHSanaei) — personal VPN panel, via Docker
svsetup clones the [3x-ui repo](https://github.com/MHSanaei/3x-ui) into
`/opt/3x-ui` and builds/runs it with Docker using **the project's own official
`docker-compose.yml` and `Dockerfile`** — no native/systemd install, fully
isolated from the host. This option is its own submenu:

1. **Install / update** — no prompts. Login `admin`/`admin` (the panel's own
   default), URL `http://<server-ip>:2080/webdw/`. Container capped at
   `cpus: 0.5`, `mem_limit: 512m` in its `docker-compose.yml` — the same plain
   Docker resource-limit mechanism Coolify's containers just don't have
   applied to them, which keeps Coolify the priority workload. Also restores
   a plain **`x-ui` command on the host** (a thin `docker exec` proxy), so
   typing `x-ui` works exactly like it did on a native install.
2. **Domain & SSL certificate** — opens the exact same native console as
   typing `x-ui` (or as a native, non-Docker install) — domain binding,
   Let's Encrypt certs via the bundled acme.sh (domain-based or IP-based),
   custom cert paths, renewal, etc. Nothing was reimplemented here; the real
   `x-ui` management CLI ships inside the image and is fully Docker-aware.
3. **Login settings** — change username/password/port/web path; if the port
   changes, the Docker port mapping is regenerated and the container restarted
   automatically.
4. **Show status & URL**.
5. **Remove 3x-ui**.

**Ports:** `2080-2090` (tcp+udp) are published from the container *and* opened
in the firewall — not just one of the two. `2080` is the panel; the rest is
headroom for Xray inbounds and, importantly, for acme.sh's HTTP-01 challenge
listener if you request a Let's Encrypt certificate for a domain (port 80 is
Coolify's, so when the console asks for a challenge port, pick a free one in
this range — it's already reachable both at the Docker and firewall layer).

The first install builds the panel from source inside Docker (Go + the Vite
frontend), so it can take a few minutes and briefly needs ~1-2GB free RAM — the
swapfile from step 1 covers this on smaller VPS plans.

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

### 8) Docker container management
A `docker ps`-style table (name, state, published ports, image) for every
container on the box, plus actions: start, stop, restart, tail logs, remove a
container (its image/volumes are kept), and a one-shot view of every host port
Docker currently publishes — so you can see at a glance what's running and
exactly which ports each container is using.

### 9) Edit important files
Lists the security-relevant config files svsetup manages (SSH hardening rules,
main `sshd_config`, the Fail2ban jail, sysctl tuning, Docker's `daemon.json`,
3x-ui's `docker-compose.yml`, open-file limits, crontab, `/etc/hosts`) and opens
your pick in `$EDITOR` (or `nano`). Backs up before editing; SSH/JSON/Compose
files are validated after saving and automatically rolled back if the edit would
break them, instead of leaving you with a config that locks you out or won't start.

### 10) Status / logs
Quick status view of which modules have run, plus pointers to the full on-server
documentation (`/root/svsetup-README.txt`) and an option to print the last 30
lines of the log right there — the fastest way to check what just happened.

### 11) Self-update
Pulls the latest version of this toolkit directly from GitHub (`git fetch` +
`reset --hard origin/main` in `/opt/svsetup`) and restarts the menu on the new
version — no need to re-run the curl one-liner.

### Bonus: per-install port prompts
Before Coolify and each Telegram bot actually installs, svsetup asks if that
specific install needs any extra firewall ports beyond what it already knows
about — so the firewall stays in sync with whatever you're deploying, without
having to remember to open ports manually afterward. (3x-ui is the one exception:
its port range is fixed and opened automatically, with no prompt — see step 3.)

### 12) Reset — undo everything svsetup installed
Walks through every component svsetup can install (Telegram bots, 3x-ui, Coolify,
Docker, firewall/SSH hardening, sysctl/swap tuning, extra packages) and offers to
remove each one, with its own confirmation — destructive steps (Coolify's data,
purging Docker) need an explicit yes. Requires typing `RESET` once up front. This
(and Exit) are deliberately last in the menu since they're the options you'll use
least often.

**You never need to reinstall or reset the underlying server (the OS) to undo this
toolkit.** Everything it does — installing packages, opening firewall ports, writing
systemd services, running Docker containers — was done with standard Ubuntu tools
(`apt`, `ufw`, `systemctl`, `docker`), and all of it can be undone the same way. If
you've been experimenting and want a clean slate, just run:

```bash
sudo svsetup --reset
# or, from the menu: option 12
```

then re-run the one-line installer (or `sudo svsetup --all`) to start fresh — no
VPS/OS reinstall needed.

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
sudo svsetup --reset       # undo everything svsetup installed (interactive confirms)
sudo svsetup --docker      # Docker container management menu
sudo svsetup --edit        # edit important config files
sudo svsetup --all         # everything in one go
sudo svsetup --ssh-strict  # opt-in: custom SSH port + key-only auth
```

## Troubleshooting: locked out of root SSH login

Versions before the fix in this section unconditionally disabled root SSH login
(`PermitRootLogin no`) during the security step. On a fresh VPS (Hetzner and most
providers) **root is the only account**, so this could block all SSH access — your
password was never changed, SSH just refuses root entirely. Resetting the root
password from your provider's panel does **not** fix this, since the password was
never the problem.

**Fix without reinstalling the server:** use your provider's *web console* (Hetzner:
server → **Console**, a VNC/serial terminal in the browser) — it logs in locally and
is not affected by `sshd` restrictions. Then run:

```bash
rm -f /etc/ssh/sshd_config.d/99-svsetup.conf
systemctl restart ssh
```

SSH access is restored immediately. Current versions of svsetup only disable root
login when a non-root sudo user with an SSH key already exists as a fallback —
otherwise it leaves root login enabled and offers to create that sudo user for you
first.

## Running options out of order, and not stepping on yourself

You can run the menu options in **any order** — there's no requirement to go
1, 2, 3... in sequence:
- Anything that needs Docker (Coolify, 3x-ui) calls a shared `ensure_docker`
  helper first, which checks for the real `docker` command rather than a
  "did module X run" flag. So `3x-ui` before `Initial setup`, or `Coolify`
  before `3x-ui`, both just install Docker on the spot if it isn't there yet —
  no matter which order you hit them in, or how Docker ended up on the box
  (svsetup's own installer, or a bot's `get.docker.com` install).
- Every module writes to its own dedicated files (`99-svsetup.conf` configs,
  its own directory under `/opt`, its own systemd unit/container name) — two
  different options never write to the *same* file, so installing them in any
  order doesn't overwrite each other's work.
- **Concurrent runs are locked, not racy.** `svsetup` takes an exclusive
  `flock` on a lock file the moment it starts. If you (or a teammate) open a
  second SSH session and run `svsetup` while one is already mid-install, the
  second one refuses immediately with "another svsetup process is already
  running" instead of two processes writing `sysctl.conf`/`ufw`/`daemon.json`
  at the same time and corrupting one or the other's change.

## Resilience & debugging

Every menu option runs inside an isolated subshell — if a module hits an error
(network blip, a package failing to install, etc.) you get an error message and
land back on the menu instead of the whole `svsetup` session dying. An earlier
version had a bug where SSH-port detection (`ss | grep ...`) could fail and silently
kill the entire session under `set -e`, which is exactly the class of failure this
subshell wrapping now contains.

Every run also writes a **full transcript** — not just curated status lines, but
the raw output of every command — to `/var/log/svsetup/svsetup.log`. If something
fails, that log has the real error message; menu option 10 (Status / logs) can
print the last 30 lines on the spot without leaving the menu.

## Firewall ports reference

| Port(s)         | Used by            | Notes                                   |
|-----------------|---------------------|------------------------------------------|
| 22 (or custom)  | SSH                 | Always kept open                         |
| 80, 443         | Coolify (Traefik)   | Public web traffic for deployed apps     |
| 8000            | Coolify             | Dashboard                                |
| 6001, 6002      | Coolify             | Realtime/websocket connections           |
| 2080            | 3x-ui panel         | Fixed — `http://<server-ip>:2080/webdw/` |
| 2081-2090       | 3x-ui inbounds/SSL  | Headroom for inbounds + acme.sh cert challenges; published from Docker AND opened in UFW |
| 8081            | tg-bot-uploader-drive | Local-only Telegram Bot API container, **not** exposed publicly |

## Resource priority

Coolify is the priority workload (~80% of server resources by design), all
enforced with plain Docker resource limits — no special scheduler needed:
- Coolify's Docker containers: **no** cpu/mem limits applied.
- 3x-ui's container: capped at `cpus: 0.5`, `mem_limit: 512m` directly in
  `/opt/3x-ui/docker-compose.yml` — edit those values and run
  `docker compose up -d` in that directory to adjust.
- Telegram bots: lightweight services with no caps needed; if you notice them
  using too many resources, they can be capped the same way via a systemd drop-in
  (auto-sender, drive-uploader) or a `cpus`/`mem_limit` entry (drive-uploader's
  Docker-based Bot API container).
- Use menu option 8 (Docker container management) any time to see what's
  actually running and how its ports are mapped.

## On-server documentation

Every module appends a section to `/root/svsetup-README.txt` as it runs, explaining
what it installed, why, and how to manage it (service names, ports, CLIs). Logs live
in `/var/log/svsetup/svsetup.log`.

## Keywords

Ubuntu server setup script, Ubuntu 24.04 VPS automation, Coolify install script,
3x-ui Sanaei panel install, Xray VPN panel Ubuntu, UFW firewall management script,
TCP BBR speed optimization, Telegram bot VPS deployment, Docker Ubuntu server setup,
SSH hardening script, Fail2ban Ubuntu, self-hosted server bootstrap, sysadmin
automation script.
