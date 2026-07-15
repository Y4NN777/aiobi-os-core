"""Rules for common network-layer errors."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


RULES: tuple[Rule, ...] = (
    Rule(
        id="net/address-in-use",
        category=Category.NETWORK_ERROR,
        match=Match(error_regex=re.compile(r"address already in use|EADDRINUSE", re.IGNORECASE)),
        cause_key="net.address_in_use",
        try_template="sudo ss -tlnp | grep -E ':[0-9]+ '",
        confidence=10,
    ),
    Rule(
        id="net/connection-refused",
        category=Category.NETWORK_ERROR,
        match=Match(error_regex=re.compile(r"connection refused|ECONNREFUSED", re.IGNORECASE)),
        cause_key="net.connection_refused",
        try_template="ss -tlnp | grep -F ':'",
        confidence=9,
    ),
    Rule(
        id="net/name-resolution",
        category=Category.NETWORK_ERROR,
        match=Match(error_regex=re.compile(
            r"name or service not known|could not resolve host|"
            r"temporary failure in name resolution|EAI_NONAME|no address associated",
            re.IGNORECASE,
        )),
        cause_key="net.name_resolution",
        try_template="resolvectl status && dig {arg1}",
        confidence=9,
    ),
    Rule(
        id="net/no-route-to-host",
        category=Category.NETWORK_ERROR,
        match=Match(error_regex=re.compile(r"no route to host|EHOSTUNREACH", re.IGNORECASE)),
        cause_key="net.no_route_to_host",
        try_template="ip route get {arg1}",
        confidence=9,
    ),
    Rule(
        id="net/connection-timed-out",
        category=Category.NETWORK_ERROR,
        match=Match(error_regex=re.compile(r"connection timed out|ETIMEDOUT|timed? out", re.IGNORECASE)),
        cause_key="net.connection_timed_out",
        try_template="ping -c 3 {arg1}",
        confidence=8,
    ),
)
