class_name MenuNav
extends RefCounted
## Keyboard / gamepad / mouse navigation helpers shared by every menu.
##
## Rules they enforce: (1) one highlight only, since the mouse moves the focus to the control it enters
## (the themes draw no separate hover style); (2) arrows follow explicit neighbours instead of Godot's
## geometric guess, so focus never jumps to a control of another menu or page drawn behind and never
## wraps around at an edge.


## Makes `control` take the focus when the mouse enters it (once per control).
static func hover_focus(control: Control) -> void:
	if control.has_meta(&"hover_focus"):
		return
	control.set_meta(&"hover_focus", true)
	control.mouse_entered.connect(_on_hover.bind(control))


static func _on_hover(control: Control) -> void:
	if not is_instance_valid(control) or not control.is_visible_in_tree() or control.has_focus():
		return
	if control.focus_mode == Control.FOCUS_NONE:
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	control.grab_focus()


## Up / down walk the list in order; left / right and the two ends keep the focus where it is.
static func link_vertical(controls: Array) -> void:
	for i in controls.size():
		var c: Control = controls[i]
		hover_focus(c)
		var up: Control = controls[maxi(i - 1, 0)]
		var down: Control = controls[mini(i + 1, controls.size() - 1)]
		c.focus_neighbor_top = c.get_path_to(up)
		c.focus_neighbor_bottom = c.get_path_to(down)
		c.focus_neighbor_left = c.get_path_to(c)
		c.focus_neighbor_right = c.get_path_to(c)


## Controls under `node` that can take the focus right now (enabled, FOCUS_ALL), in tree order.
static func focusables(node: Node) -> Array[Control]:
	var out: Array[Control] = []
	if node is Control:
		var c := node as Control
		if c.focus_mode == Control.FOCUS_ALL and not (c is BaseButton and (c as BaseButton).disabled):
			out.append(c)
	for child in node.get_children():
		out.append_array(focusables(child))
	return out


static func link(from: Control, side: Side, to: Control) -> void:
	var path := from.get_path_to(to)
	match side:
		SIDE_LEFT:
			from.focus_neighbor_left = path
		SIDE_TOP:
			from.focus_neighbor_top = path
		SIDE_RIGHT:
			from.focus_neighbor_right = path
		SIDE_BOTTOM:
			from.focus_neighbor_bottom = path
