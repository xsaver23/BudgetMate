---
name: BudgetMate
description: Bright, trustworthy budgeting for personal and shared household money.
colors:
  forest-primary: "#1E3A2B"
  cream-background: "#F8F4EC"
  cream-surface: "#FFFDF8"
  warm-surface: "#F2EBDD"
  amber-secondary: "#E7B84B"
  income-block: "#9CC957"
  expense-block: "#F49379"
  danger-ink: "#7D2B17"
  positive-teal: "#0D9488"
  member-blue: "#3B8FE2"
  member-coral: "#E2572E"
  member-teal: "#1FA37D"
  member-purple: "#7B6EE6"
  adaptive-ink: "Forest in light mode, cream in dark mode"
  adaptive-muted: "Brown in light mode, amber in dark mode"
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
    backgroundColor: "{colors.forest-primary}"
    textColor: "{colors.cream-surface}"
    rounded: "{rounded.lg}"
    padding: "14px 16px"
  card-standard:
    backgroundColor: "{colors.cream-surface}"
    textColor: "{colors.adaptive-ink}"
    rounded: "{rounded.md}"
    padding: "16px"
  card-finance:
    backgroundColor: "{colors.warm-surface}"
    textColor: "{colors.adaptive-ink}"
    rounded: "{rounded.lg}"
    padding: "18px"
---

# Design System: BudgetMate

## 1. Overview

**Creative North Star: "Bright Household Hub"**

BudgetMate should feel like a practical household finance surface with more warmth and confidence: cream canvas, forest primary actions, saturated color-block money tiles, and colorful member identity badges. It should keep settlement and debt screens especially legible so playful color never weakens trust in the numbers.

The interface should reject sterile bank UI and novelty finance visuals. Use bold color for hierarchy and identity, but keep amounts, settlement rows, and settings states readable first.

**Key Characteristics:**
- Local-first SwiftUI product UI with dashboard, transactions, budget, settings, onboarding, and shared-budget flows.
- Forest primary accent for actions and selection.
- Cream/warm surfaces instead of stark white.
- Saturated income, expense, pacing, category, and member identity colors.
- Clear semantic color for income, expense, warning, positive states, sync issues, and settlement states.
- Familiar iOS controls with custom surfaces only where they improve scanability.

## 2. Colors

The current palette uses forest green as the main product accent, a cream/warm canvas for household warmth, and saturated blocks for scanable finance summaries.

### Primary
- **Forest Primary** (#173404): Primary actions, selected navigation, onboarding mark, headings, and major positive control states.

### Secondary
- **Cream Canvas** (#F8F4EC): Light-mode app background.
- **Amber Secondary** (#FFCF70): Secondary CTAs, avatar rings, pacing blocks, and selected-member rings.

### Tertiary
- **Member Spectrum**: Blue, coral, teal, and purple badges identify household members across dashboard, transactions, settlement, budget members, and split rows.

### Neutral
- **Cream Surface** (#FFFDF8): Cards, form rows, modal content, and list surfaces.
- **Adaptive Ink:** Forest in light mode, cream in dark mode.
- **Adaptive Muted:** Accessible olive-gray in light mode, warm gray in dark mode.
- **Warm Surface** (#F2EBDD): Secondary card fills and quiet groups.

### Readability Rules

Small text uses role-specific foreground colors rather than chart colors.
Category and member hues belong on dots, icons, borders, and fills; pill text
stays primary or uses a computed high-contrast foreground. Status labels always
pair color with an icon and plain-language text.

### Named Rules

**The One Primary Rule.** Forest green is the primary product action color. Member blue is identity color only, not a competing brand action.

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

BudgetMate currently uses tonal layering, low-opacity borders, and quiet shadows. Standard cards use a 1px low-opacity warm stroke plus a small ambient shadow. Dashboard and Budget finance cards use saturated color blocks with 22-24px corners, keeping the app warm in light mode and legible in dark mode. The long-term direction should stay flatter by default, using shadows for overlays and interactive prominence rather than every repeated card.

### Shadow Vocabulary
- **Card Ambient** (`0 3px 8px rgba(0,0,0,0.05)`): Current `CardSurface` default.
- **Finance Card Lift** (`0 3px 8px rgba(0,0,0,0.05)`): Dashboard and budget finance cards after the quieter surface pass.
- **Tab Bar Lift** (`0 -6px 18px rgba(0,0,0,0.08)`): Bottom navigation separation.

### Named Rules

**The Quiet Surface Rule.** Avoid heavy shadow plus strong border on the same repeated card. Repeated finance rows should feel stable, not floaty; card shadows should stay subtle.

## 5. Components

### Buttons
- **Shape:** 18-22px rounded rectangle for primary buttons; circular icon buttons for compact actions.
- **Primary:** Forest background with white text, 14-16px vertical padding, bold label, optional SF Symbol.
- **Secondary / Text:** Amber filled actions and forest text actions where hierarchy is lower.
- **State:** Disabled and loading states exist in sync controls. Plain custom buttons use `PressableButtonStyle` for subtle scale/opacity feedback with reduced-motion support.

### Chips
- **Style:** Current chips use capsules or rounded rectangles with soft tinted backgrounds for sync state, split-bill labels, and budget status.
- **State:** Pending, active, left, removed, invited, paid, owed, syncing, error, and success states need a consistent vocabulary.

### Cards / Containers
- **Corner Style:** Standard product cards use 22px. Dashboard/Budget color blocks use 22-24px.
- **Background:** AppTheme cards use cream/adaptive surface; finance tiles use saturated color blocks.
- **Shadow Strategy:** See Elevation.
- **Border:** 1px low-opacity stroke or warm border.
- **Internal Padding:** 16-20px.

### Inputs / Fields
- **Style:** Settings uses native SwiftUI `Form`, `TextField`, segmented picker, and navigation rows. Add Transaction uses app-specific form fields.
- **Focus:** Native iOS focus behavior unless a screen earns custom styling.
- **Error / Disabled:** Error, helper, and disabled states should use plain language and visible state icons where helpful.

### Navigation
- **Style:** Custom bottom tab bar with icon + label tabs and a central add transaction button.
- **Active State:** Filled SF Symbol, label, and Forest Primary.
- **Inactive State:** Brown secondary icon and label.
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
