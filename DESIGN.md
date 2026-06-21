---
name: BudgetMate
description: Calm, trustworthy budgeting for personal and shared household money.
colors:
  brand-blue: "#2563EB"
  brand-blue-soft: "#DDE8FD"
  system-background: "#F2F2F7"
  system-surface: "#FFFFFF"
  surface-stroke: "#0000000F"
  income-green: "#16A34A"
  expense-red: "#DC2626"
  positive-teal: "#0D9488"
  warning-orange: "#EA580C"
  beaver-warm-background: "#E8E4DC"
  beaver-ink: "#4A3B32"
  beaver-wood: "#8B5A2B"
  beaver-paper: "#FFFFFF"
  beaver-bank: "#F2F2F7"
  beaver-water: "#4A90E2"
  beaver-forest: "#3E885B"
  beaver-clay: "#D97757"
  beaver-danger: "#D4183D"
typography:
  display:
    fontFamily: "SF Pro Rounded, system"
    fontSize: "32px"
    fontWeight: 700
    lineHeight: 1.15
  headline:
    fontFamily: "SF Pro, system"
    fontSize: "18px"
    fontWeight: 700
    lineHeight: 1.25
  title:
    fontFamily: "SF Pro Rounded, system"
    fontSize: "15px"
    fontWeight: 700
    lineHeight: 1.25
  body:
    fontFamily: "SF Pro, system"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.35
  label:
    fontFamily: "SF Pro, system"
    fontSize: "12px"
    fontWeight: 700
    lineHeight: 1.2
rounded:
  sm: "10px"
  md: "16px"
  lg: "20px"
spacing:
  xs: "6px"
  sm: "10px"
  md: "16px"
  lg: "24px"
components:
  button-primary:
    backgroundColor: "{colors.brand-blue}"
    textColor: "{colors.system-surface}"
    rounded: "{rounded.md}"
    padding: "14px 16px"
  card-standard:
    backgroundColor: "{colors.system-surface}"
    textColor: "{colors.beaver-ink}"
    rounded: "{rounded.md}"
    padding: "16px"
  card-warm:
    backgroundColor: "{colors.beaver-paper}"
    textColor: "{colors.beaver-ink}"
    rounded: "{rounded.lg}"
    padding: "18px"
---

# Design System: BudgetMate

## 1. Overview

**Creative North Star: "The Calm Ledger"**

BudgetMate should feel like a practical household finance surface: warm enough to lower anxiety, structured enough to make money feel precise, and quiet enough to use every day. The current direction is a blue-led SwiftUI product language with warm accents mapped through adaptive system surfaces, so light and dark mode share the same hierarchy.

The interface should reject childish theming, novelty finance visuals, crypto-like intensity, sterile bank UI, and overly beige craft-paper styling. Use warmth as a human accent, not as the entire product identity.

**Key Characteristics:**
- Local-first SwiftUI product UI with dashboard, transactions, budget, settings, onboarding, and shared-budget flows.
- Restrained primary accent for actions and selection.
- Clear semantic color for income, expense, warning, positive states, sync issues, and settlement states.
- Familiar iOS controls with custom surfaces only where they improve scanability.

## 2. Colors

The current palette uses Trust Blue as the main product accent, adaptive system surfaces for cards and grouped content, and warm secondary notes for household context.

### Primary
- **Trust Blue** (#2563EB): Primary actions, selected navigation, onboarding mark, empty-state icon, and current selection. Keep it rare and purposeful.

### Secondary
- **Ledger Warmth** (semantic warning/secondary text + adaptive grouped surfaces): Warm support colors for household context, secondary labels, and low-emphasis surfaces.
- **Clear Water**: Deprecated as a separate visual identity; Dashboard/Budget money accents should use Trust Blue unless a semantic state needs income, expense, or warning.

### Tertiary
- **Category Spectrum**: Category colors currently use SwiftUI named colors such as orange, mint, indigo, teal, red, pink, purple, cyan, gray, and yellow. These need a more deliberate, color-blind-safe ramp before broad redesign work.

### Neutral
- **System Grouped Background** (#F2F2F7 approximation): App shell background.
- **System Surface** (#FFFFFF approximation): Cards, form rows, modal content, and list surfaces.
- **Soft Stroke** (#0000000F): Standard low-contrast card border.
- **Warm Paper** (#FEFDFB): Existing warm card background.

### Named Rules

**The One Accent Rule.** Trust Blue is the primary product accent. Do not introduce a second blue for competing money emphasis.

**The Money State Rule.** Income, expense, warning, positive, owed, paid, sync issue, and pending states must not rely on color alone.

## 3. Typography

**Display Font:** SF Pro Rounded / SwiftUI `.rounded` system design
**Body Font:** SF Pro / SwiftUI system
**Label/Mono Font:** SF Pro / SwiftUI system

**Character:** Native, legible, and task-focused. Rounded typography can soften major amounts and onboarding moments, but labels, settings rows, buttons, and dense product UI should stay system-native and easy to scan.

### Hierarchy
- **Display** (bold/black, 32-34pt): Major balances, remaining budget, onboarding title. Use sparingly.
- **Headline** (bold, 17-18pt): Card titles and section-level labels.
- **Title** (rounded bold, 15-18pt): Compact card titles and transaction group headings.
- **Body** (regular, 15-17pt): Explanatory text, settings rows, form content, and transaction details.
- **Label** (bold, 11-12pt, occasional uppercase): Compact state labels such as TOTAL BALANCE, REMAINING, OVER BUDGET, and split-bill chips.

### Named Rules

**The Data First Rule.** Amounts may be bold; surrounding labels should stay quieter so users can read the number first.

## 4. Elevation

BudgetMate currently uses a hybrid of tonal layering, borders, and soft shadows. Standard cards use a 1px low-opacity stroke plus a shadow around radius 12/offset 6. Warm dashboard cards also use larger radii and shadows around radius 14-16/offset 8. The long-term direction should be flatter by default, using shadows for tab bars, overlays, and interactive prominence rather than every repeated card.

### Shadow Vocabulary
- **Card Ambient** (`0 3px 8px rgba(0,0,0,0.05)`): Current `CardSurface` default.
- **Warm Card Lift** (`0 3px 8px rgba(0,0,0,0.05)`): Dashboard and budget finance cards after the quieter surface pass.
- **Tab Bar Lift** (`0 -6px 18px rgba(0,0,0,0.08)`): Bottom navigation separation.

### Named Rules

**The Quiet Surface Rule.** Avoid heavy shadow plus strong border on the same repeated card. Repeated finance rows should feel stable, not floaty; card shadows should stay subtle.

## 5. Components

### Buttons
- **Shape:** 16px rounded rectangle for primary buttons; circular icon buttons for compact actions.
- **Primary:** Trust Blue background with white text, 14px vertical padding, bold label, optional SF Symbol.
- **Secondary / Text:** SwiftUI button styles and blue text actions currently appear in Settings and card headers.
- **State:** Disabled and loading states exist in sync controls. Plain custom buttons use `PressableButtonStyle` for subtle scale/opacity feedback with reduced-motion support.

### Chips
- **Style:** Current chips use capsules or rounded rectangles with soft tinted backgrounds for sync state, split-bill labels, and budget status.
- **State:** Pending, active, left, removed, invited, paid, owed, syncing, error, and success states need a consistent vocabulary.

### Cards / Containers
- **Corner Style:** Standard product cards use 16px. Dashboard/Budget hero cards use 20px; avoid 32px for ordinary product cards.
- **Background:** AppTheme cards use system surface; Dashboard/Budget warm cards use paper/bank colors.
- **Shadow Strategy:** See Elevation.
- **Border:** 1px low-opacity stroke or warm border.
- **Internal Padding:** 16-20px.

### Inputs / Fields
- **Style:** Settings uses native SwiftUI `Form`, `TextField`, segmented picker, and navigation rows. Add Transaction uses app-specific form fields.
- **Focus:** Native iOS focus behavior unless a screen earns custom styling.
- **Error / Disabled:** Error, helper, and disabled states should use plain language and visible state icons where helpful.

### Navigation
- **Style:** Custom bottom tab bar with icon-only tabs and a central add transaction button.
- **Active State:** Filled SF Symbol and Trust Blue.
- **Inactive State:** Secondary color SF Symbol.
- **Mobile Treatment:** Native iPhone-first layout; ensure bottom safe area and status bar scrim continue to protect content.

### Signature Component

**Settlement Rows:** Paired member avatars, owed amount, and quick settle action communicate shared-budget responsibility. These should become one of BudgetMate's most trustworthy patterns: show who owes whom, why, and what marking paid will change.

## 6. Do's and Don'ts

### Do:
- **Do** prioritize balance, remaining budget, settlement status, and sync state over decoration.
- **Do** keep primary action color purposeful and scarce.
- **Do** use SF Symbols consistently for finance, sync, member, and settlement actions.
- **Do** make shared-budget state legible with text, icon, and color together.
- **Do** test dark mode and Dynamic Type whenever changing cards, forms, or tab navigation.

### Don't:
- **Don't** make BudgetMate childish, overly cute, or novelty-themed.
- **Don't** let warm beige/brown tones dominate screens; warmth should be an accent carried by semantic color and copy.
- **Don't** make the app look like a sterile corporate bank app.
- **Don't** use crypto-style neon colors, glassmorphism, loud gradients, or finance-bro visuals.
- **Don't** use 32px card radii as the default for ordinary product cards.
- **Don't** hide exact money, membership, sync, or settlement meaning behind vague labels.
