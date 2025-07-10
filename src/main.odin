package main

import "base:runtime"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"


Vertex_Data :: struct {
	pos:   Vec3,
	color: sdl.FColor,
	uv:    Vec2,
}

Model :: struct {
	vertex_buf:  ^sdl.GPUBuffer,
	index_buf:   ^sdl.GPUBuffer,
	num_indices: u32,
	texture:     ^sdl.GPUTexture,
}


default_context: runtime.Context

frag_shader_code := #load("shader.spv.frag")
vert_shader_code := #load("shader.spv.vert")

gpu: ^sdl.GPUDevice
window: ^sdl.Window
pipeline: ^sdl.GPUGraphicsPipeline
depth_texture: ^sdl.GPUTexture
window_size: [2]i32


// We need to define the buffer where we will measure our depth for depth buffer
DEPTH_TEXTURE_FORMAT :: sdl.GPUTextureFormat.D32_FLOAT
WHITE :: sdl.FColor{1, 1, 1, 1}

init :: proc() {
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(
		proc "c" (
			userdata: rawptr,
			category: sdl.LogCategory,
			priority: sdl.LogPriority,
			message: cstring,
		) {
			context = default_context
			log.debugf("SDL {} [{}]: {}", category, priority, message)
		},
		nil,
	)

	// Iniciamos SDL con los sistemas que queremos.
	ok := sdl.Init({.VIDEO});assert(ok)

	// Iniciamos una ventana.
	window = sdl.CreateWindow("Hello SDL", 1280, 780, {});assert(window != nil)
	// Asignamos una ventana al device.
	ok = sdl.ClaimWindowForGPUDevice(gpu, window);assert(ok)
	ok = sdl.GetWindowSize(window, &window_size.x, &window_size.y);assert(ok)
	// Iniciamos un Device, y le pasamos el tipo de shaders que vamos a hacer.
	// SPIRV es el tipo de shaders utilizado por vulkan.
	gpu = sdl.CreateGPUDevice({.SPIRV}, true, nil)
	assert(gpu != nil)


	depth_texture = sdl.CreateGPUTexture(
		gpu,
		{
			format = DEPTH_TEXTURE_FORMAT,
			usage = {.DEPTH_STENCIL_TARGET},
			width = u32(window_size.x),
			height = u32(window_size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)
}

setup_pipeline :: proc() {
	// Asignamos los shaders a la GPU.
	vertex_shader := load_shader(
		gpu,
		vert_shader_code,
		.VERTEX,
		num_uniform_buffers = 1,
		num_samplers = 0,
	)

	fragment_shader := load_shader(
		gpu,
		frag_shader_code,
		.FRAGMENT,
		num_uniform_buffers = 0,
		num_samplers = 1, // Esta linea me ha matado, por su culpa la textura no renderizaba.
	)

	// Describimos nuestros datos, en este caso decimos que vamos a pasar dos datos en esas localizaciones(las definimos en nuestros shaders), 
	// tendran ese tamaño (3/4 floats), y tendran un offset de eso.
	vertex_attributes := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = u32(offset_of(Vertex_Data, pos))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Vertex_Data, color))},
		{location = 2, format = .FLOAT2, offset = u32(offset_of(Vertex_Data, uv))},
	}


	// Creamos un GPUGraphicsPipelineCreateInfo con los datos de nuestros shaders.
	pipeline = sdl.CreateGPUGraphicsPipeline(
		gpu,
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
			// Creamos GPUGraphicsPipelineTargetInfo que define el color de nuestros pixeles.
			target_info = {
				num_color_targets = 1,
				color_target_descriptions = &(sdl.GPUColorTargetDescription {
						format = sdl.GetGPUSwapchainTextureFormat(gpu, window),
					}),
				has_depth_stencil_target = true,
				depth_stencil_format = DEPTH_TEXTURE_FORMAT,
			},
		},
	)
	// Una vez hayamos hecho el binding con la pipeline, podemos liberarlos.
	sdl.ReleaseGPUShader(gpu, vertex_shader)
	sdl.ReleaseGPUShader(gpu, fragment_shader)

}


load_model :: proc(texture_path, model_path: string) -> Model {
	// Load pixels
	img_size: [2]i32
	// stbi.set_flip_vertically_on_load(1) // Coordinates are fliped, we could also invert our UV coordinates
	pixels := stbi.load(
		strings.clone_to_cstring(texture_path, context.temp_allocator),
		&img_size.x,
		&img_size.y,
		nil,
		4,
	);assert(pixels != nil);defer stbi.image_free(pixels)
	log.info(pixels)
	pixelx_byte_size := img_size.x * img_size.y * 4

	// Create texture on the gpu
	pixels_texture := sdl.CreateGPUTexture(
		gpu,
		{
			format = .R8G8B8A8_UNORM,
			usage = {.SAMPLER},
			height = u32(img_size.y),
			width = u32(img_size.x),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)


	obj_data := obj_load(model_path)


	vertices := make([]Vertex_Data, len(obj_data.faces))
	indices := make([]u16, len(obj_data.faces))

	for face, i in obj_data.faces {
		uv := obj_data.uvs[face.uv]
		vertices[i] = {
			pos   = obj_data.positions[face.pos],
			uv    = {uv.x, 1 - uv.y},
			color = WHITE,
		}
		indices[i] = u16(i)
	}

	obj_destroy(obj_data)

	num_indices := len(indices)


	vertices_byte_size := len(vertices) * size_of(vertices[0])
	indices_byte_size := len(indices) * size_of(indices[0])

	// Creamos un buffer para los datos.
	vertex_buffer := sdl.CreateGPUBuffer(gpu, {usage = {.VERTEX}, size = u32(vertices_byte_size)})
	index_buffer := sdl.CreateGPUBuffer(gpu, {usage = {.INDEX}, size = u32(indices_byte_size)})

	// Creamos un transfer_buffer, es un buffer especial desde el que podemos copiar datos al GPU buffer.
	transfer_buffer := sdl.CreateGPUTransferBuffer(
		gpu,
		{usage = .UPLOAD, size = u32(vertices_byte_size + indices_byte_size)},
	)

	// Pedimos la memoria a la que vamos a pasar nuestros datos, y la pasamos, tras esto podemos llamar a Unmap
	transfer_memory := transmute([^]byte)sdl.MapGPUTransferBuffer(gpu, transfer_buffer, false)
	mem.copy(transfer_memory, raw_data(vertices), vertices_byte_size)
	mem.copy(transfer_memory[vertices_byte_size:], raw_data(indices), indices_byte_size)
	sdl.UnmapGPUTransferBuffer(gpu, transfer_buffer)

	delete(indices)
	delete(vertices)

	tex_transfer_buffer := sdl.CreateGPUTransferBuffer(
		gpu,
		{usage = .UPLOAD, size = u32(pixelx_byte_size)},
	)

	tex_transfer_memory := sdl.MapGPUTransferBuffer(gpu, tex_transfer_buffer, false)
	mem.copy(tex_transfer_memory, pixels, int(pixelx_byte_size))
	sdl.UnmapGPUTransferBuffer(gpu, tex_transfer_buffer)


	// Para enviar ordenes necesitamos un command buffer, la orden es enviar la memoria de transfer buffer al buffer de la GPU, 
	// para ello necesitamos un copy_pass
	copy_cmd_buffer := sdl.AcquireGPUCommandBuffer(gpu)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buffer)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer_buffer},
		{buffer = vertex_buffer, size = u32(vertices_byte_size)},
		false,
	)
	sdl.UploadToGPUBuffer(
		copy_pass,
		{transfer_buffer = transfer_buffer, offset = u32(vertices_byte_size)},
		{buffer = index_buffer, size = u32(indices_byte_size)},
		false,
	)

	sdl.UploadToGPUTexture(
		copy_pass,
		{transfer_buffer = tex_transfer_buffer},
		{texture = pixels_texture, w = u32(img_size.x), h = u32(img_size.y), d = 1},
		false,
	)

	sdl.EndGPUCopyPass(copy_pass)

	ok := sdl.SubmitGPUCommandBuffer(copy_cmd_buffer);assert(ok)

	// Ya hemos terminado con el transfer_buffer, asi que lo liberamos.
	sdl.ReleaseGPUTransferBuffer(gpu, transfer_buffer)
	sdl.ReleaseGPUTransferBuffer(gpu, tex_transfer_buffer)

	return {
		vertex_buf = vertex_buffer,
		index_buf = index_buffer,
		num_indices = u32(num_indices),
		texture = pixels_texture,
	}
}


main :: proc() {

	// Creamos un custom logger para imprimir mensajes desde SDL
	context.logger = log.create_console_logger()
	default_context = context

	init()
	setup_pipeline()
	model := load_model("src/colormap.png", "assets/models/ship-pirate-large.obj")

	// Create a sampler for shader
	sampler := sdl.CreateGPUSampler(gpu, {})


	// Creamos una matriz de projeccion.
	proj_mat := linalg.matrix4_perspective_f32(
		70,
		f32(window_size.x) / f32(window_size.y),
		0.1,
		1000,
	)
	ROTATION_SPEED := linalg.to_radians(f32(90))
	rotation := f32(0)

	UBO :: struct {
		mvp: matrix[4, 4]f32,
	}


	last_tick := sdl.GetTicks()

	main_loop: for {
		free_all(context.temp_allocator)
		current_tick := sdl.GetTicks()
		delta_time := f32(current_tick - last_tick) / 1000
		last_tick = current_tick


		event: sdl.Event
		for sdl.PollEvent(&event) {
			#partial switch event.type {
			case .QUIT:
				break main_loop
			case .KEY_DOWN:
				if event.key.scancode == .ESCAPE || event.key.scancode == .Q do break main_loop
			}
		}


		// GAME STATE
		// RENDER
		// Creamos un buffer de comandos, encargado de enviar ordenes a la GPU.
		cmd_buf := sdl.AcquireGPUCommandBuffer(gpu)

		// WARN: Chekear esta swapchain texture definicion
		// Swapchain texture es una textura que con el contenido de una ventana..
		swapchain_tex: ^sdl.GPUTexture
		ok := sdl.WaitAndAcquireGPUSwapchainTexture(
			cmd_buf,
			window,
			&swapchain_tex,
			nil,
			nil,
		);assert(ok)

		rotation += ROTATION_SPEED * delta_time
		model_mat :=
			linalg.matrix4_translate_f32({0, -4, -13}) *
			linalg.matrix4_rotate_f32(rotation, {0, 1, 0})
		ubo := UBO {
			mvp = proj_mat * model_mat,
		}

		// Seria null si la ventana estubiera minimizada.
		if swapchain_tex != nil {
			color_target := sdl.GPUColorTargetInfo {
				texture     = swapchain_tex,
				load_op     = .CLEAR,
				clear_color = {0, 0.2, 0.5, 1},
				store_op    = .STORE,
			}


			depth_target_info := sdl.GPUDepthStencilTargetInfo {
				texture     = depth_texture,
				load_op     = .CLEAR,
				clear_depth = 1,
				store_op    = .DONT_CARE,
			}

			// Empezamos el proceso de pasar datos a nuestra GPU, debemos bindearlo a la pipeline.
			render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, &depth_target_info)

			sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
			sdl.BindGPUVertexBuffers(
				render_pass,
				0,
				&(sdl.GPUBufferBinding{buffer = model.vertex_buf}),
				1,
			)
			sdl.BindGPUIndexBuffer(render_pass, {buffer = model.index_buf}, ._16BIT)
			// Este 0 es el slot_index, hace referencia al binding = 0  en el vertex shader.
			sdl.PushGPUVertexUniformData(cmd_buf, 0, &ubo, size_of(ubo))
			sdl.BindGPUFragmentSamplers(
				render_pass,
				0,
				&(sdl.GPUTextureSamplerBinding{texture = model.texture, sampler = sampler}),
				1,
			)
			sdl.DrawGPUIndexedPrimitives(render_pass, model.num_indices, 1, 0, 0, 0)
			sdl.EndGPURenderPass(render_pass)
		} else {
			log.debug("NOT RENDERING!")
		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf);assert(ok)
	}
}


load_shader :: proc(
	device: ^sdl.GPUDevice,
	code: []u8,
	stage: sdl.GPUShaderStage,
	num_uniform_buffers: u32,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = "main",
			format = {.SPIRV},
			stage = stage,
			num_uniform_buffers = num_uniform_buffers,
			num_samplers = num_samplers,
		},
	)
}
