# aiobi_update — native update mechanism for Aïobi OS.
#
# Replaces Ubuntu's update-manager / update-notifier stack, which fails on
# Aïobi because it depends on apport/whoopsie/ubuntu-report — components
# aos-debloat.service removes at first boot — and carries no Aïobi branding.
#
# Package layout
#   state.py    JSON state file read/write (/var/lib/aiobi-update/state.json)
#   policy.py   /etc/aiobi/update.conf loader + blacklist
#   apt.py      subprocess wrapper around apt-get / apt list
#   notify.py   notify-send helpers (silent alerts)
#   popup.py    GTK4 + libadwaita popups (confirm / progress / summary)
#   cli.py      argparse dispatcher — the entry point installed as
#               /usr/local/bin/aiobi-update calls cli.main()

__version__ = "0.1.0"
