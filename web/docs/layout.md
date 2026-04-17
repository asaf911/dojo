# Marketing layout glossary

Canonical pattern names for the Dojo marketing site. Use these in design docs, tickets, and code (HTML `mj-section` + modifiers).

## Layers

| Layer | What lives here |
|-------|-----------------|
| **Shell** | `SiteHeader`, `SiteFooter` — global chrome, not scroll “story” |
| **Main** | Primary page flow inside `<main>` |
| **Primitives** | `container`, `stack`, `split`, `feature-row`, `btn`, `region` — reusable layout atoms |
| **Patterns** | Vertical slices: Hero, Split, Band, BackdropSplit, Social, Closing |

## Patterns (canonical → role)

| Canonical name | Role | Background ownership |
|----------------|------|------------------------|
| **Hero** | First viewport: headline, primary CTA, ratings/QR | `hero__bg` layer + `--hero-bg-image`; letterbox `--section-backdrop-fallback` |
| **SplitStory** | Two-column editorial (copy + media) | Section or gradient on `<section>`; no full-bleed pseudo unless variant says so |
| **SplitStory — media lead** | Media column first (e.g. image left) | Same as SplitStory |
| **SplitStory — media trail** | Copy column first (e.g. image right) | Same as SplitStory |
| **BackdropSplit** | Full-bleed photo via `::before` + overlapping `container` with split inside | `::before` owns `--photo-bg-fill-*`; section `background-color` uses `--section-backdrop-fallback` for region padding |
| **StatementBand** | Short full-width heading strip | Section gradient `section--band` |
| **SocialProof** | Quote grid (“testimonials” in UI copy) | Same as BackdropSplit: `::before` + image; fallback token on section |
| **Closing** | Final CTA before footer | Same as BackdropSplit pattern |

**About** uses `split` + `section__media` / `section__copy` (not `feature-row`). Treat as **SplitStory** / **SplitEditorial** with the same media-lead/trail language.

## HTML skeletons

### Hero

```html
<section class="… region region--hero">
  <div class="hero__bg" role="presentation"></div>
  <div class="container hero__inner">…</div>
</section>
```

### SplitStory (feature-row)

```html
<section class="… region">
  <div class="container feature-row feature-row--split-align">
    <div class="feature-row__text stack">…</div>
    <div class="feature-row__media …">…</div>
  </div>
</section>
```

Swap text/media DOM order for **media-lead** vs **media-trail**.

### BackdropSplit

```html
<section class="… region">
  <!-- ::before on section paints full-bleed image -->
  <div class="container feature-row …">…</div>
</section>
```

Section is `display: grid`; `::before` is `grid-row: 1`; `.container` is `grid-row: 1` with higher `z-index`.

### StatementBand

```html
<section class="section--band region--band">
  <div class="container"><h2>…</h2></div>
</section>
```

### SocialProof

```html
<section class="section--testimonials region">
  <div class="container grid-testimonials">…</div>
</section>
```

### Closing

```html
<section class="section--closing region">
  <div class="container stack stack--center">…</div>
</section>
```

## Decision tree

1. **Is it the first full-bleed story with primary CTA?** → **Hero**
2. **Is it only a centered heading between major blocks?** → **StatementBand**
3. **Does a photo cover the full section behind copy/media?** → **BackdropSplit** (use grid + `::before`)
4. **Is it two columns (copy + image/video) on a flat/gradient section?** → **SplitStory** (+ **media-lead** / **media-trail** from DOM order)
5. **Is it a grid of quotes?** → **SocialProof**
6. **Is it the final download CTA strip?** → **Closing**

## CSS class mapping (legacy → `mj-section`)

| Area in `index.html` | Legacy classes | Additive `mj-section` modifier |
|------------------------|----------------|--------------------------------|
| Hero | `section--hero` | `mj-section mj-section--hero` |
| About | `section--about` | `mj-section mj-section--about` |
| Why band | `section--band` | `mj-section mj-section--band` |
| Personalized | `section--feature section--feature-personalized` | `mj-section mj-section--personalized` |
| Proof | `section--feature section--feature-proof` | `mj-section mj-section--proof` |
| Train | `section--feature section--feature-train` | `mj-section mj-section--train` |
| Testimonials band | `section--band` | `mj-section mj-section--band` |
| Testimonials | `section--testimonials` | `mj-section mj-section--social` |
| Closing | `section--closing` | `mj-section mj-section--closing` |

Canonical **SplitStory / BackdropSplit** language still applies in prose; CSS uses stable theme modifiers (`--about`, `--proof`, …) so selectors stay unique.

**Primitives** stay unprefixed: `container`, `stack`, `region`, `feature-row`, etc.

## Internal vs external naming

- Code / CSS: **SocialProof** (`mj-section--social`) for the reviews block.
- User-facing copy may still say “Testimonials” or “Reviews”.

## Source files

- Entry barrel (import order): [`web/src/site.css`](../src/site.css) — `@import`s the split files below.
- Tokens + `@layer` prelude: [`web/src/css/tokens.css`](../src/css/tokens.css)
- Primitives / shell / patterns: [`web/src/css/primitives.css`](../src/css/primitives.css), [`shell.css`](../src/css/shell.css), [`patterns.css`](../src/css/patterns.css)
- Typography / header-over-hero: [`web/src/layout-header-over-hero.css`](../src/layout-header-over-hero.css) (loaded after the barrel from [`web/src/main.ts`](../src/main.ts))
