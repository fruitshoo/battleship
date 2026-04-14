Generated upgrade icons live here.

Style target:

- Match `res://assets/ui/items/choyogi.png` and `res://assets/ui/items/ilseongjeongsiui.png`.
- 128x128 PNG, RGBA/transparent background.
- One centered object, large readable silhouette, no text, no baked UI border.
- Painterly semi-realistic game item icon, crisp edges, warm top-left lighting, subtle shadow.
- Use tactile Joseon/naval materials: worn paper, wood, rope, bronze, iron, cloth, lacquer.
- Keep the object readable at 32px; avoid tiny scattered props.

Base generation prompt:

```text
Use case: stylized-concept
Asset type: 128x128 game upgrade icon PNG
Primary request: Create one centered upgrade icon matching the provided item icon references.
Input images: choyogi.png and ilseongjeongsiui.png are style references only.
Subject: <one upgrade object>
Style/medium: painterly semi-realistic game item icon, Joseon naval survival roguelite, crisp hand-painted texture.
Composition/framing: single object in 3/4 view, centered, fills about 70% of the canvas, transparent background.
Lighting/mood: warm soft top-left light, subtle contact shadow, readable high-contrast silhouette.
Materials/textures: worn paper, wood, rope, bronze, iron, cloth, or lacquer as appropriate.
Constraints: no text, no letters, no watermark, no UI frame, no extra background scene, no extra small props.
```

Use one PNG per upgrade id:

- `cannon.png`
- `cannon_damage.png`
- `cannon_reload.png`
- `janggun.png`
- `hull_defense.png`
- `sailing.png`
- `rowing.png`
- `supply_bonus.png`
- `crew_numbers.png`
- `crew_reserve.png`
- `boarding_resist.png`
- `crew_attack.png`
- `crew_defense.png`
- `singigeon.png`
- `fire_pot.png`
- `repeating_crossbow.png`
- `fleet_signal.png`
- `fleet_hull.png`
- `fleet_crew.png`

HUD slots automatically use `res://assets/ui/upgrades/<upgrade_id>.png` when it exists, and fall back to the Material Symbols icon otherwise.
