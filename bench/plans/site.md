# Build the SSMatic landing page

## What to do

Create one file, `bench/fixtures/site/index.html`. Nothing else.

Read `bench/fixtures/site/BRAND.md` first. It carries the palette, the contrast figures and two
constraints — self-contained, literal hex colours — that the acceptance gates depend on.

The page is a single self-contained HTML document: one inline `<style>` block, no external
requests of any kind. `lang="ro"`.

### Head

- `<title>`: `Aplicație SSM Online - Digitalizare Protecția Muncii`
- `<meta name="description">`: `Platformă SSM pentru digitalizarea completă a proceselor de
  protecția muncii: generare automată de fișe și semnătură electronică.`

### The six landmarks, in this order, each with this exact `id`

**1. `<header id="masthead">`** — the wordmark `SSMatic`, linking to `#hero`, and a nav with three
links:

| Label | Target |
| --- | --- |
| `Funcționalități` | `#features` |
| `Testimoniale` | `#testimonials` |
| `Începe gratuit` | `#cta` |

**2. `<section id="hero">`** — in this order:

- a badge reading `Platforma SSM #1 din România`
- the `<h1>`, exactly: `Transformă-ți Protecția Muncii în Era Digitală`
- a lead paragraph: `Economisește timp, bani și oferă siguranță maximă angajaților cu cea mai
  avansată platformă SSM din România`
- three stat tiles. Each tile holds its own figure and its own label, together:

| Figure | Label |
| --- | --- |
| `50+` | `Clienți Mulțumiți` |
| `80,000+` | `Documente SSM` |
| `24/7` | `Suport Tehnic` |

**3. `<section id="features">`** — six cards. Each card has an `<h3>` and a paragraph, both given:

| Heading | Body |
| --- | --- |
| `Semnături Electronice` | `Sistem avansat oferind legalitate și certitudine legală pentru orice document semnat.` |
| `Modele de Documente` | `Bibliotecă completă cu modele pentru toate nevoile SSM, disponibile gratuit.` |
| `Semnare prin SMS` | `Semnează documente direct de pe telefon, prin SMS sau email, fără configurare.` |
| `Calendar Electronic` | `Notificări și reminder-uri pentru toate documentele importante.` |
| `Acces de Oriunde` | `Generează documente de pe orice dispozitiv: telefon, tabletă sau laptop.` |
| `Generare Automată` | `Câteva mii de fișe generate în câteva minute, fără să scrii nimic manual.` |

**4. `<section id="testimonials">`** — three testimonials. Each is a `<blockquote>` holding the
quote, with the attribution in a `<cite>` or `<footer>` inside it:

| Quote | Attribution |
| --- | --- |
| `Am economisit peste 200 de ore de muncă în primul trimestru de utilizare.` | `Ing. Maria Popescu, Director HR, TechnoConstruct SRL` |
| `Investiția s-a amortizat în prima lună. Nu mai plătim consultanți externi.` | `Andrei Ionescu, Administrator, Construct Plus SRL` |
| `Suportul tehnic este excepțional și platforma extrem de ușor de folosit.` | `Elena Stoica, Șef Serviciu SSM, Industrial Group SA` |

**5. `<section id="cta">`** — an `<h2>` reading `Gata să Revoluționezi Protecția Muncii?` and one
button-styled link reading `Începe Gratuit Acum`, pointing at `#cta`.

**6. `<footer id="colophon">`** — the address `Str Tărnavelor, nr 34, Cluj-Napoca` and the phone
number `0728-787-372`.

## Do not change

`bench/fixtures/site/BRAND.md`, and every file outside `bench/fixtures/site/`.

## The traps

- **Every `href="#..."` must point at an `id` that exists on the page.** `#features` against
  `id="feature"` renders correctly and reads correctly. It is still broken.
- **Small print is `#556270`, never `#777777` or `#aaaaaa`.** Both greys fail WCAG AA for text —
  one of them by 0.02, which is the margin that survives review and fails an audit.
- **No CDN, no web font, no remote image.** A page that links its stylesheet defeats the contrast
  gate rather than passing it, because that gate cannot follow an external sheet.
- **Use hex literals, not custom properties.** `color: var(--ink)` is invisible to the same gate.

## States to handle

- **Link hover and focus.** Every link gets a visible hover state in `#b31d25`, and a focus style
  that is not `outline: none`. A focus ring removed and not replaced is a keyboard user locked out.
- **Long labels.** The nav and the stat tiles must not overflow their container when the text wraps.
- **No JavaScript.** Every part of the page is functional with scripting disabled; nothing may be
  revealed, populated or laid out by a script.
- **Large text.** If any text relies on the 3:1 large-text contrast exemption, the size must be
  declared in the CSS on that element or an ancestor. Undeclared sizes are held to 4.5:1.

## Files to touch

| Path | Action |
| --- | --- |
| `bench/fixtures/site/index.html` | create |

One file. Created, not modified. Nothing else.

## Acceptance criteria

- [ ] The page is well-formed HTML
- [ ] Exactly one `<h1>`, carrying the dictated headline
- [ ] The six landmarks are present, in order, and none is nested inside another
- [ ] Every in-page anchor resolves to an id that exists
- [ ] Three stat tiles, each figure paired with its own label
- [ ] Six feature cards, each with a distinct heading and real body text
- [ ] Three testimonials, each with a quote and an attribution
- [ ] Every image and inline svg is labelled or hidden
- [ ] `lang="ro"`, title 30-65 characters, meta description 70-160
- [ ] No off-host requests, and the styling is inline
- [ ] Every text and background pair meets 4.5:1
- [ ] Exactly one file created, and BRAND.md is byte-identical

## Verification

```bash
python3 tools/view-lint bench/fixtures/site/index.html
python3 bench/checks/site-audit headline bench/fixtures/site/index.html
python3 bench/checks/site-audit sections bench/fixtures/site/index.html
python3 bench/checks/site-audit anchors bench/fixtures/site/index.html
python3 bench/checks/site-audit stats bench/fixtures/site/index.html
python3 bench/checks/site-audit features bench/fixtures/site/index.html
python3 bench/checks/site-audit testimonials bench/fixtures/site/index.html
python3 bench/checks/site-audit alt bench/fixtures/site/index.html
python3 bench/checks/site-audit meta bench/fixtures/site/index.html
python3 bench/checks/site-audit selfcontained bench/fixtures/site/index.html
python3 tools/css-contrast bench/fixtures/site/index.html --min 4.5
git diff --quiet HEAD -- bench/fixtures/site/BRAND.md && test "$(git status --porcelain --untracked-files=all -- . ':(exclude).handoff' ':(exclude).omc' ':(exclude)vendor' ':(exclude)node_modules' | wc -l)" -eq 1
```

## Out of scope

JavaScript, responsive breakpoints beyond what the layout needs, additional pages, tests,
committing, and any file outside `bench/fixtures/site/`.
