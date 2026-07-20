# God-Tier LTSC Provisioner — Architecture Documentation

## Overview

The God-Tier LTSC Provisioner is a modular Arch Linux deployment framework
targeting specific legacy hardware (Pentium G2010 / GeForce 210 / 4 GB DDR3 / HDD).
It prioritizes **correctness, recoverability, determinism, and maintainability**
over speed or automation elegance.

---

## Design Principles

1. **Fail loudly, recover cleanly.** Every command checks its exit status.
   Failures trigger a full rollback that unmounts filesystems and saves logs.

2. **Never assume state.** Directories are created before writing. Partitions
   are discovered dynamically. Services are verified to exist before enabling.

3. **Idempotency.** Running any stage twice produces the same result without
   corruption or duplication. `idempotent_line()` prevents double-appends.
   `safe_write()` atomically replaces files.

4. **No raw injection.** User input is validated and escaped via `printf '%q'`.
   Passwords are set via `chpasswd` (pipe), not heredoc injection.
   XML is edited with `xmlstarlet`, never regex.

5. **Official packages only.** No AUR, Flatpak, Snap, or AppImage. Every
   package is verified against the live repository before any destructive
   operation begins.

---

## Module Dependency Graph

```
install.sh
├── globals.env          (configuration constants — sourced first)
├── 00-lib.sh            (shared functions — sourced second)
├── 01-preflight.sh      (env validation, input, package check)
│   └── depends on: 00-lib.sh, globals.env
├── 02-disk.sh           (partition, format, mount)
│   └── depends on: 01-preflight.sh (TARGET_DISK validated)
├── 03-pacstrap.sh       (install packages, generate fstab)
│   └── depends on: 02-disk.sh (mounted filesystems)
├── 04-core.sh           (locale, users, boot, performance)
│   └── depends on: 03-pacstrap.sh (packages installed)
├── 05-gui.sh            (desktop, themes, Firefox, entries)
│   └── depends on: 04-core.sh (user exists, services framework ready)
└── 06-validate.sh       (80+ post-install checks)
    └── depends on: 05-gui.sh (all config written)
```

All modules are `source`d by the orchestrator (not subshelled) so they
share a single Bash process and can access each other's variables.

---

## Data Flow

```
User Input (interactive)
        │
        ▼
┌─────────────┐     ┌─────────────┐
│ 01-preflight │ ──▶ │ globals.env │  (runtime values written)
└──────┬──────┘     └──────┬──────┘
       │                   │
       ▼                   ▼
┌─────────────┐     Sourced by all subsequent modules
│  02-disk    │
└──────┬──────┘
       │  GTLTSC_EFI_PART, GTLTSC_ROOT_PART (discovered dynamically)
       ▼
┌─────────────┐
│ 03-pacstrap │ ──▶ copies globals.env into chroot as
└──────┬──────┘     /tmp/gtltsc-globals.env
       │
       ▼
┌─────────────┐     ┌─────────────┐
│  04-core    │ ──▶ │ 05-gui      │ ──▶  06-validate
└─────────────┘     └─────────────┘
   (chroot)            (chroot)          (verification)
```

---

## Key Architectural Decisions

### 1. Sourced Modules vs. Subshells

Modules are `source`d rather than executed in subshells. This allows:
- Variable sharing between stages (e.g., discovered partition paths)
- Single ERR/EXIT trap for rollback
- Consistent `set -Eeuo pipefail` enforcement

Trade-off: A bug in one module can corrupt another's state. Mitigated by
strict scoping discipline and prefixing all framework variables with `GTLTSC_`.

### 2. Atomic File Writes

All configuration writes use `safe_write()` or `safe_write_heredoc()`:
1. Create parent directories via `ensure_dir()`
2. Write to a temp file in the same directory
3. Set permissions
4. `mv` atomically to final location

This prevents partial writes on power failure or interrupt.

### 3. Dynamic Partition Discovery

After `sgdisk` creates partitions:
1. `partprobe` notifies the kernel
2. `udevadm settle` waits for udev processing
3. A polling loop checks `lsblk` for partition appearance (timeout: 30s)
4. Partition paths are read from `lsblk -nrpo NAME`, never hardcoded

This handles SATA (`/dev/sda1`), NVMe (`/dev/nvme0n1p1`), and virtio
(`/dev/vda1`) transparently.

### 4. Chroot Variable Passing

Variables are passed into the chroot via a serialized file:
- `globals.env` is copied to `/tmp/gtltsc-globals.env` in the new root
- Runtime values (from interactive input) are appended using `printf '%q'`
- Chroot scripts source this file

This avoids injecting raw variables into heredocs or command strings.

### 5. PipeWire as Global User Service

PipeWire, pipewire-pulse, and wireplumber are user-level systemd services.
`systemctl --user enable` requires a user session context unavailable during
chroot. Solution: `systemctl --global enable` which applies to all users
at login time.

### 6. No Compositor

The GeForce 210 (Tesla architecture) on Nouveau has extremely limited
GPU acceleration. Compositing (picom, compton) would cause:
- Visible lag on window operations
- Potential GPU lockups
- Higher power consumption

Openbox runs without compositing for maximum responsiveness.

### 7. GTK Theme: Materia-dark

`arc-gtk-theme` has moved to the AUR and violates the "official repos only"
constraint. `materia-gtk-theme` provides a similar flat dark aesthetic and
is maintained in the Extra repository.

---

## Filesystem Layout (Installed System)

```
/
├── boot/                          # EFI System Partition (FAT32, 512M)
│   ├── vmlinuz-linux-lts
│   ├── initramfs-linux-lts.img
│   ├── intel-ucode.img
│   ├── grub/grub.cfg
│   └── EFI/BOOT/BOOTX64.EFI     # Removable EFI entry
├── etc/
│   ├── default/grub              # GRUB configuration
│   ├── environment.d/90-ui.conf  # QT_QPA_PLATFORMTHEME=qt6ct
│   ├── firefox/policies/policies.json
│   ├── hostname
│   ├── hosts
│   ├── locale.conf
│   ├── mkinitcpio.conf           # Hooks incl. plymouth
│   ├── sddm.conf.d/10-ltsc.conf
│   ├── skel/                     # Template for new users
│   │   ├── .config/
│   │   │   ├── gtk-3.0/settings.ini
│   │   │   ├── gtk-4.0/settings.ini
│   │   │   ├── lxqt/{lxqt,session,panel}.conf
│   │   │   ├── openbox/{rc.xml,autostart,environment}
│   │   │   ├── pcmanfm-qt/lxqt/settings.conf
│   │   │   ├── qt6ct/qt6ct.conf
│   │   │   ├── mimeapps.list
│   │   │   └── user-dirs.dirs
│   │   └── .gtkrc-2.0
│   ├── sudoers.d/10-wheel
│   ├── sysctl.d/99-ltsc-performance.conf
│   ├── systemd/
│   │   ├── journald.conf.d/50-ltsc.conf
│   │   └── zram-generator.conf
│   ├── udev/rules.d/60-io-scheduler.rules
│   └── vconsole.conf
└── home/<username>/              # Populated from /etc/skel
```

---

## Security Model

- **No autologin**: SDDM requires password at every boot
- **Sudoers via wheel group**: Explicit `visudo -cf` validation
- **No raw variable injection**: All user input escaped with `printf '%q'`
- **Password validation**: Minimum 4 characters, set via `chpasswd` pipe
- **Firefox hardened**: Enterprise policies disable telemetry, Pocket, studies
- **Strict mode**: `set -Eeuo pipefail` catches all unchecked errors
- **No AUR**: Eliminates unreviewed package risk
- **Boot disk protection**: Refuses to operate on the running system's disk

---

## Error Handling

```
Any command failure (exit code != 0)
        │
        ▼
set -e triggers EXIT trap (_on_exit)
        │
        ▼
Prints: stage name, exit code, log path
        │
        ▼
Calls rollback():
  1. Disables ZRAM swap if active
  2. Collects mount points under /mnt (deepest-first)
  3. Unmounts each (tries -R first, -l as fallback)
  4. Copies log to /root/god-tier-ltsc-failure-<timestamp>.log
  5. Prints rollback summary
```
