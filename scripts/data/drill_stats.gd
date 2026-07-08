extends Resource
class_name DrillStats

## Tunable stats for the drill, as a data-only resource (data/drill_stats.tres). Edit these
## in the Inspector to change how the drill performs and feels. Referenced by DrillController.

@export var power: float = 5.0            ## Max material hardness this drill can break through.
@export var max_drag_force: float = 400.0 ## Max input vector magnitude from a click-drag.
@export var acceleration: float = 600.0   ## How fast velocity eases toward the target.
@export var maneuverability: float = 3.0  ## Higher = more responsive turning; lower = heavier/sluggish feel.
@export var max_speed: float = 220.0

## Hitting material too hard to break bounces the drill backward instead of just stopping.
@export var knockback_force: float = 150.0
@export var knockback_duration: float = 0.18 ## How long the bounce-back lasts, in seconds.
@export var hit_flash_duration: float = 0.08 ## How long the "hit" animation shows before "drill" takes over for the rest of the bounce.

## Sprite shake (pixels, perpendicular to the drill axis) while actively boring through solid material.
@export var vibration_amp: float = 1.0
