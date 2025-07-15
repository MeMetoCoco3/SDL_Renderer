package main


import sdl "vendor:sdl3"


Global :: struct {
	gpu:                      ^sdl.GPUDevice,
	window:                   ^sdl.Window,
	pipeline:                 ^sdl.GPUGraphicsPipeline,
	depth_texture:            ^sdl.GPUTexture,
	depth_texture_format:     sdl.GPUTextureFormat,
	swapchain_texture_format: sdl.GPUTextureFormat,
	window_size:              [2]i32,
	sampler:                  ^sdl.GPUSampler,
	camera:                   struct {
		position: Vec3,
		target:   Vec3,
	},
	look:                     struct {
		yaw:   f32,
		pitch: f32,
	},
	key_down:                 #sparse[sdl.Scancode]bool,
	mouse_move:               Vec2,
	clear_color:              sdl.FColor,
	rotate:                   bool,
	rotation:                 f32,
	model:                    Model,
}

g: Global

WHITE :: sdl.FColor{1, 1, 1, 1}
ASSETS_PATH :: "assets"
