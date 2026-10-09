extends Node3D

const COLORS := {
	"background": Color("#08111d"),
	"floor": Color("#101d2b"),
	"body": Color("#27364a"),
	"body_top": Color("#354962"),
	"limb": Color("#91a6bd"),
	"servo": Color("#ff9f43"),
	"servo_dark": Color("#bd6427"),
	"accent": Color("#4dd8e8"),
	"eye": Color("#baf7ff"),
	"foot": Color("#152233"),
	"text": Color("#eef6ff"),
	"muted": Color("#8fa4ba"),
}

const SERVO_ORDER := [
	"head",
	"front_left_hip",
	"front_left_knee",
	"front_right_hip",
	"front_right_knee",
	"rear_left_hip",
	"rear_left_knee",
	"rear_right_hip",
	"rear_right_knee",
]

const SERVO_NAMES := {
	"head": "Head pan",
	"front_left_hip": "Front left · hip",
	"front_left_knee": "Front left · knee",
	"front_right_hip": "Front right · hip",
	"front_right_knee": "Front right · knee",
	"rear_left_hip": "Rear left · hip",
	"rear_left_knee": "Rear left · knee",
	"rear_right_hip": "Rear right · hip",
	"rear_right_knee": "Rear right · knee",
}

const POSES := {
	"Neutral": {
		"head": 0.0,
		"front_left_hip": 0.0, "front_left_knee": 0.0,
		"front_right_hip": 0.0, "front_right_knee": 0.0,
		"rear_left_hip": 0.0, "rear_left_knee": 0.0,
		"rear_right_hip": 0.0, "rear_right_knee": 0.0,
	},
	"Stand": {
		"head": 0.0,
		"front_left_hip": 18.0, "front_left_knee": -32.0,
		"front_right_hip": 18.0, "front_right_knee": -32.0,
		"rear_left_hip": -18.0, "rear_left_knee": 32.0,
		"rear_right_hip": -18.0, "rear_right_knee": 32.0,
	},
	"Crouch": {
		"head": -12.0,
		"front_left_hip": 42.0, "front_left_knee": -76.0,
		"front_right_hip": 42.0, "front_right_knee": -76.0,
		"rear_left_hip": -42.0, "rear_left_knee": 76.0,
		"rear_right_hip": -42.0, "rear_right_knee": 76.0,
	},
}

var joint_nodes: Dictionary = {}
var joint_markers: Dictionary = {}
var sliders: Dictionary = {}
var value_labels: Dictionary = {}
var collider_bindings: Array[Dictionary] = []
var robot_body: RigidBody3D
var active_joint_label: Label
var pose_label: Label
var camera: Camera3D
var camera_target := Vector3(0.0, 1.9, 0.0)
var camera_yaw := deg_to_rad(142.0)
var camera_pitch := deg_to_rad(24.0)
var camera_distance := 10.5
var orbiting := false


func _ready() -> void:
	_build_world()
	_build_robot()
	_build_interface()
	_apply_pose("Stand")
	_sync_colliders()
	_update_camera()


func _build_world() -> void:
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = COLORS.background
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#9fc7e6")
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.rotation_degrees = Vector3(-48.0, -35.0, 0.0)
	key_light.light_color = Color("#fff1d2")
	key_light.light_energy = 1.35
	key_light.shadow_enabled = true
	add_child(key_light)

	var rim_light := OmniLight3D.new()
	rim_light.position = Vector3(-4.0, 5.5, 3.5)
	rim_light.light_color = COLORS.accent
	rim_light.light_energy = 4.0
	rim_light.omni_range = 9.0
	add_child(rim_light)

	camera = Camera3D.new()
	camera.fov = 46.0
	add_child(camera)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(18.0, 18.0)
	var floor_instance := MeshInstance3D.new()
	floor_instance.mesh = floor_mesh
	floor_instance.material_override = _material(COLORS.floor, 0.82, 0.05)
	add_child(floor_instance)

	var floor_body := StaticBody3D.new()
	floor_body.name = "FloorCollision"
	floor_body.position.y = -0.1
	var floor_shape := BoxShape3D.new()
	floor_shape.size = Vector3(18.0, 0.2, 18.0)
	var floor_collider := CollisionShape3D.new()
	floor_collider.shape = floor_shape
	floor_body.add_child(floor_collider)
	add_child(floor_body)

	# Simple floor strips give the model a sense of scale without external assets.
	for index in range(-4, 5):
		_create_box(
			self,
			"GridX",
			Vector3(12.0, 0.008, 0.018),
			Vector3(0.0, 0.012, float(index) * 1.25),
			_material(Color(0.22, 0.38, 0.5, 0.26), 1.0)
		)
		_create_box(
			self,
			"GridZ",
			Vector3(0.018, 0.008, 12.0),
			Vector3(float(index) * 1.25, 0.013, 0.0),
			_material(Color(0.22, 0.38, 0.5, 0.26), 1.0)
		)


func _build_robot() -> void:
	robot_body = RigidBody3D.new()
	robot_body.name = "Bittle"
	robot_body.position = Vector3(0.0, 5.0, 0.0)
	robot_body.mass = 2.2
	robot_body.linear_damp = 0.18
	robot_body.angular_damp = 0.55
	robot_body.continuous_cd = true
	robot_body.can_sleep = true
	add_child(robot_body)

	var body_material := _material(COLORS.body, 0.38, 0.62)
	var top_material := _material(COLORS.body_top, 0.3, 0.72)
	var limb_material := _material(COLORS.limb, 0.32, 0.5)
	var servo_material := _material(COLORS.servo, 0.26, 0.4)
	var servo_dark_material := _material(COLORS.servo_dark, 0.36, 0.25)
	var foot_material := _material(COLORS.foot, 0.75, 0.1)

	_create_physics_box(robot_body, "Body", Vector3(2.55, 0.72, 3.65), Vector3.ZERO, body_material)
	_create_box(robot_body, "TopPlate", Vector3(2.25, 0.16, 2.5), Vector3(0.0, 0.43, 0.05), top_material)
	_create_box(robot_body, "SpineAccent", Vector3(0.16, 0.03, 2.1), Vector3(0.0, 0.525, 0.0), _material(COLORS.accent, 0.25, 0.4, 1.2))

	var head_pivot := Node3D.new()
	head_pivot.name = "HeadPanServo"
	head_pivot.position = Vector3(0.0, 0.02, -2.22)
	robot_body.add_child(head_pivot)
	joint_nodes["head"] = head_pivot
	joint_markers["head"] = _create_servo_marker(head_pivot, Vector3.ZERO, servo_material, servo_dark_material, true)
	_create_physics_box(head_pivot, "Head", Vector3(1.75, 1.02, 1.28), Vector3(0.0, 0.12, -0.58), body_material)
	_create_box(head_pivot, "Muzzle", Vector3(1.26, 0.48, 0.38), Vector3(0.0, -0.05, -1.34), top_material)
	_create_box(head_pivot, "LeftEye", Vector3(0.24, 0.19, 0.08), Vector3(-0.47, 0.34, -1.235), _material(COLORS.eye, 0.12, 0.05, 2.8))
	_create_box(head_pivot, "RightEye", Vector3(0.24, 0.19, 0.08), Vector3(0.47, 0.34, -1.235), _material(COLORS.eye, 0.12, 0.05, 2.8))
	_create_box(head_pivot, "LeftEar", Vector3(0.28, 0.62, 0.34), Vector3(-0.67, 0.76, -0.42), top_material, Vector3(0.0, 0.0, -10.0))
	_create_box(head_pivot, "RightEar", Vector3(0.28, 0.62, 0.34), Vector3(0.67, 0.76, -0.42), top_material, Vector3(0.0, 0.0, 10.0))

	_build_leg(robot_body, "front_left", Vector3(-1.25, -0.25, -1.25), limb_material, servo_material, servo_dark_material, foot_material)
	_build_leg(robot_body, "front_right", Vector3(1.25, -0.25, -1.25), limb_material, servo_material, servo_dark_material, foot_material)
	_build_leg(robot_body, "rear_left", Vector3(-1.25, -0.25, 1.25), limb_material, servo_material, servo_dark_material, foot_material)
	_build_leg(robot_body, "rear_right", Vector3(1.25, -0.25, 1.25), limb_material, servo_material, servo_dark_material, foot_material)


func _build_leg(
	robot: Node3D,
	leg_id: String,
	hip_position: Vector3,
	limb_material: Material,
	servo_material: Material,
	servo_dark_material: Material,
	foot_material: Material
) -> void:
	var hip := Node3D.new()
	hip.name = _title_case(leg_id) + "Hip"
	hip.position = hip_position
	robot.add_child(hip)
	joint_nodes[leg_id + "_hip"] = hip
	joint_markers[leg_id + "_hip"] = _create_servo_marker(hip, Vector3.ZERO, servo_material, servo_dark_material)
	_create_physics_box(hip, "UpperLeg", Vector3(0.42, 1.32, 0.5), Vector3(0.0, -0.77, 0.0), limb_material)

	var knee := Node3D.new()
	knee.name = _title_case(leg_id) + "Knee"
	knee.position = Vector3(0.0, -1.48, 0.0)
	hip.add_child(knee)
	joint_nodes[leg_id + "_knee"] = knee
	joint_markers[leg_id + "_knee"] = _create_servo_marker(knee, Vector3.ZERO, servo_material, servo_dark_material)
	_create_physics_box(knee, "LowerLeg", Vector3(0.34, 1.22, 0.4), Vector3(0.0, -0.72, 0.0), limb_material)
	_create_physics_box(knee, "Foot", Vector3(0.62, 0.22, 0.82), Vector3(0.0, -1.37, -0.12), foot_material)


func _create_servo_marker(
	parent: Node3D,
	local_position: Vector3,
	servo_material: Material,
	end_material: Material,
	vertical := false
) -> MeshInstance3D:
	var motor := _create_cylinder(parent, "Servo", 0.34, 0.68, local_position, servo_material)
	motor.rotation_degrees.z = 0.0 if vertical else 90.0
	var cap_offset := Vector3(0.0, 0.37, 0.0) if vertical else Vector3(0.37, 0.0, 0.0)
	var cap := _create_cylinder(parent, "ServoCap", 0.22, 0.06, local_position + cap_offset, end_material)
	cap.rotation_degrees.z = 0.0 if vertical else 90.0
	return motor


func _build_interface() -> void:
	var canvas := CanvasLayer.new()
	canvas.name = "Interface"
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.name = "ServoPanel"
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 22.0
	panel.offset_top = 22.0
	panel.offset_right = 392.0
	panel.offset_bottom = -22.0
	panel.add_theme_stylebox_override("panel", _panel_style(Color("#111f2feF"), 18.0, Color("#29445d"), 1.0))
	canvas.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = "PET ROBOT LAB  /  9-DOF"
	eyebrow.add_theme_color_override("font_color", COLORS.accent)
	eyebrow.add_theme_font_size_override("font_size", 12)
	column.add_child(eyebrow)

	var title := Label.new()
	title.text = "Bittle Joint Simulator"
	title.add_theme_color_override("font_color", COLORS.text)
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Move each servo and inspect the kinematic chain."
	subtitle.add_theme_color_override("font_color", COLORS.muted)
	subtitle.add_theme_font_size_override("font_size", 13)
	column.add_child(subtitle)

	var pose_bar := HBoxContainer.new()
	pose_bar.add_theme_constant_override("separation", 8)
	column.add_child(pose_bar)
	for pose_name in POSES:
		var button := Button.new()
		button.text = pose_name
		button.focus_mode = Control.FOCUS_NONE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 34.0
		button.pressed.connect(_apply_pose.bind(pose_name))
		pose_bar.add_child(button)

	pose_label = Label.new()
	pose_label.text = "POSE  ·  STAND"
	pose_label.add_theme_color_override("font_color", COLORS.muted)
	pose_label.add_theme_font_size_override("font_size", 11)
	column.add_child(pose_label)

	var drop_button := Button.new()
	drop_button.text = "↻  RESET DROP"
	drop_button.tooltip_text = "Move the robot above the floor and release it under gravity."
	drop_button.focus_mode = Control.FOCUS_NONE
	drop_button.custom_minimum_size.y = 34.0
	drop_button.pressed.connect(_reset_drop)
	column.add_child(drop_button)

	var separator := HSeparator.new()
	column.add_child(separator)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var controls := VBoxContainer.new()
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.add_theme_constant_override("separation", 9)
	scroll.add_child(controls)

	_add_section_label(controls, "HEAD")
	_add_servo_control(controls, "head", -75.0, 75.0)
	_add_section_label(controls, "FRONT LEGS")
	_add_servo_control(controls, "front_left_hip", -90.0, 90.0)
	_add_servo_control(controls, "front_left_knee", -120.0, 120.0)
	_add_servo_control(controls, "front_right_hip", -90.0, 90.0)
	_add_servo_control(controls, "front_right_knee", -120.0, 120.0)
	_add_section_label(controls, "REAR LEGS")
	_add_servo_control(controls, "rear_left_hip", -90.0, 90.0)
	_add_servo_control(controls, "rear_left_knee", -120.0, 120.0)
	_add_servo_control(controls, "rear_right_hip", -90.0, 90.0)
	_add_servo_control(controls, "rear_right_knee", -120.0, 120.0)

	active_joint_label = Label.new()
	active_joint_label.text = "Selected  ·  Head pan"
	active_joint_label.add_theme_color_override("font_color", COLORS.accent)
	active_joint_label.add_theme_font_size_override("font_size", 12)
	column.add_child(active_joint_label)

	var help_panel := PanelContainer.new()
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_panel.offset_left = -277.0
	help_panel.offset_top = 22.0
	help_panel.offset_right = -22.0
	help_panel.offset_bottom = 98.0
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	help_panel.add_theme_stylebox_override("panel", _panel_style(Color("#111f2fD9"), 14.0, Color("#29445d"), 1.0))
	canvas.add_child(help_panel)

	var help := Label.new()
	help.text = "VIEW CONTROLS\nDrag to orbit  ·  Scroll to zoom"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help.add_theme_color_override("font_color", COLORS.muted)
	help.add_theme_font_size_override("font_size", 12)
	help_panel.add_child(help)


func _add_section_label(parent: VBoxContainer, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", COLORS.accent)
	label.add_theme_font_size_override("font_size", 11)
	label.custom_minimum_size.y = 22.0
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	parent.add_child(label)


func _add_servo_control(parent: VBoxContainer, servo_id: String, minimum: float, maximum: float) -> void:
	var group := VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	parent.add_child(group)

	var header := HBoxContainer.new()
	group.add_child(header)
	var name_label := Label.new()
	name_label.text = SERVO_NAMES[servo_id]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", COLORS.text)
	name_label.add_theme_font_size_override("font_size", 13)
	header.add_child(name_label)

	var value_label := Label.new()
	value_label.text = "0°"
	value_label.custom_minimum_size.x = 48.0
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_label.add_theme_color_override("font_color", COLORS.servo)
	value_label.add_theme_font_size_override("font_size", 13)
	header.add_child(value_label)
	value_labels[servo_id] = value_label

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = 1.0
	slider.value = 0.0
	slider.focus_mode = Control.FOCUS_NONE
	slider.custom_minimum_size.y = 20.0
	slider.value_changed.connect(_on_servo_changed.bind(servo_id))
	group.add_child(slider)
	sliders[servo_id] = slider


func _on_servo_changed(value: float, servo_id: String) -> void:
	var joint: Node3D = joint_nodes[servo_id]
	if servo_id == "head":
		joint.rotation_degrees.y = value
	else:
		joint.rotation_degrees.x = value
	value_labels[servo_id].text = "%d°" % roundi(value)
	active_joint_label.text = "Selected  ·  %s" % SERVO_NAMES[servo_id]
	_highlight_joint(servo_id)
	_sync_colliders()
	pose_label.text = "POSE  ·  CUSTOM"


func _apply_pose(pose_name: String) -> void:
	var pose: Dictionary = POSES[pose_name]
	for servo_id in SERVO_ORDER:
		sliders[servo_id].value = pose[servo_id]
	_sync_colliders()
	pose_label.text = "POSE  ·  %s" % pose_name.to_upper()


func _reset_drop() -> void:
	robot_body.freeze = true
	robot_body.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.0, 5.0, 0.0))
	robot_body.linear_velocity = Vector3.ZERO
	robot_body.angular_velocity = Vector3.ZERO
	robot_body.reset_physics_interpolation()
	robot_body.freeze = false
	robot_body.sleeping = false


func _sync_colliders() -> void:
	if not is_instance_valid(robot_body):
		return
	var inverse_body_transform := robot_body.global_transform.affine_inverse()
	for binding in collider_bindings:
		var visual: MeshInstance3D = binding["visual"]
		var collider: CollisionShape3D = binding["collider"]
		if is_instance_valid(visual) and is_instance_valid(collider):
			collider.transform = inverse_body_transform * visual.global_transform


func _highlight_joint(servo_id: String) -> void:
	for id in joint_markers:
		var marker: MeshInstance3D = joint_markers[id]
		marker.scale = Vector3.ONE * (1.14 if id == servo_id else 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			orbiting = event.pressed
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_distance = maxf(6.5, camera_distance - 0.65)
			_update_camera()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_distance = minf(16.0, camera_distance + 0.65)
			_update_camera()
	elif event is InputEventMouseMotion and orbiting:
		camera_yaw -= event.relative.x * 0.008
		camera_pitch = clampf(camera_pitch - event.relative.y * 0.006, deg_to_rad(-8.0), deg_to_rad(62.0))
		_update_camera()


func _update_camera() -> void:
	var flat_distance := cos(camera_pitch) * camera_distance
	camera.position = camera_target + Vector3(
		sin(camera_yaw) * flat_distance,
		sin(camera_pitch) * camera_distance,
		cos(camera_yaw) * flat_distance
	)
	camera.look_at(camera_target, Vector3.UP)


func _create_box(
	parent: Node,
	node_name: String,
	size: Vector3,
	local_position: Vector3,
	material: Material,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.rotation_degrees = rotation
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _create_physics_box(
	parent: Node,
	node_name: String,
	size: Vector3,
	local_position: Vector3,
	material: Material,
	rotation := Vector3.ZERO
) -> MeshInstance3D:
	var visual := _create_box(parent, node_name, size, local_position, material, rotation)
	var shape := BoxShape3D.new()
	shape.size = size
	var collider := CollisionShape3D.new()
	collider.name = node_name + "Collision"
	collider.shape = shape
	robot_body.add_child(collider)
	collider_bindings.append({"visual": visual, "collider": collider})
	return visual


func _create_cylinder(
	parent: Node,
	node_name: String,
	radius: float,
	height: float,
	local_position: Vector3,
	material: Material
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 24
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = local_position
	instance.material_override = material
	parent.add_child(instance)
	return instance


func _material(color: Color, roughness := 0.45, metallic := 0.0, emission_energy := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = metallic
	if emission_energy > 0.0:
		material.emission_enabled = true
		material.emission = color
		material.emission_energy_multiplier = emission_energy
	if color.a < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material


func _panel_style(color: Color, radius: float, border_color: Color, border_width: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.corner_radius_top_left = int(radius)
	style.corner_radius_top_right = int(radius)
	style.corner_radius_bottom_left = int(radius)
	style.corner_radius_bottom_right = int(radius)
	style.border_width_left = int(border_width)
	style.border_width_top = int(border_width)
	style.border_width_right = int(border_width)
	style.border_width_bottom = int(border_width)
	style.border_color = border_color
	return style


func _title_case(value: String) -> String:
	var words := value.split("_")
	var titled: Array[String] = []
	for word in words:
		titled.append(word.capitalize())
	return "".join(titled)
