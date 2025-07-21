package main

import "base:runtime"
import "core:log"
import "core:math/"
import "core:math/linalg"
import "core:mem"
import "core:os"
import "core:strings"
import im "shared:imgui"
import im_sdl "shared:imgui/imgui_impl_sdl3"
import im_sdlgpu "shared:imgui/imgui_impl_sdlgpu3"
import sdl "vendor:sdl3"


init_sdl :: proc() {
	@(static) sdl_log_context: runtime.Context
	sdl_log_context = context
	sdl_log_context.logger.options -= {.Short_File_Path, .Line, .Procedure}
	sdl.SetLogPriorities(.VERBOSE)
	sdl.SetLogOutputFunction(sdl_log, &sdl_log_context)

	// Iniciamos SDL con los sistemas que queremos.
	ok := sdl.Init({.VIDEO});sdl_assert(ok)

	// Iniciamos una ventana.
	g.window = sdl.CreateWindow("Hello SDL", 1280, 780, {});sdl_assert(g.window != nil)
	ok = sdl.GetWindowSize(g.window, &g.window_size.x, &g.window_size.y)

	// Iniciamos un Device, y le pasamos el tipo de shaders que vamos a hacer.
	// SPIRV es el tipo de shaders utilizado por vulkan.
	g.gpu = sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL}, true, nil);sdl_assert(g.gpu != nil)

	// Asignamos una ventana al device.
	ok = sdl.ClaimWindowForGPUDevice(g.gpu, g.window)

	// Usamos esto para que la swapchain aplique  pow(color, 1/2.2) para conseguir colores lineales.
	ok = sdl.SetGPUSwapchainParameters(g.gpu, g.window, .SDR_LINEAR, .VSYNC);sdl_assert(ok)

	g.swapchain_texture_format = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)

	g.depth_texture_format = .D16_UNORM
	try_depth_format :: proc(format: sdl.GPUTextureFormat) {
		if sdl.GPUTextureSupportsFormat(g.gpu, format, .D2, {.DEPTH_STENCIL_TARGET}) {
			g.depth_texture_format = format
		}
	}

	try_depth_format(.D32_FLOAT)
	try_depth_format(.D24_UNORM)


	g.depth_texture = sdl.CreateGPUTexture(
		g.gpu,
		{
			format = g.depth_texture_format,
			usage = {.DEPTH_STENCIL_TARGET},
			width = u32(g.window_size.x),
			height = u32(g.window_size.y),
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)


	g.ui_input_mode = false


	_ = sdl.SetWindowRelativeMouseMode(g.window, true);sdl_assert(ok)

}

init_imgui :: proc() {
	im.CHECKVERSION()
	im.CreateContext()
	im_sdl.InitForSDLGPU(g.window)
	im_sdlgpu.Init(
		&{Device = g.gpu, ColorTargetFormat = sdl.GetGPUSwapchainTextureFormat(g.gpu, g.window)},
	)
	style := im.GetStyle()
	for &color in style.Colors {
		color.rgb = linalg.pow(color.rgb, 2.2)
	}
}
set_ui_input_mode :: proc(new_mode: bool) {
	if new_mode != g.ui_input_mode {
		g.ui_input_mode = new_mode
		_ = sdl.SetWindowRelativeMouseMode(g.window, !g.ui_input_mode)
	}
}

main :: proc() {

	// Creamos un custom logger para imprimir mensajes desde SDL
	context.logger = log.create_console_logger()

	init_sdl()
	init_imgui()

	init_game()

	last_tick := sdl.GetTicks()
	im_io := im.GetIO()


	main_loop: for {
		free_all(context.temp_allocator)

		g.mouse_move = {}

		current_tick := sdl.GetTicks()
		delta_time := f32(current_tick - last_tick) / 1000
		last_tick = current_tick

		g.ui_input_mode = !sdl.GetWindowRelativeMouseMode(g.window)


		event: sdl.Event
		for sdl.PollEvent(&event) {
			if g.ui_input_mode do im_sdl.ProcessEvent(&event)

			#partial switch event.type {
			case .QUIT:
				break main_loop
			case .KEY_DOWN:
				if !im_io.WantCaptureKeyboard {
					if event.key.scancode == .ESCAPE do break main_loop
					if event.key.scancode == .U do set_ui_input_mode(!g.ui_input_mode)
				}

				if !g.ui_input_mode {
					if event.key.scancode == .ESCAPE || event.key.scancode == .Q do break main_loop
					g.key_down[event.key.scancode] = true
				}
			case .KEY_UP:
				if !g.ui_input_mode {
					g.key_down[event.key.scancode] = false
				}

			case .MOUSE_MOTION:
				if !g.ui_input_mode {
					g.mouse_move += {event.motion.xrel, event.motion.yrel}
				}

			case .MOUSE_BUTTON_DOWN:
				if event.button.button == 2 {
					set_ui_input_mode(!g.ui_input_mode)
				}
			}

		}

		im_sdlgpu.NewFrame()
		im_sdl.NewFrame()
		im.NewFrame()

		update_game(delta_time)

		// Creamos un buffer de comandos, encargado de enviar ordenes a la GPU.
		cmd_buf := sdl.AcquireGPUCommandBuffer(g.gpu);sdl_assert(cmd_buf != nil)
		swapchain_tex: ^sdl.GPUTexture
		ok := sdl.WaitAndAcquireGPUSwapchainTexture(
			cmd_buf,
			g.window,
			&swapchain_tex,
			nil,
			nil,
		);sdl_assert(ok)


		// RENDER
		im.Render()
		im_draw_data := im.GetDrawData()

		// Seria null si la ventana estubiera minimizada.
		if swapchain_tex != nil {
			render_game(cmd_buf, swapchain_tex)

			if im_draw_data.DisplaySize.x > 0 && im_draw_data.DisplaySize.y > 0 {
				im_sdlgpu.PrepareDrawData(im_draw_data, cmd_buf)
				im_color_target := sdl.GPUColorTargetInfo {
					texture  = swapchain_tex,
					load_op  = .LOAD,
					store_op = .STORE,
				}

				im_render_pass := sdl.BeginGPURenderPass(cmd_buf, &im_color_target, 1, nil)
				im_sdlgpu.RenderDrawData(im_draw_data, cmd_buf, im_render_pass)
				sdl.EndGPURenderPass(im_render_pass)
			}

		}

		ok = sdl.SubmitGPUCommandBuffer(cmd_buf);sdl_assert(ok)
	}
}
