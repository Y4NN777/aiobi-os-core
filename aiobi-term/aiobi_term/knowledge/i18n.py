"""Localization for the knowledge base cause messages.

Design:
  * Each `Rule` references a `cause_key` (dotted, kebab-case).
  * Message dictionaries in this module map keys → localized strings,
    one flat dict per supported language.
  * `detect_language()` reads $LANG (with $AIOBI_TERM_LANG override)
    and returns the two-letter code we support (`en`, `fr`) with
    fallback to `en` for anything unrecognised.
  * `translate(key, lang)` returns the localized string, falling back
    to the English version if the key is missing in the requested
    language, or to the key itself if it's missing everywhere (visible
    to developers, hard to miss during dev).

Adding a new language = add a new dict here and populate every key
present in `MESSAGES_EN`.
"""

from __future__ import annotations

import os
from typing import Literal

Lang = Literal["en", "fr"]


# ---------------------------------------------------------------------------
# English messages — canonical source; every other language mirrors these keys
# ---------------------------------------------------------------------------
MESSAGES_EN: dict[str, str] = {
    # ---- deprecated-tool ----
    "deprecated.netstat":
        "netstat is not installed by default on Aïobi OS — the ss utility from iproute2 "
        "is the modern replacement (ships out of the box).",
    "deprecated.ifconfig":
        "ifconfig is not installed by default on Aïobi OS — the ip utility from iproute2 "
        "replaces it (ships out of the box).",
    "deprecated.route":
        "route is not installed by default on Aïobi OS — ip route from iproute2 "
        "is the modern replacement.",
    "deprecated.arp":
        "arp is not installed by default on Aïobi OS — ip neigh from iproute2 "
        "is the modern replacement.",
    "deprecated.nslookup":
        "nslookup is not shipped by default on Aïobi OS — bind9-dnsutils provides both "
        "nslookup and dig; installing that package gives you the modern dig command.",
    "deprecated.telnet":
        "telnet is not installed by default on Aïobi OS — it is deprecated for interactive "
        "use because it transmits credentials in the clear; use ssh instead.",
    "deprecated.ftp":
        "ftp (command-line client) is not installed by default on Aïobi OS — it transmits "
        "credentials in the clear; use sftp or curl over HTTPS instead.",
    "deprecated.whois":
        "whois is not installed by default on Aïobi OS — install the whois package "
        "to get it back.",
    "deprecated.rsh":
        "rsh is not installed by default on Aïobi OS — it is obsolete because "
        "it transmits credentials in the clear; use ssh instead.",
    "deprecated.rlogin":
        "rlogin is not installed by default on Aïobi OS — it is obsolete because "
        "it transmits credentials in the clear; use ssh instead.",

    # ---- aiobi-purged ----
    "aiobi_purged.snap":
        "snap is intentionally purged from Aïobi OS to keep the base minimal — "
        "install applications via apt or flatpak instead.",
    "aiobi_purged.libreoffice":
        "LibreOffice is not installed on Aïobi OS — OnlyOffice ships as the sole office "
        "suite (onlyoffice-desktopeditors).",
    "aiobi_purged.rhythmbox":
        "Rhythmbox has been removed from Aïobi OS — VLC is the shipped media player "
        "and handles the same audio formats.",
    "aiobi_purged.shotwell":
        "Shotwell has been removed from Aïobi OS — the built-in GNOME Image Viewer "
        "handles day-to-day photo viewing.",
    "aiobi_purged.transmission":
        "Transmission has been removed from Aïobi OS by design; if you need a torrent "
        "client, install one explicitly via flatpak.",

    # ---- systemd-error ----
    "systemd.unit_not_found":
        "The systemd unit does not exist on this system — check the exact unit name "
        "(spelling, .service vs .socket suffix).",
    "systemd.dependency_failed":
        "A dependency of this systemd unit failed to start; the unit will not run "
        "until the dependency is fixed.",
    "systemd.service_failed":
        "The systemd service exited with an error. The daemon logs the failure — "
        "inspect them for the actual cause.",
    "systemd.load_error":
        "The systemd unit file has a syntax error or references an invalid setting — "
        "systemd refused to load it.",

    # ---- filesystem-error ----
    "fs.permission_denied":
        "The current user does not have permission on the target — the operation "
        "needs elevated privileges or a different file mode.",
    "fs.no_such_file":
        "The path does not exist on this filesystem — verify with ls on the "
        "parent directory before retrying.",
    "fs.disk_full":
        "The filesystem hosting the target has no free space left — free some "
        "space or move the operation elsewhere.",
    "fs.read_only":
        "The target is on a read-only filesystem — either remount it read-write "
        "or write to a different location.",
    "fs.file_exists":
        "A file or directory with that name already exists — remove it first, "
        "or pick a different name.",
    "fs.is_directory":
        "The target is a directory, not a file — pass a file path or use a "
        "recursive variant of the command.",

    # ---- network-error ----
    "net.address_in_use":
        "The requested port is already bound by another process — pick a different "
        "port or stop the process holding it.",
    "net.connection_refused":
        "The remote host actively refused the connection — no service is listening "
        "on that port, or a firewall is blocking it.",
    "net.name_resolution":
        "The hostname could not be resolved — check spelling, DNS configuration, "
        "and network reachability.",
    "net.no_route_to_host":
        "There is no route from this machine to the target — the network layer "
        "cannot reach the destination.",
    "net.connection_timed_out":
        "The connection attempt timed out — the remote is unreachable, offline, "
        "or blocked by a firewall.",

    # ---- package-manager ----
    "apt.unable_to_locate":
        "No package by that name is available in the configured apt sources — "
        "check spelling or run apt search to find the exact name.",
    "apt.lock":
        "Another apt process is holding the dpkg lock — wait for it to finish or "
        "identify and stop the process holding /var/lib/dpkg/lock-frontend.",
    "apt.broken_packages":
        "The apt state is broken — dependency conflicts or interrupted installs "
        "must be resolved before new installs can proceed.",
    "apt.gpg_error":
        "The apt repository signature could not be verified — the signing key is "
        "missing or expired; refresh it before updating.",
    "dpkg.status_error":
        "dpkg reports a package in an inconsistent state — a previous install or "
        "removal was interrupted and must be finished before other operations.",

    # ---- python-error ----
    "python.module_not_found":
        "The Python interpreter cannot locate that module — install the package "
        "via apt (python3-<name>) or via a virtualenv with pip.",
    "python.pep668":
        "Aïobi OS follows PEP 668: installing packages system-wide with pip is "
        "blocked to protect the OS. Use a virtualenv, pipx, or the python3-* apt "
        "package instead.",
    "python.no_pip":
        "pip is not installed for this Python — install python3-pip via apt, "
        "or use ensurepip inside a virtualenv.",

    # ---- git-error ----
    "git.not_a_repository":
        "The current directory (or its ancestors) is not a git repository — "
        "run git init to create one, or cd into an existing repository first.",
    "git.no_upstream":
        "The current branch has no upstream configured — set one with "
        "git push -u origin <branch> or git branch --set-upstream-to.",
    "git.push_rejected":
        "The remote rejected the push — pull the latest changes and rebase, "
        "or force-push if you own the branch and understand the consequences.",
    "git.detached_head":
        "You are in a detached HEAD state — create a branch here to preserve "
        "commits before switching away.",

    # ---- ssh-error ----
    "ssh.permission_denied_publickey":
        "The remote refused publickey authentication — the local key is not "
        "authorized, or the wrong key is being offered. Check ~/.ssh/config "
        "and the remote's authorized_keys.",
    "ssh.host_key_changed":
        "The remote host key changed since your last connection — either the "
        "server was reinstalled, or a man-in-the-middle attempt is in progress. "
        "Verify with the server operator before removing the old known_hosts entry.",
    "ssh.connection_refused":
        "The remote SSH daemon is not accepting connections — sshd may be down, "
        "the port may be non-standard, or a firewall is filtering.",

    # ---- docker-error ----
    "docker.daemon_not_running":
        "The Docker daemon is not running on this system — start it with "
        "systemctl start docker (if installed) or install docker.io first.",
    "docker.socket_permission":
        "The current user cannot access /var/run/docker.sock — add the user "
        "to the docker group (a re-login is required) or use sudo.",

    # ---- display-error ----
    "display.no_display":
        "No DISPLAY environment variable is set — you are on a text console or "
        "an SSH session without X11 forwarding; graphical commands cannot run here.",
    "display.wayland_x11_tool":
        "That tool is designed for the X11 protocol — Aïobi OS runs a Wayland "
        "session by default; use the GNOME-native equivalent or start an X11 "
        "session explicitly if you must.",

    # ---- shell-builtin ----
    "builtin.no_failure":
        "This is a bash builtin — it usually succeeds silently on valid input. "
        "If you saw a specific error, pass it via --error for a tighter "
        "diagnosis.",

    # ---- generic fallbacks (used when only a broad match is possible) ----
    "generic.command_not_found":
        "The binary is not installed on Aïobi OS — search for the providing "
        "package with apt-cache search.",
}


# ---------------------------------------------------------------------------
# French messages — mirrors the EN key set; add every key here in FR too.
# Fallback behavior: missing FR key → returns EN version (translate() below).
# ---------------------------------------------------------------------------
MESSAGES_FR: dict[str, str] = {
    # ---- deprecated-tool ----
    "deprecated.netstat":
        "netstat n'est pas installé par défaut sur Aïobi OS — l'utilitaire ss "
        "d'iproute2 le remplace (installé par défaut).",
    "deprecated.ifconfig":
        "ifconfig n'est pas installé par défaut sur Aïobi OS — l'utilitaire ip "
        "d'iproute2 le remplace (installé par défaut).",
    "deprecated.route":
        "route n'est pas installé par défaut sur Aïobi OS — ip route d'iproute2 "
        "est le remplacement moderne.",
    "deprecated.arp":
        "arp n'est pas installé par défaut sur Aïobi OS — ip neigh d'iproute2 "
        "est le remplacement moderne.",
    "deprecated.nslookup":
        "nslookup n'est pas fourni par défaut sur Aïobi OS — bind9-dnsutils "
        "installe nslookup et dig ; installer ce paquet donne accès au dig moderne.",
    "deprecated.telnet":
        "telnet n'est pas installé par défaut sur Aïobi OS — il est déconseillé "
        "en usage interactif car il transmet les identifiants en clair ; utilise ssh.",
    "deprecated.ftp":
        "ftp (client) n'est pas installé par défaut sur Aïobi OS — il transmet "
        "les identifiants en clair ; utilise sftp ou curl sur HTTPS.",
    "deprecated.whois":
        "whois n'est pas installé par défaut sur Aïobi OS — installe le paquet "
        "whois pour le retrouver.",
    "deprecated.rsh":
        "rsh n'est pas installé par défaut sur Aïobi OS — c'est un outil obsolète "
        "qui transmet les identifiants en clair ; utilise ssh.",
    "deprecated.rlogin":
        "rlogin n'est pas installé par défaut sur Aïobi OS — c'est un outil obsolète "
        "qui transmet les identifiants en clair ; utilise ssh.",

    # ---- aiobi-purged ----
    "aiobi_purged.snap":
        "snap a été intentionnellement retiré d'Aïobi OS pour garder la base "
        "minimale — installe les applications via apt ou flatpak.",
    "aiobi_purged.libreoffice":
        "LibreOffice n'est pas installé sur Aïobi OS — OnlyOffice est la suite "
        "bureautique fournie (onlyoffice-desktopeditors).",
    "aiobi_purged.rhythmbox":
        "Rhythmbox a été retiré d'Aïobi OS — VLC est le lecteur média fourni "
        "et gère les mêmes formats audio.",
    "aiobi_purged.shotwell":
        "Shotwell a été retiré d'Aïobi OS — la Visionneuse d'images GNOME "
        "gère l'affichage courant.",
    "aiobi_purged.transmission":
        "Transmission a été retiré d'Aïobi OS par design ; si tu as besoin d'un "
        "client torrent, installe-le explicitement via flatpak.",

    # ---- systemd-error ----
    "systemd.unit_not_found":
        "Cette unité systemd n'existe pas sur ce système — vérifie l'orthographe "
        "et le suffixe (.service vs .socket).",
    "systemd.dependency_failed":
        "Une dépendance de cette unité systemd a échoué au démarrage ; l'unité "
        "ne démarrera pas tant que la dépendance n'est pas corrigée.",
    "systemd.service_failed":
        "Le service systemd s'est terminé sur une erreur. Les logs du daemon "
        "expliquent la cause réelle — consulte-les.",
    "systemd.load_error":
        "Le fichier unité systemd contient une erreur de syntaxe ou une directive "
        "invalide — systemd a refusé de le charger.",

    # ---- filesystem-error ----
    "fs.permission_denied":
        "L'utilisateur courant n'a pas les droits sur la cible — l'opération "
        "requiert des privilèges élevés ou un mode fichier différent.",
    "fs.no_such_file":
        "Le chemin n'existe pas sur ce système de fichiers — vérifie avec ls sur "
        "le répertoire parent avant de réessayer.",
    "fs.disk_full":
        "Le système de fichiers hébergeant la cible n'a plus d'espace libre — "
        "libère de l'espace ou déplace l'opération ailleurs.",
    "fs.read_only":
        "La cible est sur un système de fichiers en lecture seule — remonte-le "
        "en lecture-écriture ou écris ailleurs.",
    "fs.file_exists":
        "Un fichier ou dossier portant ce nom existe déjà — supprime-le d'abord "
        "ou choisis un autre nom.",
    "fs.is_directory":
        "La cible est un dossier, pas un fichier — passe un chemin de fichier "
        "ou utilise la variante récursive de la commande.",

    # ---- network-error ----
    "net.address_in_use":
        "Le port demandé est déjà occupé par un autre processus — choisis un "
        "autre port ou arrête le processus qui le tient.",
    "net.connection_refused":
        "L'hôte distant a activement refusé la connexion — aucun service n'écoute "
        "sur ce port, ou un pare-feu bloque.",
    "net.name_resolution":
        "Le nom d'hôte n'a pas pu être résolu — vérifie l'orthographe, la "
        "configuration DNS et la connectivité réseau.",
    "net.no_route_to_host":
        "Aucune route depuis cette machine vers la cible — la couche réseau "
        "ne peut pas atteindre la destination.",
    "net.connection_timed_out":
        "La tentative de connexion a expiré — l'hôte distant est injoignable, "
        "hors ligne ou bloqué par un pare-feu.",

    # ---- package-manager ----
    "apt.unable_to_locate":
        "Aucun paquet portant ce nom dans les sources apt configurées — vérifie "
        "l'orthographe ou lance apt search pour trouver le nom exact.",
    "apt.lock":
        "Un autre processus apt tient le verrou dpkg — attends qu'il termine "
        "ou identifie et stoppe le processus qui tient /var/lib/dpkg/lock-frontend.",
    "apt.broken_packages":
        "L'état apt est cassé — des conflits de dépendances ou des installs "
        "interrompus doivent être résolus avant tout nouvel install.",
    "apt.gpg_error":
        "La signature du dépôt apt n'a pas pu être vérifiée — la clé de signature "
        "est absente ou expirée ; rafraîchis-la avant l'update.",
    "dpkg.status_error":
        "dpkg signale un paquet dans un état incohérent — un install ou une "
        "suppression précédente a été interrompue et doit être terminée.",

    # ---- python-error ----
    "python.module_not_found":
        "L'interpréteur Python ne trouve pas ce module — installe le paquet "
        "via apt (python3-<nom>) ou via un virtualenv avec pip.",
    "python.pep668":
        "Aïobi OS suit PEP 668 : installer des paquets Python à l'échelle système "
        "avec pip est bloqué pour protéger l'OS. Utilise un virtualenv, pipx, ou "
        "le paquet apt python3-*.",
    "python.no_pip":
        "pip n'est pas installé pour ce Python — installe python3-pip via apt, "
        "ou utilise ensurepip dans un virtualenv.",

    # ---- git-error ----
    "git.not_a_repository":
        "Le répertoire courant (ou ses ancêtres) n'est pas un dépôt git — lance "
        "git init pour en créer un, ou déplace-toi dans un dépôt existant.",
    "git.no_upstream":
        "La branche courante n'a pas d'upstream configuré — définis-le avec "
        "git push -u origin <branche> ou git branch --set-upstream-to.",
    "git.push_rejected":
        "Le distant a rejeté le push — récupère les derniers changements et "
        "rebase, ou force-push si tu es propriétaire de la branche et en assumes "
        "les conséquences.",
    "git.detached_head":
        "Tu es en état HEAD détachée — crée une branche ici pour préserver les "
        "commits avant de partir ailleurs.",

    # ---- ssh-error ----
    "ssh.permission_denied_publickey":
        "Le distant a refusé l'authentification par clé publique — la clé locale "
        "n'est pas autorisée ou la mauvaise clé est envoyée. Vérifie "
        "~/.ssh/config et le authorized_keys du distant.",
    "ssh.host_key_changed":
        "La clé d'hôte du distant a changé depuis la dernière connexion — soit "
        "le serveur a été réinstallé, soit c'est une tentative de man-in-the-middle. "
        "Vérifie avec l'opérateur avant de retirer l'ancienne entrée known_hosts.",
    "ssh.connection_refused":
        "Le daemon SSH distant n'accepte pas les connexions — sshd est peut-être "
        "arrêté, le port est peut-être non standard, ou un pare-feu filtre.",

    # ---- docker-error ----
    "docker.daemon_not_running":
        "Le daemon Docker ne tourne pas sur ce système — démarre-le avec "
        "systemctl start docker (s'il est installé) ou installe docker.io d'abord.",
    "docker.socket_permission":
        "L'utilisateur courant ne peut pas accéder à /var/run/docker.sock — "
        "ajoute l'utilisateur au groupe docker (re-login requis) ou utilise sudo.",

    # ---- display-error ----
    "display.no_display":
        "Aucune variable DISPLAY définie — tu es sur une console texte ou dans "
        "une session SSH sans X11 forwarding ; les commandes graphiques ne "
        "peuvent pas tourner ici.",
    "display.wayland_x11_tool":
        "Cet outil est conçu pour le protocole X11 — Aïobi OS lance une session "
        "Wayland par défaut ; utilise l'équivalent GNOME natif, ou démarre "
        "explicitement une session X11 si nécessaire.",

    # ---- shell-builtin ----
    "builtin.no_failure":
        "C'est une commande interne du shell bash — elle réussit généralement "
        "en silence sur une entrée valide. Si tu as vu une erreur précise, "
        "passe-la via --error pour un diagnostic plus fin.",

    # ---- generic fallbacks ----
    "generic.command_not_found":
        "Le binaire n'est pas installé sur Aïobi OS — cherche le paquet fournisseur "
        "avec apt-cache search.",
}


# Registry — add more languages here as they are added.
_MESSAGES: dict[Lang, dict[str, str]] = {
    "en": MESSAGES_EN,
    "fr": MESSAGES_FR,
}


def detect_language() -> Lang:
    """Read $AIOBI_TERM_LANG or $LANG and return a supported language code.

    Recognises `fr_*` and `en_*` locales. Everything else defaults to `en`.
    Explicit override via $AIOBI_TERM_LANG=fr|en takes precedence over $LANG.
    """
    explicit = os.environ.get("AIOBI_TERM_LANG", "").strip().lower()
    if explicit in _MESSAGES:
        return explicit  # type: ignore[return-value]
    lang_env = os.environ.get("LANG", "").lower()
    if lang_env.startswith("fr"):
        return "fr"
    return "en"


def translate(key: str, lang: Lang | None = None) -> str:
    """Return the localized string for `key`, with graceful fallback.

    Precedence:
      1. `lang` (or detected language) → matches → return.
      2. English fallback if the requested language is missing the key.
      3. Return the raw key surrounded by brackets as last resort (visible
         to developers in test output so missing keys are hard to miss).
    """
    if lang is None:
        lang = detect_language()
    dictionary = _MESSAGES.get(lang, MESSAGES_EN)
    if key in dictionary:
        return dictionary[key]
    if key in MESSAGES_EN:
        return MESSAGES_EN[key]
    return f"[missing-i18n: {key}]"
