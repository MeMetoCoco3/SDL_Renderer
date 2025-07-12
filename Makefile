build:
	@rm -f odin 
	# glslc ./shaders/shader.glsl.frag -o ./src/shader.spv.frag || exit 1
	# glslc ./shaders/shader.glsl.vert -o ./src/shader.spv.vert || exit 1
	shadercross assets/shaders/src/shader.frag.hlsl -o assets/shaders/out/shader.frag.spv
	shadercross assets/shaders/src/shader.vert.hlsl -o assets/shaders/out/shader.vert.spv
	@odin build  ./src -out:odin -debug 
	@odin run 

clear:
	rm -f odin

comp_shad:
	shadercross assets/shaders/src/shader.vert.hlsl -o assets/shaders/out/shader.frag.spv
	shadercross assets/shaders/src/shader.vert.hlsl -o assets/shaders/out/shader.vert.spv
