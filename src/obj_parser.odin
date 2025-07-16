package main
import "core:fmt"
import os "core:os/os2"
import "core:strconv"
import "core:strings"


Obj_Data :: struct {
	positions: []Vec3,
	uvs:       []Vec2,
	normals:   []Vec3,
	faces:     []Obj_FaceIndex,
}

Obj_FaceIndex :: struct {
	pos:    uint,
	uv:     uint,
	normal: uint,
}


// main :: proc() {
// 	_ = obj_load("assets/models/ship-pirate-large.obj")
//
//
// }

obj_load :: proc(filename: string, alloc := context.allocator) -> Obj_Data {
	data, err := os.read_entire_file_from_path(filename, context.temp_allocator);assert(err == nil)
	defer free_all(context.temp_allocator)
	input_string := string(data)

	positions := make([dynamic]Vec3, alloc)
	uvs := make([dynamic]Vec2, alloc)
	normals := make([dynamic]Vec3, alloc)
	faces := make([dynamic]Obj_FaceIndex, alloc)

	for line in strings.split_lines_iterator(&input_string) {
		if len(line) == 0 do continue

		switch line[0] {
		case 'v':
			switch line[1] {
			case ' ':
				position := parse_vec3(line[2:])
				// fmt.println(position)
				append(&positions, position)
			case 't':
				uv := parse_uv(line[3:])
				append(&uvs, uv)
			case 'n':
				normal := parse_vec3(line[3:])
				append(&normals, normal)
			}
		case 'f':
			indices := parse_faces(line[2:])
			append_elems(&faces, indices[0], indices[1], indices[2])
		}
	}

	return Obj_Data{positions = positions[:], uvs = uvs[:], normals = normals[:], faces = faces[:]}
}

extract_separated :: proc(s: ^string, sep: byte) -> string {
	substring, ok := strings.split_by_byte_iterator(s, sep)
	assert(ok)
	return substring
}

parse_f32 :: proc(s: string) -> f32 {
	res, ok := strconv.parse_f32(s)
	assert(ok)
	return res
}

parse_uint :: proc(s: string) -> uint {
	res, ok := strconv.parse_uint(s)
	assert(ok)
	return res
}
parse_vec3 :: proc(s: string) -> Vec3 {
	s := s
	x := parse_f32(extract_separated(&s, ' '))
	y := parse_f32(extract_separated(&s, ' '))
	z := parse_f32(extract_separated(&s, ' '))
	return Vec3{x, y, z}
}

parse_uv :: proc(s: string) -> Vec2 {
	s := s
	x := parse_f32(extract_separated(&s, ' '))
	y := parse_f32(extract_separated(&s, ' '))
	return Vec2{x, y}
}

parse_faces :: proc(s: string) -> [3]Obj_FaceIndex {
	s := s
	return {
		parse_face_index(extract_separated(&s, ' ')),
		parse_face_index(extract_separated(&s, ' ')),
		parse_face_index(extract_separated(&s, ' ')),
	}
}

parse_face_index :: proc(s: string) -> Obj_FaceIndex {
	s := s
	return {
		pos = parse_uint(extract_separated(&s, '/')) - 1,
		uv = parse_uint(extract_separated(&s, '/')) - 1,
		normal = parse_uint(extract_separated(&s, '/')) - 1,
	}
}


obj_destroy :: proc(obj: Obj_Data) {
	delete(obj.positions)
	delete(obj.uvs)
	delete(obj.normals)
	delete(obj.faces)
}
