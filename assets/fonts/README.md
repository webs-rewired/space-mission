# Fonts

The whole game uses one theme, `assets/ui/orbit_lab_theme.tres`. `project.godot` points to it
(Project Settings > GUI > Theme > Custom), so every screen gets these fonts automatically.

| Font | Job | How to use it |
|---|---|---|
| Inter | Everything you read: captions, event text, descriptions | Default for every Label |
| Barlow Condensed | Headings and buttons: tall, narrow capitals like mission control screens | Default for Buttons. For a Label, set Theme Type Variation to `TitleLabel` |
| JetBrains Mono | Live numbers: clocks, altitude, speed, data rates. Every digit is the same width, so changing numbers don't jiggle | Theme Type Variation `DataLabel` |
| Orbitron | Only the "ORBIT LAB" logo | Theme Type Variation `LogoLabel` |

To set Theme Type Variation: select the Label, then Inspector > Theme > Theme Type Variation.
In code: `label.theme_type_variation = "DataLabel"`

All four are free to use and ship in a game under the SIL Open Font License (the `OFL_*.txt` files here),
from Google Fonts (https://fonts.google.com).
