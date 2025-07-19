package main

import "core:fmt"
import "core:log"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import im "shared:imgui"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

ROTATION_SPEED :: f32(90) * linalg.RAD_PER_DEG
EYE_HEIGHT :: 1
MOVE_SPEED :: 4
MOUSE_SENSITIVITY :: 0.5

UBO_Vert_Global :: struct #packed {
	view_projection_mat: matrix[4, 4]f32,
}

UBO_Vert_Local :: struct #packed {
	model_mat:  matrix[4, 4]f32,
	normal_mat: matrix[4, 4]f32,
}

UBO_Frag_Global :: struct #packed {
	light_position:      Vec3,
	_:                   f32,
	light_color:         Vec3,
	light_intensity:     f32,
	view_position:       Vec3,
	_:                   f32,
	ambient_light_color: Vec3,
}

UBO_Frag_Local :: struct #packed {
	material_specular_color:     Vec3,
	material_specular_shininess: f32,
}

Vertex_Data :: struct {
	pos:    Vec3,
	color:  sdl.FColor,
	uv:     Vec2,
	normal: Vec3,
}

Mesh :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	num_indices: u32,
}
Model :: struct {
	using mesh: Mesh,
	material:   Material,
}

Material :: struct {
	diffuse_texture:    ^sdl.GPUTexture,
	specular_color:     Vec3,
	specular_shininess: f32,
}

Model_Id :: distinct int

Entity :: struct {
	model_id: Model_Id,
	position: Vec3,
	rotation: quaternion128,
}

Game_State :: struct {
	object_pipeline:      ^sdl.GPUGraphicsPipeline,
	light_shape_pipeline: ^sdl.GPUGraphicsPipeline,
	light_shape_mesh:     Mesh,
	default_sampler:      ^sdl.GPUSampler,
	camera:               struct {
		position: Vec3,
		target:   Vec3,
	},
	look:                 struct {
		yaw:   f32,
		pitch: f32,
	},
	rotate:               bool,
	models:               []Model,
	entities:             []Entity,
	light_position:       Vec3,
	light_color:          Vec3,
	light_intensity:      f32,
	ambient_light_color:  Vec3,
}


init_game :: proc() {
	setup_pipeline()
	setup_light_shape_pipeline()

	g.default_sampler = sdl.CreateGPUSampler(g.gpu, {min_filter = .LINEAR, mag_filter = .LINEAR})

	copy_cmd_buffer := sdl.AcquireGPUCommandBuffer(g.gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buffer)

	g.light_shape_mesh = generate_box_mesh(copy_pass, 0.2, 0.2, 0.2)

	colormap := load_texture_file(copy_pass, "colormap.png")
	odd_floor := load_texture_file(copy_pass, "odd_floor.png")
	prototype_texture := load_texture_file(copy_pass, "texture_01.png")


	g.models = slice.clone(
		[]Model {
			{
				load_obj_file(copy_pass, "ship-small.obj"),
				{diffuse_texture = colormap, specular_color = 0, specular_shininess = 1},
			},
			{
				load_obj_file(copy_pass, "ship-pirate-large.obj"),
				{
					diffuse_texture = colormap,
					specular_color = {0, 1, 0},
					specular_shininess = 1000,
				},
			},
			{
				generate_plane_mesh(copy_pass, 10, 10),
				{diffuse_texture = odd_floor, specular_color = 0, specular_shininess = 1},
			},
			{
				generate_box_mesh(copy_pass, 1, 1, 1),
				{
					diffuse_texture = prototype_texture,
					specular_color = 1,
					specular_shininess = 100,
				},
			},
		},
	)

	g.entities = slice.clone(
		[]Entity {
			{model_id = 0, position = {-5, 0, 0}, rotation = 1}, // This rotation is equal to linalg.QUATERNIONF64_IDENTITY
			{
				model_id = 1,
				position = {8, 0, 0},
				rotation = linalg.quaternion_from_euler_angle_y_f32(15 * linalg.RAD_PER_DEG),
			},
			{model_id = 2, position = {0, -1, 0}, rotation = 0},
			{model_id = 3, position = {0, 0.5, 4}, rotation = 0},
		},
	)


	sdl.EndGPUCopyPass(copy_pass)
	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buffer);sdl_assert(ok)


	g.rotate = true

	g.light_color = {1, 1, 1}
	g.light_position = {0, 4, 0}
	g.light_intensity = 1
	g.ambient_light_color = 0.1
}

update_game :: proc(dt: f32) {
	if im.Begin("Inspector") {
		im.Checkbox("Rotate", &g.rotate)
		im.ColorEdit3("Ambient color", &g.ambient_light_color, {.Float})

		im.SeparatorText("Light")
		im.DragFloat3("Position", &g.light_position, 0.1, -10, 10)
		im.DragFloat("Intensity", &g.light_intensity, 0.1, 0, 1000)
		im.ColorEdit3("Color", &g.light_color, {.Float})

		for entity, i in g.entities {
			im.PushIDInt(i32(i)) // Allows imgui to differentiate between every entity
			im.SeparatorText(fmt.ctprintf("Object {}", i + 1))

			model := &g.models[entity.model_id]
			im.ColorEdit3("Specular Color", &model.material.specular_color, {.Float})
			im.DragFloat("Shininess", &model.material.specular_shininess, 1, 1, 1000)

			im.PopID()
		}


	}

	im.End()

	if g.rotate {
		for &entity in g.entities {
			entity.rotation *= linalg.quaternion_from_euler_angle_y_f32(ROTATION_SPEED * dt)
		}
	}
	update_camera(dt)


}

render_game :: proc(cmd_buf: ^sdl.GPUCommandBuffer, swapchain_tex: ^sdl.GPUTexture) {
	proj_mat := linalg.matrix4_perspective_f32(
		70,
		f32(g.window_size.x) / f32(g.window_size.y),
		0.1,
		1000,
	)
	view_mat := linalg.matrix4_look_at_f32(g.camera.position, g.camera.target, {0, 1, 0})

	ubo_vert_global := UBO_Vert_Global {
		view_projection_mat = proj_mat * view_mat,
	}
	sdl.PushGPUVertexUniformData(cmd_buf, 0, rawptr(&ubo_vert_global), size_of(ubo_vert_global))


	ubo_frag_global := UBO_Frag_Global {
		light_position      = g.light_position,
		light_color         = g.light_color,
		light_intensity     = g.light_intensity,
		view_position       = g.camera.position,
		ambient_light_color = g.ambient_light_color,
	}

	sdl.PushGPUFragmentUniformData(cmd_buf, 0, &ubo_frag_global, size_of(ubo_frag_global))


	clear_color: sdl.FColor = 1
	clear_color.rgb = g.ambient_light_color
	color_target := sdl.GPUColorTargetInfo {
		texture     = swapchain_tex,
		load_op     = .CLEAR,
		clear_color = clear_color,
		store_op    = .STORE,
	}


	depth_target_info := sdl.GPUDepthStencilTargetInfo {
		texture     = g.depth_texture,
		load_op     = .CLEAR,
		clear_depth = 1,
		store_op    = .DONT_CARE,
	}

	// Empezamos el proceso de pasar datos a nuestra GPU, debemos bindearlo a la pipeline.
	render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)

	// Push light visualization
	{
		sdl.BindGPUGraphicsPipeline(render_pass, g.light_shape_pipeline)

		model_mat := linalg.matrix4_translate_f32(g.light_position)
		sdl.PushGPUVertexUniformData(cmd_buf, 1, &model_mat, size_of(model_mat))

		sdl.BindGPUVertexBuffers(
			render_pass,
			0,
			&(sdl.GPUBufferBinding{buffer = g.light_shape_mesh.vertex_buf}),
			1,
		)

		sdl.BindGPUIndexBuffer(render_pass, {buffer = g.light_shape_mesh.index_buf}, ._16BIT)
		sdl.DrawGPUIndexedPrimitives(render_pass, g.light_shape_mesh.num_indices, 1, 0, 0, 0)
	}


	sdl.BindGPUGraphicsPipeline(render_pass, g.object_pipeline)

	for entity in g.entities {

		model_mat := linalg.matrix4_from_trs_f32(entity.position, entity.rotation, {1, 1, 1})
		normal_mat := linalg.inverse_transpose(model_mat)

		ubo_vert_local := UBO_Vert_Local {
			model_mat  = model_mat,
			normal_mat = normal_mat,
		}
		sdl.PushGPUVertexUniformData(cmd_buf, 1, rawptr(&ubo_vert_local), size_of(ubo_vert_local))


		model := g.models[entity.model_id]
		material := model.material

		ubo_frag_local := UBO_Frag_Local {
			material_specular_color     = material.specular_color,
			material_specular_shininess = material.specular_shininess,
		}
		sdl.PushGPUFragmentUniformData(
			cmd_buf,
			1,
			rawptr(&ubo_frag_local),
			size_of(ubo_frag_local),
		)

		sdl.BindGPUVertexBuffers(
			render_pass,
			0,
			&(sdl.GPUBufferBinding{buffer = model.vertex_buf}),
			1,
		)
		sdl.BindGPUIndexBuffer(render_pass, {buffer = model.index_buf}, ._16BIT)
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&(sdl.GPUTextureSamplerBinding {
					texture = model.material.diffuse_texture,
					sampler = g.default_sampler,
				}),
			1,
		)
		sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indices, 1, 0, 0, 0)
	}
	sdl.EndGPURenderPass(render_pass)


}

setup_light_shape_pipeline :: proc() {
	// Asignamos los shaders a la GPU.
	vertex_shader := load_shader(g.gpu, "lightshape.vert")
	fragment_shader := load_shader(g.gpu, "lightshape.frag")

	// Describimos nuestros datos, en este caso decimos que vamos a pasar dos datos en esas localizaciones(las definimos en nuestros shaders), 
	// tendran ese tamaño (3/4 floats), y tendran un offset de eso.
	vertex_attributes := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
	}


	// Creamos un GPUGraphicsPipelineCreateInfo con los datos de nuestros shaders.
	g.light_shape_pipeline = sdl.CreateGPUGraphicsPipeline(
	g.gpu,
	{
		vertex_shader = vertex_shader,
		fragment_shader = fragment_shader,
		primitive_type = .TRIANGLELIST,
		// Creamos GPUVertexInputState que da informacion de nuestro vertex buffer.
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
					slot = 0,
					pitch = size_of(Vertex_Data),
				}),
			num_vertex_attributes = u32(len(vertex_attributes)),
			vertex_attributes = raw_data(vertex_attributes),
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = .LESS,
		},
		// rasterizer_state = {cull_mode = .BACK, fill_mode = .LINE},
		rasterizer_state = {cull_mode = .BACK},
		// Creamos GPUGraphicsPipelineTargetInfo que define el color de nuestros pixeles.
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
					format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window),
				}),
			has_depth_stencil_target = true,
			depth_stencil_format = g.depth_texture_format,
		},
	},
	)
	sdl_assert(g.object_pipeline != nil)
	// Una vez hayamos hecho el binding con la pipeline, podemos liberarlos.
	sdl.ReleaseGPUShader(g.gpu, vertex_shader)
	sdl.ReleaseGPUShader(g.gpu, fragment_shader)

}


setup_pipeline :: proc() {
	// Asignamos los shaders a la GPU.
	vertex_shader := load_shader(g.gpu, "shader.vert")
	fragment_shader := load_shader(g.gpu, "shader.frag")

	// Describimos nuestros datos, en este caso decimos que vamos a pasar dos datos en esas localizaciones(las definimos en nuestros shaders), 
	// tendran ese tamaño (3/4 floats), y tendran un offset de eso.
	vertex_attributes := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
		{location = 2, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
		{location = 3, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, normal))},
	}


	// Creamos un GPUGraphicsPipelineCreateInfo con los datos de nuestros shaders.
	g.object_pipeline = sdl.CreateGPUGraphicsPipeline(
	g.gpu,
	{
		vertex_shader = vertex_shader,
		fragment_shader = fragment_shader,
		primitive_type = .TRIANGLELIST,
		// Creamos GPUVertexInputState que da informacion de nuestro vertex buffer.
		vertex_input_state = {
			num_vertex_buffers = 1,
			vertex_buffer_descriptions = &(sdl.GPUVertexBufferDescription {
					slot = 0,
					pitch = size_of(Vertex_Data),
				}),
			num_vertex_attributes = u32(len(vertex_attributes)),
			vertex_attributes = raw_data(vertex_attributes),
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = .LESS,
		},
		// rasterizer_state = {cull_mode = .BACK, fill_mode = .LINE},
		rasterizer_state = {cull_mode = .BACK},
		// Creamos GPUGraphicsPipelineTargetInfo que define el color de nuestros pixeles.
		target_info = {
			num_color_targets = 1,
			color_target_descriptions = &(sdl.GPUColorTargetDescription {
					format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window),
				}),
			has_depth_stencil_target = true,
			depth_stencil_format = g.depth_texture_format,
		},
	},
	)
	sdl_assert(g.object_pipeline != nil)
	// Una vez hayamos hecho el binding con la pipeline, podemos liberarlos.
	sdl.ReleaseGPUShader(g.gpu, vertex_shader)
	sdl.ReleaseGPUShader(g.gpu, fragment_shader)
}

update_camera :: proc(dt: f32) {
	move_input: Vec2
	if g.key_down[.W] do move_input.y = 1
	if g.key_down[.S] do move_input.y = -1
	if g.key_down[.D] do move_input.x = 1
	if g.key_down[.A] do move_input.x = -1

	look_input := g.mouse_move * MOUSE_SENSITIVITY
	g.look.yaw = math.wrap(g.look.yaw + look_input.x, 360)
	g.look.pitch = math.clamp(g.look.pitch + look_input.y, -89, 89)

	look_mat := linalg.matrix3_from_yaw_pitch_roll_f32(
		linalg.to_radians(g.look.yaw),
		linalg.to_radians(g.look.pitch),
		0,
	)

	forward := Vec3{0, 0, -1} * look_mat
	right := Vec3{1, 0, 0} * look_mat
	move_dir := forward * move_input.y + right * move_input.x
	// move_dir.y = 0

	motion := linalg.normalize0(move_dir) * MOVE_SPEED * dt

	g.camera.position += motion
	g.camera.target = g.camera.position + forward
}
