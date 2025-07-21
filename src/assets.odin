package main
import "core:path/filepath"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"


load_pixels :: proc(texture_file: string) -> (pixels: []byte, size: [2]u32) {
	texture_path := filepath.join({ASSETS_PATH, "textures", texture_file}, context.temp_allocator)

	img_size: [2]i32
	pixels_data := stbi.load(
		strings.clone_to_cstring(texture_path, context.temp_allocator),
		&img_size.x,
		&img_size.y,
		nil,
		4,
	);assert(pixels_data != nil)
	pixels_byte_size := int((img_size.x * img_size.y * 4))

	pixels = slice.bytes_from_ptr(pixels_data, int(pixels_byte_size))
	size = {u32(img_size.x), u32(img_size.y)}
	return
}

free_pixels :: proc(pixels: []byte) {
	stbi.image_free(raw_data(pixels))
}

load_cubemap_texture_files :: proc(
	copypass: ^sdl.GPUCopyPass,
	texture_paths: [sdl.GPUCubeMapFace]string,
) -> ^sdl.GPUTexture {
	pixels: [sdl.GPUCubeMapFace][]byte
	size: u32


	for file, side in texture_paths {
		texture, img_size := load_pixels(file)
		pixels[side] = texture

		assert(img_size.x == img_size.y)

		if uint(side) == 0 {
			size = img_size.x
		} else {
			assert(size == img_size.x)
		}

	}
	texture := upload_cube_texture_sides(copypass, pixels, size)

	for side in pixels {
		free_pixels(side)
	}

	return texture
}

load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {
	pixels, img_size := load_pixels(texture_file);assert(pixels != nil)
	texture := upload_texture(copy_pass, pixels, img_size.x, img_size.y)

	free_pixels(pixels)
	return texture
}

load_cubemap_texture_single :: proc(
	copy_pass: ^sdl.GPUCopyPass,
	texture_file: string,
) -> ^sdl.GPUTexture {
	pixels, img_size := load_pixels(texture_file)
	texture := upload_cubemap_texture_single(copy_pass, pixels, img_size.x, img_size.y)
	free_pixels(pixels)
	return texture
}


load_obj_file :: proc(copy_pass: ^sdl.GPUCopyPass, obj_file: string) -> Mesh {
	model_path := filepath.join({ASSETS_PATH, "models", obj_file}, context.temp_allocator)
	obj_data := obj_load(model_path)

	vertices := make([]Vertex_Data, len(obj_data.faces))
	indices := make([]u16, len(obj_data.faces))

	for face, i in obj_data.faces {
		uv := obj_data.uvs[face.uv]
		vertices[i] = {
			pos    = obj_data.positions[face.pos],
			uv     = {uv.x, 1 - uv.y},
			color  = WHITE,
			normal = obj_data.normals[face.normal],
		}
		indices[i] = u16(i)
	}

	obj_destroy(obj_data)

	mesh := upload_mesh(copy_pass, vertices, indices)
	delete(indices)
	delete(vertices)

	return mesh
}


load_model :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file, model_file: string) -> Model {
	return {
		mesh = load_obj_file(copy_pass, model_file),
		material = {diffuse_texture = load_texture_file(copy_pass, texture_file)},
	}
}
