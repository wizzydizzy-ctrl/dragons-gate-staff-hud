# Options and display

Open **OPTIONS ▾** in the Staff HUD header to control the separate Mudlet 5 starter dock titled **Mudlet UI**.

- **MUDLET STARTER UI: OFF** means the starter dock is hidden. Click it to turn the dock on.
- **MUDLET STARTER UI: ON** means the starter dock is shown. Click it to turn the dock off.
- **UNAVAILABLE** means the `mudlet-base-ui` package is not installed or enabled in this profile.

On a fresh profile, the Staff HUD turns the starter dock off. If you turn it on, that choice remains in effect after HUD reloads and updates. This option does not hide Mudlet's game console, input, toolbar, or the map embedded in the Staff HUD.

The starter dock may cover part of the HUD when shown. Drag its title bar to move it.

## Skill Settings

Open **OPTIONS → Skill Settings** to control skill formatting and sorting. **MAIN SKILLS** stays on by default and formats complete `skill` responses in aligned **Number / Skill / LVL / USES** columns. Turn it off to keep future responses in the game's original layout.

**Main Display** and **Right Sidebar** have independent sorting choices. For each, choose a primary key: **Level**, **Uses**, **Name**, **Number**, **Ready to train (0 uses)**, or **Category (combat vs utility)**. Choose ascending or descending order, and optionally add a secondary key with its own direction. Both displays default to **Level descending**, then **Uses ascending**. For “level then uses,” choose **Level** as the primary key and **Uses** as the secondary key.

Changing **Right Sidebar** ordering immediately reorders its existing skill rows. **Main Display** ordering applies to the next complete `skill` output; previously printed tables stay as they are. Formatting and sorting choices are saved for the whole Mudlet profile and survive character changes, reloads, restarts, and HUD updates.

**Number** is the game's fixed catalog ID used for training, not a display rank. All captured skills remain visible; Category and Ready to train sorting only change their order.

```text
Number  Skill    LVL  USES
     9  Dodging    5    50
     2  Sharps     4   400
```

Tables ending in blank lines update on the next UI tick, without waiting for another prompt or sending an extra Enter. The right-hand Skills panel gets the same completed list and keeps its existing appearance.

Rows with **0 uses remaining are green**, combat skills are **blue**, and utility skills are **yellow**. Zero uses takes priority. Customize the three styles under **OPTIONS → COLOR SETTINGS → TEXT STYLES → Skills**. The **SKILL ROW COLORS** category turns coloring on or off without disabling the aligned layout.

Color choices are also saved with the profile. No training commands are sent, and unrelated output is left alone.
