# Exemplu brand sheet

Read-only. The plan that uses this fixture may not modify it.

The palette is the live site's own (`a production marketing site, kept because its mistakes are real`), and the
contrast figures below are computed by `tools/css-contrast`, not estimated.

## Colours

| Role | Hex | Use it for | On white |
| --- | --- | --- | ---: |
| brand | `#d9232d` | headings, buttons, accents, the wordmark | 4.97:1 |
| brand-hover | `#b31d25` | hover, focus and active states | 6.73:1 |
| ink | `#556270` | **all body text and all small print** | 6.24:1 |
| surface | `#f8f9fa` | alternating section backgrounds | — |
| paper | `#ffffff` | the page background | — |
| rule | `#777777` | **borders, dividers and rules only — never text** | 4.48:1 |
| disabled | `#aaaaaa` | **disabled controls only — never text** | 2.32:1 |

The live site's own hover red, `#df3740`, is **not** in this table: it computes to 4.41:1 and
fails. It sits in the contrast gate's blind spot too, because the gate cannot resolve
pseudo-classes — so a hover state is one of the few places on this page where a failure would go
unmeasured. `#b31d25` is used instead, and passes in both directions.

White text on `brand` is 4.97:1 and passes. Both greys fail WCAG AA for text: `rule` misses it by
0.02, which is exactly the kind of margin that survives review and fails an audit. Small print goes
in `ink`.

## Constraints the page must respect

**Self-contained.** One file, no external requests. Inline the CSS in a `<style>` block; no CDN
stylesheets, no web fonts, no remote images, no analytics.

This is not a stylistic preference. `tools/css-contrast` does not follow external stylesheets, so a
page that `<link>`s its CSS makes the contrast gate check nothing and report "not checked" — which
reads as a pass. The gate only has teeth when the styling is in the page.

**Literal colours.** Declare colours as hex literals. The contrast gate does not resolve CSS custom
properties, so `color: var(--ink)` is invisible to it, with the same consequence.

## Type

System font stack. Body 16px minimum. The large-text contrast exemption (3:1) applies only at 24px,
or 18.66px bold, and only where the size is declared on the element or an ancestor — so anything
relying on it must say so in the CSS.
