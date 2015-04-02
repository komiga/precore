
dofile("../precore_import.lua")

import_precore()

-- Configs can be created before initialization

precore.make_config("example.config", nil, {
{
	global = function()
		print("from example.config at global")
	end,
	solution = function(sol)
		print("from example.config at solution '" .. sol.obj.name .. "'")
	end,
	project = function(proj)
		print("from example.config at project '" .. proj.obj.name .. "'")
	end
},
function()
	print("from example.config at sub-block function")
end})

precore.make_config("example.generic-project-config", nil, {
function()
	configuration {}
		includedirs {"include"}
		files {"src/**.cpp"}
end})

precore.init(
	-- env
	nil,

	-- precore configs
	{
		"precore.clang-opts",
		"precore.c++11-core",
		"precore.env-common",
		"precore.generic",
		"example.config",
	}
)

precore.make_solution(
	-- name
	"example_solution",

	-- configurations
	{"debug", "release"},

	-- platforms
	{"native"},

	-- env, precore configs
	nil, nil
)

precore.make_project(
	-- name
	"example_lib",

	-- language, kind
	"C++", "StaticLib",

	-- target and obj dirs
	"lib/", "obj/",

	-- env, precore configs
	nil, nil
)

--[[
	premake tries to reference by project when linking -- even cross-
	solution. Since test/ is a separate solution, we can't link to
	the example_lib project by its name, so we'll rename the build
	target.
--]]
configuration {}
	targetname("magic")

-- Can also be passed to make_project()
precore.apply("example.generic-project-config")

precore.import("test")

-- For ultimate pedantry, ensure output directories are obliterated
precore.action_clean("obj", "lib")
