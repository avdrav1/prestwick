class_name FeedTuning
extends Resource
## Designer-tuned numbers for the guests' feed and map tags (E3-S7; scenes/feed_panel.gd,
## scenes/reaction_tags.gd, guests/reaction_feed.gd). Loaded from res://scenes/feed_tuning.tres.
## How many reactions a map tag counts is `rating_window` in data/guests.json (D39).

const PATH: String = "res://scenes/feed_tuning.tres"

## Lines the feed shows at once, newest at the top; older lines scroll off the bottom.
@export var visible_rows: int = 5
## A burst (several guests finishing in one step) comes in one line at a time, at most one a
## this many real seconds, so the list never jumps by more than one row at once. A backlog of
## more than visible_rows lines shows at once (the older ones would only scroll past).
@export var reveal_interval_s: float = 0.4
## The newest line is drawn highlighted for this many real seconds after it comes in.
@export var highlight_s: float = 1.5
## The feed's width, screen px (a line wraps to it; the longest, 140 characters, takes 3 lines).
@export var width: float = 300.0
## Lines a row is given room for: the panel keeps the height of `visible_rows` rows of this
## many lines, so it never grows over the map as lines come in (the longest line takes 3).
@export var row_lines: int = 3
## Font size of a line, px.
@export var font_size: int = 13
## E3-S68: the alpha a line draws at once its hole has been edited since it was given
## (ReactionFeed.Entry.edited), so an old verdict on a fixed hole reads as history.
@export var edited_alpha: float = 0.45
## A map tag whose box covers a guest figure drawn now draws at this alpha (E3-S63), so the
## golfers it talks about show through it; hovered, it draws in full.
@export_range(0.0, 1.0) var tag_covered_alpha: float = 0.3
## Lines the feed keeps (ReactionFeed.max_entries).
@export var max_entries: int = 100


static func load_default() -> FeedTuning:
	return load(PATH) as FeedTuning
