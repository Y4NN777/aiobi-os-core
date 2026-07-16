# design/ --- UML Architecture Diagrams

This directory contains the UML architecture diagrams that back the design
choices made in the customization pipeline of `aiobi-os-core` and in the
companion Bachelor thesis. Diagrams are provided in two authoring formats:

- **PNG exported from draw.io** for the legacy core-OS set (three files
  authored during the first sprint).
- **PlantUML / Mermaid text sources** for the current AI-layer and
  native-component set --- these render deterministically to PNG through
  the containerised `plantuml/plantuml` and `minlag/mermaid-cli` images,
  keeping diagram sources diff-friendly and reviewable.

## Diagrams

### Core OS architecture (draw.io PNGs)

| File                       | Type                | What it shows                                                                                     |
|----------------------------|---------------------|---------------------------------------------------------------------------------------------------|
| `aiobi_component.png`      | Component diagram   | Three-strata decomposition: inherited Linux base, customization layer, user-facing surface. Superseded by `ai_layer_overview` for the AI layer view. |
| `secure_boot_seq.png`      | Sequence diagram    | UEFI Secure Boot chain augmented by the branded artefacts (GRUB theme, Plymouth splash).          |
| `security_layer.png`       | Component diagram   | Layered view: hardware root of trust, firmware, kernel, MAC, user-space containment. Complemented by `05-zero-data-leak-defense-in-depth`. |

### AI layer overview (Mermaid sources)

| Source file                                        | Rendered PNG                       | Type                        | What it shows |
|----------------------------------------------------|------------------------------------|-----------------------------|---------------|
| `01-ai-layer-overview.mmd`                         | `ai_layer_overview.png`            | C4-container overview       | Container view of the AI layer with the single shared inference endpoint. Replaces `aiobi_component.png` and `ai_deployment.png` for the AI layer. |
| `05-zero-data-leak-defense-in-depth.mmd`           | `zero_data_leak_defense.png`       | Defense-in-depth diagram    | Three independent lines of network isolation evidence: loopback bind, iptables OUTPUT REJECT, external probe refused. |

### aiobi-term terminal assistant (PlantUML sources)

| Source file                            | Rendered PNG                          | Type              |
|----------------------------------------|---------------------------------------|-------------------|
| `aiobi-term-class.puml`                | `aiobi_term_class.puml`               | Class diagram     |
| `aiobi-term-cmd-sequence.puml`         | `aiobi_term_cmd_sequence.png`         | Sequence diagram  |
| `aiobi-term-explain-sequence.puml`     | `aiobi_term_explain_sequence.png`     | Sequence diagram  |

### aiobi-update native update manager (PlantUML sources)

| Source file                            | Rendered PNG                          | Type              |
|----------------------------------------|---------------------------------------|-------------------|
| `aiobi-update-class.puml`              | `aiobi_update_class.png`              | Class diagram     |
| `aiobi-update-apply-sequence.puml`     | `aiobi_update_apply_sequence.png`     | Sequence diagram  |

### Ollama daemon lifecycle (PlantUML source)

| Source file                       | Rendered PNG                    | Type                    |
|-----------------------------------|---------------------------------|-------------------------|
| `ollama-daemon-state.puml`        | `ollama_daemon_state.png`       | State machine diagram   |

### Shell integration (PlantUML source)

| Source file                            | Rendered PNG                              | Type              |
|----------------------------------------|-------------------------------------------|-------------------|
| `06-shell-integration-activity.puml`   | `shell_integration_activity.png`          | Activity diagram  |

### Legacy AI-layer draw.io PNGs (retained for reference)

The following draw.io PNGs from the first AI-integration pass reflect an
earlier design and are retained for historical continuity. They have been
superseded in the thesis by the text-source diagrams above.

| File                       | Superseded by                                            |
|----------------------------|----------------------------------------------------------|
| `ai_usecase.png`           | still cited (design intent unchanged)                    |
| `ai_sequence.png`          | `aiobi-term-cmd-sequence` + `aiobi-term-explain-sequence`|
| `ai_model_lifecycle.png`   | `ollama-daemon-state`                                    |
| `ai_deployment.png`        | `ai_layer_overview` + `zero_data_leak_defense`           |

## Editing

**draw.io PNGs** carry the drawio source embedded as PNG metadata --- open
the `.png` file directly in the draw.io desktop app or the web editor and
re-export in place.

**PlantUML / Mermaid text sources** are edited as plain text. To re-render
to PNG:

```bash
# PlantUML sources
docker run --rm -v "$PWD:/data" plantuml/plantuml:latest -tpng "/data/*.puml"

# Mermaid sources
docker run --rm -u "$(id -u):$(id -g)" -v "$PWD:/data" minlag/mermaid-cli:latest \
    -i /data/01-ai-layer-overview.mmd -o /data/ai_layer_overview.png -b white -w 1600
```

Rendered PNGs are then copied under `thesis/images/` for inclusion in the
manuscript.

## Supporting documents

- `design-narrative.md` --- architectural narrative that motivates each
  design decision and links back to the diagrams. Written to accompany
  the diagrams rather than replace them.
- `existing-diagram-update-specs.md` --- audit of the seven legacy draw.io
  UMLs against the current architecture, with per-diagram change specs
  (kept / superseded / update recommendations).

## Consumption in the thesis

Chapter 3 (*System Design*) consumes the AI-layer overview, the defense
diagram, both class diagrams, and the Ollama state machine. Chapter 4
(*Implementation*) consumes the sequence diagrams (aiobi-term `cmd`,
aiobi-term `explain`, aiobi-update apply) and the shell-integration
activity diagram. Cross-references are managed with `~\ref{fig:...}`.

## Provenance

- The three core-OS draw.io PNGs were produced during the first-sprint
  design phase.
- The four legacy AI-layer draw.io PNGs were produced during the second
  sprint alongside the initial Ollama integration.
- The nine text-source diagrams (PlantUML + Mermaid) were produced during
  the second-sprint consolidation to capture the shipped architecture
  (post-composition RC3), and to give future maintainers a diff-reviewable
  source of truth.
