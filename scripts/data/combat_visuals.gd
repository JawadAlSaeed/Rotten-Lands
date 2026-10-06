class_name CombatVisuals
extends Resource
## Presentation-only data for the combat scene: effect, stage and UI art paths, the stage layout
## and animation feel. Nothing here changes rules or defence judging (those live in tuning.tres).
## Edit data/presentation/combat_visuals.tres. Replace art by overwriting the file at a path.

@export_group("Effect art")
## Star burst for parries (16x16, transparent background).
@export_file_path("*.png") var spark_path: String = "res://assets/sprites/fx/spark.png"
## Crest of a ground wave (64x16, transparent background).
@export_file_path("*.png") var shockwave_path: String = "res://assets/sprites/fx/shockwave.png"
## Soft dark ellipse drawn under every fighter (32x12).
@export_file_path("*.png") var shadow_path: String = "res://assets/sprites/fx/shadow.png"
## White arc shown when a party member strikes (32x32).
@export_file_path("*.png") var slash_path: String = "res://assets/sprites/fx/slash.png"

@export_group("Stage art")
## Seamlessly tileable floor (32x32).
@export_file_path("*.png") var floor_tile_path: String = "res://assets/sprites/env/floor_tile.png"
## Far background silhouettes (320x120, transparent background).
@export_file_path("*.png") var backdrop_path: String = "res://assets/sprites/env/backdrop.png"

@export_group("UI art")
## Padlock shown over the party during a whiff lockout (12x12).
@export_file_path("*.png") var lock_icon_path: String = "res://assets/sprites/ui/lock.png"
## Filled AP gem (10x10).
@export_file_path("*.png") var ap_pip_path: String = "res://assets/sprites/ui/ap_pip.png"
## Empty AP gem (10x10).
@export_file_path("*.png") var ap_pip_empty_path: String = "res://assets/sprites/ui/ap_pip_empty.png"

@export_group("Stage layout")
## Where each party slot stands (feet). Keep them on one straight line: ground waves travel with
## a front parallel to that line so they reach everyone at the same moment.
@export var party_positions: Array[Vector3] = [Vector3(-2.1, 0.0, -1.5), Vector3(-2.9, 0.0, 0.0), Vector3(-3.7, 0.0, 1.5)]
## Where each enemy slot stands (feet).
@export var enemy_positions: Array[Vector3] = [Vector3(3.0, 0.0, 0.0), Vector3(4.2, 0.0, 1.6), Vector3(4.2, 0.0, -1.6)]
## True if the character sheets are drawn facing right (the party faces right, toward the enemy).
@export var party_art_faces_right: bool = true
## True if the enemy sheets are drawn facing left (the enemy faces left, toward the party).
@export var enemy_art_faces_left: bool = true
@export var camera_position: Vector3 = Vector3(0.8, 3.4, 10.0)
@export var camera_target: Vector3 = Vector3(0.0, 1.0, 0.0)
## Vertical field of view in degrees.
@export_range(10.0, 100.0, 0.5) var camera_fov: float = 40.0
## Width and depth of the floor plane in world units.
@export_range(4.0, 200.0, 0.5) var floor_size: float = 48.0
## World size of one floor tile.
@export_range(0.1, 10.0, 0.05) var floor_tile_world_size: float = 1.6
@export var backdrop_position: Vector3 = Vector3(0.0, 0.0, -13.0)
## World units per backdrop pixel.
@export_range(0.001, 1.0, 0.001) var backdrop_pixel_size: float = 0.1
## World units per pixel for sparks, slashes and shockwaves.
@export_range(0.001, 0.2, 0.001) var fx_pixel_size: float = 0.045
## Width of the shadow blob under each fighter, as a fraction of the sprite frame width.
@export_range(0.05, 3.0, 0.05) var shadow_width_factor: float = 0.85
## How far in front of the target an enemy lunge connects (world units).
@export_range(0.1, 6.0, 0.05) var contact_gap: float = 1.6
## How far in front of the enemy a party member strikes (world units).
@export_range(0.1, 6.0, 0.05) var strike_gap: float = 1.5
## Height of popups and lock icons above a fighter's feet, as a fraction of the sprite height.
@export_range(0.0, 2.0, 0.05) var head_height_factor: float = 1.05

@export_group("Environment")
@export var background_color: Color = Color(0.05, 0.055, 0.075)
@export var ambient_color: Color = Color(0.32, 0.34, 0.42)
@export_range(0.0, 4.0, 0.05) var ambient_energy: float = 0.7
@export var fog_color: Color = Color(0.16, 0.18, 0.24)
@export_range(0.0, 0.3, 0.001) var fog_density: float = 0.025
@export var light_color: Color = Color(1.0, 0.92, 0.82)
@export_range(0.0, 8.0, 0.05) var light_energy: float = 1.1
## Directional light rotation (pitch, yaw, roll) in degrees.
@export var light_rotation_degrees: Vector3 = Vector3(-55.0, -30.0, 0.0)

@export_group("Enemy choreography")
## A feint starts its false lunge this long before the real lunge.
@export_range(0, 2000, 1, "suffix:ms") var feint_lead_ms: int = 350
## How much of a normal lunge the false start plays before it stops, in percent of approach time.
@export_range(10, 90, 1, "suffix:%") var feint_portion_percent: int = 60
## The enemy holds its contact pose this long after a hit.
@export_range(0, 1000, 1, "suffix:ms") var contact_hold_ms: int = 90
## Between hits the enemy recoils back over this long.
@export_range(0, 1000, 1, "suffix:ms") var recoil_ms: int = 120
## How far it recoils, in percent of the distance between home and the contact point.
@export_range(0, 100, 1, "suffix:%") var recoil_percent: int = 35
## After the last hit the enemy walks home over this long.
@export_range(0, 2000, 1, "suffix:ms") var return_ms: int = 260
## The slam pose is held this long when a ground wave is launched.
@export_range(0, 2000, 1, "suffix:ms") var slam_hold_ms: int = 260
## Length of the telegraph flash when a lunge starts.
@export_range(0, 1000, 1, "suffix:ms") var telegraph_flash_ms: int = 90
## Strength of the telegraph flash (0 to 1).
@export_range(0.0, 1.0, 0.05) var telegraph_flash_strength: float = 0.55
## The wave keeps travelling past the party for this share of its approach, fading out.
@export_range(0, 100, 1, "suffix:%") var wave_overshoot_percent: int = 25
## Number of crest sprites that make up one wave front.
@export_range(1, 12) var wave_crest_count: int = 5
## Shortest distance a wave travels (world units), even if the enemy slams up close.
@export_range(0.1, 10.0, 0.05) var wave_min_travel: float = 2.0
## How far the wave front extends past the outer party members (world units).
@export_range(0.0, 5.0, 0.05) var wave_line_margin: float = 0.8
## Glow colour of the enemy wind-up.
@export var windup_glow_color: Color = Color(1.0, 0.45, 0.2)

@export_group("Party defence poses")
## Parry stance lasts at least this long (and at least until the parry window closes).
@export_range(0, 2000, 1, "suffix:ms") var parry_pose_min_ms: int = 150
## Dodge pose lasts at least this long (and at least until the dodge window closes).
@export_range(0, 2000, 1, "suffix:ms") var dodge_pose_min_ms: int = 250
## How far a dodge slides back (world units).
@export_range(0.0, 3.0, 0.05) var dodge_slide_distance: float = 0.75
## Total time in the air for a jump.
@export_range(100, 2000, 1, "suffix:ms") var jump_airtime_ms: int = 480
## Shortest rise from take-off to the apex (the apex sits at impact when the press is early enough).
@export_range(20, 1000, 1, "suffix:ms") var jump_rise_min_ms: int = 120
## Jump height (world units).
@export_range(0.1, 5.0, 0.05) var jump_height: float = 1.3
## A failed press shows its pose for this long.
@export_range(0, 2000, 1, "suffix:ms") var whiff_pose_ms: int = 260
## Flinch after a hit lands.
@export_range(0, 2000, 1, "suffix:ms") var hurt_pose_ms: int = 320
## Flinch knock-back distance (world units).
@export_range(0.0, 2.0, 0.05) var hurt_knockback: float = 0.35
## White flash length on parries and hits.
@export_range(0, 1000, 1, "suffix:ms") var flash_ms: int = 120
## Volume change of the muted click for a press during lockout.
@export_range(-40.0, 0.0, 0.5, "suffix:dB") var locked_click_volume_db: float = -10.0

@export_group("Effects")
@export_range(0, 32) var sparks_per_parry: int = 8
## How far sparks fly (world units).
@export_range(0.0, 5.0, 0.05) var spark_spread: float = 1.1
@export_range(10, 2000, 1, "suffix:ms") var spark_ms: int = 280
@export_range(10, 2000, 1, "suffix:ms") var slash_ms: int = 220
## Scale of the slash sprite.
@export_range(0.1, 10.0, 0.05) var slash_scale: float = 2.2

@export_group("Camera feel")
## Screen shake when a hit lands on the party (world units, decays over the duration).
@export_range(0.0, 2.0, 0.01) var shake_hurt: float = 0.12
@export_range(0, 2000, 1, "suffix:ms") var shake_hurt_ms: int = 200
## Small shake on a parry.
@export_range(0.0, 2.0, 0.01) var shake_parry: float = 0.05
@export_range(0, 2000, 1, "suffix:ms") var shake_parry_ms: int = 120
## Camera punch-in on a parry (world units toward the target).
@export_range(0.0, 5.0, 0.05) var punch_parry: float = 0.35
## Bigger punch-in on the parry of the last hit.
@export_range(0.0, 5.0, 0.05) var punch_parry_final: float = 0.8
## Shake and punch when a counter or a strike lands.
@export_range(0.0, 2.0, 0.01) var shake_counter: float = 0.16
@export_range(0, 2000, 1, "suffix:ms") var shake_counter_ms: int = 220
@export_range(0.0, 5.0, 0.05) var punch_counter: float = 0.9
@export_range(0.0, 2.0, 0.01) var shake_strike: float = 0.06
@export_range(0, 2000, 1, "suffix:ms") var shake_strike_ms: int = 140
## How long a punch-in takes to settle back.
@export_range(10, 2000, 1, "suffix:ms") var punch_ms: int = 220

@export_group("HUD")
## How far popups float up while fading (pixels at 1080p).
@export_range(0.0, 400.0, 1.0) var popup_rise_px: float = 70.0
## Training ring radius when it appears and when it closes (pixels at 1080p).
@export_range(4.0, 600.0, 1.0) var ring_start_radius_px: float = 150.0
@export_range(0.0, 200.0, 1.0) var ring_end_radius_px: float = 22.0
@export_range(1.0, 30.0, 0.5) var ring_width_px: float = 6.0
## Portrait size on the timeline (pixels at 1080p).
@export_range(8.0, 256.0, 1.0) var portrait_px: float = 56.0
## AP gem size (pixels at 1080p).
@export_range(4.0, 64.0, 1.0) var ap_pip_px: float = 22.0
## Lock icon size (pixels at 1080p).
@export_range(4.0, 128.0, 1.0) var lock_icon_px: float = 40.0

@export_group("Calibration")
## Time between calibration beats.
@export_range(200, 3000, 1, "suffix:ms") var calibration_interval_ms: int = 750
@export_range(2, 64) var calibration_beats: int = 12
## The result is the median of this many of the last presses.
@export_range(1, 64) var calibration_sample_count: int = 8
## Fewest presses needed before a calibration can be saved.
@export_range(1, 64) var calibration_min_presses: int = 4
## Pause before the first beat.
@export_range(0, 5000, 1, "suffix:ms") var calibration_lead_ms: int = 1500
## How long the circle stays lit on each beat.
@export_range(10, 1000, 1, "suffix:ms") var calibration_flash_ms: int = 120
