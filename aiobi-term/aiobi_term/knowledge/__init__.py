"""Knowledge base for aiobi-term --explain — public API.

Deterministic short-circuit for well-known Aïobi OS / Ubuntu 24.04
failure modes. Called by the CLI before falling through to the LLM
path.

Typical use:
    from aiobi_term.knowledge import lookup, LookupResult
    result: LookupResult | None = lookup(command, error="", lang="en")
    if result:
        print(result.cause)
        print(f"Try: {result.try_line}")
    else:
        # fall back to LLM path
        ...
"""

from aiobi_term.knowledge.engine import lookup
from aiobi_term.knowledge.rule import (
    Category,
    LookupResult,
    Match,
    Rule,
)

__all__ = (
    "lookup",
    "LookupResult",
    "Rule",
    "Match",
    "Category",
)
