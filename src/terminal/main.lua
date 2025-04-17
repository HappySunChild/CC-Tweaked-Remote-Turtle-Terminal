local completion = require("cc.completion")
local pretty = require("cc.pretty")

local COMMAND_PROTOCOL = "controller.command"
local REQUEST_PROTOCOL = "controller.request"
local RESPONSE_PROTOCOL = "controller.response"

local DISPLAY_STATS = {
	"fuel",
	"facing",
	"position",
}

local COMMANDS_LIST = {
	"loadstring",

	"shutdown",
	"reboot",

	"select",
	"navigate",

	"download",
	"delete",
	"pastebin",
	"wrun",

	"turtles",
}
local COMMAND_COMPLETIONS = {
	-- turtle
	move = { default = { "up", "forward", "down", "back", "left", "right" } },
	attack = { { "up", "forward", "down" } },
	dig = { { "up", "forward", "down" } },
	place = { { "up", "forward", "down" } },
	drop = { { "up", "forward", "down" } },
	suck = { { "up", "forward", "down" } },
	shell = {
		default = function(args)
			local sLine = table.concat({ select(2, unpack(args)) }, " ")

			return shell.complete(sLine)
		end,
	},

	-- terminal
	clear = { { "screen", "history" } },
}

for key in next, COMMAND_COMPLETIONS do
	table.insert(COMMANDS_LIST, key)
end

---@param str string
---@param sep string?
---@return string[]
local function parse(str, sep)
	str = str:gsub("\\n", "\n") -- replace
	sep = sep or "%s"

	local output = {}

	local bInString = false
	local bControl = false
	local current = ""

	local function terminate()
		if #current <= 0 then
			return
		end

		table.insert(output, current)

		current = ""
	end

	for i = 1, #str do
		local char = str:sub(i, i)

		local isQuote = char == '"'
		local isSep = char:match(sep)

		if isQuote and not bControl then
			bInString = not bInString

			terminate()
		else
			if char == "\\" and not bControl then
				bControl = true
			else
				bControl = false
			end

			if not bControl then
				if not isSep or (isSep and bInString) then
					current = current .. char
				end
			end

			if not bInString and isSep and #current > 0 then
				terminate()
			end
		end
	end

	terminate()

	return output
end

---@param partial string
---@return string[]
local function terminalCompletion(partial)
	local args = parse(partial)

	if #args <= 1 then
		return completion.choice(partial, COMMANDS_LIST, true)
	end

	local commandKey = args[1]
	local info = COMMAND_COMPLETIONS[commandKey]

	local argIndex = #args - 1

	if not info then
		return {}
	end

	local argument = info[argIndex] or info.default

	if type(argument) == "table" then
		return completion.choice(args[#args], argument)
	elseif type(argument) == "function" then
		return argument(args)
	end

	return {}
end

local connectedTurtles = {}
local history = {}

local TERMINAL_COMMANDS = {
	-- clears the screen
	clear = function(target)
		target = target or "screen"

		if target == "screen" then
			term.clear()
			term.setCursorPos(1, 1)
		elseif target == "history" then
			history = {}
		else
			printError("Invalid target.")
		end
	end,
	-- displays all the currently connected turtles
	turtles = function()
		local function statDocument(name, value)
			return pretty.text(name .. ":", colors.orange)
				.. pretty.space
				.. pretty.text(tostring(value), colors.magenta)
				.. pretty.space_line
		end

		for id, info in next, connectedTurtles do
			local output = pretty.text("Turtle ", colors.yellow)
				.. pretty.text(string.format("#%s", id), colors.red)
				.. pretty.space
				.. pretty.text(string.format("(%s)", info.label), colors.gray)
				.. pretty.line

			for _, stat in ipairs(DISPLAY_STATS) do
				output = output .. statDocument(stat, info[stat])
			end

			pretty.print(pretty.nest(2, output))
		end
	end,
	-- navigate wrapper
	navigate = function(x, y, z)
		local cX, cY, cZ = gps.locate()

		if cX and cY and cZ then
			local function convert(a, b)
				local sign, offset = string.match(a, "^(~)(.*)$")

				if sign then
					return tostring(b + (tonumber(offset) or 0))
				end

				return a
			end

			x = convert(x, cX)
			y = convert(y, cY)
			z = convert(z, cZ)
		end

		rednet.broadcast({ key = "navigate", arguments = { x, y, z } }, COMMAND_PROTOCOL)
	end,
}

---@param id number
---@param packet request_packet|rednet.transmittable
local function processPacket(id, packet)
	if type(packet) ~= "table" then
		return
	end

	if packet.type == "connect" then
		rednet.send(id, true, RESPONSE_PROTOCOL)

		local body = packet.body
		local pos = body.position

		if pos then
			pos = vector.new(pos.x, pos.y, pos.z)
		end

		connectedTurtles[id] = {
			label = body.label,
			fuel = body.fuel,
			position = pos,
			facing = body.facing,
		}

		return
	end

	local isConnected = connectedTurtles[id] ~= nil

	if isConnected then
		if packet.type == "update" then
			local body = packet.body
			local pos = body.position

			if pos then
				pos = vector.new(pos.x, pos.y, pos.z)
			end

			local info = connectedTurtles[id]
			info.label = body.label
			info.fuel = body.fuel
			info.position = pos
			info.facing = body.facing
		end
	end
end

local function receiver()
	while true do
		local id, packet = rednet.receive(REQUEST_PROTOCOL)

		processPacket(id, packet)
	end
end

local function processTerminalInput(input)
	local args = parse(input)
	local key = table.remove(args, 1)

	local terminalFunc = TERMINAL_COMMANDS[key]

	if not terminalFunc then
		rednet.broadcast({ key = key, arguments = args }, COMMAND_PROTOCOL)

		return
	end

	local success, err = pcall(terminalFunc, unpack(args))

	if not success then
		printError(err)
	end
end

local function terminal()
	term.clear()
	term.setCursorPos(1, 1)

	peripheral.find("modem", rednet.open)

	while true do
		term.setTextColor(colors.lime)
		write("$ ")

		term.setTextColor(colors.white)
		local input = read(nil, history, terminalCompletion)

		table.insert(history, input)

		processTerminalInput(input)
	end
end

parallel.waitForAll(terminal, receiver)
