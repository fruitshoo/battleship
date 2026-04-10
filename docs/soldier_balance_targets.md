# Soldier Balance Targets

This note is a working baseline for soldier combat tuning.
It is not a final balance sheet. The goal is to define stable targets first,
then tune values to those targets with harnesses and reports.

## Design Goals

- Boarding should be dangerous, but not instantly decisive.
- Ranged units should soften or disrupt before contact, not outperform melee in straight deck fights.
- Melee should win at close range, but not erase ranged identity.
- Meta progression and run upgrades should improve player crew without collapsing enemy threat too early.
- Role differences should come from reliable tradeoffs, not from hidden script-order side effects.

## Role Targets

- `general`
  Flexible baseline unit. Should be acceptable at range and in melee, but best at neither.
- `spearman`
  Anti-boarding and reach control. Better than general in sustained melee, weaker in ranged pressure.
- `repeating_crossbow`
  Anti-personnel suppression. Good sustained pressure, lower burst per bolt, poor in melee.
- `singigeon`
  Specialist burst and area denial. Slow cadence, high swing value, low reliability versus single moving targets.
- `fire_pot`
  Close-range area disruption. High local impact, but positional and cooldown constrained.
- `captain`
  Small elite multiplier, not a solo carry.

## Target TTK Bands

These are rough target bands against a standard non-captain soldier with no temporary buffs.

- `general melee vs general`: 7.0s to 9.0s
- `general ranged vs general on open deck`: 10.0s to 13.0s
- `general ranged vs general under cover`: 12.0s to 16.0s
- `spearman vs general in melee`: 6.5s to 8.0s
- `repeating_crossbow vs general at safe range`: 8.5s to 11.0s
- `captain vs general in melee`: 4.5s to 6.0s
- `two generals focus-firing one general`: 3.5s to 5.0s

## Upgrade Curve Targets

- Run upgrade max should not more than double base crew lethality.
- Defense should extend TTK, but should not invalidate ranged damage.
- Meta upgrades should be lower-impact than run upgrades on a per-level basis.
- If both meta and run upgrades stack on the same axis, their combined effect should be explicitly capped or offset elsewhere.

## Current Risks To Watch

- Flat defense plus ranged cover can suppress ranged damage too hard.
- Melee slot weapons currently tend to converge toward the same attack value, reducing role distinction.
- Specialist ranged weapons have mixed stat sources, so the effective damage curve can differ from the intended JSON values.
- Player crew progression stacks both meta and run bonuses, which can collapse enemy threat in longer runs.

## Tooling

- `python3 scripts/dev/soldier_balance_report.py`
  Prints a current-balance summary and rough TTK estimates from the code-facing data.
- `python3 scripts/dev/soldier_balance_report.py --meta-crew-health 3 --meta-crew-attack 2 --meta-crew-defense 2`
  Useful for checking how progression shifts the bands.
