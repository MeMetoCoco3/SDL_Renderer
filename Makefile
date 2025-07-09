build:
	@rm -f odin 
	glslc ./shaders/shader.glsl.frag -o ./src/shader.spv.frag || exit 1
	glslc ./shaders/shader.glsl.vert -o ./src/shader.spv.vert || exit 1
	@odin build  ./src -out:odin -debug 
	@odin run 

run:
	odin run .
clear:
	rm -f odin

comp_shad:
	glslc ./shaders/shader.glsl.frag -o ./src/shader.spv.frag || exit 1
	glslc ./shaders/shader.glsl.vert -o ./src/shader.spv.vert || exit 1
