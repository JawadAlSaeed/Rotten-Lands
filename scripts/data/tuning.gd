class_name Tuning
extends Resource
## Every global timing and balance number in the game.
## Edit the values in data/tuning/tuning.tres (double-click it in the editor's FileSystem panel;
## the values appear in the Inspector, each with a tooltip).
## Per-move numbers (how many hits, when they land, percentages) live in each move's own file and
## are percentages of the values below. Change balance in tuning.tres, not the defaults here.

@export_group("Defence windows")
## Total time you have to land a parry, in milliseconds. Smaller is harder.
@export_range(20, 600, 1, "suffix:ms") var parry_window_ms: int = 150
## Total time you have to land a dodge, in milliseconds. Wider and safer than a parry.
@export_range(20, 800, 1, "suffix:ms") var dodge_window_ms: int = 250
## Total time you have to land a jump over a ground attack, in milliseconds.
@export_range(20, 800, 1, "suffix:ms") var jump_window_ms: int = 220
## How much of each window comes after the moment of impact, in percent.
## 0 = the whole window is before impact, 100 = the whole window is after it.
@export_range(0, 100, 1, "suffix:%") var window_late_percent: int = 35
## After a press that matches nothing (too early, too late, wrong button), your defence buttons
## stop working for this long. Pressing again while locked restarts the lock (stops mashing).
@export_range(0, 2000, 1, "suffix:ms") var whiff_lockout_ms: int = 300
## Default lag compensation, subtracted from every press time to cancel screen and pad lag.
## The calibration (F2 in a fight) measures your own value and overrides this one.
@export_range(-200, 200, 1, "suffix:ms") var input_latency_compensation_ms: int = 30

@export_group("Enemy attack pacing")
## Pause between the attack banner appearing and the attack starting.
@export_range(0, 3000, 1, "suffix:ms") var attack_lead_in_ms: int = 700
## Speed of every enemy attack, in percent of its authored timing. 120 = 20% slower.
@export_range(25, 300, 1, "suffix:%") var attack_tempo_percent: int = 100
## Time after an attack's last hit before the turn moves on (when there is no counter).
@export_range(0, 3000, 1, "suffix:ms") var attack_recover_ms: int = 450
## Freeze on a parry that is not the attack's last hit. Keep it well under the early part of
## the parry window (about 97 ms by default) or rhythm parries on fast strings start failing.
@export_range(0, 200, 1, "suffix:ms") var hitstop_parry_ms: int = 45
## Freeze on a parry of the attack's last hit (right before the counter).
@export_range(0, 500, 1, "suffix:ms") var hitstop_parry_final_ms: int = 110
## Freeze on a successful jump.
@export_range(0, 200, 1, "suffix:ms") var hitstop_jump_ms: int = 40
## Freeze when a hit lands on you, so a string keeps a similar rhythm whether you parry or not.
@export_range(0, 200, 1, "suffix:ms") var hitstop_hurt_ms: int = 50
## Freeze when a counterattack lands.
@export_range(0, 500, 1, "suffix:ms") var hitstop_counter_ms: int = 120
## Delay between the last parry and the counterattack starting.
@export_range(0, 1000, 1, "suffix:ms") var counter_delay_ms: int = 220

@export_group("Timing cues")
## Training aid: a ring that shrinks onto the target and closes exactly at impact.
## Off by default so you learn to read the enemy. Toggle in a fight with F1 > R.
@export var show_timing_ring: bool = false
## How long before impact the ring appears.
@export_range(100, 3000, 1, "suffix:ms") var ring_lead_ms: int = 700
## The enemy flashes when it starts each lunge (a visual cue, not a beat).
@export var show_telegraph_flash: bool = true
## After each defence press, show how early or late it was (for example "LATE +23").
@export var show_timing_feedback: bool = true

@export_group("HP and damage")
## HP of a character at 100% hp.
@export_range(1, 99999) var base_character_hp: int = 100
## HP of an enemy at 100% hp.
@export_range(1, 999999) var base_enemy_hp: int = 1500
## Damage of a party attack when every percentage is 100.
@export_range(1, 99999) var base_party_damage: int = 40
## Damage of one enemy hit when every percentage is 100.
## With 100 HP characters, 28 means 4 normal hits kill and 3 heavy (130%) hits kill.
@export_range(1, 99999) var base_enemy_hit_damage: int = 28
## Random spread on every damage roll, in percent (0 = always the same number).
@export_range(0, 50, 1, "suffix:%") var damage_variance_percent: int = 0
## Counterattack damage, in percent of the countering character's power.
@export_range(0, 1000, 5, "suffix:%") var counter_percent: int = 150
## Team counter: every character strikes together as one hit. Its damage is this percent of
## each character's power, added up. (Raised again for online co-op in phase 5.)
@export_range(0, 1000, 5, "suffix:%") var team_counter_percent: int = 120

@export_group("AP")
## AP each character has when a fight starts.
@export_range(0, 99) var start_ap: int = 1
## Most AP a character can hold.
@export_range(1, 99) var max_ap: int = 9
## AP gained for each successful parry.
@export_range(0, 9) var ap_per_parry: int = 1
## AP gained for each successful jump over a ground attack.
@export_range(0, 9) var ap_per_jump: int = 0

@export_group("Timeline")
## One turn costs timeline_base / speed. Only the ratio between speeds matters.
@export_range(100, 1000000) var timeline_base: int = 10000
## How many upcoming turns the timeline shows.
@export_range(1, 20) var turn_order_preview: int = 8

@export_group("Presentation pacing")
## A character dashing to the enemy before striking.
@export_range(0, 2000, 1, "suffix:ms") var action_dash_ms: int = 180
## Pause on the strike before returning.
@export_range(0, 2000, 1, "suffix:ms") var action_hold_ms: int = 150
## A character returning to their spot.
@export_range(0, 2000, 1, "suffix:ms") var action_return_ms: int = 220
## Short pause between turns.
@export_range(0, 2000, 1, "suffix:ms") var turn_gap_ms: int = 200
## How long damage numbers and result popups stay up.
@export_range(100, 5000, 1, "suffix:ms") var popup_ms: int = 900

@export_group("Practice and debug")
## Phase 1 practice keys: 1-5 force an enemy attack, I = party cannot die,
## O = enemy cannot die, R = restart, F1 = stats overlay, F2 = lag calibration.
@export var practice_tools_enabled: bool = true
## 0 = a new random fight every time. Any other number replays the same enemy choices.
@export var fixed_seed: int = 0


## Window edges in microseconds relative to impact: Vector2i(early (negative), late (positive)).
@warning_ignore("integer_division")
func window_edges_us(window_ms: int) -> Vector2i:
	var total_us: int = window_ms * 1000
	var late_us: int = (total_us * window_late_percent + 50) / 100
	return Vector2i(late_us - total_us, late_us)
