
function make_test(group, name, fileglob)
	local pc_proj = precore.make_project(
		group .. "_" .. name,
		"C++", "ConsoleApp",
		"./", "obj/",
		nil, nil
	)

	configuration {}
		targetname(name)

		includedirs {
			precore.subst("${ROOT}/include")
		}
		files {fileglob}

		libdirs {precore.subst("${ROOT}/lib")}
		links {"magic"}
end

function make_tests(group, tests)
	for name, fileglob in pairs(tests) do
		make_test(group, name, fileglob)
	end
end

precore.make_solution(
	"test_solution",
	{"debug", "release"},
	{"native"}
)

precore.include("general")
