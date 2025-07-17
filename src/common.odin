package main


import sdl "vendor:sdl3"

Vec3 :: [3]f32
Vec2 :: [2]f32


WHITE :: sdl.FColor{1, 1, 1, 1}
ASSETS_PATH :: "assets"


Global :: struct {
	gpu:                      ^sdl.GPUDevice,
	window:                   ^sdl.Window,
	depth_texture:            ^sdl.GPUTexture,
	depth_texture_format:     sdl.GPUTextureFormat,
	swapchain_texture_format: sdl.GPUTextureFormat,
	window_size:              [2]i32,
	key_down:                 #sparse[sdl.Scancode]bool,
	mouse_move:               Vec2,
	using game:               Game_State,
}

g: Global
