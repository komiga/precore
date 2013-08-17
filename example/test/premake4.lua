
function make_test(group, name, fileglob)
	precore.make_project(
		group .. "_" .. name,
		"C++", "ConsoleApp",
		"./", "interm/"
	)

	configuration()
		includedirs(
			precore.subst("${ROOT}/include")
		)
		files(fileglob)

		targetname(name)
		libdirs("${ROOT}/lib")
		links("example_lib")
end

function make_tests(group, tests)
	for name, fileglob in pairs(tests) do
		make_test(group, name, fileglob)
	end
end

include("general")
