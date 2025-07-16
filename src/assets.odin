package main
import "core:path/filepath"
import "core:slice"
import "core:strings"
import sdl "vendor:sdl3"
import stbi "vendor:stb/image"

load_texture_file :: proc(copy_pass: ^sdl.GPUCopyPass, texture_file: string) -> ^sdl.GPUTexture {

	texture_path := filepath.join({ASSETS_PATH, "textures", texture_file}, context.temp_allocator)

	img_size: [2]i32
	pixels := stbi.load(
		strings.clone_to_cstring(texture_path, context.temp_allocator),
		&img_size.x,
		&img_size.y,
		nil,
		4,
	);assert(pixels != nil);defer stbi.image_free(pixels)
	pixels_byte_size := int((img_size.x * img_size.y * 4))

	texture := upload_texture(
		copy_pass,
		slice.from_ptr(pixels, pixels_byte_size),
		u32(img_size.x),
		u32(img_size.y),
	)

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
		texture = load_texture_file(copy_pass, texture_file),
	}
}
