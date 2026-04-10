#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOLDIER_RULES_PATH = ROOT / "data" / "soldier_rules.json"
UPGRADES_PATH = ROOT / "data" / "upgrades.json"


def load_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def clamp(value: float, minimum: float, maximum: float) -> float:
    return max(minimum, min(maximum, value))


def expected_crit_multiplier(crit_chance: float, crit_multiplier: float) -> float:
    crit_chance = clamp(crit_chance, 0.0, 1.0)
    return (1.0 - crit_chance) + (crit_chance * crit_multiplier)


def damage_after_defense(raw_damage: float, target_defense: float, reduction: float = 0.0) -> float:
    mitigated = max(raw_damage - target_defense, 1.0)
    return max(mitigated * (1.0 - reduction), 1.0)


def ttk(health: float, dps: float) -> float:
    if dps <= 0.0:
        return float("inf")
    return health / dps


def fmt_float(value: float) -> str:
    if value == float("inf"):
        return "inf"
    return f"{value:.2f}"


def main() -> int:
    parser = argparse.ArgumentParser(description="Report current soldier combat balance and rough TTK bands.")
    parser.add_argument("--meta-crew-health", type=int, default=0, help="Assumed permanent crew_health level.")
    parser.add_argument("--meta-crew-attack", type=int, default=0, help="Assumed permanent crew_attack level.")
    parser.add_argument("--meta-crew-defense", type=int, default=0, help="Assumed permanent crew_defense level.")
    parser.add_argument("--run-crew-attack", type=int, default=0, help="Assumed run crew_attack level.")
    parser.add_argument("--run-crew-defense", type=int, default=0, help="Assumed run crew_defense level.")
    args = parser.parse_args()

    soldier_rules = load_json(SOLDIER_RULES_PATH)
    upgrades_root = load_json(UPGRADES_PATH)
    upgrades = upgrades_root["upgrades"]

    base = soldier_rules["base"]
    crew_attack_add = float(upgrades["crew_attack"]["stats"].get("attack_add_per_lv", 2.0))
    crew_defense_add = float(upgrades["crew_defense"]["stats"].get("defense_add_per_lv", 1.0))

    base_health = float(base["max_health"])
    base_attack = float(base["attack_damage"])
    base_defense = float(base["defense"])
    crit_chance = float(base["crit_chance"])
    crit_multiplier = float(base["crit_multiplier"])

    meta_health_mult = 1.0 + (args.meta_crew_health * 0.12)
    meta_attack_bonus = args.meta_crew_attack * 2.0
    meta_defense_bonus = args.meta_crew_defense * 1.0
    run_attack_bonus = args.run_crew_attack * crew_attack_add
    run_defense_bonus = args.run_crew_defense * crew_defense_add

    effective_health = base_health * meta_health_mult
    effective_attack = base_attack + meta_attack_bonus + run_attack_bonus
    effective_defense = base_defense + meta_defense_bonus + run_defense_bonus

    melee_expected_crit = expected_crit_multiplier(crit_chance, crit_multiplier)
    harpoon_expected_crit = expected_crit_multiplier(crit_chance + 0.15, 2.5)

    # Mirror the code-facing formulas, not the design intent.
    sword_damage = effective_attack * 1.25
    spear_damage = effective_attack * 1.25
    trident_damage = effective_attack * 1.25
    harpoon_damage = effective_attack * 1.25
    bow_damage = effective_attack

    repeater_upgrade_damage = (
        float(upgrades["repeating_crossbow"]["stats"].get("base_damage", 10.0))
        + max(0, args.run_crew_attack - 1) * float(upgrades["repeating_crossbow"]["stats"].get("damage_per_lv", 2.0))
    )
    singigeon_base_damage = float(upgrades["singigeon"]["stats"].get("base_damage", 2.2))
    singigeon_personnel_mult = float(upgrades["singigeon"]["stats"].get("personnel_damage_mult", 6.0))

    target_defense = effective_defense
    ranged_cover = 0.20

    rows = [
        {
            "weapon": "sword",
            "raw_hit": sword_damage,
            "cooldown": 1.0,
            "expected_hit": sword_damage * melee_expected_crit,
            "notes": "Current code applies melee-slot weapons from soldier effective_attack * 1.25.",
        },
        {
            "weapon": "spear",
            "raw_hit": spear_damage,
            "cooldown": 1.2,
            "expected_hit": spear_damage * melee_expected_crit,
            "notes": "Scene defaults differ, but current soldier stat sync tends to flatten melee-slot damage.",
        },
        {
            "weapon": "trident",
            "raw_hit": trident_damage,
            "cooldown": 1.6,
            "expected_hit": trident_damage * melee_expected_crit,
            "notes": "Higher scene default exists, but current soldier stat sync tends to flatten melee-slot damage.",
        },
        {
            "weapon": "harpoon",
            "raw_hit": harpoon_damage,
            "cooldown": 1.1,
            "expected_hit": harpoon_damage * harpoon_expected_crit,
            "notes": "Gets higher crit expectation than other melee variants.",
        },
        {
            "weapon": "bow",
            "raw_hit": bow_damage,
            "cooldown": 2.0,
            "expected_hit": bow_damage,
            "notes": "No crit in current projectile path; ranged cover applies on target side.",
        },
        {
            "weapon": "repeating_crossbow",
            "raw_hit": bow_damage,
            "cooldown": 2.0,
            "expected_hit": bow_damage * 3.0,
            "notes": f"Current soldier sync can overwrite per-bolt base damage. Intended upgrade base hit starts near {repeater_upgrade_damage:.1f}.",
        },
        {
            "weapon": "singigeon",
            "raw_hit": singigeon_base_damage * singigeon_personnel_mult,
            "cooldown": 5.0,
            "expected_hit": singigeon_base_damage * singigeon_personnel_mult,
            "notes": "Personnel splash specialist; value shown is direct personnel hit before splash falloff.",
        },
    ]

    print("Soldier Balance Report")
    print(f"- base health: {base_health:.1f}")
    print(f"- effective health: {effective_health:.1f}")
    print(f"- effective attack stat: {effective_attack:.1f}")
    print(f"- effective defense stat: {effective_defense:.1f}")
    print(
        "- assumptions: "
        f"meta_health={args.meta_crew_health}, meta_attack={args.meta_crew_attack}, meta_defense={args.meta_crew_defense}, "
        f"run_attack={args.run_crew_attack}, run_defense={args.run_crew_defense}"
    )
    print()
    print("weapon                  hit    hit_vs_def  hit_vs_def_cover  dps    ttk    ttk_cover")
    for row in rows:
        expected_hit = row["expected_hit"]
        hit_vs_def = damage_after_defense(expected_hit, target_defense, 0.0)
        hit_vs_def_cover = damage_after_defense(expected_hit, target_defense, ranged_cover)
        dps = hit_vs_def / row["cooldown"]
        dps_cover = hit_vs_def_cover / row["cooldown"]
        print(
            f"{row['weapon']:<22}"
            f"{fmt_float(expected_hit):>6}  "
            f"{fmt_float(hit_vs_def):>10}  "
            f"{fmt_float(hit_vs_def_cover):>16}  "
            f"{fmt_float(dps):>5}  "
            f"{fmt_float(ttk(effective_health, dps)):>5}  "
            f"{fmt_float(ttk(effective_health, dps_cover)):>9}"
        )
    print()
    print("Notes")
    for row in rows:
        print(f"- {row['weapon']}: {row['notes']}")
    print("- cover column is only meaningful for ranged damage sources, but is printed consistently for quick comparison.")
    print("- spear/trident/harpoon scene defaults are not always the final applied damage, because soldier stat sync can overwrite melee-slot damage values.")
    print("- repeating_crossbow and singigeon also mix role-specific stats with owner stat sync, so intended JSON values and effective runtime values can diverge.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
