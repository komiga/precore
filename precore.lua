
-- precore

-- TODO: Substitution table access for solution and project

precore = {
	internal = {},
	configs = {},

	state = {
		initialized = false,
		env = {},
		enabled_opts = {},
		configs = {},
		solutions = {}
	}
}

local SubBlockFunctionKind = {
	init = 1,
	solution = 2,
	project = 3,
	non_global = 4
}

local ConfigScopeKind = {
	global = 1,
	solution = 2,
	project = 3
}

function precore.internal.init_guard()
	if not precore.state.initialized then
		error(
			"precore must be initialized"
		)
	end
end

function precore.internal.table_find_name(t, name)
	for _, v in pairs(t) do
		if name == v.name then
			return v
		end
	end
	return nil
end

function precore.internal.table_has(t, v)
	for _, tv in pairs(t) do
		if tv == v then
			return true
		end
	end
	return false
end

function precore.internal.table_flatten(t)
	for i, v in ipairs(t) do
		if "table" == type(v) then
			table.remove(t, i)
			for ii, vv in ipairs(v) do
				table.insert(t, i + ii - 1, vv)
			end
		end
	end
	return t
end

function precore.internal.do_subst(str, env)
	return string.gsub(str, "%${(%w+)}", env)
end

function precore.internal.execute_func_block(func, kind, scope_kind)
	assert(
		"function" == type(func)
	)

	local execute = false
	local obj = nil

	if kind == SubBlockFunctionKind.init then
		execute = (scope_kind == ConfigScopeKind.global)
	elseif kind == SubBlockFunctionKind.solution then
		execute = (scope_kind == ConfigScopeKind.solution)
		obj = precore.active_solution()
	elseif kind == SubBlockFunctionKind.project then
		execute = (scope_kind == ConfigScopeKind.project)
		obj = precore.active_project()
	elseif kind == SubBlockFunctionKind.non_global then
		execute = (scope_kind ~= ConfigScopeKind.global)
	else
		error(
			"unexpected function kind: '" .. tostring(kind) .. "'"
		)
	end

	if execute then
		func(obj)
	end
end

function precore.internal.execute_opt_block(opt_table, scope_kind)
	assert(
		"table" == type(opt_table.data) and
		(
			nil == opt_table.init_handler or
			"function" == type(opt_table.init_handler)
		)
	)

	if true ~= precore.state.enabled_opts[opt_table] then
		precore.state.enabled_opts[opt_table] = true
		newoption(opt_table.data)
		if
			nil ~= opt_table.init_handler and
			scope_kind == ConfigScopeKind.global
		then
			opt_table.init_handler()
		end
	end
end

function precore.internal.execute_table_block(sub_block, scope_kind)
	for name, value in pairs(sub_block) do
		if "option" == name then
			if scope_kind == ConfigScopeKind.global then
				precore.internal.execute_opt_block(
					value,
					scope_kind
				)
			end
		elseif
			"init" == name or
			"solution" == name or
			"project" == name
		then
			precore.internal.execute_func_block(
				value,
				SubBlockFunctionKind[name],
				scope_kind
			)
		else
			error(
				"unrecognized sub-block table key: '" .. name .. "'"
			)
		end
	end
end

function precore.internal.execute_block(scope, block, scope_kind)
	for _, sub_block in pairs(block) do
		if "string" == type(sub_block) then
			precore.internal.execute_block_by_name(
				scope,
				sub_block,
				scope_kind
			)
		elseif "function" == type(sub_block) then
			precore.internal.execute_func_block(
				sub_block,
				SubBlockFunctionKind.non_global,
				scope_kind
			)
		elseif "table" == type(sub_block) then
			precore.internal.execute_table_block(
				sub_block,
				scope_kind
			)
		else
			error(
				"sub-block of type '"  .. type(sub_block) ..
				"' not expected"
			)
		end
	end
end

function precore.internal.execute_block_by_name(scope, name, scope_kind)
	local block = precore.configs[name]
	if nil == block then
		error(
			"config '" .. name .. "' does not exist"
		)
	elseif not precore.internal.table_has(scope, name) then
		table.insert(scope, name)
		precore.internal.execute_block(
			scope,
			block,
			scope_kind
		)
	end
end

function precore.internal.configure(scope, names, scope_kind)
	for _, name in pairs(names) do
		precore.internal.execute_block_by_name(
			scope,
			name,
			scope_kind
		)
	end
end

--[[
	Get list of all solutions.
--]]
function precore.solutions()
	return precore.state.solutions
end

--[[
	Get the active precore solution for the active premake solution.

	Returns nil if either there is no active solution or the active
	solution was not created with make_solution().
--]]
function precore.active_solution()
	local sol = solution()
	if nil ~= sol then
		return precore.state.solutions[sol.name]
	end
	return nil
end

--[[
	Get the active precore project for the active premake project.

	Returns nil if there is no active solution or project, or if the
	active solution or project was not created with make_solution()
	or make_project().
--]]
function precore.active_project()
	local pc_sol = precore.active_solution()
	if nil ~= pc_sol then
		local proj = project()
		if nil ~= proj then
			return pc_sol.projects[proj.name]
		end
	end
	return nil
end

--[[
	Substitute substrings in the form "${NAME}" with their respective
	values from the given substitution table, the active project
	table, the active solution table, and the global table, in that
	order.

	If 'env' is nil, it is not used for substitution.
--]]
function precore.subst(str, env)
	if nil ~= env then
		str = precore.internal.do_subst(str, env)
	end

	local pc_proj = precore.active_project()
	if nil ~= pc_proj then
		str = precore.internal.do_subst(str, pc_proj.env)
	end

	local pc_sol = precore.active_solution()
	if nil ~= pc_sol then
		str = precore.internal.do_subst(str, pc_sol.env)
	end

	--[[
		NB: do_subst returns gsub values, which is (str, repcount).
		Because this will generally be passed straight to list-taking
		premake functions, we don't want to leak that number in the
		return.
	--]]
	str = precore.internal.do_subst(str, precore.state.env)
	return str
end

--[[
	Add a precore configuration block.

	'block' is a table of sub-blocks -- references, functions, and
	tables -- to apply.

	It should be expected that sub-blocks will modify the current
	configuration filter, so the user should always explicitly state
	the filter group when specifying its own configuration.

	If the sub-block is a string, it is a config reference. If a
	config has already been enabled at the current level, the
	reference is not executed.

	If the sub-block is a function, it is executed from
	precore.apply() or when a new solution, or project is created (if
	the config is enabled globally). Most project/solution
	configuration is done with explicit calls to premake functions in
	these sub-blocks.

	If the sub-block is a table, it can contain the following keys:

	- option

		A table with the following structure:

		{
			data = { ... },
			init_handler = nil or function(sub_block) ... end
		}

		Where the data table is passed to premake's newoption()
		function, and where init_handler is a function to be called
		when precore is initialized.

		This sub-block is only executed from precore.init().

	- init

		A function to be executed only from precore.init().

	- solution

		A function to be executed only at the solution level, taking
		as argument the active precore solution.

	- project

		A function to be executed only at the project level, taking
		as argument the active precore project.
--]]
function precore.make_config(name, block)
	if nil ~= precore.configs[name] then
		error(
			"could not create config '" .. name ..
			"' because it already exists"
		)
	end

	precore.configs[name] = block
end

--[[
	Initialize precore.

	'env' is an optional table of substitutions for the global scope.
	Solutions and projects have their own substitution tables, but
	can still access the global substitution table. For resolution
	order, see precore.subst().

	'...' is a vararg string list or table of precore config names to
	enable globally. All of these propagate to solutions and projects.
--]]
function precore.init(env, ...)
	if true == precore.state.initialized then
		error(
			"precore has already been initialized"
		)
	end

	assert(
		(nil == env or "table" == type(env))
	)

	if nil ~= env then
		precore.state.env = env
	end

	if nil ~= ... then
		precore.internal.configure(
			precore.state.configs,
			precore.internal.table_flatten({...}),
			ConfigScopeKind.global
		)
	end

	precore.state.initialized = true
end

--[[
	Create a solution.

	'configs' is a table of configuration names to declare at the
	solution level -- it is passed to premake's configurations()
	function.

	'plats' is a table of platform names to enable.

	'env' is an optional table of substitutions for the solution
	scope.

	'...' is a vararg string list or table of precore config names to
	enable on the solution. These are executed after propagation from
	the global configs.

	Returns the new precore solution; the new premake solution will
	be active.
--]]
function precore.make_solution(name, configs, plats, env, ...)
	precore.internal.init_guard()

	if
		nil ~= precore.state.solutions[name] or
		nil ~= premake.solution.list[name]
	then
		error(
			"could not create solution '" .. name ..
			"' because it already exists"
		)
	end

	assert(
		"string" == type(name),
		"table" == type(configs),
		"table" == type(plats),
		(nil == env or "table" == type(env))
	)

	local pc_sol = {
		scope_kind = ConfigScopeKind.solution,
		env = {},
		configs = {},
		projects = {},
		obj = solution(name)
	}

	configurations(configs)
	platforms(plats)

	precore.state.solutions[name] = pc_sol

	if nil ~= env then
		pc_sol.env = env
	end

	precore.internal.configure(
		pc_sol.configs,
		precore.state.configs,
		pc_sol.scope_kind
	)

	if nil ~= ... then
		precore.internal.configure(
			pc_sol.configs,
			precore.internal.table_flatten({...}),
			pc_sol.scope_kind
		)
	end

	return pc_sol
end

--[[
	Create a new project within the active solution.

	Defaults the configuration to:

		language(lang)

		configuration {}
			kind(knd)
			targetname(name)
			targetdir(target_dir)
			objdir(obj_dir)

	If 'target_dir' or 'obj_dir' are nil, they are not set.

	'env' is an optional table of substitutions for the project
	scope.

	'...' is a vararg string list or table of precore config names to
	enable on the project. These are executed after propagation from
	the global configs.

	Returns the new precore project; the new premake project will be
	active.
--]]
function precore.make_project(name, lang, knd, target_dir, obj_dir, env, ...)
	precore.internal.init_guard()

	local pc_sol = precore.active_solution()
	if nil == pc_sol then
		error(
			"could not create project '" .. name ..
			"' because no solution is active or the active" ..
			"solution was not created by precore"
		)
	elseif nil ~= pc_sol.obj.projects[name] then
		error(
			"could not create project '" .. name ..
			"' because it already exists within the " ..
			"active solution ('" .. pc_sol.obj.name .. "')"
		)
	end

	assert(
		"string" == type(name),
		"string" == type(lang),
		"string" == type(knd),
		"string" == type(target_dir),
		"string" == type(obj_dir),
		(nil == env or "table" == type(env))
	)

	local pc_proj = {
		scope_kind = ConfigScopeKind.project,
		env = {},
		configs = {},
		solution = pc_sol,
		obj = project(name)
	}

	language(lang)

	configuration {}
		kind(knd)
		targetname(name)
		if nil ~= target_dir then
			targetdir(target_dir)
		end
		if nil ~= obj_dir then
			objdir(obj_dir)
		end

	pc_sol.projects[name] = pc_proj

	if nil ~= env then
		pc_proj.env = env
	end

	precore.internal.configure(
		pc_proj.configs,
		pc_sol.configs,
		pc_proj.scope_kind
	)

	if nil ~= ... then
		precore.internal.configure(
			pc_proj.configs,
			precore.internal.table_flatten({...}),
			pc_proj.scope_kind
		)
	end

	return pc_proj
end

--[[
	Apply precore configs by name.

	'...' is a vararg string list or table of precore config names to
	enable at the current scope. Configs that have already been
	executed are not executed again.

	This will apply to the active premake project or solution, in
	order of activeness, or, if no project or solution is active,
	globally.

	Any existing children of the scope will not receive these configs.
--]]
function precore.apply(...)
	local pc_obj = precore.active_project()
	if nil == pc_obj then
		pc_obj = precore.active_solution()
	end

	local names = precore.internal.table_flatten({...})
	if nil ~= pc_obj then
		precore.internal.configure(
			pc_obj.configs,
			names,
			pc_obj.scope_kind
		)
	else
		precore.internal.configure(
			precore.state.configs,
			names,
			ConfigScopeKind.global
		)
	end
end

function precore.internal.put_env_root(env, parent_env, default_dir, relative)
	if nil == env["ROOT"] then
		if
			true == relative and
			nil ~= parent_env["ROOT"] and
			0 ~= #parent_env["ROOT"]
		then
			env["ROOT"] = path.getrelative(
				default_dir,
				parent_env["ROOT"]
			)
		else
			env["ROOT"] = default_dir
		end
	end
end

--[[
	Clean sub-directories of projects when _ACTION == "clean".
--]]
function precore.action_clean(...)
	local subdirs = precore.internal.table_flatten({...})
	local clean_project = function(pc_proj)
		print("Cleaning project: " .. pc_proj.obj.name)
		for _, name in pairs(subdirs) do
			local dir = path.join(pc_proj.obj.basedir, name)
			os.rmdir(dir)
		end
	end
	if "clean" == _ACTION then
		print("Cleaning sub-directories of projects: ")
		for _, name in pairs(subdirs) do
			print("    " .. name)
		end
		for _, pc_sol in pairs(precore.state.solutions) do
			for _, pc_proj in pairs(pc_sol.projects) do
				clean_project(pc_proj)
			end
		end
	end
end

--[[
	Defines the substitution key "ROOT" according to scope.

	At each scope, the following occurs only if "ROOT" is not defined
	in its substitution table.

	At the global scope, defines "ROOT" to the current working
	directory.

	At the solution and project scopes, defines "ROOT" to the object's
	basedir property relative to the global "ROOT" value, or simply to
	the object's basedir property if the global substitution table
	either does not have "ROOT" or "ROOT" is an empty string.
--]]
precore.make_config("precore-env-root", {
	{
		init = function()
			precore.internal.put_env_root(
				precore.state.env,
				nil,
				os.getcwd(),
				false
			)
		end,
		solution = function(pc_sol)
			precore.internal.put_env_root(
				pc_sol.env,
				precore.state.env,
				pc_sol.obj.basedir,
				true
			)
		end,
		project = function(pc_proj)
			precore.internal.put_env_root(
				pc_proj.env,
				precore.state.env,
				pc_proj.obj.basedir,
				true
			)
		end
	}
})

--[[
	Generic configuration for debug and release configurations.

	Enables ExtraWarnings flag globally.

	Enables the following for the "debug" configuration:

		- flags: Symbols
		- defines: DEBUG, _DEBUG

	Enables the following for the "release" configuration:

		- flags: Optimize
		- defines: NDEBUG
--]]
precore.make_config("precore-generic", {
	function()
		configuration {"debug"}
			flags {"Symbols"}
			defines {"DEBUG", "_DEBUG"}

		configuration {"release"}
			flags {"Optimize"}
			defines {"NDEBUG"}

		configuration {}
			flags {"ExtraWarnings"}
	end
})

--[[
	Core C++11 config.

	Uses `-std=c++11` on Linux and OSX.

	Should generally be enabled globally.
--]]
precore.make_config("c++11-core", {
	function()
		configuration {"linux or macosx"}
			buildoptions {"-std=c++11"}
	end
})

--[[
	Clang compiler replacement for premake4.x.

	Enables Clang with --clang and optionally selects the stdlib
	with --stdlib=name, defaulting to 'stdc++' (libstdc++).

	Should be enabled globally.
--]]
precore.make_config("opt-clang", {
	{
		option = {
			data = {
				trigger = "clang",
				description = "Use Clang in-place of GCC"
			},
			init_handler = function()
				if nil ~= _OPTIONS["clang"] then
					premake.gcc.cc = "clang"
					premake.gcc.cxx = "clang++"
				end
			end
		}
	},
	{
		option = {
			data = {
				trigger = "stdlib",
				description = "C++ stdlib to use for Clang"
			},
			init_handler = function()
				if nil == _OPTIONS["stdlib"] then
					if os.is("linux") then
						_OPTIONS["stdlib"] = "stdc++"
					elseif os.is("macosx") then
						_OPTIONS["stdlib"] = "c++"
					end
				end
			end
		}
	},
	function()
		configuration {"clang"}
			buildoptions {"-stdlib=lib" .. _OPTIONS["stdlib"]}
			links {_OPTIONS["stdlib"]}
	end
})
