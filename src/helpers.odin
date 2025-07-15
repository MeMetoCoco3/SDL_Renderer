package main

import "core:log"
import sdl "vendor:sdl3"

sdl_assert :: proc(ok: bool) {
	if !ok do log.panicf("SDL Error: {}", sdl.GetError())
}
