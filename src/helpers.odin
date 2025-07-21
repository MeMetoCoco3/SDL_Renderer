package main

import "base:runtime"
import "core:encoding/json"
import "core:log"
import "core:os"
import "core:path/filepath"
import "core:strings"
import sdl "vendor:sdl3"

load_shader :: proc(device: ^sdl.GPUDevice, shader_name: string) -> ^sdl.GPUShader {

	stage: sdl.GPUShaderStage
	switch filepath.ext(shader_name) {
	case ".vert":
		stage = .VERTEX

	case ".frag":
		stage = .FRAGMENT
	}

	format: sdl.GPUShaderFormatFlag
	format_ext: string
	entrypoint: cstring = "main"

	supported_formats := sdl.GetGPUShaderFormats(device)
	if .SPIRV in supported_formats {
		format = .SPIRV // In my case, just .SPIRV is supported!
		format_ext = ".spv"
	} else if .MSL in supported_formats {
		format = .MSL
		format_ext = ".msl"
		entrypoint = "main0"
	} else if .DXIL in supported_formats {
		format = .DXIL
		format_ext = ".dxil"
	} else {
		log.panicf("No sopported shader format: {}", supported_formats)
	}

	shader_path := filepath.join(
		{ASSETS_PATH, "shaders", "out", shader_name},
		context.temp_allocator,
	)
	shaderfile := strings.concatenate({shader_path, format_ext}, context.temp_allocator)
	code, ok := os.read_entire_file_from_filename(shaderfile, context.temp_allocator);assert(ok)
	info := load_shader_info(shader_path)

	return sdl.CreateGPUShader(
		device,
		{
			code_size = len(code),
			code = raw_data(code),
			entrypoint = entrypoint,
			format = {format},
			stage = stage,
			num_uniform_buffers = info.uniform_buffers,
			num_samplers = info.samplers,
			num_storage_buffers = info.storage_buffers,
			num_storage_textures = info.storage_textures,
		},
	)
}


Shader_Info :: struct {
	samplers:         u32,
	storage_textures: u32,
	storage_buffers:  u32,
	uniform_buffers:  u32,
}

load_shader_info :: proc(shader_path: string) -> Shader_Info {
	json_filename := strings.concatenate({shader_path, ".json"}, context.temp_allocator)
	json_data, ok := os.read_entire_file_from_filename(
		json_filename,
		context.temp_allocator,
	);assert(ok)

	result: Shader_Info
	err := json.unmarshal(
		json_data,
		&result,
		allocator = context.temp_allocator,
	);assert(err == nil)

	return result
}


sdl_assert :: proc(ok: bool, loc := #caller_location) {
	if !ok {
		log.warnf("Error on : {}, {}", loc, ok)
		log.panicf("SDL Error: {}", sdl.GetError())}
}

sdl_log :: proc "c" (
	userdata: rawptr,
	category: sdl.LogCategory,
	priority: sdl.LogPriority,
	message: cstring,
) {
	context = (transmute(^runtime.Context)userdata)^

	level: log.Level
	switch priority {
	case .DEBUG, .INVALID, .VERBOSE, .TRACE:
		level = .Debug
	case .INFO:
		level = .Info
	case .WARN:
		level = .Warning
	case .ERROR:
		level = .Error
	case .CRITICAL:
		level = .Fatal
	}

	log.logf(level, "SDL {} : {}", category, message)
}
