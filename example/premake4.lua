
dofile("../precore.lua")

-- Configs can be created before initialization

precore.make_config("example_config", {
	{
		init = function()
			print("from example_config at init()")
		end,
		solution = function(sol)
			print("from example_config at solution '" .. sol.name .. "'")
		end,
		project = function(proj)
			print("from example_config at project '" .. proj.name .. "'")
		end
	},
	function()
		print("from example_config at sub-block function")
	end
})

precore.make_config("example_generic_project_config", {
	function()
		configuration()
			includedirs(
				"include"
			)
			files(
				"src/**.cpp"
			)
	end
})

precore.init(
	-- env
	nil,

	-- precore configs
	{
		"c++11-core",
		"opt-clang",
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

	-- env
	nil,

	-- precore configs
	nil
)

precore.make_project(
	-- name
	"example_lib",

	-- language, kind
	"C++", "StaticLib",

	-- target and obj dirs
	"lib/", "interm/",

	-- env
	nil,

	-- precore configs
	nil
)

-- Could just as easily be placed in make_project()
precore.apply("example_generic_project_config")

include("test")


print(
	"global: " .. precore.state.env["ROOT"] .. "\n" ..
	"solution: " .. precore.active_solution().env["ROOT"]
)

for name, pc_proj in pairs(precore.active_solution().projects) do
	print(
		"project '" .. name .. "': '" .. pc_proj.env["ROOT"] ..
		"' with basedir: '" .. pc_proj.obj.basedir .. "'"
	)
end
