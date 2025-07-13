build:
	@rm -f odin 
	shadercross assets/shaders/src/shader.frag.hlsl -o assets/shaders/out/shader.frag.spv
	shadercross assets/shaders/src/shader.vert.hlsl -o assets/shaders/out/shader.vert.spv
	@odin build  ./src -out:odin -debug 
	# @odin run 
	# ./odin
bo:
	odin run build.odin -file
bor: 
	odin run build.odin -file -- run
clear:
	rm -f odin
comp_shad:
	shadercross assets/shaders/src/shader.vert.hlsl -o assets/shaders/out/shader.frag.spv
	shadercross assets/shaders/src/shader.vert.hlsl -o assets/shaders/out/shader.vert.spv
