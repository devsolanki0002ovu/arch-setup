# God-Tier LTSC Provisioner — Maintenance Recommendations

## Overview

Arch Linux is a rolling-release distribution. The installed system will
require periodic maintenance to remain secure and functional. This document
covers procedures specific to this deployment profile.

---

## Routine System Updates

### Weekly Update Procedure

```bash
# 1. Check for updates (dry run)
checkupdates

# 2. Update all packages
sudo pacman -Syu

# 3. If linux-lts was updated, rebuild initramfs
sudo mkinitcpio -P

# 4. If GRUB was updated, regenerate config
sudo grub-mkconfig -o /boot/grub/grub.cfg

# 5. Reboot if kernel was updated
```

> **IMPORTANT**: The LTS kernel updates infrequently (~quarterly), but when
> it does, you MUST rebuild the initramfs. The plymouth hook must be
> re-injected into the new initramfs image.

### Verifying Initramfs After Kernel Update

```bash
# Check plymouth hook is present
lsinitcpio /boot/initramfs-linux-lts.img | grep plymouth

# If missing, rebuild
sudo mkinitcpio -P
```

---

## Package Management

### Checking for Orphaned Packages

```bash
# List orphans (installed as dependencies, no longer needed)
pacman -Qdtq

# Remove orphans
sudo pacman -Rns $(pacman -Qdtq)
```

### Checking for Broken Packages

```bash
# Verify package file integrity
sudo pacman -Qkk 2>&1 | grep -v "0 altered files"
```

### Package Cache Cleanup

```bash
# Keep only the 2 most recent versions of each package
sudo paccache -rk2

# Remove all cached versions of uninstalled packages
sudo paccache -ruk0
```

---

## Monitoring Framework Health

### ZRAM Status

```bash
# Check ZRAM device
zramctl

# Expected output: /dev/zram0 with ~4G size, zstd compression
# If not active, check:
systemctl status systemd-zram-setup@zram0.service
```

### EarlyOOM Status

```bash
systemctl status earlyoom

# View recent OOM kills
journalctl -u earlyoom --since "1 week ago" | grep -i kill
```

### I/O Scheduler

```bash
# Verify BFQ is active
cat /sys/block/sda/queue/scheduler
# Expected: [bfq] (bfq should be in brackets)

# Verify read_ahead_kb
cat /sys/block/sda/queue/read_ahead_kb
# Expected: 128
```

### PipeWire Status

```bash
# Check user services (run as your user, not root)
systemctl --user status pipewire pipewire-pulse wireplumber

# Quick audio test
pactl info | grep "Server Name"
# Should show: PulseAudio (on PipeWire ...)
```

---

## Theme & Appearance Maintenance

### Monitoring Package Deprecation

The following packages should be monitored for deprecation:

| Package | Risk | Alternative |
|---------|------|-------------|
| `materia-gtk-theme` | Medium — unmaintained upstream | `adw-gtk-theme` |
| `papirus-icon-theme` | Low — actively maintained | N/A |
| `lxqt-themes` (Leech) | Low — bundled with LXQt | Any LXQt theme |
| `qt6ct` | Low — actively maintained | N/A |
| `xf86-video-nouveau` | Medium — may be replaced by `modesetting` | Remove package, use kernel modesetting |

### If materia-gtk-theme Is Removed

```bash
# Switch to Adwaita-dark (built into GTK)
# Update GTK3 config:
sed -i 's/gtk-theme-name=Materia-dark/gtk-theme-name=Adwaita-dark/' \
    ~/.config/gtk-3.0/settings.ini

# Update GTK2 config:
sed -i 's/gtk-theme-name="Materia-dark"/gtk-theme-name="Adwaita-dark"/' \
    ~/.gtkrc-2.0

# Update skel for future users:
sudo sed -i 's/Materia-dark/Adwaita-dark/g' /etc/skel/.config/gtk-3.0/settings.ini
sudo sed -i 's/Materia-dark/Adwaita-dark/g' /etc/skel/.gtkrc-2.0
```

### If Nouveau Breaks After Mesa Update

```bash
# Symptom: Black screen after login, Xorg crash
# Check Xorg log:
cat /var/log/Xorg.0.log | grep -E "(EE|Fatal)"

# Try modesetting driver instead:
sudo rm /etc/X11/xorg.conf.d/*nouveau*

# Create modesetting config:
sudo tee /etc/X11/xorg.conf.d/20-modesetting.conf <<EOF
Section "Device"
    Identifier "GPU"
    Driver "modesetting"
EndSection
EOF

# Restart SDDM
sudo systemctl restart sddm
```

---

## Journald Maintenance

Journald is configured to cap at 50M. Verify:

```bash
journalctl --disk-usage
# Should be under 50M

# If needed, vacuum manually
sudo journalctl --vacuum-size=50M
```

---

## GRUB Maintenance

### After Any GRUB Package Update

```bash
# Reinstall to EFI
sudo grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable

# Regenerate config
sudo grub-mkconfig -o /boot/grub/grub.cfg

# Verify
ls -la /boot/EFI/BOOT/BOOTX64.EFI
grep menuentry /boot/grub/grub.cfg
```

### If UEFI NVRAM Is Cleared

Because we used `--removable`, the system should still boot from the
fallback path `/EFI/BOOT/BOOTX64.EFI`. No manual intervention needed.

---

## Firefox Policy Maintenance

Firefox enterprise policies are in `/etc/firefox/policies/policies.json`.

### After Firefox Major Updates

Verify policies still load:
1. Open Firefox
2. Navigate to `about:policies`
3. All policies should show as "Active"

If policies stopped working, Mozilla may have changed the schema.
Check: https://mozilla.github.io/policy-templates/

---

## Desktop Entry Maintenance

Package updates may overwrite renamed `.desktop` files. After updating
GUI application packages:

```bash
# Check if names reverted
grep "^Name=" /usr/share/applications/firefox.desktop
# If it says "Firefox Web Browser" instead of "Web Browser", re-apply:

# Re-run the rename loop from 05-gui.sh or manually:
sudo sed -i 's/^Name=.*/Name=Web Browser/' /usr/share/applications/firefox.desktop
```

---

## Disaster Recovery Checklist

If the system becomes unbootable:

- [ ] Boot from Arch Linux live USB
- [ ] Mount root: `mount /dev/sda2 /mnt`
- [ ] Mount EFI: `mount /dev/sda1 /mnt/boot`
- [ ] Chroot: `arch-chroot /mnt`
- [ ] Check kernel: `ls /boot/vmlinuz-linux-lts`
- [ ] Rebuild initramfs: `mkinitcpio -P`
- [ ] Reinstall GRUB: `grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable`
- [ ] Regenerate GRUB config: `grub-mkconfig -o /boot/grub/grub.cfg`
- [ ] Verify EFI binary: `ls /boot/EFI/BOOT/BOOTX64.EFI`
- [ ] Exit chroot: `exit`
- [ ] Unmount: `umount -R /mnt`
- [ ] Reboot: `reboot`

---

## Hardware-Specific Notes

### Intel Pentium G2010 (Ivy Bridge)
- Microcode updates via `intel-ucode` — installed automatically
- No issues expected with modern kernels
- Hardware virtualization (VT-x) is NOT supported on this CPU

### GeForce 210 (GT218 / Tesla)
- Nouveau driver only — proprietary drivers stopped at 340.xx (incompatible)
- No GPU reclocking in Nouveau by default (power management limited)
- If the GPU dies, integrated Intel HD Graphics is NOT available on this CPU
- Maximum resolution via Nouveau: typically 1920x1080 (monitor-dependent)

### 4 GB DDR3
- ZRAM effectively doubles usable memory to ~6-7 GB
- EarlyOOM protects against hard lockups from OOM
- Avoid opening more than ~10 Firefox tabs simultaneously
- `swappiness=100` ensures ZRAM is used aggressively before OOM

### 7200 RPM HDD
- `noatime` mount option reduces unnecessary writes
- BFQ scheduler optimizes for rotational media latency
- `read_ahead_kb=128` improves sequential read performance
- Expect 60-120 second boot times (Plymouth spinner hides this)
- Consider adding an SSD in the future for a dramatic improvement

### Gigabyte H61M-S1
- UEFI supported (no Secure Boot needed)
- `--removable` GRUB handles NVRAM quirks common on budget boards
- USB 2.0 only — MTP/iPhone transfers will be slow
