class_name TopoTuning
extends Resource
## Designer-tuned numbers for the course-wide contour overlay in Play (E3-S57,
## course/topo_overlay.gd). Loaded from res://course/topo_tuning.tres.

const PATH: String = "res://course/topo_tuning.tres"

## A line every `interval` steps, counted from `offset`. At 0.5 (E3-S59) each line runs along the
## middle of the slopes it crosses, where the drawn ground is at that level; at 0 every whole
## step, each line along its terrace's falling edge through the edge tiles' centres
## (ContourTracer), which outlined the terraces while the ground was drawn as terraces (E3-S57).
@export var interval: float = 1.0
@export var offset: float = 0.5
## Sub-cells a side per tile-centre cell (ContourTracer subdiv).
@export var subdiv: int = 2
## Ink line width and its chalk halo's, screen px at every zoom, and the ink's opacity.
@export var line_width_px: float = 2.0
@export var halo_width_px: float = 0.0
@export var line_alpha: float = 0.8
## Downhill ticks on each line's low side: one every `tick_spacing_px` along it, about
## `tick_length_px` long, screen px (ticks are laid out again only when the zoom changes).
@export var tick_spacing_px: float = 36.0
@export var tick_length_px: float = 5.0
## Tiles traced past the visible window on every side, so the camera can move that far before
## the overlay traces again.
@export var margin_tiles: int = 24


static func load_default() -> TopoTuning:
	return load(PATH) as TopoTuning
