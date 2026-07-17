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
2. It checks you're online (offers a Wi-Fi prompt if not; going without
   network is fine too — the base install runs entirely from the USB's baked
   package repo), then asks for: the **target disk** (with a typed `YES`
   confirmation before wiping), **hostname**, **username**, **password**,
   whether to **encrypt the disk** (default yes), and whether to **enroll
   TPM2 + PIN unlock** (default yes — the passphrase you set becomes a
   recovery key).
3. It does the base install: GPT partitioning (1 GiB EFI + root), optional
   **LUKS2 encryption of the root partition** on the systemd/`sd-encrypt`
   initramfs stack, `pacstrap` of a minimal base **from the ISO's offline
   repo** (network only as a fallback), systemd-boot, your user with sudo,
   NetworkManager enabled (Wi-Fi credentials carried over if you used them).
4. It copies this repo to `~/src/enigmaOS` on the new system and arms a
   **one-shot first-boot** step.
5. Reboot. The first boot unlocks with the **recovery passphrase** (the TPM
   isn't enrolled yet), auto-logs in on tty1, and — if TPM enrollment was
   chosen — **enrolls the TPM2 keyslot and prompts you to set a PIN** (this
   must happen here, on the real boot, so the measured boot state matches).
   It then runs the repo's own `install.sh` — packages, AUR builds, dotfiles
   (`stow`), services — and reboots into the SDDM login screen. Pick the
   **Hyprland (uwsm)** session. From then on, boot asks for the **PIN**.

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
  systemd-boot can load the kernel — the standard, robust layout. Uses the
  systemd/`sd-encrypt` initramfs stack.
- **TPM2 + PIN auto-unlock** — prompted (default yes). On first boot,
  `systemd-cryptenroll` binds a keyslot to the TPM with a PIN, so normal
  boots ask only for a short PIN (rate-limited by the TPM) instead of the
  full passphrase. The install-time passphrase stays as a **recovery key**.
  Needs a TPM2 chip — if none is found, enrollment is skipped and the
  passphrase is used. `TPM_PCRS` (default `7`) controls PCR binding; after a
  firmware/Secure-Boot change the TPM may refuse and you unlock with the
  recovery passphrase, then re-run `systemd-cryptenroll`.
- root account locked; the created user has sudo via the `wheel` group

Not wired in: encrypting `/boot` (needs GRUB or a UKI), TPM2 without a PIN
(edit the `--tpm2-with-pin` flag in `enigma-install`), and alternative
bootloaders.

> **Testing TPM in a VM:** a plain QEMU guest has no TPM. Add an emulated one
> with `swtpm` (`-tpmdev emulator,... -device tpm-tis,...`) or the enrollment
> step will just skip and fall back to the passphrase.

## Still not automated (same as a normal enigmaOS run)

The first-boot `install.sh` finishes the desktop, but the manual follow-ups
from `stages/90-summary.sh` still apply: GitHub auth + cloning the private
`scripts` repo, 1Password sign-in, `tailscale up`, VPN/RDP profiles.

## The offline package repo

The build bakes a pacman repo into the ISO holding the **full dependency
closure** of the base install (both ucodes included), `packages/core.txt`,
and **pre-built AUR packages** from `packages/core-aur.txt` (plus `yay`
itself). What that buys:

- `pacstrap` installs from the USB — a base install needs **no network**.
- The installer copies the repo to `/var/cache/enigma-offline` on the target
  and registers it ahead of `core`/`extra`, so the first-boot core stages
  install from disk: no mirror downloads, **no AUR compiles** for anything
  pre-built. After a successful first-boot install the repo and its
  `pacman.conf` entry are deleted (a stale snapshot must not shadow updates).
- First boot still wants network for GPU drivers (`packages/gpu/`), optional
  tiers, and any AUR package whose pre-build failed at ISO-build time (those
  fall back to a normal on-target build, with the usual failure report).

Build mechanics: downloads and AUR build results are cached in `iso/cache/`
and reused across rebuilds — `rm -rf iso/cache/aur` (or `make clean-cache`)
to force fresh AUR builds, e.g. for `-git` packages you want current.
`makepkg` may install build dependencies **on the build host** and refuses
to run as root (run `build-iso.sh` as your normal user; a root run just
skips the AUR pre-builds). Expect the ISO to come out several GB larger
than a stock archiso.

## Notes

- The ISO snapshots the repo **as it is on disk** (uncommitted changes
  included). Rebuild after changing anything you want on the target.
- **Test in a VM first.** e.g. an OVMF/UEFI QEMU guest with a scratch disk,
  before flashing hardware — the installer erases a real disk.
- `iso/work/` and `iso/out/` are build artifacts and are git-ignored, as is
  the `iso/cache/` package/AUR-build cache.
