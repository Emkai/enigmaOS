# enigmaOS install USB

Turn this repo into a bootable Arch USB that installs a full enigmaOS
machine — base Arch **and** the Hyprland desktop — with a short guided
prompt and no GitHub auth needed on the target.

## The three commands

```sh
# 1. Build the ISO (on any Arch box; installs `archiso` if missing)
make iso                      # or: ./iso/build-iso.sh

# 2. Write it to a USB stick (lists disks, makes you confirm)
make flash                    # or: ./iso/flash-usb.sh [iso/out/enigmaos-*.iso]

# 3. Boot the target machine from the USB (UEFI). The installer auto-runs.
```

`make` (run from the repo root) is just a front-end over the two scripts;
`make help` lists the targets, and `make clean` removes the build artifacts.

## What happens when you boot the USB

1. The live environment auto-launches the **guided installer** on tty1.
2. It checks you're online (offers a Wi-Fi prompt if not), then asks for:
   the **target disk** (with a typed `YES` confirmation before wiping),
   **hostname**, **username**, **password**, and whether to **encrypt the
   disk** (default yes — you set a LUKS passphrase you'll type at every boot).
3. It does the base install: GPT partitioning (1 GiB EFI + root), optional
   **LUKS2 encryption of the root partition**, `pacstrap` of a minimal base,
   systemd-boot, your user with sudo, NetworkManager enabled (Wi-Fi
   credentials carried over if you used them).
4. It copies this repo to `~/src/enigmaOS` on the new system and arms a
   **one-shot first-boot** step.
5. Reboot. On first boot the machine auto-logs in on tty1 and runs the
   repo's own `install.sh` — packages, AUR builds, dotfiles (`stow`),
   services — then reboots into the SDDM login screen. Pick the
   **Hyprland (uwsm)** session.

The base install and the desktop install stay separate on purpose:
`install.sh` runs on the real, booted system (a proper user session +
network), which is the environment it was designed for — `systemctl --user`
and AUR/`makepkg` behave, unlike inside a chroot.

## Defaults (edit before building if you want)

Top of `iso/airootfs/usr/local/bin/enigma-install`:

- Locale `en_US.UTF-8`, keymap `us`, timezone `Europe/Stockholm`
- systemd-boot
- **LUKS2 disk encryption** — prompted at install (default yes). Encrypts
  the **root partition only**; the ESP (`/boot`) stays unencrypted so
  systemd-boot can load the kernel — the standard, robust layout. Unlocked
  at boot by a passphrase via the `encrypt` mkinitcpio hook.
- root account locked; the created user has sudo via the `wheel` group

Not wired in: encrypting `/boot` (needs GRUB or a UKI), TPM2 auto-unlock
(`systemd-cryptenroll`), and alternative bootloaders. Add them in
`enigma-install` if you want them.

## Still not automated (same as a normal enigmaOS run)

The first-boot `install.sh` finishes the desktop, but the manual follow-ups
from `stages/90-summary.sh` still apply: GitHub auth + cloning the private
`scripts` repo, 1Password sign-in, `tailscale up`, VPN/RDP profiles.

## Notes

- The ISO snapshots the repo **as it is on disk** (uncommitted changes
  included). Rebuild after changing anything you want on the target.
- **Test in a VM first.** e.g. an OVMF/UEFI QEMU guest with a scratch disk,
  before flashing hardware — the installer erases a real disk.
- `iso/work/` and `iso/out/` are build artifacts and are git-ignored.
