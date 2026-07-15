"""Rules for X11 / Wayland session mismatches on Aïobi OS (Wayland default)."""

from __future__ import annotations

import re

from aiobi_term.knowledge.rule import Category, Match, Rule


RULES: tuple[Rule, ...] = (
    Rule(
        id="display/no-display",
        category=Category.DISPLAY_ERROR,
        match=Match(error_regex=re.compile(
            r"cannot open display|no display specified|"
            r"could not connect to display|DISPLAY environment variable",
            re.IGNORECASE,
        )),
        cause_key="display.no_display",
        try_template="echo $DISPLAY $WAYLAND_DISPLAY   # both empty = no GUI session",
        confidence=9,
    ),
    Rule(
        id="display/wayland-x11-tool",
        category=Category.DISPLAY_ERROR,
        match=Match(command_regex=re.compile(
            r"^\s*(sudo\s+)?(xdotool|wmctrl|xrandr|xkill|xprop|xwininfo)\b",
        )),
        cause_key="display.wayland_x11_tool",
        try_template="loginctl show-session $XDG_SESSION_ID -p Type   # 'wayland' or 'x11'",
        confidence=7,
    ),
)
