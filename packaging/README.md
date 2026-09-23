# Standalone Packaging for AlDente Hardware Broker

This directory contains standalone packaging files for the optional root-owned broker and systemd persistence units (`omarchy-aldente-helper`).

> [!NOTE]
> AlDente operates natively out-of-the-box using standard Linux `pkexec` (Polkit). Installing this package is optional and recommended for users wanting passwordless background daemon adjustments (sailing mode, thermal guard) and automatic charge limit restoration across reboots and suspend/resume cycles.

## Package Architecture

The package installs and manages:
- `/usr/local/libexec/aldente-set-limit` (root:root 0755): Strictly validated broker script.
- `/etc/systemd/system/aldente-hardware.service` (root:root 0644): Oneshot service restoring the limit on boot and resume.
- `/etc/udev/rules.d/99-aldente-charge-limit.rules` (root:root 0644): Udev event forwarder to systemd.
- `/etc/sudoers.d/aldente-charge-limit` (root:root 0440): Scoped sudoers drop-in permitting passwordless execution strictly for `/usr/local/libexec/aldente-set-limit ^([2-9][0-9]|100|--restore)$`.

## Building & Installing

Run `makepkg` directly inside this directory:

```bash
cd packaging
makepkg -si
```

This ensures:
1. Sources are authenticated via sha256 checksums before installation.
2. Installation is managed cleanly by `pacman`.
3. No code from unprivileged user checkouts executes directly as root.

## Removal

To completely remove the broker package and all associated system services:

```bash
sudo pacman -R omarchy-aldente-helper
```
