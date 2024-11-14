@tool
extends StaticBody3D
class_name InfiniteTerrain


@export var player: Node3D
@export_category("Terrain")
@export var generate_terrain := true
@export var use_terrain_noise := true
@export var terrain_noise: FastNoiseLite
@export var terrain_noise_large: FastNoiseLite
@export_enum("Add", "Sub", "Mult", "Pow") var terrain_large_function = 0
@export var terrain_chunk_size: float = 30.0
@export var chunk_radius: int = 20
@export var chunk_subdivisor: int = 12
@export var terrain_height_multiplier := 300.0
#@export var use_paths := false
#@export var path_noise: FastNoiseLite
#@export var path_curve: Curve
#@export var path_smooth_radius: float = 10.0
@export var two_colors := true
@export var terrain_color_steepness_curve: Curve
@export var terrain_level_color: Color = Color.DARK_OLIVE_GREEN
@export var terrain_cliff_color: Color = Color.DIM_GRAY
#@export var path_color: Color = Color.TAN
@export var mountain_mode := false
@export var mountain_strength: float = 0.01
@export var use_equation := false
@export var terrain_material: ShaderMaterial
@export_category("Bigmesh")
@export var use_bigmesh := true
@export var bigmesh_on_thread := true
@export var bigmesh_subdivision: int = 300
@export var bigmesh_size: float = 16000.0
@export var bigmesh_material: ShaderMaterial
@export_category("Multimesh")
@export var use_multimesh := false
@export var multimesh_radius: int = 6
@export var multimesh_noise: FastNoiseLite
@export var multimesh_mesh: Mesh
@export var multimesh_threshold: float = 0.01
@export var multimesh_jitter: float = 5.0
@export var multimesh_on_cliffs := false
@export var multimesh_steep_threshold: float = 0.5
@export var multimesh_total_coverage := false
@export var multimesh_times: int = 1
@export var multimesh_color_1: Color = Color("656839")
@export var multimesh_color_2: Color = Color("5d6b37")


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
	if generate_terrain and not Engine.is_editor_hint():
		mutex = Mutex.new()
		semaphore = Semaphore.new()
		exit_thread = true
		
		thread = Thread.new()
		thread.start(_thread_function, Thread.PRIORITY_HIGH)
		
		for x in range(-chunk_radius, chunk_radius + 1):
			for y in range(-chunk_radius, chunk_radius + 1):
				var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y))
				if newmesh_and_mm:
					var newmesh = newmesh_and_mm[0]
					if use_multimesh:
						var newmm = newmesh_and_mm[1]
						newmm.add_to_group("do_not_own")
						add_child(newmm)
						var vis = (absi(x) < multimesh_radius
								or absi(y) < multimesh_radius)
						newmm.visible = vis
					newmesh.add_to_group("do_not_own")
					add_child(newmesh)
				var newcollider = generate_terrain_collision(Vector2i(x, y))
				if newcollider:
					newcollider.add_to_group("do_not_own")
					add_child(newcollider)
					newcollider.rotation.y = -PI/2.0
					newcollider.global_position = Vector3(x * terrain_chunk_size, 0.0, y * terrain_chunk_size)
		if use_bigmesh:
			var new_bigmesh = generate_bigmesh(Vector2i(0, 0))
			new_bigmesh.add_to_group("do_not_own")
			add_child(new_bigmesh)
			new_bigmesh.global_position.y -= 3.0
			big_mesh = new_bigmesh


func _process(delta):
	if player and generate_terrain and not Engine.is_editor_hint():
		var player_pos_3d = player.global_position.snapped(Vector3(terrain_chunk_size,
															terrain_chunk_size,
															terrain_chunk_size)) / terrain_chunk_size
		current_player_chunk = Vector2i(player_pos_3d.x, player_pos_3d.z)
		
		if queue_thread:
			if exit_thread:
				#print(current_car_chunk)
				exit_thread = false
				semaphore.post()
				queue_thread = false



func _physics_process(delta):
	pass


func get_terrain_height(pos_x: float, pos_z: float) -> float:
	var spawn_pos_xz = Vector2(pos_x, pos_z)
	var nval_spawn = sample_2dv(spawn_pos_xz)
	return nval_spawn * terrain_height_multiplier


func _player_in_new_chunk():
	if exit_thread:
		exit_thread = false
		semaphore.post()
	else:
		#print("thread busy")
		queue_thread = true


func _thread_function():
	## relevant data: mesh_dict, current_player_chunk, exit_thread
	while true:
		semaphore.wait()
		
		mutex.lock()
		var should_exit = exit_thread
		mutex.unlock()
		
		if should_exit:
			break
		
		mutex.lock()
		load_counter += 1
		
		var ccc = current_player_chunk
		
		if load_counter < 20 or not bigmesh_on_thread:
			for ix in range(-chunk_radius, chunk_radius + 1):
				var x = ccc.x + ix
				for iy in range(-chunk_radius, chunk_radius + 1):
					var y = ccc.y + iy
					if use_terrain_noise:
						var newmesh_and_mm = generate_terrain_mesh(Vector2i(x, y))
						if newmesh_and_mm:
							var newmesh = newmesh_and_mm[0]
							if use_multimesh:
								var newmm = newmesh_and_mm[1]
								newmm.call_deferred("add_to_group", "do_not_own")
								call_deferred("add_child", newmm)
								var vis = (absi(ix) < multimesh_radius
										or absi(iy) < multimesh_radius)
								newmm.call_deferred("set_visible", vis)
							newmesh.call_deferred("add_to_group", "do_not_own")
							call_deferred("add_child", newmesh)
						var newcollider = generate_terrain_collision(Vector2i(x, y))
						if newcollider:
							newcollider.call_deferred("add_to_group", "do_not_own")
							call_deferred("add_child", newcollider)
							newcollider.call_deferred("rotate_y", -PI/2.0)
							newcollider.call_deferred("set_global_position", Vector3(x * terrain_chunk_size, 0.0, y * terrain_chunk_size))
		else:
			load_counter = 0
			if use_bigmesh and bigmesh_on_thread:
				var new_bigmesh = generate_bigmesh(ccc)
				big_mesh.call_deferred("queue_free")
				call_deferred("add_child", new_bigmesh)
				new_bigmesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				big_mesh = new_bigmesh
		
		# remove distant meshes
		for k: Vector2i in mesh_dict.keys():
			if absi(ccc.x - k.x) > chunk_radius or absi(ccc.y - k.y) > chunk_radius:
				var mesh_to_remove = mesh_dict[k]
				if use_terrain_noise and collider_dict.has(k):
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
					var vis = (absi(ccc.x - k.x) < multimesh_radius
							or absi(ccc.y - k.y) < multimesh_radius)
					multimesh_dict[k].call_deferred("set_visible", vis)
		
		mutex.unlock()
		
		mutex.lock()
		exit_thread = true
		mutex.unlock()


func generate_bigmesh(chunk: Vector2i):
	var new_mesh = MeshInstance3D.new()
	
	var arrmesh = ArrayMesh.new()
	
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	
	var verts: PackedVector3Array = []
	var uvs: PackedVector2Array = []
	var norms: PackedVector3Array = []
	var colors: PackedColorArray = []
	var indices: PackedInt32Array = []
	
	var chunk_x = float(chunk.x)
	var chunk_z = float(chunk.y)
	
	var chunk_center = Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
	
	var start_x = chunk_center.x - (bigmesh_size * 0.5)
	var start_z = chunk_center.y - (bigmesh_size * 0.5)
	
	var end_x = chunk_center.x + (bigmesh_size * 0.5)
	var end_z = chunk_center.y + (bigmesh_size * 0.5)
	
	var four_counter: int = 0
	
	for x_division in bigmesh_subdivision:
		var progress_x = float(x_division) / float(bigmesh_subdivision)
		var x_coord = lerp(start_x, end_x, progress_x)
		
		var progress_x_next = float(x_division + 1) / float(bigmesh_subdivision)
		var x_coord_next = lerp(start_x, end_x, progress_x_next)
		for z_division in bigmesh_subdivision:
			var progress_z = float(z_division) / float(bigmesh_subdivision)
			var z_coord = lerp(start_z, end_z, progress_z)
			
			var progress_z_next = float(z_division + 1) / float(bigmesh_subdivision)
			var z_coord_next = lerp(start_z, end_z, progress_z_next)
			
			var uv_scale = 500.0 / bigmesh_size
			
			
			var coord_2d = Vector2(x_coord, z_coord)
			var nval = sample_2dv(coord_2d)
			#var nval_path = (1.0 - path_noise.get_noise_2dv(coord_2d)) * 0.5
			#nval_path = path_threshold_curve.sample_baked(nval_path)
			var coord_3d = Vector3(x_coord, nval * terrain_height_multiplier, z_coord)
			var norm1 = _generate_noise_normal(coord_2d)
			var uv1 = Vector2(progress_x, progress_z) / uv_scale
			var steepness1 = clampf(Vector3.UP.dot(norm1), 0.0, 1.0)
			steepness1 = terrain_color_steepness_curve.sample_baked(steepness1)
			
			
			var coord_2d_next_x = Vector2(x_coord_next, z_coord)
			var nval_next_x = sample_2dv(coord_2d_next_x)
			#var nval_path_next_x = (1.0 - path_noise.get_noise_2dv(coord_2d_next_x)) * 0.5
			#nval_path_next_x = path_threshold_curve.sample_baked(nval_path_next_x)
			var coord_3d_next_x = Vector3(x_coord_next, nval_next_x * terrain_height_multiplier, z_coord)
			var norm2 = _generate_noise_normal(coord_2d_next_x)
			var uv2 = Vector2(progress_x_next, progress_z) / uv_scale
			var steepness2 = clampf(Vector3.UP.dot(norm2), 0.0, 1.0)
			steepness2 = terrain_color_steepness_curve.sample_baked(steepness2)
			
			
			var coord_2d_next_z = Vector2(x_coord, z_coord_next)
			var nval_next_z = sample_2dv(coord_2d_next_z)
			#var nval_path_next_z = (1.0 - path_noise.get_noise_2dv(coord_2d_next_z)) * 0.5
			#nval_path_next_z = path_threshold_curve.sample_baked(nval_path_next_z)
			var coord_3d_next_z = Vector3(x_coord, nval_next_z * terrain_height_multiplier, z_coord_next)
			var norm3 = _generate_noise_normal(coord_2d_next_z)
			var uv3 = Vector2(progress_x, progress_z_next) / uv_scale
			var steepness3 = clampf(Vector3.UP.dot(norm3), 0.0, 1.0)
			steepness3 = terrain_color_steepness_curve.sample_baked(steepness3)
			
			
			var coord_2d_next_xz = Vector2(x_coord_next, z_coord_next)
			var nval_next_xz = sample_2dv(coord_2d_next_xz)
			#var nval_path_next_xz = (1.0 - path_noise.get_noise_2dv(coord_2d_next_xz)) * 0.5
			#nval_path_next_xz = path_threshold_curve.sample_baked(nval_path_next_xz)
			var coord_3d_next_xz = Vector3(x_coord_next, nval_next_xz * terrain_height_multiplier, z_coord_next)
			var norm4 = _generate_noise_normal(coord_2d_next_xz)
			var uv4 = Vector2(progress_x_next, progress_z_next) / uv_scale
			var steepness4 = clampf(Vector3.UP.dot(norm4), 0.0, 1.0)
			steepness4 = terrain_color_steepness_curve.sample_baked(steepness4)
			
			
			if mountain_mode:
				coord_3d.y -= generate_mountain_y(coord_2d)
				coord_3d_next_x.y -= generate_mountain_y(coord_2d_next_x)
				coord_3d_next_z.y -= generate_mountain_y(coord_2d_next_z)
				coord_3d_next_xz.y -= generate_mountain_y(coord_2d_next_xz)
			
			
			var color1: Color
			var color2: Color
			var color3: Color
			var color4: Color
			
			if two_colors:
				color1 = terrain_cliff_color.lerp(terrain_level_color, steepness1)
				color2 = terrain_cliff_color.lerp(terrain_level_color, steepness2)
				color3 = terrain_cliff_color.lerp(terrain_level_color, steepness3)
				color4 = terrain_cliff_color.lerp(terrain_level_color, steepness4)
			else:
				color1 = terrain_level_color
				color2 = terrain_level_color
				color3 = terrain_level_color
				color4 = terrain_level_color
			
			#if use_paths:
				#color1 = color1.lerp(path_color, 1.0 - get_path_effect(coord_2d))
				#color2 = color2.lerp(path_color, 1.0 - get_path_effect(coord_2d_next_x))
				#color3 = color3.lerp(path_color, 1.0 - get_path_effect(coord_2d_next_z))
				#color4 = color4.lerp(path_color, 1.0 - get_path_effect(coord_2d_next_xz))
			
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
	
	new_mesh.set_surface_override_material(0, bigmesh_material)
	
	new_mesh.sorting_offset = -200.0
	
	return new_mesh


func generate_terrain_mesh(chunk: Vector2i):
	if not mesh_dict.has(chunk):
		var new_mesh = MeshInstance3D.new()
		var chunkmesh = new_mesh
		mesh_dict[chunk] = chunkmesh
		
		var multimesh_positions: PackedVector3Array = []
		
		var arrmesh = ArrayMesh.new()
		
		var arrays = []
		arrays.resize(Mesh.ARRAY_MAX)
		
		var verts: PackedVector3Array = []
		var uvs: PackedVector2Array = []
		var norms: PackedVector3Array = []
		var colors: PackedColorArray = []
		var indices: PackedInt32Array = []
		
		var chunk_x = float(chunk.x)
		var chunk_z = float(chunk.y)
		
		var chunk_center = Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
		
		var start_x = chunk_center.x - (terrain_chunk_size * 0.5)
		var start_z = chunk_center.y - (terrain_chunk_size * 0.5)
		
		var end_x = chunk_center.x + (terrain_chunk_size * 0.5)
		var end_z = chunk_center.y + (terrain_chunk_size * 0.5)
		
		var four_counter: int = 0
		
		var chunk_subdivisions = int(terrain_chunk_size / chunk_subdivisor)
		
		for x_division in chunk_subdivisions:
			var progress_x = float(x_division) / float(chunk_subdivisions)
			var x_coord = lerp(start_x, end_x, progress_x)
			
			var progress_x_next = float(x_division + 1) / float(chunk_subdivisions)
			var x_coord_next = lerp(start_x, end_x, progress_x_next)
			for z_division in chunk_subdivisions:
				var progress_z = float(z_division) / float(chunk_subdivisions)
				var z_coord = lerp(start_z, end_z, progress_z)
				
				var progress_z_next = float(z_division + 1) / float(chunk_subdivisions)
				var z_coord_next = lerp(start_z, end_z, progress_z_next)
				
				var uv_scale = 500.0 / terrain_chunk_size
				
				
				var coord_2d = Vector2(x_coord, z_coord)
				var nval = sample_2dv(coord_2d)
				
				var coord_2d_next_x = Vector2(x_coord_next, z_coord)
				var nval_next_x = sample_2dv(coord_2d_next_x)
				
				var coord_2d_next_z = Vector2(x_coord, z_coord_next)
				var nval_next_z = sample_2dv(coord_2d_next_z)
				
				var coord_2d_next_xz = Vector2(x_coord_next, z_coord_next)
				var nval_next_xz = sample_2dv(coord_2d_next_xz)
				
				
				if mountain_mode:
					nval -= generate_mountain_y(coord_2d)
					nval_next_x -= generate_mountain_y(coord_2d_next_x)
					nval_next_z -= generate_mountain_y(coord_2d_next_z)
					nval_next_xz -= generate_mountain_y(coord_2d_next_xz)
				
				
				var coord_3d = Vector3(x_coord, nval * terrain_height_multiplier, z_coord)
				var norm1 = _generate_noise_normal(coord_2d)
				var uv1 = Vector2(progress_x, progress_z) / uv_scale
				var steepness1 = clampf(Vector3.UP.dot(norm1), 0.0, 1.0)
				steepness1 = terrain_color_steepness_curve.sample_baked(steepness1)
				
				
				var coord_3d_next_x = Vector3(x_coord_next, nval_next_x * terrain_height_multiplier, z_coord)
				var norm2 = _generate_noise_normal(coord_2d_next_x)
				var uv2 = Vector2(progress_x_next, progress_z) / uv_scale
				var steepness2 = clampf(Vector3.UP.dot(norm2), 0.0, 1.0)
				steepness2 = terrain_color_steepness_curve.sample_baked(steepness2)
				
				
				var coord_3d_next_z = Vector3(x_coord, nval_next_z * terrain_height_multiplier, z_coord_next)
				var norm3 = _generate_noise_normal(coord_2d_next_z)
				var uv3 = Vector2(progress_x, progress_z_next) / uv_scale
				var steepness3 = clampf(Vector3.UP.dot(norm3), 0.0, 1.0)
				steepness3 = terrain_color_steepness_curve.sample_baked(steepness3)
				
				
				var coord_3d_next_xz = Vector3(x_coord_next, nval_next_xz * terrain_height_multiplier, z_coord_next)
				var norm4 = _generate_noise_normal(coord_2d_next_xz)
				var uv4 = Vector2(progress_x_next, progress_z_next) / uv_scale
				var steepness4 = clampf(Vector3.UP.dot(norm4), 0.0, 1.0)
				steepness4 = terrain_color_steepness_curve.sample_baked(steepness4)
				
				
				var color1: Color
				var color2: Color
				var color3: Color
				var color4: Color
				
				if two_colors:
					color1 = terrain_cliff_color.lerp(terrain_level_color, steepness1)
					color2 = terrain_cliff_color.lerp(terrain_level_color, steepness2)
					color3 = terrain_cliff_color.lerp(terrain_level_color, steepness3)
					color4 = terrain_cliff_color.lerp(terrain_level_color, steepness4)
				else:
					color1 = terrain_level_color
					color2 = terrain_level_color
					color3 = terrain_level_color
					color4 = terrain_level_color
				
				#if use_paths:
					#color1 = color1.lerp(path_color, 1.0 - get_path_effect(coord_2d))
					#color2 = color2.lerp(path_color, 1.0 - get_path_effect(coord_2d_next_x))
					#color3 = color3.lerp(path_color, 1.0 - get_path_effect(coord_2d_next_z))
					#color4 = color4.lerp(path_color, 1.0 - get_path_effect(coord_2d_next_xz))
				
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
					var mm_points = [coord_2d, coord_2d_next_x, coord_2d_next_z, coord_2d_next_xz]
					multimesh_positions = generate_multimesh_positions(multimesh_positions, mm_points, multimesh_times)
		
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
			var newmultimesh = MultiMeshInstance3D.new()
			multimesh_dict[chunk] = newmultimesh
			newmultimesh.multimesh = MultiMesh.new()
			newmultimesh.multimesh.transform_format = MultiMesh.TRANSFORM_3D
			newmultimesh.multimesh.mesh = multimesh_mesh
			newmultimesh.multimesh.use_colors = true
			newmultimesh.multimesh.use_custom_data = true
			newmultimesh.multimesh.instance_count = multimesh_positions.size()
			for mpi in multimesh_positions.size():
				var pos = multimesh_positions[mpi]
				var bas = Basis(Vector3(randfn(1.0, 0.1), 0.0, 0.0),
								Vector3(0.0, randf_range(0.5, 1.5), 0.0),
								Vector3(0.0, 0.0, randfn(1.0, 0.1)))
				bas = bas.rotated(Vector3.UP, randf_range(-PI/2.0, PI/2.0))
				var xform = Transform3D(bas, pos)
				var mm_nval = multimesh_noise.get_noise_2dv(Vector2(pos.x, pos.z))
				var scale_factor = clampf(abs(mm_nval) * 10.0, 0.5, 1.5)
				xform = xform.scaled_local(Vector3(scale_factor, scale_factor, scale_factor))
				newmultimesh.multimesh.set_instance_transform(mpi, xform)
				var clr = multimesh_color_1.lerp(multimesh_color_2, randf_range(0.0, 1.0))
				newmultimesh.multimesh.set_instance_color(mpi, clr)
				newmultimesh.multimesh.set_instance_custom_data(mpi, Color(pos.x, pos.y, pos.z, 0.0))
			
			newmultimesh.multimesh.visible_instance_count = multimesh_positions.size()
			newmultimesh.cast_shadow = false
			
			return[chunkmesh, newmultimesh]
			#chunkmesh.call_deferred("add_child", newmultimesh)
		else:
			return [chunkmesh]
	else:
		return false


func generate_multimesh_positions(arr: PackedVector3Array, points: Array, times: int) -> PackedVector3Array:
	for t in times:
		for pt in points:
			var other_points = points.duplicate()
			other_points.erase(pt)
			var selected_pt = other_points.pick_random()
			var new_pt = pt.lerp(selected_pt, randf_range(0.0, 1.0))
			new_pt += Vector2(randfn(0.0, multimesh_jitter), randfn(0.0, multimesh_jitter))
			#if not multimesh_total_coverage:
			var mm_nval = multimesh_noise.get_noise_2dv(new_pt)
			if mm_nval >= multimesh_threshold:
				var nval_pt = sample_2dv(new_pt)
				if mountain_mode:
					nval_pt -= generate_mountain_y(new_pt)
				var new_pt_3d = Vector3(new_pt.x, nval_pt * terrain_height_multiplier, new_pt.y)
				var norm_pt = _generate_noise_normal(new_pt)
				var steep = Vector3.UP.dot(norm_pt)
				steep = clampf(steep, 0.0, 1.0)
				steep = terrain_color_steepness_curve.sample_baked(steep)
				if steep >= multimesh_steep_threshold or multimesh_on_cliffs:
					arr.append(new_pt_3d)
	return arr


func generate_terrain_collision(chunk: Vector2i):
	if not collider_dict.has(chunk):
		var newcollider = CollisionShape3D.new()
		newcollider.shape = HeightMapShape3D.new()
		newcollider.shape.map_width = terrain_chunk_size + 1.0
		newcollider.shape.map_depth = terrain_chunk_size + 1.0
		collider_dict[chunk] = newcollider
		
		var map_data: PackedFloat32Array = []
		
		var chunk_x = float(chunk.x)
		var chunk_z = float(chunk.y)
		
		var chunk_center = Vector2(chunk_x * terrain_chunk_size, chunk_z * terrain_chunk_size)
		
		var start_x = chunk_center.x - (terrain_chunk_size * 0.5)
		var start_z = chunk_center.y - (terrain_chunk_size * 0.5)
		
		var end_x = chunk_center.x + (terrain_chunk_size * 0.5)
		var end_z = chunk_center.y + (terrain_chunk_size * 0.5)
		
		for x_division in int(terrain_chunk_size) + 1:
			var progress_x = float(x_division) / terrain_chunk_size
			var x_coord = lerp(end_x, start_x, progress_x)
			
			var progress_x_next = float(x_division + 1) / terrain_chunk_size
			var x_coord_next = lerp(start_x, end_x, progress_x_next)
			for z_division in int(terrain_chunk_size) + 1:
				var progress_z = float(z_division) / terrain_chunk_size
				var z_coord = lerp(start_z, end_z, progress_z)
				
				var coord_2d = Vector2(x_coord, z_coord)
				var nval = sample_2dv(coord_2d)
				if mountain_mode:
					nval -= generate_mountain_y(coord_2d)
				map_data.append(nval * terrain_height_multiplier)
		
		newcollider.shape.map_data = map_data
		
		return newcollider
	else:
		return false


func _generate_noise_normal(point: Vector2) -> Vector3:
	var gradient_pos_x = point + Vector2(0.1, 0.0)
	var gradient_pos_z = point + Vector2(0.0, 0.1)
	var nval_wheel = sample_2dv(point)
	var nval_gx = sample_2dv(gradient_pos_x)
	var nval_gz = sample_2dv(gradient_pos_z)
	
	var pos_3d_nval_wheel = Vector3(point.x, nval_wheel * terrain_height_multiplier, point.y)
	var pos_3d_nval_gx = Vector3(gradient_pos_x.x, nval_gx * terrain_height_multiplier, gradient_pos_x.y)
	var pos_3d_nval_gz = Vector3(gradient_pos_z.x, nval_gz * terrain_height_multiplier, gradient_pos_z.y)
	
	if mountain_mode:
		pos_3d_nval_wheel.y -= generate_mountain_y(point)
		pos_3d_nval_gx.y -= generate_mountain_y(gradient_pos_x)
		pos_3d_nval_gz.y -= generate_mountain_y(gradient_pos_z)
	
	var gradient_x = pos_3d_nval_gx - pos_3d_nval_wheel
	var gradient_z = pos_3d_nval_gz - pos_3d_nval_wheel
	
	var gx_norm = gradient_x.normalized()
	var gz_norm = gradient_z.normalized()
	var normal = gz_norm.cross(gx_norm)
	
	return normal.normalized()


func _generate_noise_normal_smooth(point: Vector2) -> Vector3:
	var gradient_pos_x = point + Vector2(0.1, 0.0)
	var gradient_pos_z = point + Vector2(0.0, 0.1)
	var nval_wheel = sample_2dv_smooth(point)
	var nval_gx = sample_2dv_smooth(gradient_pos_x)
	var nval_gz = sample_2dv_smooth(gradient_pos_z)
	
	var pos_3d_nval_wheel = Vector3(point.x, nval_wheel * terrain_height_multiplier, point.y)
	var pos_3d_nval_gx = Vector3(gradient_pos_x.x, nval_gx * terrain_height_multiplier, gradient_pos_x.y)
	var pos_3d_nval_gz = Vector3(gradient_pos_z.x, nval_gz * terrain_height_multiplier, gradient_pos_z.y)
	
	if mountain_mode:
		pos_3d_nval_wheel.y -= generate_mountain_y(point)
		pos_3d_nval_gx.y -= generate_mountain_y(gradient_pos_x)
		pos_3d_nval_gz.y -= generate_mountain_y(gradient_pos_z)
	
	var gradient_x = pos_3d_nval_gx - pos_3d_nval_wheel
	var gradient_z = pos_3d_nval_gz - pos_3d_nval_wheel
	
	var gx_norm = gradient_x.normalized()
	var gz_norm = gradient_z.normalized()
	var normal = gz_norm.cross(gx_norm)
	
	return normal.normalized()


func generate_mountain_y(point: Vector2) -> float:
	var value = point.length()
	#value = pow(value, 2.0) - pow(value, 1.999)
	#value = log(value)
	value *= mountain_strength
	value = pow(value, 2.0) - pow(7.388, log(value))
	value = max(value, 0.0)
	return value# * mountain_strength * 0.01


#func get_path_effect(point: Vector2) -> float:
	#var pn = path_noise.get_noise_2dv(point)
	#return path_curve.sample(clampf(1.0 - abs(pn), 0.0, 1.0))


func sample_2dv(point: Vector2) -> float:
	var value: float
	
	if not use_equation:
		value = terrain_noise.get_noise_2dv(point)
		
		if terrain_noise_large:
			if terrain_large_function == 0:
				value += terrain_noise_large.get_noise_2dv(point) * 5.0
			elif terrain_large_function == 1:
				value -= terrain_noise_large.get_noise_2dv(point)
			elif terrain_large_function == 2:
				value *= terrain_noise_large.get_noise_2dv(point)
			elif terrain_large_function == 3:
				value = pow(value, terrain_noise_large.get_noise_2dv(point))
		
		#if use_paths:
			#var pn_smooth_pathless = sample_2dv_smooth_pathless(point)
			#var path_effect = get_path_effect(point)
			#value = lerpf(value, pn_smooth_pathless, 1.0 - path_effect)
	else:
		var r = point.length() * 0.07
		var theta = atan2(point.y, point.x)
		value = (sin(r + theta) + r) * clamp(r * 0.1, 0.0, 1.0)
		value /= 50.0
	#
	#if terrain_sample_curve:
		#value *= pre_curve_multiplier
		#value = terrain_sample_curve.sample_baked(value)
	
	return value


func sample_2dv_pathless(point: Vector2) -> float:
	var value: float
	
	if not use_equation:
		value = terrain_noise.get_noise_2dv(point)
		
		if terrain_noise_large:
			if terrain_large_function == 0:
				value += terrain_noise_large.get_noise_2dv(point) * 5.0
			elif terrain_large_function == 1:
				value -= terrain_noise_large.get_noise_2dv(point)
			elif terrain_large_function == 2:
				value *= terrain_noise_large.get_noise_2dv(point)
			elif terrain_large_function == 3:
				value = pow(value, terrain_noise_large.get_noise_2dv(point))
		
	else:
		var r = point.length() * 0.07
		var theta = atan2(point.y, point.x)
		value = (sin(r + theta) + r) * clamp(r * 0.1, 0.0, 1.0)
	#
	#if terrain_sample_curve:
		#value *= pre_curve_multiplier
		#value = terrain_sample_curve.sample_baked(value)
	
	return value


func sample_2dv_smooth(point: Vector2) -> float:
	var value: float
	
	var smooth = 0.1
	
	var v1 = sample_2dv(point + Vector2(0.0, smooth))
	var v2 = sample_2dv(point + Vector2(0.0, -smooth))
	var v3 = sample_2dv(point + Vector2(smooth, 0.0))
	var v4 = sample_2dv(point + Vector2(-smooth, 0.0))
	var v5 = sample_2dv(point)
	
	value = (v1 + v2 + v3 + v4 + v5) / 5.0
	
	return value


#func sample_2dv_smooth_pathless(point: Vector2) -> float:
	#var value: float
	#
	#var v1 = sample_2dv_pathless(point + Vector2(0.0, path_smooth_radius))
	#var v2 = sample_2dv_pathless(point + Vector2(0.0, -path_smooth_radius))
	#var v3 = sample_2dv_pathless(point + Vector2(path_smooth_radius, 0.0))
	#var v4 = sample_2dv_pathless(point + Vector2(-path_smooth_radius, 0.0))
	#
	#value = (v1 + v2 + v3 + v4) / 4.0
	#
	#return value


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
