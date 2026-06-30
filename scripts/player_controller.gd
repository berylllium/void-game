extends CharacterBody3D

@export var look_sensitivity: float = 0.004

@export var jump_velocity: float = 3.0
@export var walk_speed: float = 3.0
@export var sprint_speed: float = 5.0
@export var noclip_speed_mult: float = 3.0

@export var headbob_move_amount: float = 0.03
@export var headbob_frequency: float = 2.8

@onready var head: Node3D = %head
@onready var camera: Camera3D = %camera
@onready var collision_shape: CollisionShape3D = %collision_shape
@onready var stairs_ahead_raycast: RayCast3D = %stairs_ahead_raycast
@onready var stairs_below_raycast: RayCast3D = %stairs_below_raycast

@export var arm_sprite: Sprite2D

var input_dir := Vector3.ZERO
var cam_aligned_input_dir := Vector3.ZERO
var headbob_time := 0.0
var noclip := false
var snapped_to_stairs_last_frame := false
var last_frame_was_on_floor := -INF
var in_mouse_mode := false

const GRAVITY: float = 9.81
const MAX_STEP_HEIGHT: float = 0.5


func _ready() -> void:
	arm_sprite.visible = false


func _process(delta: float) -> void:
	if in_mouse_mode and arm_sprite.visible:
		var mouse_pos := get_viewport().get_mouse_position()
		var screen_width := get_viewport().get_visible_rect().size.x
		arm_sprite.position = arm_sprite.position.lerp(mouse_pos, 20.0 * delta)
		var distance := mouse_pos.x - (screen_width * 0.7)
		var max_rot := PI/6
		var rot_c := max_rot / screen_width * 0.7 
		var rot := distance * rot_c
		arm_sprite.rotation = rot + deg_to_rad(33.0)
		


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not in_mouse_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("ui_cancel") and not in_mouse_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event.is_action_pressed("player_jump"):
		in_mouse_mode = true
		arm_sprite.visible = true
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN

	elif event.is_action_released("player_jump"):
		in_mouse_mode = false
		arm_sprite.visible = false
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
   
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseMotion:
			rotate_y(-event.relative.x * look_sensitivity)
			camera.rotate_x(-event.relative.y * look_sensitivity)
			camera.rotation.x = clampf(camera.rotation.x, -0.5 * PI, 0.5 * PI)
		elif event.is_action_pressed("player_noclip"):
			toggle_noclip()


func handle_headbob(delta: float) -> void:
	headbob_time += delta * self.velocity.length()
	camera.transform.origin = Vector3(
		cos(headbob_time * headbob_frequency * 0.5) * headbob_move_amount,
		sin(headbob_time * headbob_frequency) * headbob_move_amount,
		0,
	)


func handle_air_physics(delta: float) -> void:
	self.velocity.y -= GRAVITY * delta


func handle_ground_physics(delta: float) -> void:
	self.velocity.x = input_dir.x * get_move_speed()
	self.velocity.z = input_dir.z * get_move_speed()

	handle_headbob(delta)


func handle_noclip(delta: float) -> void:
	var speed = get_move_speed() * noclip_speed_mult

	self.velocity = cam_aligned_input_dir * speed
	global_position += self.velocity * delta


func handle_stair_snap_up(delta: float) -> bool:
	if not is_on_floor() and not snapped_to_stairs_last_frame:
		return false

	var expected_move_motion := self.velocity * Vector3(1, 0, 1) * delta
	var step_pos_with_clearance := self.global_transform.translated(expected_move_motion + Vector3(0, MAX_STEP_HEIGHT * 2, 0))

	var down_check_result := PhysicsTestMotionResult3D.new()
	if (run_body_test_motion(step_pos_with_clearance, Vector3(0, -MAX_STEP_HEIGHT * 2, 0), down_check_result)
			and (down_check_result.get_collider().is_class("StaticBody3D"))):
		var step_height := ((step_pos_with_clearance.origin + down_check_result.get_travel()) - self.global_position).y
		if step_height > MAX_STEP_HEIGHT or step_height <= 0.01 or (down_check_result.get_collision_point() - self.global_position).y > MAX_STEP_HEIGHT:
			return false
		stairs_ahead_raycast.global_position = down_check_result.get_collision_point() + Vector3(0, MAX_STEP_HEIGHT, 0) + expected_move_motion.normalized() * 0.1
		stairs_ahead_raycast.force_raycast_update()
		if stairs_ahead_raycast.is_colliding() and not is_surface_too_steep(stairs_ahead_raycast.get_collision_normal()):
			self.global_position = step_pos_with_clearance.origin + down_check_result.get_travel()
			apply_floor_snap()
			snapped_to_stairs_last_frame = true
			return true
	return false


func handle_stair_snap_down() -> void:
	var did_snap := false
	var was_on_floor_last_frame := Engine.get_physics_frames() - last_frame_was_on_floor == 1

	var floor_below: bool = stairs_below_raycast.is_colliding() and not is_surface_too_steep(stairs_below_raycast.get_collision_normal())

	if not is_on_floor() and velocity.y <= 0 and (was_on_floor_last_frame or snapped_to_stairs_last_frame) and floor_below:
		var body_test_result = PhysicsTestMotionResult3D.new()
		if run_body_test_motion(self.global_transform, Vector3(0, -MAX_STEP_HEIGHT, 0), body_test_result):
			var translate_y := body_test_result.get_travel().y
			self.position.y += translate_y
			apply_floor_snap()
			did_snap = true

	snapped_to_stairs_last_frame = did_snap


func _physics_process(delta: float) -> void:
	if is_on_floor() or snapped_to_stairs_last_frame:
		last_frame_was_on_floor = Engine.get_physics_frames()

	var dir = Input.get_vector("player_left", "player_right", "player_forward", "player_backward").normalized()
	input_dir = self.global_transform.basis * Vector3(dir.x, 0.0, dir.y)
	cam_aligned_input_dir = camera.global_transform.basis * Vector3(dir.x, 0.0, dir.y)

	if noclip:
		handle_noclip(delta)
	else:
		if is_on_floor() or snapped_to_stairs_last_frame:
			handle_ground_physics(delta)
		else:
			handle_air_physics(delta)

		if not handle_stair_snap_up(delta):
			move_and_slide()
			handle_stair_snap_down()


func get_move_speed() -> float:
	return sprint_speed if Input.is_action_pressed("player_sprint") else walk_speed


func toggle_noclip() -> void:
	noclip = !noclip
	collision_shape.disabled = noclip


func is_surface_too_steep(normal: Vector3) -> bool:
	return normal.angle_to(Vector3.UP) > self.floor_max_angle


func run_body_test_motion(from: Transform3D, motion: Vector3, result = null) -> bool:
	if not result:
		result = PhysicsTestMotionResult3D.new()

	var params := PhysicsTestMotionParameters3D.new()
	params.from = from
	params.motion = motion

	return PhysicsServer3D.body_test_motion(self.get_rid(), params, result)
