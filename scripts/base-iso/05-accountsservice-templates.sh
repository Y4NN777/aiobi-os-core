#!/usr/bin/env bash
# =============================================================================
# Aïobi OS — Base ISO — Step 05 — AccountsService template severance
# =============================================================================
# WHAT
#   1. Divert /usr/share/accountsservice/user-templates/{administrator,standard}
#      and rewrite each without the hardcoded `Icon=${HOME}/.face` line.
#   2. Ship /etc/gnome-initial-setup/vendor.conf with the account and
#      parental-controls pages skipped, so the first-boot wizard cannot
#      re-attach an avatar and reintroduce the ~/.face linkage.
#
# WHY
#   Stock templates emit `Icon=${HOME}/.face` at user creation time even
#   when `~/.face` does not exist. AccountsService reports the property
#   to gnome-shell via D-Bus, which triggers the `.user-avatar` CSS class
#   and Yaru's inset box-shadow ring around the avatar widget — plus the
#   fallback-symbolic StIcon overlay that the GDM CSS in step 04 targets
#   (block 1.7). Removing the Icon= line at the template level severs
#   the linkage upstream so downstream CSS mitigations are belt-and-
#   suspenders rather than load-bearing.
#
# WHY dpkg-divert
#   Same Anti-Casse pattern as the Plymouth / GRUB / GDM steps. Any
#   future accountsservice package update will restore its
#   administrator.distrib / standard.distrib content but leave our
#   rewritten files at the canonical path untouched.
#
# WHY skip parental-controls too
#   The parental-controls page enables the `malcontent` daemon by default
#   even when the user does not touch it, which schedules idle-time
#   scans. Skipping the page avoids introducing a service the base
#   distribution does not need.
#
# SOURCES
#   - https://gitlab.freedesktop.org/accountsservice/accountsservice
#   - https://gitlab.gnome.org/GNOME/gnome-initial-setup — see gis-pages.c
#
# IDEMPOTENT: dpkg-divert --add guarded by --list; template rewrite via
#   heredoc overwrites; vendor.conf written with `cat` overwrite.
# =============================================================================

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "ERROR: must run as root (sudo)"; exit 1; }

TEMPLATES_DIR="/usr/share/accountsservice/user-templates"

echo "==> Aïobi — 05-accountsservice-templates.sh"

# ----- 1) Templates: divert + rewrite ---------------------------------------
for template in administrator standard; do
    target="$TEMPLATES_DIR/$template"
    if [ ! -f "$target" ] && [ ! -f "$target.distrib" ]; then
        echo "  WARN: $target absent (and no .distrib) — skipping"
        continue
    fi

    if ! dpkg-divert --list | grep -q " $target$"; then
        echo "  registering dpkg-divert on $target"
        dpkg-divert --local --rename --add "$target"
    else
        echo "  dpkg-divert on $target already registered — skip"
    fi

    # Rewrite without Icon= — leaves nothing for AccountsService to feed
    # to gnome-shell about a per-user avatar path.
    cat > "$target" << 'TEMPLATE'
[Template]
#EnvironmentFiles=/etc/os-release;

[User]
Session=
TEMPLATE
    chmod 644 "$target"
    echo "  rewrote $target (no Icon= line)"
done

# ----- 2) gnome-initial-setup vendor.conf -----------------------------------
echo "  writing /etc/gnome-initial-setup/vendor.conf"
mkdir -p /etc/gnome-initial-setup
cat > /etc/gnome-initial-setup/vendor.conf << 'EOF'
[pages]
skip=account;parental-controls
EOF
chmod 644 /etc/gnome-initial-setup/vendor.conf

# ----- 3) Verification -------------------------------------------------------
echo
echo "  Verification:"
printf "    diverted templates : "; dpkg-divert --list | grep -c accountsservice/user-templates || true
for template in administrator standard; do
    printf "    %s has Icon= : " "$template"
    grep -q '^Icon=' "$TEMPLATES_DIR/$template" 2>/dev/null && echo "YES (unexpected)" || echo "no (good)"
done
printf "    vendor.conf skips  : "
grep -E '^skip=' /etc/gnome-initial-setup/vendor.conf

echo "==> 05 done"
