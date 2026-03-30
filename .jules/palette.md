## 2025-06-12 - Navbar Accessibility Improvements
**Learning:** Found that the main navigation bar was missing crucial `aria-current` attributes for active page indicators and the user dropdown lacked `aria-haspopup` and dynamic `aria-expanded` state tracking. These are common oversights in custom dropdowns and navigation links that severely impact screen reader users.
**Action:** Ensure custom dropdown toggles always include `aria-expanded` that syncs with their visible state via JS, and `aria-haspopup="menu"`. Add `aria-current="page"` to active navigation items.
