extends Resource
class_name NoiseSettings

## Controls the Perlin/Simplex noise field used to bend terrain layer boundaries
## into organic blobs instead of flat rows. Lower frequency = bigger areas.

@export var noise_type: FastNoiseLite.NoiseType = FastNoiseLite.TYPE_PERLIN
@export var frequency: float = 0.025
@export var fractal_octaves: int = 3
@export var fractal_lacunarity: float = 2.0
@export var fractal_gain: float = 0.5

## How many cells of depth-distortion the noise applies to layer boundaries.
## 0 = no blobbiness, flat depth bands. Higher = patchier, more "next material poking through".
@export var warp_amount: float = 45.0
