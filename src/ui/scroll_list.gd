class_name ScrollList
extends ScrollContainer
## A vertical list that scrolls when dragged from anywhere on it.
##
## On a touch screen the engine scrolls a ScrollContainer only if the drag
## reaches it, and any control whose mouse filter is STOP keeps the touch to
## itself. Every button is STOP, and so is every PanelContainer - which is what
## list rows are made of - so a stock list only moves when the finger happens to
## start in the gap between two rows. (A mouse wheel is exempt from the filter,
## which is why the lists scrolled on a Mac and not on a phone.)
##
## This list opens everything placed inside it to PASS: the row or button still
## gets the touch, and so does the list. Once the finger has travelled past the
## deadzone the engine tells buttons to forget the press, so a swipe that starts
## on a BUY button scrolls and buys nothing, while a tap still buys.

## How far a touch may move, in viewport units (the design width is 720),
## before it is a scroll and no longer a tap. A real fingertip wobbles a few
## units between touching down and lifting; without this every such tap on a
## button inside the list would be thrown away.
const DEADZONE := 18


func _init() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_deadzone = DEADZONE
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func _enter_tree() -> void:
	# Rows are rebuilt whenever a screen refreshes, so this has to keep up with
	# whatever is added later, at any depth, not just what is here now.
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	open_all()


func _exit_tree() -> void:
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is Control and is_ancestor_of(node):
		_open(node)


## Lets drags through everything currently inside the list.
func open_all() -> void:
	_open_below(self)


func _open_below(node: Node) -> void:
	for child in node.get_children(true):
		if child is Control:
			_open(child)
		_open_below(child)


func _open(control: Control) -> void:
	# Sliders (and this list's own scroll bars) and text fields need the whole
	# drag for themselves.
	if control is Range or control is LineEdit or control is TextEdit:
		return
	if control.mouse_filter == Control.MOUSE_FILTER_STOP:
		control.mouse_filter = Control.MOUSE_FILTER_PASS


## Controls inside the list that would still swallow a drag. Empty when the
## list is healthy; tests use it to check every screen.
func blockers() -> Array[Control]:
	var found: Array[Control] = []
	_collect_blockers(self, found)
	return found


func _collect_blockers(node: Node, into: Array[Control]) -> void:
	for child in node.get_children(true):
		var control := child as Control
		if control != null and control.mouse_filter == Control.MOUSE_FILTER_STOP \
				and not (control is Range or control is LineEdit or control is TextEdit):
			into.append(control)
		_collect_blockers(child, into)
