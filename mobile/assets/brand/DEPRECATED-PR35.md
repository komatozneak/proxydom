# DEPRECATED — PR #35 visual assets (do not ship)

**Date:** 2026-07-12  
**Status:** removed from the repo 2026-08-17 (license ship-blocker) — this note
kept as the audit record. They were never listed in `pubspec.yaml` assets.

## Why

12 PNGs under `assets/backgrounds/textures/` and `assets/backgrounds/empty_states/`
were generated with **FLUX.2 Klein 9B**, which has a **non-commercial license**.
They must not ship in a commercial VPN client (Teremok Connect).

Additional quality issues (oak→orange drift, noisy textures, look-alike empty
states) are secondary; license alone is a ship-blocker.

## Research

The decision rests on licence, not taste: FLUX.2 Klein 9B output carries a
non-commercial licence, so it cannot be shipped in a distributed client. The
in-repo record is this file plus the palette decision in
`mobile/docs/design/palette-v3-decision.md`.

## Replacement path (Visual epic #2 = A→B)

1. **A (this epic):** code-only polish — theme tokens, Phosphor icons, 3-layer
   adaptive icon, optional Rive/CustomPainter motion. No new AI batch.
2. **B (later):** at most one commercial-clean hero (FLUX.2 flex / Recraft), if
   owner wants “wow” after Pixel smoke.

Do **not** re-bundle these directories without a commercial-clean re-generation
and explicit owner go.
