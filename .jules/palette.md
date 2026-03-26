## 2024-03-21 - Icon-only buttons lacking ARIA labels
**Learning:** Icon-only buttons like those in the theme toggle were missing `aria-label` and `title` attributes. Without these, screen readers announce nothing useful, preventing non-visual users from understanding the toggle's function or its current state options.
**Action:** Always add `aria-label` (and ideally `title` for tooltip on hover) to all icon-only buttons to guarantee accessibility for screen reader and keyboard users.
