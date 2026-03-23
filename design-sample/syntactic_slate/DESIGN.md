# Design System Specification

## 1. Overview & Creative North Star: "The Architectural Blueprint"
This design system is engineered to move beyond the "standard SaaS dashboard" into the realm of high-end technical editorial. The Creative North Star is **The Architectural Blueprint**: a vision where precision meets depth. 

Instead of treating the UI as a flat screen of boxes, we treat it as a multi-layered workspace. We break the "template" feel through **intentional tonal layering** and **asymmetric information density**. This system avoids the "Lego-brick" look by using varying surface elevations to group complex data, ensuring the interface feels like a professional-grade instrument—stable, sophisticated, and authoritative.

---

## 2. Colors & Surface Logic

### Tonal Foundation
The palette is rooted in a deep, obsidian charcoal. We move away from pure blacks to a sophisticated slate that allows for rich shadow depth and vibrant accents.

*   **Background (Surface):** `#0b1326` (The base canvas)
*   **Primary (Action):** `#adc6ff` (Electric Blue highlight)
*   **Secondary (Success):** `#4edea3` (Emerald Green for validation)
*   **Tertiary (Warning/Special):** `#ffb786` (Warm amber for technical alerts)

### The "No-Line" Rule
**Explicit Instruction:** Designers are prohibited from using 1px solid borders for sectioning or layout containment. 
Structure must be defined through:
1.  **Background Color Shifts:** Use `surface-container-low` vs. `surface-container-high` to define boundaries.
2.  **Vertical Space:** Leverage the Spacing Scale (e.g., `8` or `10`) to create clear logical breaks.

### Surface Hierarchy & Nesting
Treat the UI as a series of physical layers. Use the following tiers to create a "nested" depth that guides the eye:
*   **Lowest (`#060e20`):** Use for deep-set areas like the main background or code-block wells.
*   **Low/Base (`#0b1326`):** The primary workspace level.
*   **High/Highest (`#222a3d` to `#2d3449`):** Use for interactive elements like architecture cards or sidebar navigation items that need to "rise" toward the user.

### The "Glass & Gradient" Rule
To inject a premium "editorial" feel, floating elements (modals, dropdowns, tooltips) must use **Glassmorphism**:
*   **Fill:** `surface-container-highest` at 70% opacity.
*   **Effect:** `backdrop-blur` (12px to 20px).
*   **Accents:** Use a subtle linear gradient on Primary CTAs (transitioning from `primary` to `primary_container`) to provide visual "soul" and avoid a flat, lifeless appearance.

---

## 3. Typography: Precision & Scale

The system employs a dual-font strategy to balance human readability with technical rigor.

*   **Inter (UI & Body):** Used for all navigation, labels, and documentation prose. It provides a neutral, highly readable foundation.
*   **JetBrains Mono (Technical Values):** Reserved strictly for code blocks, Terraform variables, AWS resource IDs, and difficulty tags.

### Hierarchy Strategy
*   **Display/Headline:** High-contrast sizing (e.g., `display-lg` at 3.5rem) should be used for section headers to provide an editorial "anchor."
*   **Label-SM (`0.6875rem`):** Used in all-caps with 0.05em letter spacing for metadata (e.g., "DIFFICULTY: ADVANCED") to create a sense of technical documentation.
*   **Body-MD/LG:** Generous line heights (1.6+) are mandatory for documentation sections to ensure long-form technical content is digestible.

---

## 4. Elevation & Depth: Tonal Layering

We abandon traditional structural lines in favor of **Tonal Layering**.

### The Layering Principle
Depth is achieved by "stacking" the surface tiers. 
*   *Example:* Place a `surface_container_highest` architecture card on a `surface_container_low` dashboard section. This creates a soft, natural lift.

### Ambient Shadows
For floating elements (Drawers, Tooltips), use "Ambient Shadows":
*   **Shadow Color:** A tinted version of `on_surface` (deep blue-grey) at 6% opacity.
*   **Blur:** High diffusion (20px to 40px) to mimic natural light dispersion rather than a harsh drop shadow.

### The "Ghost Border" Fallback
If a border is required for accessibility (e.g., input fields), use a **Ghost Border**:
*   **Token:** `outline_variant` at 15% opacity.
*   **Constraint:** Never use 100% opaque borders for decorative grouping.

---

## 5. Components

### Architecture Cards
*   **Base:** `surface_container_high`.
*   **Rounding:** `lg` (0.5rem).
*   **Interaction:** On hover, shift to `surface_container_highest` and apply a Primary `surface_tint` subtle glow (2px).
*   **No Dividers:** Separate card headers from content using a `2.5` (0.5rem) spacing gap or a slight background shift to `surface_container_low` for the card footer.

### Buttons
*   **Primary:** Linear gradient (`primary` to `primary_container`). White text (`on_primary_fixed`). `md` (0.375rem) rounding.
*   **Secondary:** Ghost style. Transparent fill with a `ghost-border` (15% opacity). On hover, fill with `primary` at 8% opacity.

### Navigation (Sidebar)
*   **Background:** `surface_container_lowest`.
*   **Active State:** No heavy boxes. Use a vertical `primary` bar (2px wide) on the far left and a subtle `surface_container_high` background highlight.

### Code Blocks & Documentation
*   **Well:** `surface_container_lowest`.
*   **Syntax Highlighting:** High-contrast colors using `secondary` (green) for strings and `tertiary` (amber) for functions.
*   **Split-View:** Use an asymmetric 40/60 split. The documentation (Inter) occupies the wider lane, while the code (JetBrains Mono) sits in the 40% lane, creating an editorial, technical-whitepaper feel.

---

## 6. Do's and Don'ts

### Do
*   **Do** use `JetBrains Mono` for any value that could be copy-pasted into a terminal.
*   **Do** use `surface-container` shifts to create "zones" of information.
*   **Do** allow for "breathing room" (Spacing `12` or `16`) between major architectural modules.

### Don't
*   **Don't** use 1px solid borders to separate list items; use `surface_container_low` background alternates or white space.
*   **Don't** use pure white text; use `on_surface` (`#dae2fd`) to reduce eye strain in the dark theme.
*   **Don't** use standard "drop shadows" with black/grey values; always tint shadows with the deep slate background tone.