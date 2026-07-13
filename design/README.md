# design/ --- UML Architecture Diagrams

This directory contains the UML architecture diagrams that back the design
choices made in the customization pipeline of `aiobi-os-core` and in the
companion Bachelor thesis. Each diagram is provided as a PNG exported from
draw.io.

## Diagrams

### Core OS architecture

| File                       | Type                | What it shows                                                                                     |
|----------------------------|---------------------|---------------------------------------------------------------------------------------------------|
| `aiobi_component.png`      | Component diagram   | Three-strata decomposition: inherited Linux base, customization layer, user-facing surface.       |
| `secure_boot_seq.png`      | Sequence diagram    | UEFI Secure Boot chain augmented by the branded artefacts (GRUB theme, Plymouth splash).          |
| `security_layer.png`       | Component diagram   | Layered view: hardware root of trust, firmware, kernel, MAC, user-space containment.              |

### AI layer (Sprint 2 deliverables)

| File                       | Type                | What it shows                                                                                     |
|----------------------------|---------------------|---------------------------------------------------------------------------------------------------|
| `ai_usecase.png`           | Use-case diagram    | Terminal users, desktop users, and the shared AI layer with its Ollama-backed inference API.      |
| `ai_sequence.png`          | Sequence diagram    | Full flow of a natural-language shell request through the `aiobi-ai` wrapper into Ollama.         |
| `ai_model_lifecycle.png`   | State diagram       | Model lifecycle (Unloaded / Loading / Ready / Inferring) and the mechanism behind zero-idle RAM.  |
| `ai_deployment.png`        | Deployment diagram  | Physical layout of the AI layer, with loopback-only exposure of the Ollama daemon.                |

## Editing

The diagrams are authored in [draw.io](https://drawio-desktop.github.io/)
(also known as diagrams.net). To edit any of them: open the corresponding
`.png` file directly in the draw.io desktop app or the web editor --- the
file carries the drawio source embedded as PNG metadata, so no separate
`.drawio` file is required. Re-export replaces the file in place.

## Consumption

The four AI diagrams are embedded in Chapter 3.2 (*System Design*) of the
thesis manuscript and back the following claims:

- **Use-case diagram** --- scope of the AI functionality delivered by the
  first release milestone.
- **Sequence diagram** --- realises Objective 3 (system-level AI
  functionality) by showing the intercept-to-response path.
- **State (lifecycle) diagram** --- backs the memory-budget claim of
  Hypothesis H2 (idle RAM under 500 MB) through socket activation and
  keep-alive expiration.
- **Deployment diagram** --- backs the Zero-Data-Leak posture (Ollama
  daemon bound to `127.0.0.1`, no outbound path).

## Provenance

- Core-OS diagrams were produced during the design phase of the first
  sprint.
- AI-layer diagrams were produced during the second sprint alongside the
  Ollama integration work.
