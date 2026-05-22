#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SOLDIER_RULES_PATH = ROOT / "data" / "soldier_rules.json"
UPGRADES_PATH = ROOT / "data" / "upgrades.json"
ATTACK_COOLDOWN_TEMPO_MULT = 1.12


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
    parser.add_argument("--soldier-level", type=int, default=1, help="Assumed player soldier personal level.")
    parser.add_argument("--repeating-crossbow-level", type=int, default=1, help="Assumed repeating_crossbow specialist upgrade level.")
    args = parser.parse_args()

    soldier_rules = load_json(SOLDIER_RULES_PATH)
    upgrades_root = load_json(UPGRADES_PATH)
    upgrades = upgrades_root["upgrades"]

    base = soldier_rules["base"]
    run_damage_bonus_per_level = float(upgrades["crew_attack"]["stats"].get("damage_bonus_pct_per_lv", 0.06))
    crew_defense_add = float(upgrades["crew_defense"]["stats"].get("defense_add_per_lv", 1.0))

    base_health = float(base["max_health"])
    base_attack = float(base["attack_damage"])
    base_defense = float(base["defense"])
    crit_chance = float(base["crit_chance"])
    crit_multiplier = float(base["crit_multiplier"])

    soldier_level_bonus_by_level = {
        1: 0.0,
        2: 0.08,
        3: 0.16,
        4: 0.25,
        5: 0.35,
    }
    soldier_level = max(1, min(5, args.soldier_level))
    meta_health_mult = 1.0 + (args.meta_crew_health * 0.12)
    meta_damage_bonus = args.meta_crew_attack * 0.04
    soldier_level_damage_bonus = soldier_level_bonus_by_level[soldier_level]
    meta_defense_bonus = args.meta_crew_defense * 1.0
    run_damage_bonus = args.run_crew_attack * run_damage_bonus_per_level
    run_defense_bonus = args.run_crew_defense * crew_defense_add
    total_damage_bonus = max(0.0, meta_damage_bonus + run_damage_bonus + soldier_level_damage_bonus)

    effective_health = base_health * meta_health_mult
    effective_defense = base_defense + meta_defense_bonus + run_defense_bonus

    melee_expected_crit = expected_crit_multiplier(crit_chance, crit_multiplier)
    harpoon_expected_crit = expected_crit_multiplier(crit_chance + 0.15, 2.5)

    # Mirror the current code-facing formula: weapon base damage * one summed bonus.
    sword_damage = 8.0 * (1.0 + total_damage_bonus)
    spear_damage = 10.0 * (1.0 + total_damage_bonus)
    trident_damage = 10.0 * (1.0 + total_damage_bonus)
    harpoon_damage = 12.0 * (1.0 + total_damage_bonus)
    bow_damage = 8.0 * (1.0 + total_damage_bonus)

    repeating_crossbow_level = max(1, args.repeating_crossbow_level)
    repeating_stats = upgrades["repeating_crossbow"]["stats"]
    repeater_upgrade_damage = (
        float(repeating_stats.get("base_damage", 7.0))
        + max(0, repeating_crossbow_level - 1) * float(repeating_stats.get("damage_per_lv", 1.0))
    )
    repeater_burst_count = 3
    if repeating_crossbow_level >= 3:
        repeater_burst_count = 4
    repeater_cooldown = float(repeating_stats.get("base_cooldown", 2.2)) - max(0, repeating_crossbow_level - 1) * float(repeating_stats.get("cooldown_reduce_per_lv", 0.05))
    repeater_burst_delay = float(repeating_stats.get("burst_delay", 0.15))
    repeater_cooldown = max(repeater_cooldown, repeater_burst_count * repeater_burst_delay + 0.5)
    repeater_cooldown *= ATTACK_COOLDOWN_TEMPO_MULT
    repeater_damage = repeater_upgrade_damage * (1.0 + total_damage_bonus)
    singigeon_base_damage = float(upgrades["singigeon"]["stats"].get("base_damage", 12.0))
    singigeon_personnel_mult = float(upgrades["singigeon"]["stats"].get("personnel_damage_mult", 1.0))
    singigeon_personnel_damage = singigeon_base_damage * singigeon_personnel_mult * (1.0 + total_damage_bonus)

    target_defense = effective_defense
    ranged_cover = 0.20

    rows = [
        {
            "weapon": "sword",
            "raw_hit": sword_damage,
            "cooldown": 1.0 * ATTACK_COOLDOWN_TEMPO_MULT,
            "expected_hit": sword_damage * melee_expected_crit,
            "notes": "General melee baseline using weapon base damage plus the summed damage bonus.",
        },
        {
            "weapon": "spear",
            "raw_hit": spear_damage,
            "cooldown": 1.2 * ATTACK_COOLDOWN_TEMPO_MULT,
            "expected_hit": spear_damage * melee_expected_crit,
            "notes": "Longer reach baseline using the spear/trident base damage.",
        },
        {
            "weapon": "trident",
            "raw_hit": trident_damage,
            "cooldown": 1.6 * ATTACK_COOLDOWN_TEMPO_MULT,
            "expected_hit": trident_damage * melee_expected_crit,
            "notes": "Spear-family heavy cadence variant using the same base hit with a slower cooldown.",
        },
        {
            "weapon": "harpoon",
            "raw_hit": harpoon_damage,
            "cooldown": 1.1 * ATTACK_COOLDOWN_TEMPO_MULT,
            "expected_hit": harpoon_damage * harpoon_expected_crit,
            "notes": "Gets higher crit expectation than other melee variants.",
        },
        {
            "weapon": "bow",
            "raw_hit": bow_damage,
            "cooldown": 2.0 * ATTACK_COOLDOWN_TEMPO_MULT,
            "expected_hit": bow_damage,
            "notes": "No crit in current projectile path; ranged cover applies on target side.",
        },
        {
            "weapon": "repeating_crossbow",
            "raw_hit": repeater_damage,
            "cooldown": repeater_cooldown,
            "expected_hit": repeater_damage * repeater_burst_count,
            "notes": f"Current per-bolt base hit is {repeater_upgrade_damage:.1f} at level {repeating_crossbow_level}, with {repeater_burst_count} bolts per burst before the summed damage bonus.",
        },
        {
            "weapon": "singigeon",
            "raw_hit": singigeon_personnel_damage,
            "cooldown": 5.0 * ATTACK_COOLDOWN_TEMPO_MULT,
            "expected_hit": singigeon_personnel_damage,
            "notes": "Personnel splash specialist; value shown is direct personnel hit before splash falloff.",
        },
    ]

    print("Soldier Balance Report")
    print(f"- base health: {base_health:.1f}")
    print(f"- effective health: {effective_health:.1f}")
    print(f"- weapon damage bonus: {total_damage_bonus * 100.0:.1f}%")
    print(f"- effective defense stat: {effective_defense:.1f}")
    print(
        "- assumptions: "
        f"meta_health={args.meta_crew_health}, meta_attack={args.meta_crew_attack}, meta_defense={args.meta_crew_defense}, "
        f"run_attack={args.run_crew_attack}, run_defense={args.run_crew_defense}, "
        f"soldier_level={soldier_level}, "
        f"repeating_crossbow_level={repeating_crossbow_level}"
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
    print("- weapon families preserve role-specific base damage and apply one summed damage bonus from soldier level, meta upgrades, and run upgrades.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
