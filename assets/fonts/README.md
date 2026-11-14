# Fonts

The whole game uses one theme, `assets/ui/orbit_lab_theme.tres`. `project.godot` points to it
(Project Settings > GUI > Theme > Custom), so every screen gets these fonts automatically.

| Font | Job | How to use it |
|---|---|---|
| Inter | Everything you read: captions, event text, descriptions | Default for every Label |
| Space Grotesk | Headings, buttons and the "ORBIT LAB" logo: a clean, technical look (the same heading font as the Webs With U site) | Default for Buttons. For a Label, set Theme Type Variation to `TitleLabel` (or `LogoLabel` for the logo) |
| Barlow Condensed | Drop-down lists (part pickers): narrow, so long part names fit | Default for OptionButtons |
| JetBrains Mono | Live numbers: clocks, altitude, speed, data rates. Every digit is the same width, so changing numbers don't jiggle | Theme Type Variation `DataLabel` |
| Orbitron | Kept for older scenes; no longer used by the theme | |

To set Theme Type Variation: select the Label, then Inspector > Theme > Theme Type Variation.
In code: `label.theme_type_variation = "DataLabel"`

All five are free to use and ship in a game under the SIL Open Font License (the `OFL_*.txt` files here),
from Google Fonts (https://fonts.google.com).

The destination codex (the solar system's Go to... menu) uses the same fonts with its own colors and sizes,
in `assets/ui/codex_theme.tres` (Space Grotesk titles, JetBrains Mono labels, Inter text, slanted Inter for notes).
