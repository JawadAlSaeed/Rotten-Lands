class_name AttackHitData
extends Resource
## One hit inside an enemy attack.

enum Kind {
	## Dodge or parry it.
	NORMAL,
	## A shockwave along the floor. Only a jump avoids it.
	GROUND,
}

## When the hit lands, in milliseconds after the attack starts (scaled by tuning attack_tempo_percent).
@export_range(0, 20000, 1, "suffix:ms") var impact_ms: int = 1000
@export var kind: Kind = Kind.NORMAL
## Damage, in percent of the enemy's power.
@export_range(0, 1000, 5, "suffix:%") var damage_percent: int = 100
## Normal hits: how long the visible lunge into the target lasts, ending at impact.
## Ground hits: how long the shockwave travels before reaching the party.
@export_range(50, 3000, 1, "suffix:ms") var approach_ms: int = 200
## Fake-out: the enemy starts a lunge early, stops, and holds before the real one.
@export var feint: bool = false
## Sound cue played if the hit connects.
@export var impact_sfx: String = "hurt"
