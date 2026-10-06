class_name EnemyAttackData
extends Resource
## An enemy move: who it targets and the hits it is made of.

enum TargetMode {
	## One party member (named in the banner).
	SINGLE,
	## The whole party.
	PARTY,
}

## Unique id used in events and save data.
@export var id: String = ""
@export var display_name: String = ""
@export var target_mode: TargetMode = TargetMode.SINGLE
## How likely the enemy is to pick this move compared to its other moves.
@export_range(0, 100) var weight: int = 1
## Play the alert sound when the attack starts.
@export var alert_cue: bool = true
## Allow the training ring on this attack (turn off for feints).
@export var allow_timing_ring: bool = true
## Hits in the order they land. Impact times must increase.
@export var hits: Array[AttackHitData] = []
