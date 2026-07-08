extends RefCounted
class_name TerrainNoise

## Thin wrapper around FastNoiseLite, configured from a NoiseSettings resource.
## Used by WorldGenerator to "warp" the depth coordinate before picking a base
## material, which bends layer boundaries into organic blobs instead of flat rows.

var warp_amount: float
var _noise: FastNoiseLite

func _init(settings: NoiseSettings, seed_value: int) -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = seed_value
	_noise.noise_type = settings.noise_type
	_noise.frequency = settings.frequency
	_noise.fractal_octaves = settings.fractal_octaves
	_noise.fractal_lacunarity = settings.fractal_lacunarity
	_noise.fractal_gain = settings.fractal_gain
	warp_amount = settings.warp_amount

## Depth value to use for layer selection at (x, y), distorted by the noise field
## so a material's region grows/shrinks/bulges into organic shapes rather than a
## straight horizontal band.
func warped_depth(x: int, y: int) -> float:
	return float(y) + _noise.get_noise_2d(float(x), float(y)) * warp_amount
