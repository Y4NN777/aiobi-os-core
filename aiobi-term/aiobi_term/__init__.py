"""Aïobi OS terminal assistant — Python package.

This package hosts the knowledge base, safety guardrail, LLM client
and CLI dispatch for the `aiobi-term` command-line tool. The thin
entry-point script `aiobi-term` (installed to /usr/local/bin/) imports
from here.

Kept intentionally light on public surface — external callers should
import through the sub-packages:
  * aiobi_term.knowledge  — deterministic knowledge base + lookup API
  * (future) aiobi_term.llm     — Ollama client + prompts
  * (future) aiobi_term.safety  — destructive-pattern guardrail
"""

__version__ = "0.2.0"
