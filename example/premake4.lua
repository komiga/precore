
dofile("../precore.lua")

-- Configs can be created before initialization

precore.make_config("example_config", {
	{
		init = function()
			print("from example_config at init()")
		end,
		solution = function(sol)
			print("from example_config at solution '" .. sol.obj.name .. "'")
		end,
		project = function(proj)
			print("from example_config at project '" .. proj.obj.name .. "'")
		end
	},
	function()
		print("from example_config at sub-block function")
	end
})

precore.make_config("example_generic_project_config", {
	function()
		configuration {}
			includedirs {"include"}
			files {"src/**.cpp"}
	end
})

precore.init(
	-- env
	nil,

	-- precore configs
	{
		"opt-clang",
		"c++11-core",
		"precore-env-root",
		"precore-generic",
		"example_config"
	}
)

precore.make_solution(
	-- name
	"example_solution",

	-- configurations
	{"debug", "release"},

	-- platforms
	{"x32", "x64"},

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
precore.apply("example_generic_project_config")

include("test")

-- For ultimate pedantry, ensure output directories are obliterated
precore.action_clean("obj", "lib")
