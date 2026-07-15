"""Rule aggregator for the knowledge base.

Discovers every rule module under `aiobi_term.knowledge.rules.*` via
explicit import (no runtime magic — every category is listed here by
name, which keeps grep/rename/IDE-navigation predictable) and returns
the concatenated tuple of `Rule` objects.

To add a new rule category:
  1. Create `aiobi_term/knowledge/rules/<name>.py` exposing a
     module-level `RULES: tuple[Rule, ...]`.
  2. Import the module here and add its `RULES` to `_ALL`.
  3. Add matching i18n keys to `aiobi_term/knowledge/i18n.py`.
  4. Add fixture tests.
"""

from __future__ import annotations

from aiobi_term.knowledge.rule import Rule
from aiobi_term.knowledge.rules import (
    aiobi_purged,
    deprecated_tools,
    docker_errors,
    filesystem_errors,
    git_errors,
    network_errors,
    package_mgr,
    python_errors,
    ssh_errors,
    systemd_errors,
    xorg_wayland,
)


_ALL: tuple[Rule, ...] = (
    *deprecated_tools.RULES,
    *aiobi_purged.RULES,
    *systemd_errors.RULES,
    *filesystem_errors.RULES,
    *network_errors.RULES,
    *package_mgr.RULES,
    *python_errors.RULES,
    *git_errors.RULES,
    *ssh_errors.RULES,
    *docker_errors.RULES,
    *xorg_wayland.RULES,
)


def get_all_rules() -> tuple[Rule, ...]:
    """Return the frozen tuple of every registered rule."""
    return _ALL


def get_rules_by_category(category_value: str) -> tuple[Rule, ...]:
    """Return only rules whose `category.value` matches `category_value`."""
    return tuple(r for r in _ALL if r.category.value == category_value)


def get_rule_by_id(rule_id: str) -> Rule | None:
    """Return the rule with the given id, or None if not present."""
    for r in _ALL:
        if r.id == rule_id:
            return r
    return None
