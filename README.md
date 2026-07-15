# enigmaOS

Reproduces the Hyprland desktop on a fresh Arch Linux machine: packages,
dotfiles, and the daily-driver scripts the desktop depends on, all in one
repo.

## Scope

This assumes a **base Arch install already exists** — booted, networked, a
user account created (e.g. via `archinstall`), and `sudo` working. It does
not partition disks or run the base install; it picks up from there.

**From bare metal instead?** `iso/` builds a bootable Arch USB with this
repo baked in: build the ISO, flash it, boot the target, answer a few
prompts (disk, hostname, user) and it does the base install *and* runs the
desktop install for you. See [`iso/README.md`](iso/README.md).

## Layout

- `configs/` — GNU Stow dotfiles (hypr, waybar, wofi, dunst, kitty, nvim, tmux, bash).
- `scripts/` — the desktop-facing scripts these configs reference (wofi menus,
  waybar status scripts, monitor switching, the stow helpers, an RDP/VPN
  connection manager, etc). Referenced by absolute path
  (`~/src/enigmaOS/scripts/...`) from the configs, and added to `$PATH`.
- `packages/` — tiered package lists (plain text, one package per line).
- `services/` — systemd units to enable.
- `stages/` — the individual install steps, run in order by `install.sh`.
- `tools/export-current-state.sh` — snapshot this machine's installed
  packages/services for diffing against the curated lists above.

## Usage

```sh
git clone https://github.com/Emkai/enigmaOS.git ~/src/enigmaOS
cd ~/src/enigmaOS
./install.sh
```

Flags:

- `--gpu=intel,nvidia` — GPU vendor package set(s) to install. Defaults to
  `auto` (detected via `lspci`; supports multiple simultaneous vendors for
  hybrid graphics).
- `--extras="embedded extras"` — optional package tiers to install on top of
  the core desktop (see `packages/optional/`).
- `--from=20` — resume a failed run starting at a given stage number,
  skipping earlier (already-applied) stages.

`install.sh` is safe to re-run — every stage is idempotent.

## What's NOT automated

- Disk partitioning / base Arch install.
- GitHub auth. Cloning this repo itself requires it to be public (or you
  already have SSH/token access configured).
- The private `scripts` repo (`linux/edit`, `linux/work` — personal/work
  convenience scripts, not required for the desktop to function). Clone it
  manually once GitHub auth is set up:
  `git clone git@github.com:Emkai/scripts.git ~/src/scripts`
- Secrets/auth: 1Password sign-in, `tailscale up`, VPN/RDP connection
  profiles (credentials are never stored in git — the `vpn`/`rdp` menus
  start empty on a fresh machine).

See `stages/90-summary.sh` for the full manual checklist printed at the end
of a run.

## Updating the package lists

Run `tools/export-current-state.sh` on a live machine, then diff its output
(`packages/_exported/`, `services/_exported/`) against the curated files in
`packages/` and `services/` to manually re-file anything new or removed.
This is deliberately a human step, not automatic — it keeps the GPU/CPU/
optional tiering meaningful instead of collapsing into one flat list.
