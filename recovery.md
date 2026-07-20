# God-Tier LTSC Provisioner — Manual Recovery Guide

## Overview

This guide covers recovery procedures for every failure mode the provisioner
can encounter. Each section assumes you have access to an Arch Linux live ISO.

---

## Prerequisites for All Recovery

1. Boot from the Arch Linux live USB/CD
2. Ensure you are root: `whoami`
3. Ensure network is available: `ping -c1 archlinux.org`

---

## Identifying the Failure

Check the install log:

```bash
# During the failed install session:
cat /tmp/god-tier-ltsc/install.log

# If the log was saved by rollback:
ls /root/god-tier-ltsc-failure-*.log
cat /root/god-tier-ltsc-failure-*.log
```

The log will show the exact stage and command that failed.

---

## Recovery Procedure: Re-enter Chroot

Most recovery operations require chrooting into the installed system:

```bash
# 1. Identify partitions
lsblk -f

# 2. Mount root (replace /dev/sdaX with your root partition)
mount /dev/sda2 /mnt

# 3. Mount EFI
mount /dev/sda1 /mnt/boot

# 4. Enter chroot
arch-chroot /mnt

# 5. When done:
exit
umount -R /mnt
```

---

## Failure: Stage 01 — Preflight

### Problem: Package not found in repositories
**Cause**: A required package has been renamed, removed, or is in an
unavailable repository.

**Recovery**:
1. Check which package failed: look at the log
2. Search for it: `pacman -Ss <package_name>`
3. If renamed: update `globals.env` with the new name
4. If removed: find a replacement and update `globals.env`
5. Re-run the installer

### Problem: Network unavailable
**Recovery**:
```bash
# Check interface
ip link

# Bring up interface
ip link set <interface> up

# DHCP
dhcpcd <interface>

# Or use iwctl for Wi-Fi
iwctl
```

---

## Failure: Stage 02 — Disk

### Problem: Partitions not appearing after sgdisk
**Recovery**:
```bash
# Manual partition table reload
partprobe /dev/sda
udevadm settle
sleep 5
lsblk
```

### Problem: Disk is mounted / in use
**Recovery**:
```bash
# Find what's using it
lsblk -o NAME,MOUNTPOINT /dev/sda
findmnt -S /dev/sda

# Unmount everything
umount -R /mnt 2>/dev/null
swapoff -a 2>/dev/null

# If a process holds it open
fuser -mv /dev/sda
```

### Problem: Partitioning completed but formatting failed
**Recovery**:
```bash
# Re-format manually
mkfs.fat -F 32 /dev/sda1    # EFI
mkfs.ext4 -F /dev/sda2      # Root

# Mount and continue
mount -o noatime /dev/sda2 /mnt
mkdir -p /mnt/boot
mount /dev/sda1 /mnt/boot
```

---

## Failure: Stage 03 — Pacstrap

### Problem: Partial package installation
**Cause**: Network drop, mirror issue, or disk space.

**Recovery**:
```bash
# Mount the system
mount -o noatime /dev/sda2 /mnt
mount /dev/sda1 /mnt/boot

# Retry pacstrap (it's idempotent)
pacstrap -K /mnt base linux-lts linux-lts-headers linux-firmware ...

# Or from inside the chroot:
arch-chroot /mnt
pacman -Syu
pacman -S <missing_packages>
```

### Problem: Keyring errors
**Recovery**:
```bash
pacman-key --init
pacman-key --populate archlinux
pacman -Sy archlinux-keyring
```

### Problem: fstab incorrect or missing
**Recovery**:
```bash
# Mount everything correctly first, then:
genfstab -U /mnt > /mnt/etc/fstab

# Verify:
cat /mnt/etc/fstab
```

---

## Failure: Stage 04 — Core Configuration

### Problem: locale-gen failed
**Recovery**:
```bash
arch-chroot /mnt
# Verify locale.gen has the line uncommented:
grep "en_US.UTF-8" /etc/locale.gen
# If commented, uncomment it:
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
```

### Problem: GRUB install failed
**Recovery**:
```bash
arch-chroot /mnt

# Reinstall GRUB
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable

# Regenerate config
grub-mkconfig -o /boot/grub/grub.cfg

# Verify
ls -la /boot/EFI/BOOT/BOOTX64.EFI
cat /boot/grub/grub.cfg | grep menuentry
```

### Problem: mkinitcpio failed or plymouth hook missing
**Recovery**:
```bash
arch-chroot /mnt

# Verify hooks line in mkinitcpio.conf:
grep "^HOOKS=" /etc/mkinitcpio.conf
# Should contain: base udev plymouth autodetect modconf kms keyboard keymap consolefont block filesystems fsck

# Fix if needed:
nano /etc/mkinitcpio.conf

# Rebuild:
mkinitcpio -P

# Verify plymouth is in the image:
lsinitcpio /boot/initramfs-linux-lts.img | grep plymouth
```

### Problem: User creation failed
**Recovery**:
```bash
arch-chroot /mnt

# Check if user exists
id <username>

# Create if missing
useradd -m -G wheel,video,audio,storage,optical,input -s /bin/bash <username>

# Set password
passwd <username>

# Verify sudo
cat /etc/sudoers.d/10-wheel
visudo -cf /etc/sudoers.d/10-wheel
```

### Problem: Wrong timezone
**Recovery**:
```bash
arch-chroot /mnt
ln -sf /usr/share/zoneinfo/Asia/Kolkata /etc/localtime
hwclock --systohc
```

---

## Failure: Stage 05 — GUI Configuration

### Problem: Theme files missing
**Recovery**:
```bash
arch-chroot /mnt

# Verify theme packages
pacman -Q materia-gtk-theme papirus-icon-theme lxqt-themes

# Install missing ones
pacman -S materia-gtk-theme papirus-icon-theme lxqt-themes

# Verify Leech theme
ls /usr/share/lxqt/themes/Leech/
```

### Problem: Desktop entries corrupted
**Recovery**:
```bash
arch-chroot /mnt

# Reinstall the package that owns the .desktop file
pacman -Qo /usr/share/applications/firefox.desktop
pacman -S firefox  # reinstalls and restores original .desktop

# Then re-apply renames manually if desired
```

### Problem: Firefox policies not loading
**Recovery**:
```bash
arch-chroot /mnt

# Verify file exists and is valid JSON
cat /etc/firefox/policies/policies.json
python3 -m json.tool /etc/firefox/policies/policies.json

# Test in Firefox: navigate to about:policies
# If blank, the JSON has a syntax error
```

### Problem: Qt apps don't follow theme
**Recovery**:
```bash
arch-chroot /mnt

# Verify environment variable
cat /etc/environment.d/90-ui.conf
# Should contain: QT_QPA_PLATFORMTHEME=qt6ct

# Verify qt6ct config
ls -la /home/<username>/.config/qt6ct/qt6ct.conf
```

---

## Failure: Stage 06 — Validation

Validation failures don't break the install — they report issues.

- **CRITICAL failures**: The system may not boot. Address them before rebooting.
- **WARNING failures**: Cosmetic issues. The system will boot but may look wrong.

Review the validation output and fix specific items using the recovery
procedures above.

---

## Emergency: System Won't Boot After Install

### Black screen after GRUB
```bash
# Boot live ISO
# Mount and chroot (see above)

# Check GRUB config has correct kernel path
cat /boot/grub/grub.cfg | grep vmlinuz

# Check initramfs exists
ls -la /boot/initramfs-linux-lts.img

# Rebuild everything
mkinitcpio -P
grub-mkconfig -o /boot/grub/grub.cfg
```

### GRUB menu doesn't appear
```bash
# Boot live ISO
mount /dev/sda2 /mnt
mount /dev/sda1 /mnt/boot
arch-chroot /mnt

# Reinstall GRUB to the removable path
grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB --removable
grub-mkconfig -o /boot/grub/grub.cfg
```

### SDDM doesn't start (tty only)
```bash
# Log in at the TTY
# Check SDDM status
systemctl status sddm

# Check Xorg log
cat /var/log/Xorg.0.log | grep EE

# Common fix: reinstall Nouveau driver
pacman -S xf86-video-nouveau mesa

# Restart SDDM
systemctl restart sddm
```

### No network after boot
```bash
# Check NetworkManager is running
systemctl status NetworkManager

# If not enabled
systemctl enable --now NetworkManager

# Connect
nmtui
```

---

## Nuclear Option: Full Reinstall

If the system is beyond repair:

```bash
# Boot live ISO
# Wipe and start fresh
umount -R /mnt 2>/dev/null
sgdisk --zap-all /dev/sda

# Copy the framework to the live ISO (USB, network, etc.)
# Run install.sh again
bash install.sh
```

---

## Log Locations

| Location | Description |
|----------|-------------|
| `/tmp/god-tier-ltsc/install.log` | Main install log (live session) |
| `/root/god-tier-ltsc-failure-*.log` | Saved on rollback |
| `/var/log/Xorg.0.log` | X11 log (post-boot) |
| `journalctl -b` | Systemd journal (post-boot) |
| `journalctl -u sddm` | SDDM logs (post-boot) |
| `systemctl --failed` | Failed services (post-boot) |
