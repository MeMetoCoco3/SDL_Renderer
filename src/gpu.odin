package main
import "core:mem"
import "core:slice"
import sdl "vendor:sdl3"


upload_texture :: proc(
	copy_pass: ^sdl.GPUCopyPass,
	pixels: []byte,
	width, height: u32,
) -> ^sdl.GPUTexture {
	texture := sdl.CreateGPUTexture(
		g.gpu,
		{
			type = .D2,
			format = .R8G8B8A8_UNORM_SRGB,
			usage = {.SAMPLER},
			height = height,
			width = width,
			layer_count_or_depth = 1,
			num_levels = 1,
		},
	)

	tex_transfer_buffer := sdl.CreateGPUTransferBuffer(
		g.gpu,
		{usage = .UPLOAD, size = u32(len(pixels))},
	)
	tex_transfer_memory := sdl.MapGPUTransferBuffer(g.gpu, tex_transfer_buffer, false)
	mem.copy(tex_transfer_memory, raw_data(pixels), len(pixels))
	sdl.UnmapGPUTransferBuffer(g.gpu, tex_transfer_buffer)

	sdl.UploadToGPUTexture(
		copy_pass,
		{transfer_buffer = tex_transfer_buffer},
		{texture = texture, w = width, h = height, d = 1},
		false,
	)

	sdl.ReleaseGPUTransferBuffer(g.gpu, tex_transfer_buffer)

	return texture
}

upload_cubemap_texture_single :: proc(
	copy_pass: ^sdl.GPUCopyPass,
	pixels: []byte,
	width, height: u32,
) -> ^sdl.GPUTexture {
	/*
	 The cubemap images are layed out in a single texture like this:

	  t
	 lfrb
	  b

	 there are 3 rows and 4 columns
	 1st row contains top image at the 2nd column
	 2nd row contains left->front->right->bottom images (so all 4 columns used)
	 3rd row contains bottom image at the 2nd column

	 hence the size of the cube texture (side) is actually w/4 or h/3 (must be the same)
	*/
	CUBE_COLS :: 4
	CUBE_ROWS :: 3

	size := width / CUBE_COLS
	assert(width == size * CUBE_COLS)
	assert(height == size * CUBE_ROWS)

	texture := sdl.CreateGPUTexture(
	g.gpu,
	{
		type                 = .CUBE,
		format               = .R8G8B8A8_UNORM_SRGB, // pixels are in sRGB, converted to linear in shaders
		usage                = {.SAMPLER},
		width                = size,
		height               = size,
		layer_count_or_depth = 6,
		num_levels           = 1,
	},
	)

	tex_transfer_buf := sdl.CreateGPUTransferBuffer(
		g.gpu,
		{usage = .UPLOAD, size = u32(len(pixels))},
	)
	tex_transfer_mem := sdl.MapGPUTransferBuffer(g.gpu, tex_transfer_buf, false)
	mem.copy(tex_transfer_mem, raw_data(pixels), len(pixels))
	sdl.UnmapGPUTransferBuffer(g.gpu, tex_transfer_buf)

	for side in sdl.GPUCubeMapFace {
		row, col: u32
		switch side {
		case .POSITIVEX:
			row, col = 1, 2
		case .NEGATIVEX:
			row, col = 1, 0
		case .POSITIVEY:
			row, col = 0, 1
		case .NEGATIVEY:
			row, col = 2, 1
		case .POSITIVEZ:
			row, col = 1, 1
		case .NEGATIVEZ:
			row, col = 1, 3
		}

		BYTES_PER_PIXEL :: 4

		cube_row_byte_size := width * size * BYTES_PER_PIXEL

		offset := cube_row_byte_size * row
		offset += size * BYTES_PER_PIXEL * col

		sdl.UploadToGPUTexture(
			copy_pass,
			{transfer_buffer = tex_transfer_buf, offset = offset, pixels_per_row = width},
			{texture = texture, layer = u32(side), w = size, h = size, d = 1},
			false,
		)
	}

	sdl.ReleaseGPUTransferBuffer(g.gpu, tex_transfer_buf)

	return texture
}
// upload_cube_texture_single :: proc(
// 	copy_pass: ^sdl.GPUCopyPass,
// 	pixels: []byte,
// 	width, height: u32,
// ) -> ^sdl.GPUTexture {
//
// 	CUBE_COLS :: 4
// 	CUBE_ROWS :: 3
//
// 	size := width / CUBE_COLS
// 	assert(width == size * CUBE_COLS)
// 	assert(height == size * CUBE_ROWS)
//
// 	texture := sdl.CreateGPUTexture(
// 		g.gpu,
// 		{
// 			type = .CUBE,
// 			format = .R8G8B8A8_UNORM_SRGB,
// 			usage = {.SAMPLER},
// 			height = size,
// 			width = size,
// 			layer_count_or_depth = 6,
// 			num_levels = 1,
// 		},
// 	)
//
// 	tex_transfer_buffer := sdl.CreateGPUTransferBuffer(
// 		g.gpu,
// 		{usage = .UPLOAD, size = u32(len(pixels))},
// 	)
// 	tex_transfer_memory := sdl.MapGPUTransferBuffer(g.gpu, tex_transfer_buffer, false)
// 	mem.copy(tex_transfer_memory, raw_data(pixels), len(pixels))
// 	sdl.UnmapGPUTransferBuffer(g.gpu, tex_transfer_buffer)
//
// 	for side in sdl.GPUCubeMapFace {
// 		row, col: u32
// 		switch side {
// 		case .POSITIVEX:
// 			row, col = 1, 2
// 		case .NEGATIVEX:
// 			row, col = 1, 0
// 		case .POSITIVEY:
// 			row, col = 0, 1
// 		case .NEGATIVEY:
// 			row, col = 2, 1
// 		case .POSITIVEZ:
// 			row, col = 1, 1
// 		case .NEGATIVEZ:
// 			row, col = 1, 3
// 		}
//
// 		PIXEL_SIZE :: 4
//
// 		cube_row_byte_size := width * size * PIXEL_SIZE
//
// 		offset := cube_row_byte_size * row
// 		offset += cube_row_byte_size * col * PIXEL_SIZE
// 		sdl.UploadToGPUTexture(
// 			copy_pass,
// 			{transfer_buffer = tex_transfer_buffer, offset = offset, pixels_per_row = width},
// 			{texture = texture, layer = u32(side), w = size, h = size, d = 1},
// 			false,
// 		)
// 	}
//
// 	sdl.ReleaseGPUTransferBuffer(g.gpu, tex_transfer_buffer)
//
// 	return texture
// }
//
upload_cube_texture_sides :: proc(
	copy_pass: ^sdl.GPUCopyPass,
	pixels: [sdl.GPUCubeMapFace][]byte,
	size: u32,
) -> ^sdl.GPUTexture {
	texture := sdl.CreateGPUTexture(
		g.gpu,
		{
			type = .CUBE,
			format = .R8G8B8A8_UNORM_SRGB,
			usage = {.SAMPLER},
			height = size,
			width = size,
			layer_count_or_depth = 6,
			num_levels = 1,
		},
	)

	side_byte_size := int(size * size * 4)
	for side in pixels do assert(len(side) == side_byte_size)

	tex_transfer_buffer := sdl.CreateGPUTransferBuffer(
		g.gpu,
		{usage = .UPLOAD, size = u32(side_byte_size * 6)},
	)
	tex_transfer_memory := transmute([^]byte)sdl.MapGPUTransferBuffer(
		g.gpu,
		tex_transfer_buffer,
		false,
	)

	offset := 0
	for side in pixels {
		mem.copy(tex_transfer_memory[offset:], raw_data(side), side_byte_size)
		offset += side_byte_size
	}
	sdl.UnmapGPUTransferBuffer(g.gpu, tex_transfer_buffer)

	offset = 0
	for side, i in pixels {
		sdl.UploadToGPUTexture(
			copy_pass,
			{transfer_buffer = tex_transfer_buffer, offset = u32(offset)},
			{texture = texture, w = size, h = size, d = 1, layer = u32(i)},
			false,
		)
		offset += side_byte_size
	}

	sdl.ReleaseGPUTransferBuffer(g.gpu, tex_transfer_buffer)

	return texture
}

upload_mesh :: proc(copy_pass: ^sdl.GPUCopyPass, vertices: []$T, indices: []$S) -> Mesh {
	return upload_mesh_bytes(
		copy_pass,
		slice.to_bytes(vertices),
		slice.to_bytes(indices),
		len(indices),
	)
}


upload_mesh_bytes :: proc(
	copy_pass: ^sdl.GPUCopyPass,
	vertices: []byte,
	indices: []byte,
	num_indices: int,
) -> Mesh {
	vertices_byte_size := len(vertices) * size_of(vertices[0])
	indices_byte_size := len(indices) * size_of(indices[0])

	// Creamos un buffer para los datos.
	vertex_buffer := sdl.CreateGPUBuffer(
		g.gpu,
		{usage = {.VERTEX}, size = u32(vertices_byte_size)},
	)
	index_buffer := sdl.CreateGPUBuffer(g.gpu, {usage = {.INDEX}, size = u32(indices_byte_size)})

	// Creamos un transfer_buffer, es un buffer especial desde el que podemos copiar datos al GPU buffer.
	transfer_buffer := sdl.CreateGPUTransferBuffer(
		g.gpu,
		{usage = .UPLOAD, size = u32(vertices_byte_size + indices_byte_size)},
	)


	// Pedimos la memoria a la que vamos a pasar nuestros datos, y la pasamos, tras esto podemos llamar a Unmap
	transfer_memory := transmute([^]byte)sdl.MapGPUTransferBuffer(g.gpu, transfer_buffer, false)
	mem.copy(transfer_memory, raw_data(vertices), vertices_byte_size)
	mem.copy(transfer_memory[vertices_byte_size:], raw_data(indices), indices_byte_size)
	sdl.UnmapGPUTransferBuffer(g.gpu, transfer_buffer)

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

	sdl.ReleaseGPUTransferBuffer(g.gpu, transfer_buffer)

	return {vertex_buf = vertex_buffer, index_buf = index_buffer, num_indices = u32(num_indices)}
}
