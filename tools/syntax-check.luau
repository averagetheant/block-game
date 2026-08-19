--!strict
-- Compile every .luau file under src/ and report the ones that don't parse.
--
-- `rojo build` does not validate Luau — it packs text into an .rbxlx and a syntax
-- error rides along silently until Studio hits it at runtime. `lune run
-- tools/split` doesn't either; it copies files. This is the missing check: the
-- Luau compiler itself, run over the tree, which fails loudly on anything the
-- parser rejects.
--
-- Only *syntax*. It says nothing about types, undefined globals, or whether a
-- require resolves — Roblox globals (`game`, `workspace`, `script`) are perfectly
-- valid Luau and compile fine here.

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local ROOT = "src"

local checked = 0
local failures: { string } = {}

local function walk(dir: string)
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			walk(path)
		elseif string.sub(path, -5) == ".luau" then
			checked += 1
			local ok, err = pcall(luau.compile, fs.readFile(path))
			if not ok then
				table.insert(failures, `{path}\n    {err}`)
			end
		end
	end
end

walk(ROOT)

if #failures > 0 then
	print(`[syntax-check] {#failures} of {checked} file(s) failed to parse:`)
	for _, failure in failures do
		print(`  {failure}`)
	end
	process.exit(1)
end

print(`[syntax-check] ok — {checked} file(s) parse.`)
