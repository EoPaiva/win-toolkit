---
name: upaiva.dev
description: The owner's personal site, operating a Windows PC.
colors:
  ink: "#FFFFFF"
  signal-red: "#FF6B6B"
  void-black: "#000000"
  terminal-black: "#050505"
  press-fill: "#141414"
  hairline: "#1C1C1C"
  hairline-strong: "#2A2A2A"
  mark-gray: "#5C5C5C"
  dim: "#7A7A7A"
  muted: "#8C8C8C"
  soft: "#D4D4D4"
  scrim: "#000000CC"
typography:
  section-number:
    fontFamily: "Inter Display Thin, Segoe UI Light"
    fontSize: "58px"
    fontWeight: 100
    lineHeight: 1.12
    letterSpacing: "-2px"
  display:
    fontFamily: "Inter Display Light, Segoe UI Light"
    fontSize: "42px"
    fontWeight: 300
    lineHeight: 1.12
    letterSpacing: "-1.5px"
  headline:
    fontFamily: "Inter Display Light, Segoe UI Light"
    fontSize: "32px"
    fontWeight: 300
    lineHeight: 1.12
    letterSpacing: "-1px"
  confirm-title:
    fontFamily: "Inter Display Light, Segoe UI Light"
    fontSize: "28px"
    fontWeight: 300
    lineHeight: 1.12
    letterSpacing: "-0.8px"
  wordmark:
    fontFamily: "Inter Display Light, Segoe UI Light"
    fontSize: "23px"
    fontWeight: 300
    lineHeight: 1.12
    letterSpacing: "-0.7px"
  title:
    fontFamily: "Inter Display Light, Segoe UI Light"
    fontSize: "21px"
    fontWeight: 300
    lineHeight: 1.12
    letterSpacing: "-0.5px"
  body:
    fontFamily: "Inter, Segoe UI"
    fontSize: "13px"
    fontWeight: 400
  body-long:
    fontFamily: "Inter, Segoe UI"
    fontSize: "13.5px"
    fontWeight: 400
    lineHeight: "22px"
  body-small:
    fontFamily: "Inter, Segoe UI"
    fontSize: "12.5px"
    fontWeight: 400
  label:
    fontFamily: "Inter Medium, Segoe UI Semibold"
    fontSize: "10.5px"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "3px"
  nav:
    fontFamily: "Inter Medium, Segoe UI Semibold"
    fontSize: "11.5px"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "2.5px"
  button-primary:
    fontFamily: "Inter Medium, Segoe UI Semibold"
    fontSize: "11.5px"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "2.3px"
  button-pill:
    fontFamily: "Inter Medium, Segoe UI Semibold"
    fontSize: "10.5px"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "2px"
  status:
    fontFamily: "Inter Medium, Segoe UI Semibold"
    fontSize: "10px"
    fontWeight: 500
    lineHeight: 1.12
    letterSpacing: "2px"
  mono:
    fontFamily: "Cascadia Mono, Consolas"
    fontSize: "11.5px"
    fontWeight: 400
    lineHeight: "17px"
  mono-input:
    fontFamily: "Cascadia Mono, Consolas"
    fontSize: "13px"
    fontWeight: 400
  mono-output:
    fontFamily: "Cascadia Mono, Consolas"
    fontSize: "12.5px"
    fontWeight: 400
  mono-small:
    fontFamily: "Cascadia Mono, Consolas"
    fontSize: "11px"
    fontWeight: 400
rounded:
  mark: "3px"
  caption: "15px"
  pill: "16px"
  terminal: "16px"
  pill-primary: "21px"
  overlay: "22px"
spacing:
  pill-gap: "6px"
  action-gap: "8px"
  mark-gap: "10px"
  row-y: "12px"
  group-gap: "18px"
  overlay-inset: "22px"
  page-margin: "36px"
  bar: "66px"
  number-column: "104px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.void-black}"
    typography: "{typography.button-primary}"
    rounded: "{rounded.pill-primary}"
    padding: "0 22px"
    height: "42px"
  button-primary-hover:
    backgroundColor: "{colors.soft}"
  button-primary-disabled:
    backgroundColor: "{colors.press-fill}"
    textColor: "{colors.dim}"
  button-pill:
    backgroundColor: "transparent"
    textColor: "{colors.soft}"
    typography: "{typography.button-pill}"
    rounded: "{rounded.pill}"
    padding: "0 14px"
    height: "32px"
  button-pill-hover:
    textColor: "{colors.ink}"
  button-pill-pressed:
    backgroundColor: "{colors.press-fill}"
  button-pill-disabled:
    textColor: "{colors.dim}"
  window-button:
    textColor: "{colors.muted}"
    rounded: "{rounded.caption}"
    width: "34px"
    height: "30px"
  window-button-hover:
    backgroundColor: "{colors.press-fill}"
    textColor: "{colors.ink}"
  nav-tab:
    textColor: "{colors.muted}"
    typography: "{typography.nav}"
    padding: "8px 0"
  nav-tab-active:
    textColor: "{colors.ink}"
  checkbox:
    textColor: "{colors.muted}"
    typography: "{typography.body}"
    rounded: "{rounded.mark}"
    size: "13px"
  checkbox-checked:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.soft}"
  search-field:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    typography: "{typography.mono-input}"
    height: "32px"
  list-row:
    padding: "12px 0"
  level-selector:
    padding: "16px 22px 14px 0"
  queue-item:
    textColor: "{colors.soft}"
    typography: "{typography.body-small}"
  terminal-window:
    backgroundColor: "{colors.terminal-black}"
    textColor: "{colors.muted}"
    typography: "{typography.mono}"
    rounded: "{rounded.terminal}"
  terminal-palette:
    backgroundColor: "{colors.terminal-black}"
    textColor: "{colors.muted}"
    typography: "{typography.mono-output}"
    rounded: "{rounded.overlay}"
    width: "660px"
    height: "400px"
  terminal-confirm:
    backgroundColor: "{colors.terminal-black}"
    textColor: "{colors.muted}"
    typography: "{typography.body-long}"
    rounded: "{rounded.overlay}"
    width: "560px"
---

# Design System: upaiva.dev

## Overview

**Creative North Star: "The Planet That Tells the Truth"**

upaiva.dev is the owner's personal site, https://upaiva.dev, operating a Windows PC: a true black field, white type, hairlines and one particle planet. Everything on screen is real. Commands, PIDs, exit codes and telemetry come from the machine and the run log. The planet is the only decoration, and even it reports the truth when something runs.

The system is dense but quiet, built for a technical reader in a fixed 1280 by 800 window. Hierarchy comes from scale and tone rather than surfaces: a thin 58px number and light 42px titles sit over long lists on hairlines at 13px, and white is spent on whatever is current, selected or about to happen. Machine output speaks in mono; people get plain sentences in Inter.

The owner named the site as the style to follow, and its thin section numbers and tracked labels above titles are kept here as the owner's brand. Confirmed rejections: gradients on surfaces, neon, glass, sidebars, cards around lists and conventional progress rings.

**Key Characteristics:**
- Monochrome on true black, with one red that only reports failure.
- Thin section number, tracked label and two-line title at the head of every view.
- Hairline rows in place of cards.
- One white pill with an arrow for the primary action; outline pills for the rest.
- A terminal window with three dots for machine output, the Ctrl K palette and confirmations.
- A particle planet whose inner orbit reports real progress and nothing else.

## Colors

A monochrome ladder on true black, with one red that only ever means something went wrong.

### Primary
- **Ink White** (#FFFFFF): The system's only emphasis. Primary pill fill, first title line, section number, active navigation, selected level rule, checked box, focus ring, focused search underline, commands in the terminal, lit orbit points and the progress hairline.

### Secondary
- **Signal Red** (#FF6B6B): The only hue. Failed queue items, failed terminal lines, critical and high findings, device errors and blocking notices in the footer (7.57:1 on black).

### Neutral
- **Void Black** (#000000): The window and every page surface, and the label on the white pill.
- **Terminal Black** (#050505): Terminal windows only, one step off the page.
- **Press Fill** (#141414): Pressed outline pill, hovered window button and disabled primary pill.
- **Hairline** (#1C1C1C): Row dividers, the section header rule, the footer rule and terminal title bar dividers.
- **Strong Hairline** (#2A2A2A): Outline pill borders, the window frame, terminal window borders, unselected level rules, the resting search underline and the second and third terminal dots.
- **Mark Gray** (#5C5C5C): Non-text marks only: the scrollbar thumb and the unchecked box border (3.14:1 on black).
- **Dim** (#7A7A7A): The lowest text tone. Placeholders, counters, timestamps, pending queue items, level numbers and disabled labels.
- **Muted** (#8C8C8C): Second title line, tracked labels, inactive navigation, unchecked labels, running text and default terminal output (6.25:1 on black).
- **Soft** (#D4D4D4): Outline pill labels, checked labels, finished queue items, level risk lines and the primary pill's hover fill (14.17:1 on black).
- **Scrim** (#000000CC, written #CC000000 in WPF): 80% black behind overlays, with no blur.

### Named Rules
**The One Signal Rule.** Red means failure, a critical or high finding, or a blocking notice. It is never an accent, a hover or a warning that an action is serious: Reverter tudo is still an outline pill.

**The Dim Floor Rule.** Dim (#7A7A7A) is the lowest tone text may use, and it is a deliberate divergence from the site, whose dim is #5C5C5C. That value measures 3.14:1 on black and fails for text, so here it marks non-text only. Computed WCAG ratios for Dim: 4.89:1 on black, 4.75:1 on terminal black, 4.59:1 at the limb of the planet's halo.

## Typography

**Display Font:** Inter Display Light, with Inter Display Thin for section numbers (bundled in `fonts/`; Segoe UI Light only if a file is missing)
**Body Font:** Inter Regular (with Segoe UI)
**Label/Mono Font:** Inter Medium (with Segoe UI Semibold) for labels; Cascadia Mono (with Consolas) for machine output

**Character:** Large, light, tightly set display type over small, wide-open uppercase labels, the contrast the site is built on. Cascadia Mono sits beside them as a second voice that belongs to the machine.

### Hierarchy
- **Section number** (Thin 100, 58px, -2px): Top left of each view header, in Ink, inside a 104px column.
- **Display** (Light 300, 42px, 1.12, -1.5px): The two-line view title. First line Ink, second line Muted.
- **Headline** (Light 300, 32px, -1px): Optimization level names. Ink when selected, Muted otherwise.
- **Confirm title** (Light 300, 28px, -0.8px): The question in a confirmation overlay.
- **Wordmark** (Light 300, 23px, -0.7px): "upaiva.dev" at the left of the navigation.
- **Title** (Light 300, 21px, -0.5px): Maintenance routine names in hairline rows.
- **Body** (Regular 400, 13px): Row titles, checkbox labels and summaries. Group names step up to 13.5px; footer notices step down to 12px.
- **Body long** (Regular 400, 13.5px, 22px line height): Level descriptions, and confirmation text at a 21px line height.
- **Body small** (Regular 400, 12.5px): Item names in the run queue.
- **Label** (Medium 500, 10.5px, +3px, uppercase): The tracked label above the title, and list group names such as CATÁLOGO OPCIONAL.
- **Navigation** (Medium 500, 11.5px, +2.5px, uppercase): Top navigation tabs.
- **Button** (Medium 500, uppercase): 11.5px at +2.3px on the primary pill, 10.5px at +2px on outline pills.
- **Status** (Medium 500, 10px, +2px, uppercase): Severity words in the findings column.
- **Mono** (Regular 400, 11.5px, 17px line height in the terminal): Terminal output, telemetry and command detail lines. 13px for typed input, 12.5px for palette output, 11px for counts and level numbers.

### Named Rules
**The Tight Title, Open Label Rule.** Display type closes up as it grows, from -0.5px at 21px to -2px at 58px. Labels open up, from +2px to +3px. WPF has no letter spacing, so every tracked string is drawn glyph by glyph through the `TextoTrack` element; a plain `TextBlock` cannot carry these roles.

**The Section Header Rule.** Every view opens with the same header: thin number, tracked label, two-line title with the second line in Muted. These are the owner's brand devices from the site, kept by explicit decision. The thin number appears nowhere else, and a tracked label elsewhere names a list group rather than topping a title.

**The Machine Voice Rule.** Cascadia Mono means the machine is speaking or being queried: commands, telemetry, counts, command details and typed input. Sentences written for a person stay in Inter.

## Layout

A fixed 1280 by 800 window, borderless with a 1px Strong Hairline frame, that can be minimized but never resized. There are no breakpoints and no reflow. The grid is four rows: a 66px navigation bar, the auto-height section header, flexible content, and a 66px footer that holds telemetry and the actions. The page margin is 36px on the left, and on the right wherever a rule or the footer needs to align; scrolling content keeps a small inset for the scrollbar.

The section header carries a top hairline and 24px over 20px padding. Install rows use a 250px group column and 212px wrapping item columns. Optimization levels split the width into four equal columns. The running view splits 4 to 7 with a 28px gutter, queue at left and terminal at right. Rows breathe at 12px above and below, or 15px over 9px for install groups. Pills sit 6px apart in a set and 8px apart as actions, with 18px between sets.

The planet floats at the top right, 420 by 168, behind the content and outside hit testing. Content may run beneath it.

**The Hairline Row Rule.** A list is rows divided by a 1px top hairline directly on black. No card, no fill, no zebra.

## Elevation & Depth

The system is flat. The build has no shadow or blur effect anywhere. Depth is tonal and comes in three steps: page black, terminal black with a Strong Hairline border, and overlays above an 80% black scrim. The only light belongs to the planet: its radial body shading, a faint white halo (alpha 20 of 255) and small comet heads (alpha 70 of 255).

**The Flat Black Rule.** Nothing casts a shadow, and nothing blurs. An overlay separates from the page with the scrim and its border.

**The Only Light Rule.** Radial gradients exist only inside the planet. Every surface is one solid color.

## Shapes

Three forms and nothing between them: square-cornered hairlines, soft-cornered terminal windows, and fully round pills. Outline pills round at 16px on their 32px height and the primary pill at 21px on 42px; window buttons round at 15px on 30px. Embedded terminal windows use 16px and overlays use 22px. Small marks keep a 3px corner (checkbox and focus ring), and the scrollbar thumb 2px.

Icons are thin drawn paths, with a 1.5px check and a 1.2px diagonal arrow. Terminal title dots are 7px circles. Planet particles are squares of about 1 to 2px.

**The Full Round Rule.** A pill's radius is always half its height. A control of any other height gets its radius recalculated, so a pill never reads as a rounded rectangle.

## Components

### Buttons
Few, unmistakable and always labeled with exactly what will happen.

- **Shape:** Fully round pills (see The Full Round Rule).
- **Primary:** Ink fill, black uppercase label, 42px tall with 22px side padding, followed by a drawn diagonal arrow. At most one per view, in the footer or a confirmation. The label states the real action and count: INSTALAR 61 ITENS, APLICAR MÉDIA, MARQUE UM ITEM.
- **Primary Hover / Pressed:** Fill drops to Soft on hover; the pill scales to 0.98 when pressed.
- **Primary Disabled:** Press Fill with a Dim label and no arrow. This measures 4.29:1, below the 4.5:1 text floor, and is tolerated only because the control is inactive.
- **Primary Without Arrow:** Confirmations and the return action after a run drop the arrow.
- **Outline:** Transparent fill, 1px Strong Hairline border, Soft uppercase label, 32px tall with 14px side padding. It may shrink to 26 to 28px inside the palette and grows to 42px beside the primary pill in a confirmation.
- **Outline Hover / Pressed / Disabled:** Hover shifts the border to Muted and the label to Ink. Pressed fills with Press Fill. Disabled drops the label to Dim.
- **Focus:** All buttons, tabs, checkboxes and levels share a 1px Ink focus ring with a 3px radius, offset 3px.
- **Window buttons:** Minimize and close, 34 by 30, Muted, filling with Press Fill and turning Ink on hover. They use the Windows caption glyphs, a platform exception that does not license font icons anywhere else.

### Checkboxes
- **Style:** 13px square with a 3px corner and a 1px Mark Gray border, 10px from its label. The label is Muted.
- **State:** Hover raises the border to Soft and the label to Ink. Checked fills with Ink, draws a black check and sets the label to Soft.

### Inputs / Fields
- **Search:** No box, only a bottom rule, 32px tall. Input and placeholder are mono; the placeholder is Dim. The rule is Strong Hairline at rest and Ink on focus, and the caret is Ink.
- **Palette input:** The same mono text after a Muted `~ $` prompt, with no rule.

### Navigation
- **Style:** The wordmark sits at left, tracked uppercase tabs in the center (30px apart) and the outline `>_ CTRL K` pill plus window buttons at right. The bar also drags the window.
- **State:** Tabs are Muted, turning Ink on hover and when active. There is no underline, pill or indicator: tone alone marks the current view. Changing view fades the content from 0.2 to full opacity over 180ms with an exponential ease-out.

### Lists
- **Hairline rows:** Top hairline, 12px vertical padding, Ink or Muted body, and an optional mono detail line beneath. Actions dock right as outline pills.
- **Install groups:** Group checkbox and mono "23 de 23" counter at left; item checkboxes wrap at right.
- **Findings:** A tracked severity word in an 86px column, then title and mono detail. Fixes are opt-in checkboxes, unchecked by default.
- **Scrollbar:** No track or arrows, only a 3px Mark Gray thumb at the right edge.

### Level Selector
Four equal columns under a single top rule, adapted from the site's four steps. Unselected rules are 1px Strong Hairline, hover is Muted and selected is 2px Ink. Each column stacks a mono Dim number, the level name in Headline, a Soft risk line and a Muted description.

### Run Queue
One line per item, with a mono bracket tag in a 38px column, the name in Body small, and time or reason as mono detail at right.

- `[..]` Dim: waiting. The whole queue is visible from the start.
- `[>>]` Ink: running now.
- `[OK]` Soft: finished, with elapsed time. Muted with "já feito" when it was already done.
- `[SIM]` Soft: simulated, nothing applied.
- `[!!]` Signal Red: failed, with the full reason wrapping at right.
- `[--]` Dim: did not run ("não rodou") or was cancelled ("cancelado").

### Terminal Window
The site's terminal, used wherever the machine speaks or is asked something. Terminal Black fill, 1px Strong Hairline border and a title bar with a Hairline divider. The bar holds three 7px dots (Ink filled, Strong Hairline filled, Strong Hairline outlined) and "upaiva@windows: ~" in mono. The dots are static and never carry state.

- **Run output:** Embedded beside the queue at a 16px radius. Dim timestamps with a hanging indent; `$` commands in Ink, step starts in Soft, process output in Dim, failures in Signal Red and everything else in Muted.
- **Ctrl K palette:** A 660 by 400 overlay at a 22px radius that filters programs, profiles and sections. The first match is Ink with a `>` marker and runs on Enter; Esc closes.
- **Confirmation:** A 560px overlay at a 22px radius with Confirm title, Muted text, the outline "Voltar" pill and an arrowless primary pill. Esc closes.

### Footer Telemetry
Mono Muted `cpu`, `ram` and `net` read live from the operating system, with `pid` and elapsed time added while a process runs. A Hairline rule runs across the footer's top edge; the progress hairline fills over it in Ink.

### Planet
The one decoration: 760 particles on a sphere, lit from the upper left in nine white steps, with two particle rings and two comets on the outer ring. It rotates slowly at rest and about three times faster while a process runs, and holds still when Windows client-area animation is off. Monochrome always.

### State Honesty
Status on screen is a promise. These rules outrank any visual preference.

**The Lit Orbit Rule.** The inner orbit lights only from real progress, in proportion to completed work, and only while something runs. When nothing runs it goes dark: uniform dim dust with no bright arc, including right after a run ends.

**The SIM Rule.** A simulation never reads as applied. The queue shows `[SIM]`, the terminal shows `[ sim ]`, the title ends "Simulação concluída. Nada foi alterado.", and neither the progress hairline nor the orbit ever fills.

**The Did Not Run Rule.** Queue items that did not run are shown as such. Anything still waiting or running when a process ends becomes `[--]` "não rodou", and the title counts them. Never show them as done.

**The Earned Bar Rule.** The footer hairline carries the same value as the orbit, capped at 99% while running. It reaches 100% only on a clean finish; otherwise it stays at what was really done.

**The No Invented Number Rule.** Without a known total the title says "Em andamento." and shows no percentage. A check that could not be read says NÃO LIDO, never OK.

**The Safe Focus Rule.** Confirmations use the terminal window overlay with keyboard focus on the safe option, "Voltar", so a stray Enter applies nothing. Never a stock dialog.

**The Last Stock Dialog Rule.** The only stock dialog is the fatal startup error, when no interface exists to carry it. Nothing else earns one.

## Do's and Don'ts

### Do:
- **Do** open every view with the thin number, tracked label and two-line title, second line in Muted (#8C8C8C).
- **Do** keep at most one white pill per view, labeled with the real action and count, and make every other action an outline pill.
- **Do** build lists as rows on 1px hairlines (#1C1C1C) directly on true black (#000000).
- **Do** keep text at Dim (#7A7A7A) or brighter, and reserve Mark Gray (#5C5C5C) for non-text marks.
- **Do** set commands, telemetry, counts and typed input in Cascadia Mono, and write sentences for people in Inter.
- **Do** draw icons as thin paths, like the check and the diagonal arrow.
- **Do** light the inner orbit and the footer hairline from the same real progress value, and darken the orbit when nothing runs.
- **Do** send every confirmation through the terminal window overlay with focus on "Voltar".

### Don't:
- **Don't** put gradients on surfaces. The planet's own shading, halo and comet glow are the only gradients in the system.
- **Don't** use neon, colored glow, glass, blur or shadows.
- **Don't** add a sidebar or wrap a list in a card. A terminal window holds machine output; it is not a card.
- **Don't** add progress rings or spinners. The planet's inner orbit is the only ring that reports progress.
- **Don't** let decoration read as status: no lit orbit without a run, no state on the terminal dots.
- **Don't** use Signal Red (#FF6B6B) for anything but failure, critical or high findings and blocking notices.
- **Don't** show a simulation as applied, or fill the progress hairline or orbit during one.
- **Don't** show a percentage without a known total, or mark an item that did not run as done.
- **Don't** open a stock dialog for anything but the fatal startup error.
- **Don't** add font glyph icons. The two window caption glyphs are the platform's own and stay there.
