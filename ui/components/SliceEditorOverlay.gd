class_name SliceEditorOverlay
extends Control

const LanguageServerRange = LanguageServerError.ErrorRange


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _gui_input(event: InputEvent) -> void:
	var mm = event as InputEventMouseMotion
	if mm:
		var point = get_local_mouse_position()
		for overlay in get_children():
			overlay = overlay as ErrorOverlay
			if not overlay or not is_instance_valid(overlay):
				continue

			if overlay.try_consume_mouse(point):
				return


func clean() -> void:
	for overlay in get_children():
		overlay.queue_free()


func update_overlays() -> void:
	var text_edit := get_parent() as TextEdit
	if not text_edit:
		return

	for overlay in get_children():
		overlay = overlay as ErrorOverlay
		if not overlay or not is_instance_valid(overlay):
			continue

		overlay.regions = _get_error_range_regions(overlay.error_range, text_edit)


func add_error(error: LanguageServerError) -> ErrorOverlay:
	var text_edit := get_parent() as TextEdit
	if not text_edit:
		return null

	var error_overlay := ErrorOverlay.new()
	error_overlay.severity = error.severity
	error_overlay.error_range = error.error_range
	error_overlay.regions = _get_error_range_regions(error.error_range, text_edit)
	add_child(error_overlay)

	return error_overlay


# FIXME: There seem to be stange behavior around tabs, may be an engine bug with the new methods, need to check.
func _get_error_range_regions(error_range: LanguageServerRange, text_edit: TextEdit) -> Array:
	var regions := []

	# Iterate through the lines of the error range and find the regions for each character
	# span in the line, accounting for line wrapping.
	var line_index := error_range.start.line
	while line_index <= error_range.end.line:
		var line = text_edit.get_line(line_index)
		var region := Rect2(-1, -1, 0, 0)

		# Starting point of the first line is as reported by the LSP. For the following
		# lines it's the first character in the line.
		var char_start : int
		if line_index == error_range.start.line:
			char_start = error_range.start.character
		else:
			char_start = 0

		# Ending point of the last line is as reported by the LSP. For the preceding
		# lines it's the last character in the line.
		var char_end : int
		if line_index == error_range.end.line:
			char_end = error_range.end.character
		else:
			char_end = line.length()

		# Iterate through the characters to find those which are visible in the TextEdit.
		# This also handles wrapping, as characters report different vertical offset when
		# that happens.
		var char_index := char_start
		while char_index <= char_end:
			var char_rect = text_edit.get_rect_at_line_column(line_index, char_index)
			if char_rect.position.x == -1 or char_rect.position.y == -1:
				char_index += 1
				continue

			# If region is empty (first in line), fill it with the first character's data.
			if region.position.x == -1:
				region.position = char_rect.position
				region.size = char_rect.size
			# If the region is on a different vertical offset than the next character, then
			# we hit a wrapping point; store the region and create a new one.
			elif not region.position.y == char_rect.position.y:
				regions.append(region)
				region = Rect2(char_rect.position, char_rect.size)
			# If nothing else, just extend the region horizontal with the size of the next
			# character.
			else:
				region.size.x += char_rect.size.x

			char_index += 1

		# In case we somehow didn't fill a single region with characters.
		if not region.position.x == -1:
			regions.append(region)
		line_index += 1

	return regions


class ErrorOverlay extends Control:
	enum Severity { ERROR, WARNING, NOTICE }

	const COLOR_ERROR := Color("#E83482")
	const COLOR_WARNING := Color("#D2C84F")
	const COLOR_NOTICE := Color("#79F2D6")

	signal region_entered(panel_position)
	signal region_exited

	var severity := -1
	var error_range#: LanguageServerRange
	var regions := [] setget set_regions

	var _lines := []
	var _hovered_region := -1


	func _init() -> void:
		name = "ErrorOverlay"
		rect_min_size = Vector2(0, 0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _ready() -> void:
		set_anchors_and_margins_preset(Control.PRESET_WIDE)


	func try_consume_mouse(point: Vector2) -> bool:
		var region_has_point := -1
		var i := 0
		for region_rect in regions:
			if region_rect.has_point(point):
				region_has_point = i
				break

			i += 1

		if _hovered_region == region_has_point:
			return false

		if _hovered_region == -1 and not region_has_point == -1:
			var panel_position = _lines[i].rect_position
			emit_signal("region_entered", panel_position)
		elif not _hovered_region == -1 and region_has_point == -1:
			emit_signal("region_exited")
		else:
			emit_signal("region_exited")

			var panel_position = _lines[i].rect_position
			emit_signal("region_entered", panel_position)

		_hovered_region = region_has_point
		return true


	func set_regions(error_regions: Array) -> void:
		for underline in _lines:
			underline = underline as ErrorUnderline
			if not underline or not is_instance_valid(underline):
				continue
			remove_child(underline)
			underline.queue_free()

		_lines = []
		regions = []

		for error_region in error_regions:
			var underline := ErrorUnderline.new()

			match severity:
				Severity.ERROR:
					underline.line_type = ErrorUnderline.LineType.JAGGED
					underline.line_color = COLOR_ERROR
				Severity.WARNING:
					underline.line_type = ErrorUnderline.LineType.SQUIGGLY
					underline.line_color = COLOR_WARNING
				_:
					underline.line_type = ErrorUnderline.LineType.DASHED
					underline.line_color = COLOR_NOTICE

			underline.rect_position = Vector2(error_region.position.x, error_region.end.y)
			underline.line_length = error_region.size.x

			add_child(underline)
			_lines.append(underline)
			regions.append(error_region)


class ErrorUnderline extends Control:
	enum LineType { SQUIGGLY, JAGGED, DASHED }

	const LINE_THICKNESS := 2.0

	const SQUIGGLY_HEIGHT := 3.0
	const SQUIGGLY_STEP_WIDTH := 20.0
	const SQUIGGLY_VERTEX_COUNT := 16

	const JAGGED_HEIGHT := 5.0
	const JAGGED_STEP_WIDTH := 12.0

	const DASHED_STEP_WIDTH := 14.0
	const DASHED_GAP := 8.0

	var line_length := 64.0 setget set_line_length
	var line_type := -1 setget set_line_type
	var line_color := Color.white setget set_line_color

	var _points: PoolVector2Array


	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE


	func _draw() -> void:
		if line_type == LineType.DASHED:
			# draw_multiline doesn't support thickness, so we have to do this manually.
			var i := 0
			while i < _points.size() - 1:
				draw_line(_points[i], _points[i + 1], line_color, LINE_THICKNESS, true)
				i += 2
		else:
			draw_polyline(_points, line_color, LINE_THICKNESS, true)


	func update_points() -> void:
		_points = PoolVector2Array()

		match line_type:
			LineType.SQUIGGLY:
				for i in SQUIGGLY_VERTEX_COUNT * line_length / SQUIGGLY_STEP_WIDTH:
					_points.append(Vector2(
						SQUIGGLY_STEP_WIDTH * i / SQUIGGLY_VERTEX_COUNT,
						SQUIGGLY_HEIGHT / 2.0 * sin(TAU * i / SQUIGGLY_VERTEX_COUNT)
					))

			LineType.JAGGED:
				for i in line_length / JAGGED_STEP_WIDTH:
					_points.append(Vector2(
						JAGGED_STEP_WIDTH * i,
						0.0
					))
					_points.append(Vector2(
						JAGGED_STEP_WIDTH * i + JAGGED_STEP_WIDTH / 4.0,
						-JAGGED_HEIGHT / 2.0
					))
					_points.append(Vector2(
						JAGGED_STEP_WIDTH * i + JAGGED_STEP_WIDTH * 3.0 / 4.0,
						JAGGED_HEIGHT / 2.0
					))

			LineType.DASHED:
				for i in line_length / (DASHED_STEP_WIDTH + DASHED_GAP):
					_points.append(Vector2(
						(DASHED_STEP_WIDTH + DASHED_GAP) * i,
						0.0
					))
					
					var end_x = (DASHED_STEP_WIDTH + DASHED_GAP) * (i + 1) - DASHED_GAP
					if end_x > line_length:
						end_x = line_length
					_points.append(Vector2(
						end_x,
						0.0
					))

			_:
				_points.append(Vector2(
					0.0,
					0.0
				))
				_points.append(Vector2(
					line_length,
					0.0
				))


	func set_line_length(value: float) -> void:
		line_length = value
		update_points()
		update()


	func set_line_type(value: int) -> void:
		line_type = value
		update_points()
		update()


	func set_line_color(value: Color) -> void:
		line_color = value
		update()
