
-- precore

precore = {
	internal = {
		imported_paths = {},
		wd_stack = {},
	},
	configs = {},

	initialized = false,
	state = nil,
}

local SubBlockFunctionKind = {
	global = 1,
	solution = 2,
	project = 3,
	non_global = 4,
}

local ConfigScopeKind = {
	global = 1,
	solution = 2,
	project = 3,
}

function precore.internal.init_guard()
	if not precore.initialized then
		error("precore must be initialized")
	end
end

function precore.internal.table_find_name(t, name)
	for _, v in pairs(t) do
		if v.name == name then
			return v
		end
	end
	return nil
end

function precore.internal.table_last(t)
	return t[#t]
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
		if type(v) == "table" then
			table.remove(t, i)
			for ii, vv in ipairs(v) do
				table.insert(t, i + ii - 1, vv)
			end
		end
	end
	return t
end

function precore.internal.do_subst(str, env)
	local str = string.gsub(str, "%${([%w_]+)}", env)
	return str
end

function precore.internal.make_config_state()
	return {
		applied = {},
		nest_count = 0,
		pos = 0,
	}
end

function precore.internal.execute_func_block(func, kind, scope_kind)
	assert(type(func) == "function")

	local execute = false
	local obj = nil

	if kind == SubBlockFunctionKind.global then
		execute = scope_kind == ConfigScopeKind.global
	elseif kind == SubBlockFunctionKind.solution then
		execute = scope_kind == ConfigScopeKind.solution
		obj = precore.active_solution()
	elseif kind == SubBlockFunctionKind.project then
		execute = scope_kind == ConfigScopeKind.project
		obj = precore.active_project()
	elseif kind == SubBlockFunctionKind.non_global then
		execute = scope_kind ~= ConfigScopeKind.global
	else
		error(string.format("unexpected function kind: '%s'", tostring(kind)))
	end

	if execute then
		func(obj)
	end
end

function precore.internal.execute_opt_block(opt_table, scope_kind)
	assert(
		type(opt_table.data) == "table" and
		(
			opt_table.init_handler == nil or
			type(opt_table.init_handler) == "function"
		)
	)

	if not precore.state.enabled_opts[opt_table] then
		precore.state.enabled_opts[opt_table] = true
		newoption(opt_table.data)
		if opt_table.init_handler ~= nil then
			opt_table.init_handler()
		end
	end
end

function precore.internal.execute_table_block(config, scope, sub_block, scope_kind)
	for name, value in pairs(sub_block) do
		if name == "option" then
			if scope_kind == ConfigScopeKind.global then
				precore.internal.execute_opt_block(value, scope_kind)
			end
		elseif name == "wd_scoped" then
			precore.push_wd(value.path)
			precore.internal.execute_block(config, scope, value.block, scope_kind)
			precore.pop_wd()
		elseif
			name == "global" or
			name == "solution" or
			name == "project"
		then
			precore.internal.execute_func_block(
				value,
				SubBlockFunctionKind[name],
				scope_kind
			)
		else
			error(string.format("unrecognized sub-block table key: '%s'", name))
		end
	end
end

function precore.internal.execute_sub_block(config, scope, sub_block, scope_kind)
	if type(sub_block) == "string" then
		precore.internal.execute_block_by_name(scope, sub_block, scope_kind)
	elseif type(sub_block) == "function" then
		precore.internal.execute_func_block(
			sub_block,
			SubBlockFunctionKind.non_global,
			scope_kind
		)
	elseif type(sub_block) == "table" then
		precore.internal.execute_table_block(config, scope, sub_block, scope_kind)
	else
		error(string.format(
			"sub-block of type '%s' not expected", type(sub_block)
		))
	end
end

function precore.internal.execute_block(config, scope, block, scope_kind)
	if config.properties.reverse then
		for i = #block, 1, -1 do
			precore.internal.execute_sub_block(config, scope, block[i], scope_kind)
		end
	else
		for _, sub_block in pairs(block) do
			precore.internal.execute_sub_block(config, scope, sub_block, scope_kind)
		end
	end
end

function precore.internal.execute_block_by_name(scope, name, scope_kind)
	local config = precore.configs[name]
	if not config then
		error(string.format("config '%s' does not exist", name))
	elseif
		(config.properties.once and config.properties.__exec_count > 0) or
		precore.internal.table_has(scope.applied, name)
	then
		return
	end

	assert(scope.nest_count >= 0)
	scope.nest_count = scope.nest_count + 1
	if scope.nest_count == 1 then
		scope.pos = #scope.applied + 1
	end
	config.properties.__exec_count = config.properties.__exec_count + 1
	table.insert(scope.applied, scope.pos, name)
	precore.internal.execute_block(config, scope, config.block, scope_kind)
	scope.nest_count = scope.nest_count - 1
end

function precore.internal.configure(scope, names, scope_kind)
	for _, name in pairs(names) do
		precore.internal.execute_block_by_name(scope, name, scope_kind)
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
	if sol ~= nil then
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
	if pc_sol ~= nil then
		local proj = project()
		if proj ~= nil then
			return pc_sol.projects[proj.name]
		end
	end
	return nil
end

function precore.internal.subst_first(name, env)
	local value = nil
	if env ~= nil then
		value = env[name]
	end
	if value ~= nil then return value end

	local pc_proj = precore.active_project()
	if pc_proj ~= nil then
		value = pc_proj.env[name]
	end
	if value ~= nil then return value end

	local pc_sol = precore.active_solution()
	if pc_sol ~= nil then
		value = pc_sol.env[name]
	end
	if value ~= nil then return value end

	value = precore.state.env[name]
	return value
end

--[[
	Substitute substrings in the form "${NAME}" with their respective
	values from the given substitution table, the active project
	table, the active solution table, and the global table, in that
	order.

	If 'env' is nil, it is not used for substitution.
--]]
function precore.subst(str, env)
	if env ~= nil then
		str = precore.internal.do_subst(str, env)
	end
	local pc_proj = precore.active_project()
	if pc_proj ~= nil then
		str = precore.internal.do_subst(str, pc_proj.env)
	end
	local pc_sol = precore.active_solution()
	if pc_sol ~= nil then
		str = precore.internal.do_subst(str, pc_sol.env)
	end
	str = precore.internal.do_subst(str, precore.state.env)
	return str
end

--[[
	Substitute only through the global scope.
--]]
function precore.subst_global(str)
	str = precore.internal.do_subst(str, precore.state.env)
	return str
end

--[[
	Translate path relative to some root.

	'to' is passed through precore.subst().

	If 'root' is nil, it defaults to "ROOT" through the substitution chain.
--]]
function precore.path_relative(to, root)
	local root = root or precore.internal.subst_first("ROOT")
	assert(root ~= nil)
	return path.getrelative(precore.subst(to), root)
end

--[[
	Returns the following functions:

	precore.subst
	precore.subst_global
	precore.path_relative

	These can be used to alias the oft-used functions locally; e.g.:

	local S, G, R = precore.helpers()
--]]
function precore.helpers()
	return precore.subst, precore.subst_global, precore.path_relative
end

--[[
	Push 'path' as the current working directory.
--]]
function precore.push_wd(path)
	table.insert(precore.internal.wd_stack, os.getcwd())
	assert(os.chdir(path) == true)
end

--[[
	Pop the current working directory.

	This changes the current working directory to the previous path on the
	stack.
--]]
function precore.pop_wd()
	assert(#precore.internal.wd_stack > 0)
	local prev_wd = table.remove(precore.internal.wd_stack)
	assert(os.chdir(prev_wd) == true)
end

--[[
	Wrap a function to retain the current working directory upon calling.

	When the returned function is called, the working directory is reverted
	after calling 'func'.
--]]
function precore.wd_scoped(func)
	local wrapped_wd = os.getcwd()
	local wrapped = function(...)
		precore.push_wd(wrapped_wd)
		func(...)
		precore.pop_wd()
	end
	return wrapped
end

--[[
	Add a precore configuration.

	'properties' is an optional table of configuration properties. It can
	contain the following:

	- once

		Whether the config should be executed only once.

	- reverse

		Whether the config should be executed in reverse.

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

		This sub-block is executed only from precore.init() or global scope.

	- global

		A function to be executed only from precore.init() or global scope.

	- solution

		A function to be executed only at the solution level, taking
		as argument the active precore solution.

	- project

		A function to be executed only at the project level, taking
		as argument the active precore project.
--]]
function precore.make_config(name, properties, block)
	assert(type(block) == "table")
	assert(properties == nil or type(properties) == "table")
	if precore.configs[name] then
		error(string.format(
			"could not create config '%s' because it already exists", name
		))
	end
	properties = properties or {}
	properties.__exec_count = 0
	precore.configs[name] = {
		block = block,
		properties = properties,
	}
end

--[[
	Add a precore configuration as through wrapped by precore.wd_scoped().
--]]
function precore.make_config_scoped(name, properties, block)
	block = {{wd_scoped = {
		path = os.getcwd(),
		block = block,
	}}}
	precore.make_config(name, properties, block)
end

--[[
	Append sub-blocks to an existing config.

	'block' is the same as for precore.make_config().
--]]
function precore.append_config(name, block)
	assert(type(block) == "table")
	local config = precore.configs[name]
	if not config then
		error(string.format(
			"could not append to config '%s' because it doesn't exist", name
		))
	end
	for _, sub in pairs(block) do
		table.insert(config.block, sub)
	end
end

--[[
	Append sub-blocks to an existing config as through wrapped by
	precore.wd_scoped().
--]]
function precore.append_config_scoped(name, block)
	assert(type(block) == "table")
	block = {{wd_scoped = {
		path = os.getcwd(),
		block = block,
	}}}
	precore.append_config(name, block)
end

--[[
	Import build script at path.

	Unless path ends with ".lua", this loads (path .. "/build.lua").

	If the path has already been imported, this does nothing.
--]]
function precore.import(p)
	if string.sub(p, -4) ~= ".lua" then
		p = p .. "/build.lua"
	end
	p = path.getabsolute(p)
	if not precore.internal.imported_paths[p] then
		precore.internal.imported_paths[p] = true
		dofile(p)
	end
end

--[[
	Initialize precore.

	'env' is an optional table of substitutions for the global scope.
	Solutions and projects have their own substitution tables, but
	can still access the global substitution table. For resolution
	order, see precore.subst().

	'...' is a vararg string list or table of precore config names to
	enable globally. All of these propagate to solutions and projects.

	If "ROOT" is not defined in the global substitution table, it is defined
	to the current working directory.
--]]
function precore.init(env, ...)
	if precore.initialized then
		error("precore has already been initialized")
	end
	precore.initialized = true

	precore.state = {
		config_func_once = {},
		env = {},
		config_state = precore.internal.make_config_state(),
		enabled_opts = {},
		solutions = {},
	}

	assert(env == nil or type(env) == "table")
	if env ~= nil then
		precore.state.env = env
	end
	if precore.state.env["ROOT"] == nil then
		precore.state.env["ROOT"] = os.getcwd()
	end

	if ... ~= nil then
		precore.apply_global(...)
	end
end

function precore.internal.env_set(env, add, no_overwrite)
	assert(add == nil or type(add) == "table")
	if add then
		for k, v in pairs(add) do
			assert(type(k) == "string")
			if not no_overwrite or env[k] == nil or #env[k] == 0 then
				env[k] = v
			end
		end
	end
	return env
end

--[[
	Add definitions to the most immediate substitution table.

	Returns the substitution table.

	If 'no_overwrite' is true, values in 'add' that are already defined are
	ignored.
--]]
function precore.env_immediate(add, no_overwrite)
	local obj = precore.active_project()
	if obj == nil then obj = precore.active_solution() end
	if obj == nil then obj = precore.state end
	return precore.internal.env_set(obj.env, add, no_overwrite)
end

--[[
	Add definitions to the global substitution table.
--]]
function precore.env_global(add, no_overwrite)
	precore.internal.init_guard()
	return precore.internal.env_set(precore.state.env, add, no_overwrite)
end

--[[
	Add definitions to the solution substitution table.
--]]
function precore.env_solution(add, no_overwrite)
	local obj = precore.active_solution()
	assert(obj)
	return precore.internal.env_set(obj.env, add, no_overwrite)
end

--[[
	Add definitions to the project substitution table.
--]]
function precore.env_project(add, no_overwrite)
	local obj = precore.active_project()
	assert(obj)
	return precore.internal.env_set(obj.env, add, no_overwrite)
end

--[[
	Define ROOT, DEP, and BUILD substitutions at global scope by group name.

	Defines the following iff they are not already defined:

		<name>_ROOT = path
		<name>_DEP = ${<name>_ROOT}/dep
		<name>_BUILD = ${<name>_ROOT}/build
--]]
function precore.define_group(name, path)
	assert(type(name) == "string" and #name > 0)
	local root_name = name .. "_ROOT"
	precore.env_global({
		[root_name] = path,
	}, true)
	precore.env_global({
		[name .. "_DEP"] = precore.subst_global("${" .. root_name .. "}/dep"),
		[name .. "_BUILD"] = precore.subst_global("${" .. root_name .. "}/build"),
	}, true)
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
	apply to the solution. These are executed after propagation from
	the global configs.

	Returns the new precore solution; the new premake solution will
	be active.
--]]
function precore.make_solution(name, configs, plats, env, ...)
	precore.internal.init_guard()
	if
		precore.state.solutions[name] ~= nil or
		premake.solution.list[name] ~= nil
	then
		error(string.format(
			"could not create solution '%s' because it already exists", name
		))
	end

	assert(
		type(name) == "string",
		type(configs) == "table",
		type(plats) == "table",
		(env == nil or type(env) == "table")
	)

	local pc_sol = {
		scope_kind = ConfigScopeKind.solution,
		env = {},
		config_state = precore.internal.make_config_state(),
		projects = {},
		obj = solution(name)
	}
	precore.state.solutions[name] = pc_sol

	configurations(configs)
	platforms(plats)

	if env ~= nil then
		pc_sol.env = env
	end
	precore.internal.configure(
		pc_sol.config_state,
		precore.state.config_state.applied,
		pc_sol.scope_kind
	)
	if ... ~= nil then
		precore.internal.configure(
			pc_sol.config_state,
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
	apply to the project. These are executed after propagation from
	the global configs.

	Returns the new precore project; the new premake project will be
	active.
--]]
function precore.make_project(name, lang, knd, target_dir, obj_dir, env, ...)
	precore.internal.init_guard()

	local pc_sol = precore.active_solution()
	if not pc_sol then
		error(string.format(
			"could not create project '%s' because no solution is active " ..
			"or the active solution was not created by precore",
			name
		))
	elseif pc_sol.obj.projects[name] then
		error(string.format(
			"could not create project '%s' because it already " ..
			"exists within the active solution ('%s')",
			name, pc_sol.obj.name
		))
	end

	assert(
		type(name) == "string",
		type(lang) == "string",
		type(knd) == "string",
		(target_dir == nil or type(target_dir) == "string"),
		(obj_dir == nil or type(obj_dir) == "string"),
		(env == nil or type(env) == "table")
	)

	local pc_proj = {
		scope_kind = ConfigScopeKind.project,
		env = env or {},
		config_state = precore.internal.make_config_state(),
		solution = pc_sol,
		obj = project(name),
	}
	pc_sol.projects[name] = pc_proj

	language(lang)
	configuration {}
		kind(knd)

	precore.internal.configure(
		pc_proj.config_state,
		pc_sol.config_state.applied,
		pc_proj.scope_kind
	)
	if ... ~= nil then
		precore.internal.configure(
			pc_proj.config_state,
			precore.internal.table_flatten({...}),
			pc_proj.scope_kind
		)
	end

	configuration {}
		targetname(precore.subst(name))
		if target_dir ~= nil then
			targetdir(precore.subst(target_dir))
		end
		if obj_dir ~= nil then
			objdir(precore.subst(obj_dir))
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
	precore.internal.init_guard()
	local pc_obj = precore.active_project()
	if pc_obj == nil then
		pc_obj = precore.active_solution()
	end
	if pc_obj then
		precore.internal.configure(
			pc_obj.config_state,
			precore.internal.table_flatten({...}),
			pc_obj.scope_kind
		)
	else
		precore.apply_global(...)
	end
end

--[[
	Apply precore configs by name at global scope.

	Same effect as precore.apply(), but ignoring project/solution scope.
--]]
function precore.apply_global(...)
	precore.internal.init_guard()
	precore.internal.configure(
		precore.state.config_state,
		precore.internal.table_flatten({...}),
		ConfigScopeKind.global
	)
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
	if _ACTION == "clean" then
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

function precore.internal.print_debug(prefix, obj)
	print(prefix .. "env:")
	for k, v in pairs(obj.env) do
		print(prefix .. string.format("  %s = %s", k, tostring(v)))
	end
	print("\n" .. prefix .. "config:")
	for _, name in pairs(obj.config_state.applied) do
		print(prefix .. "  " .. name)
	end
end

--[[
	Print applied configs and substitution tables.

	If 'obj' is non-nil, prints only properties of 'obj'.
--]]
function precore.print_debug(obj)
	if obj then
		print(obj.name .. " env:")
		precore.internal.print_debug("  ", obj)
	end

	print("- global:")
	precore.internal.print_debug(string.format("  "), precore.state)

	for s_name, s in pairs(precore.state.solutions) do
		print(string.format("\n- solution '%s':", s_name))
		precore.internal.print_debug(string.format("  "), s)
		for p_name, p in pairs(s.projects) do
			print(string.format("\n  - project '%s':", p_name))
			precore.internal.print_debug(string.format("    "), p)
		end
	end
	print("")
end

--[[
	Defines common substitution keys.

	Defines the following substitutions unless they are already defined:

	At the global scope:

		"DEP_PATH" to "${ROOT}/dep"
		"BUILD_PATH" to "${ROOT}/build"

	At the project scope:

		"NAME" to the project name
--]]
precore.make_config("precore.env-common", nil, {
{global = function()
	local env = precore.env_global({
		DEP_PATH = precore.subst_global("${ROOT}/dep"),
		BUILD_PATH = precore.subst_global("${ROOT}/build"),
	}, true)
end},
{project = function(pc_proj)
	local env = pc_proj.env
	if not env["NAME"] then
		env["NAME"] = pc_proj.obj.name
	end
end}})

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
precore.make_config("precore.generic", nil, {
function()
	configuration {"debug"}
		flags {"Symbols"}
		defines {"DEBUG", "_DEBUG"}

	configuration {"release"}
		flags {"Optimize"}
		defines {"NDEBUG"}

	configuration {}
		flags {"ExtraWarnings"}
end})

--[[
	Core C++11 config.

	Uses `-std=c++11` on Linux and OSX.

	Should generally be enabled globally.
--]]
precore.make_config("precore.c++11-core", nil, {
function()
	configuration {"linux or macosx"}
		buildoptions {"-std=c++11"}
end})

--[[
	Clang compiler replacement for premake4.x.

	Enables Clang with --clang and optionally selects the stdlib
	with --stdlib=name, defaulting to 'stdc++' (libstdc++).

	Should be enabled globally.
--]]
precore.make_config("precore.clang-opts", nil, {
{option = {
	data = {
		trigger = "clang",
		description = "Use Clang in-place of GCC"
	},
	init_handler = function()
		if _OPTIONS["clang"] ~= nil then
			premake.gcc.cc = "clang"
			premake.gcc.cxx = "clang++"
		end
	end
}},
{option = {
	data = {
		trigger = "stdlib",
		description = "C++ stdlib to use for Clang"
	},
	init_handler = function()
		if _OPTIONS["stdlib"] == nil then
			if os.is("linux") then
				_OPTIONS["stdlib"] = "stdc++"
			elseif os.is("macosx") then
				_OPTIONS["stdlib"] = "c++"
			end
		end
	end
}},
{project = function()
	configuration {"clang"}
		buildoptions {"-stdlib=lib" .. _OPTIONS["stdlib"]}

	if not precore.env_project()["NO_LINK"] then
		links {_OPTIONS["stdlib"]}
	end
end}})
