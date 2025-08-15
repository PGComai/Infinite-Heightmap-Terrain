@tool
extends StaticBody3D
class_name InfiniteTerrain


## The node that the terrain will generate around.
@export var player: Node3D
## Generate a preview of the terrain in the editor.
@export_tool_button("Preview Terrain") var preview_terrain = generate_preview
@export_group("Near Terrain")
## Enable or disable all terrain generation.
@export var generate_terrain := true
## Enable or disable generation of new terrain chunks.
@export var generate_new_chunks := true
## The primary source of bumps and hills in the terrain.
@export var terrain_noise: FastNoiseLite
## Extra layers of noise for the terrain. Many layers will add variety but slow
## the generation of the terrain.
@export var extra_terrain_noise_layers: Array[FastNoiseLite] = []
## The size of a single terrain chunk.
@export var terrain_chunk_size: float = 30.0
## How many chunks of terrain are generated away from the player.
@export var chunk_radius: int = 20
## How detailed the terrain mesh is. Lower values are simpler and faster to generate,
## while higher values are more detailed and slower to generate.
@export_range(0.1, 2.0, 0.15) var mesh_resolution: float = 0.2
## The height of the terrain.
@export var terrain_height_multiplier: float = 150.0
## Moves the terrain up or down in the world.
@export var terrain_height_offset: float = 0.0
## If checked the terrain color depends on the steepness of the terrain.
## If unchecked, all terrain will be set to the Terrain Level Color.
@export var two_colors := true
## The relationship between steepness and color.
@export var terrain_color_steepness_curve: Curve
## The color of level terrain.
@export var terrain_level_color: Color = Color.DARK_OLIVE_GREEN
## The color of steep terrain.
@export var terrain_cliff_color: Color = Color.DIM_GRAY
## The material applied to all terrain meshes.
@export var terrain_material: StandardMaterial3D
@export_group("Distant Terrain")
## Enable or disable generation of distant, low-res terrain.
@export var enable_distant_terrain := true
## Enable or disable generation of new distant terrain as the player moves.
@export var distant_terrain_update_during_gameplay := true
## How detailed the distant terrain mesh is. Lower values are simpler and faster to generate,
## while higher values are more detailed and slower to generate.
@export_range(0.1, 1.0, 0.1) var distant_terrain_mesh_resolution: float = 0.5
## How large the distant terrain mesh is.
@export var distant_terrain_mesh_size: float = 16000.0
@export_group("Multimesh")
## Enable or disable generation of scattered multimeshes on the terrain. This can be
## used to add things like grass or rocks to the terrain.
@export var use_multimesh := false
## Shadow casting setting for the multimeshes.
@export var multimesh_cast_shadow: MeshInstance3D.ShadowCastingSetting
## How many chunks away from the player the multimeshes are made visible.
@export var multimesh_radius: int = 6
## The source of variation in the placement of multimesh instances.
@export var multimesh_noise: FastNoiseLite
## The mesh that is scattered on the terrain by the multimesh.
@export var multimesh_mesh: Mesh
## The terrain coverage of scattered meshes. High values mean higher coverage, low
## values mean more sparse coverage.
@export_range(0.0, 1.0, 0.01) var multimesh_coverage: float = 0.5
## The randomness of scattered mesh placement. High values make the placement
## more random, while low values place the meshes in a grid-like pattern.
@export_range(0.0, 10.0, 0.1) var multimesh_jitter: float = 5.0
## Enable or disable the scattering of meshes on cliffs and steep slopes.
@export var multimesh_on_cliffs := false
## The threshold which decides when a slope is too steep for scattered meshes.
## High values require very steep slopes, while low values will count shallow slopes.
@export_range(0.0, 1.0, 0.1) var multimesh_steep_threshold: float = 0.5
## The number of times to repeat the mesh scattering process. This multiplies
## the amount of total meshes, so higher values will be much slower to generate.
@export_range(1.0, 10.0, 1.0) var multimesh_repeats: int = 1


var current_player_chunk: Vector2i:
	set(value):
		if current_player_chunk:
			if current_player_chunk != value:
				_player_in_new_chunk()
		current_player_chunk = value
var mesh_dict: Dictionary = {}
var collider_dict: Dictionary = {}
var multimesh_dict: Dictionary = {}
var big_mesh: MeshInstance3D

var mutex: Mutex
var semaphore: Semaphore
var thread: Thread
var exit_thread := false
var queue_thread := false
var load_counter: int = 0


func _enter_tree():
	# Initialization of the plugin goes here.
	pass


func _ready():
	ensure_default_values()
	
	if generate_terrain and not Engine.is_editor_hint() and terrain_noise:
		if generate_new_chunks:
			mutex = Mutex.new()
			semaphore = Semaphore.new()
			exit_thread = true
			
			thread = Thread.new()
			thread.start(_thread_function, Thread.PRIORITY_HIGH)
		
		for x: int in range(-chunk_radius, chunk_radius + 1):
			for y: int in range(-chunk_radius, chunk_radius + 1):
				var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y))
				if newmesh_and_mm:
					var newmesh = newmesh_and_mm[0]
					if use_multimesh:
						var newmm = newmesh_and_mm[1]
						newmm.add_to_group("do_not_own")
						add_child(newmm)
						newmm.global_position.y = terrain_height_offset
						var vis = Vector2(x, y).length() < multimesh_radius
						newmm.visible = vis
					newmesh.add_to_group("do_not_own")
					add_child(newmesh)
					newmesh.global_position.y = terrain_height_offset
				var newcollider = generate_terrain_collision(Vector2i(x, y))
				if newcollider:
					newcollider.add_to_group("do_not_own")
					add_child(newcollider)
					newcollider.rotation.y = -PI/2.0
					newcollider.global_position = Vector3(x * terrain_chunk_size, terrain_height_offset, y * terrain_chunk_size)
		if enable_distant_terrain:
			var new_bigmesh = generate_bigmesh(Vector2i(0, 0))
			new_bigmesh.add_to_group("do_not_own")
			add_child(new_bigmesh)
			new_bigmesh.global_position.y = terrain_height_offset - 3.0
			big_mesh = new_bigmesh


func _process(delta):
	if player and generate_terrain and not Engine.is_editor_hint() and generate_new_chunks:
		var player_pos_3d: Vector3
		player_pos_3d = player.global_position.snapped(Vector3(terrain_chunk_size,
															terrain_chunk_size,
															terrain_chunk_size)) / terrain_chunk_size
		current_player_chunk = Vector2i(player_pos_3d.x, player_pos_3d.z)
		
		if queue_thread:
			if exit_thread:
				#print(current_car_chunk)
				exit_thread = false
				semaphore.post()
				queue_thread = false


func ensure_default_values() -> void:
	if not terrain_color_steepness_curve:
		terrain_color_steepness_curve = Curve.new()
		terrain_color_steepness_curve.add_point(Vector2(0.0, 0.0))
		terrain_color_steepness_curve.add_point(Vector2(1.0, 1.0))
	
	if use_multimesh:
		if not multimesh_mesh:
			multimesh_mesh = RibbonTrailMesh.new()
		if not multimesh_noise:
			multimesh_noise = FastNoiseLite.new()
	
	if not terrain_material:
		terrain_material = StandardMaterial3D.new()
		#terrain_material.albedo_color = Color.GRAY
		terrain_material.vertex_color_use_as_albedo = true
	
	if not terrain_noise:
		terrain_noise = FastNoiseLite.new()
		terrain_noise.frequency = 0.0005


func generate_preview():
	if Engine.is_editor_hint() and terrain_noise:
		ensure_default_values()
		
		for child in get_children():
			child.queue_free()
		
		for x in range(-chunk_radius, chunk_radius + 1):
			for y in range(-chunk_radius, chunk_radius + 1):
				var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y), true)
				if newmesh_and_mm:
					var newmesh = newmesh_and_mm[0]
					if use_multimesh:
						var newmm = newmesh_and_mm[1]
						#newmm.add_to_group("do_not_own")
						add_child(newmm)
						newmm.global_position.y = terrain_height_offset
						var vis = Vector2(x, y).length() < multimesh_radius
						newmm.visible = vis
					#newmesh.add_to_group("do_not_own")
					add_child(newmesh)
					newmesh.global_position.y = terrain_height_offset
				var newcollider = generate_terrain_collision(Vector2i(x, y), true)
				if newcollider:
					#newcollider.add_to_group("do_not_own")
					add_child(newcollider)
					newcollider.rotation.y = -PI/2.0
					newcollider.global_position = Vector3(x * terrain_chunk_size, terrain_height_offset, y * terrain_chunk_size)
		if enable_distant_terrain:
			var new_bigmesh = generate_bigmesh(Vector2i(0, 0))
			#new_bigmesh.add_to_group("do_not_own")
			add_child(new_bigmesh)
			new_bigmesh.global_position.y = terrain_height_offset - 3.0
			big_mesh = new_bigmesh


func get_terrain_height(pos_x: float, pos_z: float) -> float:
	var pos_xz = Vector2(pos_x, pos_z)
	var nval_spawn = sample_2dv(pos_xz)
	return (nval_spawn * terrain_height_multiplier) + terrain_height_offset


func _player_in_new_chunk():
	if exit_thread:
		exit_thread = false
		semaphore.post()
	else:
		#print("thread busy")
		queue_thread = true


func _thread_function():
	while true:
		semaphore.wait()
		
		mutex.lock()
		var should_exit = exit_thread
		mutex.unlock()
		
		if should_exit:
			break
		
		mutex.lock()
		load_counter += 1
		
		var ccc := current_player_chunk
		
		if (load_counter < 20 or not distant_terrain_update_during_gameplay) and terrain_noise:
			for ix in range(-chunk_radius, chunk_radius + 1):
				var x = ccc.x + ix
				for iy in range(-chunk_radius, chunk_radius + 1):
					var y = ccc.y + iy
					var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y))
					if newmesh_and_mm:
						var newmesh = newmesh_and_mm[0]
						if use_multimesh:
							var newmm = newmesh_and_mm[1]
							newmm.call_deferred("add_to_group", "do_not_own")
							call_deferred("add_child", newmm)
							newmm.call_deferred("global_translate", Vector3(0.0, terrain_height_offset, 0.0))
							var vis: bool = Vector2(ix, iy).length() < multimesh_radius
							newmm.call_deferred("set_visible", vis)
						newmesh.call_deferred("add_to_group", "do_not_own")
						call_deferred("add_child", newmesh)
						newmesh.call_deferred("global_translate", Vector3(0.0, terrain_height_offset, 0.0))
					var newcollider = generate_terrain_collision(Vector2i(x, y))
					if newcollider:
						newcollider.call_deferred("add_to_group", "do_not_own")
						call_deferred("add_child", newcollider)
						newcollider.call_deferred("rotate_y", -PI/2.0)
						newcollider.call_deferred("set_global_position", Vector3(x * terrain_chunk_size, terrain_height_offset, y * terrain_chunk_size))
		else:
			load_counter = 0
			if enable_distant_terrain and distant_terrain_update_during_gameplay and terrain_noise:
				var new_bigmesh = generate_bigmesh(ccc)
				big_mesh.call_deferred("queue_free")
				call_deferred("add_child", new_bigmesh)
				new_bigmesh.call_deferred("global_translate", Vector3(0.0, terrain_height_offset - 3.0, 0.0))
				new_bigmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				big_mesh = new_bigmesh
		
		# remove distant meshes
		for k: Vector2i in mesh_dict.keys():
			if absi(ccc.x - k.x) > chunk_radius or absi(ccc.y - k.y) > chunk_radius:
				var mesh_to_remove = mesh_dict[k]
				if collider_dict.has(k):
					var col_to_remove = collider_dict[k]
					collider_dict.erase(k)
					col_to_remove.call_deferred("queue_free")
				if use_multimesh and multimesh_dict.has(k):
					var mm_to_remove = multimesh_dict[k]
					multimesh_dict.erase(k)
					mm_to_remove.call_deferred("queue_free")
				mesh_dict.erase(k)
				mesh_to_remove.call_deferred("queue_free")
			else:
				if multimesh_dict.has(k):
					var chunk: Vector2i = k - ccc
					var vis: bool = Vector2(chunk.x, chunk.y).length() < multimesh_radius
					multimesh_dict[k].call_deferred("set_visible", vis)
		
		mutex.unlock()
		
		mutex.lock()
		exit_thread = true
		mutex.unlock()


func generate_bigmesh(chunk: Vector2i):
	var new_mesh := MeshInstance3D.new()
	
	var arrmesh := ArrayMesh.new()
	
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var norms: PackedVector3Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []
	
	var chunk_x := float(chunk.x)
	var chunk_z := float(chunk.y)
	
	var chunk_center := Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
	
	var start_x: float = chunk_center.x - (distant_terrain_mesh_size * 0.5)
	var start_z: float = chunk_center.y - (distant_terrain_mesh_size * 0.5)
	
	var end_x: float = chunk_center.x + (distant_terrain_mesh_size * 0.5)
	var end_z: float = chunk_center.y + (distant_terrain_mesh_size * 0.5)
	
	var four_counter: int = 0
	
	var chunk_subdivisions := int(distant_terrain_mesh_size * (distant_terrain_mesh_resolution * 0.05))
	
	for x_division: int in chunk_subdivisions:
		var progress_x := float(x_division) / float(chunk_subdivisions)
		var x_coord := lerpf(start_x, end_x, progress_x)
		
		var progress_x_next := float(x_division + 1) / float(chunk_subdivisions)
		var x_coord_next := lerpf(start_x, end_x, progress_x_next)
		for z_division: int in chunk_subdivisions:
			var progress_z := float(z_division) / float(chunk_subdivisions)
			var z_coord := lerpf(start_z, end_z, progress_z)
			
			var progress_z_next := float(z_division + 1) / float(chunk_subdivisions)
			var z_coord_next := lerpf(start_z, end_z, progress_z_next)
			
			var uv_scale := 500.0 / distant_terrain_mesh_size
			
			
			var coord_2d := Vector2(x_coord, z_coord)
			var nval := sample_2dv(coord_2d)
			var coord_3d := Vector3(x_coord, nval * terrain_height_multiplier, z_coord)
			var norm1 := _generate_noise_normal(coord_2d)
			var uv1 := Vector2(progress_x, progress_z) / uv_scale
			
			
			var coord_2d_next_x := Vector2(x_coord_next, z_coord)
			var nval_next_x := sample_2dv(coord_2d_next_x)
			var coord_3d_next_x := Vector3(x_coord_next, nval_next_x * terrain_height_multiplier, z_coord)
			var norm2 := _generate_noise_normal(coord_2d_next_x)
			var uv2 := Vector2(progress_x_next, progress_z) / uv_scale
			
			
			var coord_2d_next_z := Vector2(x_coord, z_coord_next)
			var nval_next_z := sample_2dv(coord_2d_next_z)
			var coord_3d_next_z := Vector3(x_coord, nval_next_z * terrain_height_multiplier, z_coord_next)
			var norm3 := _generate_noise_normal(coord_2d_next_z)
			var uv3 := Vector2(progress_x, progress_z_next) / uv_scale
			
			
			var coord_2d_next_xz := Vector2(x_coord_next, z_coord_next)
			var nval_next_xz := sample_2dv(coord_2d_next_xz)
			var coord_3d_next_xz := Vector3(x_coord_next, nval_next_xz * terrain_height_multiplier, z_coord_next)
			var norm4 := _generate_noise_normal(coord_2d_next_xz)
			var uv4 := Vector2(progress_x_next, progress_z_next) / uv_scale
			
			
			var color1: Color
			var color2: Color
			var color3: Color
			var color4: Color
			
			if two_colors:
				var steepness1 := clampf(Vector3.UP.dot(norm1), 0.0, 1.0)
				steepness1 = terrain_color_steepness_curve.sample_baked(steepness1)
				
				var steepness2 := clampf(Vector3.UP.dot(norm2), 0.0, 1.0)
				steepness2 = terrain_color_steepness_curve.sample_baked(steepness2)
				
				var steepness3 := clampf(Vector3.UP.dot(norm3), 0.0, 1.0)
				steepness3 = terrain_color_steepness_curve.sample_baked(steepness3)
				
				var steepness4 := clampf(Vector3.UP.dot(norm4), 0.0, 1.0)
				steepness4 = terrain_color_steepness_curve.sample_baked(steepness4)
				
				color1 = terrain_cliff_color.lerp(terrain_level_color, steepness1)
				color2 = terrain_cliff_color.lerp(terrain_level_color, steepness2)
				color3 = terrain_cliff_color.lerp(terrain_level_color, steepness3)
				color4 = terrain_cliff_color.lerp(terrain_level_color, steepness4)
			else:
				color1 = terrain_level_color
				color2 = terrain_level_color
				color3 = terrain_level_color
				color4 = terrain_level_color
			
			verts.append(coord_3d)
			norms.append(norm1)
			uvs.append(uv1)
			colors.append(color1)
			
			verts.append(coord_3d_next_x)
			norms.append(norm2)
			uvs.append(uv2)
			colors.append(color2)
			
			verts.append(coord_3d_next_z)
			norms.append(norm3)
			uvs.append(uv3)
			colors.append(color3)
			
			verts.append(coord_3d_next_xz)
			norms.append(norm4)
			uvs.append(uv4)
			colors.append(color4)
			
			
			indices.append_array([four_counter + 0, four_counter + 1, four_counter + 3, four_counter + 3, four_counter + 2, four_counter + 0])
			
			four_counter += 4
			
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	
	arrmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	
	new_mesh.mesh = arrmesh
	
	#new_mesh.custom_aabb = AABB(Vector3.ZERO, Vector3(2000.0, 2000.0, 2000.0))
	
	var bigmesh_material: StandardMaterial3D = terrain_material.duplicate()
	bigmesh_material.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
	bigmesh_material.distance_fade_min_distance = terrain_chunk_size * float(chunk_radius) * 0.8
	bigmesh_material.distance_fade_max_distance = terrain_chunk_size * float(chunk_radius) * 0.95
	bigmesh_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	new_mesh.set_surface_override_material(0, bigmesh_material)
	
	new_mesh.sorting_offset = -200.0
	
	return new_mesh


func generate_terrain_mesh(chunk: Vector2i, ignore_dict: bool = false):
	if not mesh_dict.has(chunk) or ignore_dict:
		var chunkmesh := MeshInstance3D.new()
		
		if not ignore_dict:
			mesh_dict[chunk] = chunkmesh
		
		var multimesh_positions: PackedVector3Array = []
		
		var arrmesh := ArrayMesh.new()
		
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		
		var verts: PackedVector3Array = []
		var uvs: PackedVector2Array = []
		var norms: PackedVector3Array = []
		var colors: PackedColorArray = []
		var indices: PackedInt32Array = []
		
		var chunk_x := float(chunk.x)
		var chunk_z := float(chunk.y)
		
		var chunk_center := Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
		
		var start_x: float = chunk_center.x - (terrain_chunk_size * 0.5)
		var start_z: float = chunk_center.y - (terrain_chunk_size * 0.5)
		
		var end_x: float = chunk_center.x + (terrain_chunk_size * 0.5)
		var end_z: float = chunk_center.y + (terrain_chunk_size * 0.5)
		
		var four_counter: int = 0
		
		var chunk_subdivisions := int(terrain_chunk_size * (mesh_resolution))
		
		for x_division: int in chunk_subdivisions:
			var progress_x := float(x_division) / float(chunk_subdivisions)
			var x_coord := lerpf(start_x, end_x, progress_x)
			
			var progress_x_next := float(x_division + 1) / float(chunk_subdivisions)
			var x_coord_next := lerpf(start_x, end_x, progress_x_next)
			for z_division: int in chunk_subdivisions:
				var progress_z := float(z_division) / float(chunk_subdivisions)
				var z_coord := lerpf(start_z, end_z, progress_z)
				
				var progress_z_next := float(z_division + 1) / float(chunk_subdivisions)
				var z_coord_next := lerpf(start_z, end_z, progress_z_next)
				
				var uv_scale := 500.0 / terrain_chunk_size
				
				
				var coord_2d := Vector2(x_coord, z_coord)
				var nval := sample_2dv(coord_2d)
				
				var coord_2d_next_x := Vector2(x_coord_next, z_coord)
				var nval_next_x := sample_2dv(coord_2d_next_x)
				
				var coord_2d_next_z := Vector2(x_coord, z_coord_next)
				var nval_next_z := sample_2dv(coord_2d_next_z)
				
				var coord_2d_next_xz := Vector2(x_coord_next, z_coord_next)
				var nval_next_xz := sample_2dv(coord_2d_next_xz)
				
				
				var coord_3d := Vector3(x_coord, nval * terrain_height_multiplier, z_coord)
				var norm1 := _generate_noise_normal(coord_2d)
				var wind1 := Vector2.ONE
				var uv1 := Vector2(progress_x, progress_z) / uv_scale
				
				
				var coord_3d_next_x := Vector3(x_coord_next, nval_next_x * terrain_height_multiplier, z_coord)
				var norm2 := _generate_noise_normal(coord_2d_next_x)
				var wind2 := Vector2.ONE
				var uv2 := Vector2(progress_x_next, progress_z) / uv_scale
				
				
				var coord_3d_next_z := Vector3(x_coord, nval_next_z * terrain_height_multiplier, z_coord_next)
				var norm3 := _generate_noise_normal(coord_2d_next_z)
				var wind3 := Vector2.ONE
				var uv3 := Vector2(progress_x, progress_z_next) / uv_scale
				
				
				var coord_3d_next_xz := Vector3(x_coord_next, nval_next_xz * terrain_height_multiplier, z_coord_next)
				var norm4 := _generate_noise_normal(coord_2d_next_xz)
				var wind4 := Vector2.ONE
				var uv4 := Vector2(progress_x_next, progress_z_next) / uv_scale
				
				
				var color1: Color
				var color2: Color
				var color3: Color
				var color4: Color
				
				if two_colors:
					var steepness1 := clampf(Vector3.UP.dot(norm1), 0.0, 1.0)
					steepness1 = terrain_color_steepness_curve.sample_baked(steepness1)
					
					var steepness2 := clampf(Vector3.UP.dot(norm2), 0.0, 1.0)
					steepness2 = terrain_color_steepness_curve.sample_baked(steepness2)
					
					var steepness3 := clampf(Vector3.UP.dot(norm3), 0.0, 1.0)
					steepness3 = terrain_color_steepness_curve.sample_baked(steepness3)
					
					var steepness4 := clampf(Vector3.UP.dot(norm4), 0.0, 1.0)
					steepness4 = terrain_color_steepness_curve.sample_baked(steepness4)
					
					color1 = terrain_cliff_color.lerp(terrain_level_color, steepness1)
					color2 = terrain_cliff_color.lerp(terrain_level_color, steepness2)
					color3 = terrain_cliff_color.lerp(terrain_level_color, steepness3)
					color4 = terrain_cliff_color.lerp(terrain_level_color, steepness4)
				else:
					color1 = terrain_level_color
					color2 = terrain_level_color
					color3 = terrain_level_color
					color4 = terrain_level_color
				
				verts.append(coord_3d)
				norms.append(norm1)
				uvs.append(uv1)
				colors.append(color1)
				
				verts.append(coord_3d_next_x)
				norms.append(norm2)
				uvs.append(uv2)
				colors.append(color2)
				
				verts.append(coord_3d_next_z)
				norms.append(norm3)
				uvs.append(uv3)
				colors.append(color3)
				
				verts.append(coord_3d_next_xz)
				norms.append(norm4)
				uvs.append(uv4)
				colors.append(color4)
				
				
				indices.append_array([four_counter + 0, four_counter + 1, four_counter + 3, four_counter + 3, four_counter + 2, four_counter + 0])
				
				four_counter += 4
				
				if use_multimesh:
					var mm_points := [coord_2d, coord_2d_next_x, coord_2d_next_z, coord_2d_next_xz]
					multimesh_positions = generate_multimesh_positions(multimesh_positions, mm_points, multimesh_repeats)
		
		#var dict_lods := {100.0: PackedInt32Array([]),
					#}
		#
		#var four_counter_lod0: int = 0
		#
		#for x_division in chunk_subdivisions / 50:
			#for z_division in chunk_subdivisions / 50:
				#dict_lods[100.0].append_array([(four_counter_lod0 + 0) * 50,
												#(four_counter_lod0 + 1) * 50,
												#(four_counter_lod0 + 3) * 50,
												#(four_counter_lod0 + 3) * 50,
												#(four_counter_lod0 + 2) * 50,
												#(four_counter_lod0 + 0) * 50])
				#four_counter_lod0 += 4 * 50
		
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
		
		arrmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		
		chunkmesh.mesh = arrmesh
		
		chunkmesh.set_surface_override_material(0, terrain_material)
		
		if use_multimesh:
			var newmultimesh := MultiMeshInstance3D.new()
			if not ignore_dict:
				multimesh_dict[chunk] = newmultimesh
			newmultimesh.multimesh = MultiMesh.new()
			newmultimesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			newmultimesh.multimesh.mesh = multimesh_mesh
			newmultimesh.multimesh.use_colors = true
			newmultimesh.multimesh.use_custom_data = true
			newmultimesh.multimesh.instance_count = multimesh_positions.size()
			for mpi: int in multimesh_positions.size():
				var pos := multimesh_positions[mpi]
				var bas := Basis(Vector3(randfn(1.0, 0.1), 0.0, 0.0),
								Vector3(0.0, randf_range(0.5, 1.5), 0.0),
								Vector3(0.0, 0.0, randfn(1.0, 0.1)))
				bas = bas.rotated(Vector3.UP, randf_range(-PI/2.0, PI/2.0))
				var xform := Transform3D(bas, pos)
				var mm_nval := multimesh_noise.get_noise_2dv(Vector2(pos.x, pos.z))
				var scale_factor := clampf(abs(mm_nval) * 10.0, 0.5, 1.5)
				xform = xform.scaled_local(Vector3(scale_factor, scale_factor, scale_factor))
				newmultimesh.multimesh.set_instance_transform(mpi, xform)
				newmultimesh.multimesh.set_instance_custom_data(mpi, Color(pos.x, pos.y, pos.z, 0.0))
			
			newmultimesh.multimesh.visible_instance_count = multimesh_positions.size()
			newmultimesh.cast_shadow = multimesh_cast_shadow
			
			return[chunkmesh, newmultimesh]
		else:
			return [chunkmesh]
	else:
		return false


func generate_multimesh_positions(arr: PackedVector3Array, points: Array, times: int) -> PackedVector3Array:
	for t: int in times:
		for pt: Vector2 in points:
			var other_points := points.duplicate()
			other_points.erase(pt)
			var selected_pt: Vector2= other_points.pick_random()
			var new_pt := pt.lerp(selected_pt, randf_range(0.0, 1.0))
			new_pt += Vector2(randfn(0.0, multimesh_jitter), randfn(0.0, multimesh_jitter))
			var mm_nval := multimesh_noise.get_noise_2dv(new_pt)
			if mm_nval <= (multimesh_coverage * 2.0) - 1.0:
				var nval_pt := sample_2dv(new_pt)
				var new_pt_3d := Vector3(new_pt.x, nval_pt * terrain_height_multiplier, new_pt.y)
				var norm_pt := _generate_noise_normal(new_pt)
				var steep := Vector3.UP.dot(norm_pt)
				steep = clampf(steep, 0.0, 1.0)
				steep = terrain_color_steepness_curve.sample_baked(steep)
				if steep >= multimesh_steep_threshold or multimesh_on_cliffs:
					arr.append(new_pt_3d)
	return arr


func generate_terrain_collision(chunk: Vector2i, ignore_dict: bool = false):
	if not collider_dict.has(chunk) or ignore_dict:
		var newcollider := CollisionShape3D.new()
		newcollider.shape = HeightMapShape3D.new()
		newcollider.shape.map_width = terrain_chunk_size + 1.0
		newcollider.shape.map_depth = terrain_chunk_size + 1.0
		
		if not ignore_dict:
			collider_dict[chunk] = newcollider
		
		var map_data: PackedFloat32Array = []
		
		var chunk_x := float(chunk.x)
		var chunk_z := float(chunk.y)
		
		var chunk_center := Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
		
		var start_x: float = chunk_center.x - (terrain_chunk_size * 0.5)
		var start_z: float = chunk_center.y - (terrain_chunk_size * 0.5)
		
		var end_x: float = chunk_center.x + (terrain_chunk_size * 0.5)
		var end_z: float = chunk_center.y + (terrain_chunk_size * 0.5)
		
		for x_division: int in int(terrain_chunk_size) + 1:
			var progress_x := float(x_division) / terrain_chunk_size
			var x_coord := lerpf(end_x, start_x, progress_x)
			
			var progress_x_next := float(x_division + 1) / terrain_chunk_size
			var x_coord_next := lerpf(start_x, end_x, progress_x_next)
			for z_division: int in int(terrain_chunk_size) + 1:
				var progress_z := float(z_division) / terrain_chunk_size
				var z_coord := lerpf(start_z, end_z, progress_z)
				
				var coord_2d := Vector2(x_coord, z_coord)
				var nval := sample_2dv(coord_2d)
				map_data.append(nval * terrain_height_multiplier)
		
		newcollider.shape.map_data = map_data
		
		return newcollider
	else:
		return false


func _generate_noise_normal(point: Vector2) -> Vector3:
	var gradient_pos_x := point + Vector2(0.1, 0.0)
	var gradient_pos_z := point + Vector2(0.0, 0.1)
	var nval_wheel := sample_2dv(point)
	var nval_gx := sample_2dv(gradient_pos_x)
	var nval_gz := sample_2dv(gradient_pos_z)
	
	var pos_3d_nval_wheel := Vector3(point.x, nval_wheel * terrain_height_multiplier, point.y)
	var pos_3d_nval_gx := Vector3(gradient_pos_x.x, nval_gx * terrain_height_multiplier, gradient_pos_x.y)
	var pos_3d_nval_gz := Vector3(gradient_pos_z.x, nval_gz * terrain_height_multiplier, gradient_pos_z.y)
	
	var gradient_x := pos_3d_nval_gx - pos_3d_nval_wheel
	var gradient_z := pos_3d_nval_gz - pos_3d_nval_wheel
	
	var gx_norm := gradient_x.normalized()
	var gz_norm := gradient_z.normalized()
	var normal := gz_norm.cross(gx_norm)
	
	return normal.normalized()


func sample_2dv(point: Vector2) -> float:
	var value: float = terrain_noise.get_noise_2dv(point)
	
	for etn: FastNoiseLite in extra_terrain_noise_layers:
		value += etn.get_noise_2dv(point)
	
	return value


func sample_wind(point: Vector2) -> Vector2:
	var gradient_pos_x := point + Vector2(0.1, 0.0)
	var gradient_pos_z := point + Vector2(0.0, 0.1)
	
	return Vector2.ONE


func _on_tree_exiting():
	if not Engine.is_editor_hint() and mutex:
		mutex.lock()
		exit_thread = true # Protect with Mutex.
		mutex.unlock()

		# Unblock by posting.
		semaphore.post()

		# Wait until it exits.
		thread.wait_to_finish()


func _exit_tree():
	# Clean-up of the plugin goes here.
	pass


func _on_tree_entered() -> void:
	ensure_default_values()
