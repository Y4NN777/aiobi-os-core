"""Rules for legacy tools not installed by default on Ubuntu 24.04 / Aïobi OS.

Sources verified 2026-07: net-tools and inetutils are present in the
Noble universe repository but are NOT part of the default desktop
image, so `netstat`, `ifconfig`, `route`, `arp`, `telnet`, `ftp`, `rsh`
and similar commands produce a `command not found` on a fresh install.
"""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


RULES: tuple[Rule, ...] = (
    Rule(
        id="deprecated-tool/netstat",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?netstat\b")),
        cause_key="deprecated.netstat",
        try_template="ss -tuln",
        confidence=9,
        since="Ubuntu 22.04",
        references=("https://wiki.debian.org/NetToolsDeprecation",),
    ),
    Rule(
        id="deprecated-tool/ifconfig",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?ifconfig\b")),
        cause_key="deprecated.ifconfig",
        try_template="ip addr show",
        confidence=9,
        since="Ubuntu 22.04",
        references=("https://wiki.debian.org/NetToolsDeprecation",),
    ),
    Rule(
        id="deprecated-tool/route",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?route\b")),
        cause_key="deprecated.route",
        try_template="ip route",
        confidence=9,
        since="Ubuntu 22.04",
    ),
    Rule(
        id="deprecated-tool/arp",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?arp\b")),
        cause_key="deprecated.arp",
        try_template="ip neigh",
        confidence=9,
        since="Ubuntu 22.04",
    ),
    Rule(
        id="deprecated-tool/nslookup",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?nslookup\b")),
        cause_key="deprecated.nslookup",
        try_template="apt install bind9-dnsutils && dig {arg1}",
        confidence=9,
    ),
    Rule(
        id="deprecated-tool/telnet",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?telnet\b")),
        cause_key="deprecated.telnet",
        try_template="ssh {arg1}",
        confidence=8,
    ),
    Rule(
        id="deprecated-tool/ftp",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?ftp\b(?!\.)")),
        cause_key="deprecated.ftp",
        try_template="sftp {arg1}",
        confidence=8,
    ),
    Rule(
        id="deprecated-tool/whois",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?whois\b")),
        cause_key="deprecated.whois",
        try_template="apt install whois && whois {arg1}",
        confidence=7,
    ),
    Rule(
        id="deprecated-tool/rsh",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?rsh\b")),
        cause_key="deprecated.rsh",
        try_template="ssh {arg1}",
        confidence=9,
    ),
    Rule(
        id="deprecated-tool/rlogin",
        category=Category.DEPRECATED_TOOL,
        match=Match(command_regex=re.compile(r"^\s*(sudo\s+)?rlogin\b")),
        cause_key="deprecated.rlogin",
        try_template="ssh {arg1}",
        confidence=9,
    ),
)
