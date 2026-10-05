# Options and display

Open **OPTIONS ▾** in the Staff HUD header to control the separate Mudlet 5 starter dock titled **Mudlet UI**.

- **MUDLET STARTER UI: OFF** means the starter dock is hidden. Click it to turn the dock on.
- **MUDLET STARTER UI: ON** means the starter dock is shown. Click it to turn the dock off.
- **UNAVAILABLE** means the `mudlet-base-ui` package is not installed or enabled in this profile.

On a fresh profile, the Staff HUD turns the starter dock off. If you turn it on, that choice remains in effect after HUD reloads and updates. This option does not hide Mudlet's game console, input, toolbar, or the map embedded in the Staff HUD.

The starter dock may cover part of the HUD when shown. Drag its title bar to move it.

## Main skills output

**OPTIONS → MAIN SKILLS** is on by default. Complete `skill` responses use aligned **Number / Skill / LVL / USES** columns, sorted by highest level and then fewest uses remaining. The number is the fixed game skill ID, not a row number. Every possessed skill is included.

```text
Number  Skill    LVL  USES
     9  Dodging    5    50
     2  Sharps     4   400
```

Tables ending in blank lines update on the next UI tick, without waiting for another prompt or sending an extra Enter. The right-hand Skills panel gets the same completed list and keeps its existing appearance.

Rows with **0 uses remaining are green**, combat skills are **blue**, and utility skills are **yellow**. Zero uses takes priority. Customize the three styles under **OPTIONS → COLOR SETTINGS → TEXT STYLES → Skills**. The **SKILL ROW COLORS** category turns coloring on or off without disabling the aligned layout.

Turn **MAIN SKILLS** off to leave future responses in the game's original layout. Both formatting and color choices are saved with the profile and survive updates and restarts. No training commands are sent, and unrelated output is left alone.
