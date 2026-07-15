"""Rules for Ubuntu-default applications that Aïobi OS deliberately purges.

These apps are removed by `scripts/10-snap-final-purge.sh` and
`scripts/13-productivity-stack.sh` during ISO build. Users invoking
them expect Ubuntu's default and need to be told about the Aïobi
replacement.
"""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


RULES: tuple[Rule, ...] = (
    Rule(
        id="aiobi-purged/snap",
        category=Category.AIOBI_PURGED,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?snap\b")),
        cause_key="aiobi_purged.snap",
        try_template="apt install {argN}   # or: flatpak install flathub <app-id>",
        confidence=10,
    ),
    Rule(
        id="aiobi-purged/libreoffice",
        category=Category.AIOBI_PURGED,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?(libreoffice|soffice|loffice)\b")),
        cause_key="aiobi_purged.libreoffice",
        try_template="onlyoffice-desktopeditors",
        confidence=10,
    ),
    Rule(
        id="aiobi-purged/rhythmbox",
        category=Category.AIOBI_PURGED,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?rhythmbox\b")),
        cause_key="aiobi_purged.rhythmbox",
        try_template="vlc",
        confidence=10,
    ),
    Rule(
        id="aiobi-purged/shotwell",
        category=Category.AIOBI_PURGED,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?shotwell\b")),
        cause_key="aiobi_purged.shotwell",
        try_template="xdg-open {arg1}",
        confidence=9,
    ),
    Rule(
        id="aiobi-purged/transmission",
        category=Category.AIOBI_PURGED,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?transmission(-gtk|-cli|-daemon)?\b")),
        cause_key="aiobi_purged.transmission",
        try_template="flatpak install flathub com.transmissionbt.Transmission",
        confidence=9,
    ),
)
