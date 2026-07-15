"""Rule modules for the Aïobi OS knowledge base.

Each submodule exposes a top-level `RULES: tuple[Rule, ...]`. The
loader concatenates all of them. Adding a new category = new module
here + explicit import in `../loader.py`.
"""
