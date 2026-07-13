# Security Policy

## Scope

This repository contains a customization pipeline for the Aïobi OS
distribution. The pipeline modifies system files during the ISO
build process and requires root privileges when applied inside a
Cubic chroot or on an installed system.

## Trust boundary

- **Inputs.** The scripts read the base Ubuntu ISO filesystem, the
  Ubuntu package archive, upstream Papirus and Yaru source
  repositories, and vendor repositories added under
  `/etc/apt/sources.list.d/` (Brave, OnlyOffice, Papirus PPA).
  Every added repository is signed with its published GPG key,
  which the scripts fetch via `gpg --recv-keys` or as ASCII-armoured
  key files. No unsigned source is retained.
- **Outputs.** The scripts write under `/etc/`, `/usr/share/`,
  `/usr/local/`, and (for a first-boot service) `/var/lib/`. No
  script writes to the user's home directory of the build operator.
- **Privileges.** Every script requires `root`. The scripts refuse
  to run as a non-root user (`id -u -ne 0` check at the top).

## Reporting a vulnerability

If you identify a security concern in the customization pipeline
--- for example a script that leaks credentials, a missing
signature verification, an insecure temporary file --- please open
a GitHub issue with the label `security` or contact the maintainer
directly at the address listed in the top of the commits.

## Non-goals

This repository does not attempt to harden the resulting Aïobi OS
beyond the baseline security posture inherited from Ubuntu
24.04 LTS. Distribution-level hardening (AppArmor profiles,
systemd sandboxing overlays, firewall configuration, full-disk
encryption defaults) is scoped for a subsequent release cycle.
