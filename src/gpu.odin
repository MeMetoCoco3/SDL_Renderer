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
