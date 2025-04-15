-- receiver.lua
-- meant to be used in a Pocket Computer or some sort of master computer
-- lets you remotely control turtles

local COMMAND_PROTOCOL = "controller.command"
local REQUEST_PROTOCOL = "controller.request"
local RESPONSE_PROTOCOL = "controller.response"

local ERR_PROCESS_COMMAND = "Error running command '%s';\n%s"
local ERR_UNKNOWN_COMMAND = "Unknown command '%s'"
local ERR_UNKNOWN_PROGRAM = "Unknown shell program '%s'"

local FACING_ENUM = {
	North = 0, -- negative Z
	East = 1, -- positive X
	South = 2, -- positive Z
	West = 3, -- negative X
}
local FACING_VECTOR_LOOKUP = {
	[0] = vector.new(0, 0, -1),
	[1] = vector.new(1, 0, 0),
	[2] = vector.new(0, 0, 1),
	[3] = vector.new(-1, 0, 0),
}

local GPS_ENABLED = gps.locate(1) ~= nil
local CURRENT_FACING = FACING_ENUM.North
local CURRENT_POSITION = vector.new(0, 0, 0)

-- override methods
local turtle = setmetatable({
	turnLeft = function()
		CURRENT_FACING = (CURRENT_FACING - 1) % 4

		return turtle.native.turnLeft()
	end,
	turnRight = function()
		CURRENT_FACING = (CURRENT_FACING + 1) % 4

		return turtle.native.turnRight()
	end,
	up = function()
		local success = turtle.native.up()

		if success then
			CURRENT_POSITION.y = CURRENT_POSITION.y + 1
		end

		return success
	end,
	down = function()
		local success = turtle.native.down()

		if success then
			CURRENT_POSITION.y = CURRENT_POSITION.y - 1
		end

		return success
	end,
	forward = function()
		local success = turtle.native.forward()

		if success then
			local off = FACING_VECTOR_LOOKUP[CURRENT_FACING]

			CURRENT_POSITION = CURRENT_POSITION + off
		end

		return success
	end,
	back = function()
		local success = turtle.native.back()

		if success then
			local off = FACING_VECTOR_LOOKUP[CURRENT_FACING]

			CURRENT_POSITION = CURRENT_POSITION - off
		end

		return success
	end,
}, { __index = turtle })

local DIRECTION_FUNCTIONS = {
	move = {
		up = turtle.up,
		forward = turtle.forward,
		down = turtle.down,
		back = turtle.back,
		left = turtle.turnLeft,
		right = turtle.turnRight,
	},
	dig = {
		up = turtle.digUp,
		forward = turtle.dig,
		down = turtle.digDown,
	},
	place = {
		up = turtle.placeUp,
		forward = turtle.place,
		down = turtle.placeDown,
	},
	drop = {
		up = turtle.dropUp,
		forward = turtle.drop,
		down = turtle.dropDown,
	},
	suck = {
		up = turtle.suckUp,
		forward = turtle.suck,
		down = turtle.suckDown,
	},
	attack = {
		up = turtle.attackUp,
		forward = turtle.attack,
		down = turtle.attackDown,
	},
}

---@return vector.Vector
local function getPosition()
	if not GPS_ENABLED then
		return CURRENT_POSITION
	end

	return vector.new(gps.locate())
end

---@return number
local function getFacing()
	if not GPS_ENABLED then
		return CURRENT_FACING
	end

	local start = getPosition()

	turtle.dig()
	turtle.forward()

	local finish = getPosition()

	turtle.back()

	---@type vector.Vector
	local dif = finish - start

	if dif.x == -1 then
		return FACING_ENUM.West
	elseif dif.x == 1 then
		return FACING_ENUM.East
	elseif dif.z == -1 then
		return FACING_ENUM.North
	elseif dif.z == 1 then
		return FACING_ENUM.South
	end

	return CURRENT_FACING
end

---@param direction number
local function faceTowards(direction)
	while CURRENT_FACING ~= direction do
		turtle.turnRight()
	end
end

---@type table<string, fun(...: rednet.transmittable): nil>
local COMMANDS = {
	-- run lua code
	loadstring = function(...)
		local code = table.concat({ ... }, " ")
		local func = loadstring(code)

		if func then
			local env = getfenv(func)
			env.turtle = turtle

			func()
		end
	end,
	-- run a program
	shell = function(name, ...)
		local program = shell.resolveProgram(name)

		if not program then
			error(ERR_UNKNOWN_PROGRAM:format(name))
		end

		local env = { arg = { ... }, turtle = turtle }

		local index = multishell.launch(env, program, ...)
		multishell.setTitle(index, "sub" .. index)
		multishell.setFocus(index)
	end,
	-- download a program
	download = function(url, path)
		if fs.exists(path) then
			fs.delete(path)
		end

		shell.execute("wget", url, path)
	end,

	-- move the turtle
	move = function(...)
		local lastMove = nil

		for _, dirKey in next, { ... } do
			local count = tonumber(dirKey)

			if count and lastMove then
				for _ = 1, count - 1 do
					lastMove()
				end
			else
				local moveFunc = DIRECTION_FUNCTIONS.move[dirKey]
				moveFunc()
				lastMove = moveFunc
			end
		end
	end,
	-- dig a block
	dig = function(direction)
		direction = direction or "forward"

		DIRECTION_FUNCTIONS.dig[direction]()
	end,
	-- place a block
	place = function(direction, text)
		direction = direction or "forward"

		DIRECTION_FUNCTIONS.place[direction](text)
	end,
	-- select a slot
	select = function(slot)
		turtle.select(tonumber(slot))
	end,
	-- drop an item
	drop = function(direction, amount)
		direction = direction or "forward"
		amount = tonumber(amount) or 1

		DIRECTION_FUNCTIONS.drop[direction](amount)
	end,
	-- suck an item
	suck = function(direction, amount)
		direction = direction or "forward"
		amount = tonumber(amount) or 64

		DIRECTION_FUNCTIONS.suck[direction](amount)
	end,
	-- attack
	attack = function(direction, side)
		direction = direction or "forward"

		DIRECTION_FUNCTIONS.attack[direction](side)
	end,

	-- gps navigation
	navigate = function(x, y, z)
		local target = vector.new(tonumber(x), tonumber(y), tonumber(z))

		print("navigating to", target)

		-- east/west
		if target.x ~= CURRENT_POSITION.x then
			local difX = target.x - CURRENT_POSITION.x

			if difX < 0 then
				faceTowards(FACING_ENUM.West)
			else
				faceTowards(FACING_ENUM.East)
			end

			for _ = 1, math.abs(difX) do
				turtle.dig()
				turtle.forward()
			end
		end

		-- north/south
		if target.z ~= CURRENT_POSITION.z then
			local difZ = target.z - CURRENT_POSITION.z

			if difZ < 0 then
				faceTowards(FACING_ENUM.North)
			else
				faceTowards(FACING_ENUM.South)
			end

			for _ = 1, math.abs(difZ) do
				turtle.dig()
				turtle.forward()
			end
		end

		-- vertical
		if target.y ~= CURRENT_POSITION.y then
			local difY = target.y - CURRENT_POSITION.y

			for _ = 1, math.abs(difY) do
				if difY > 0 then
					turtle.digUp()
					turtle.up()
				else
					turtle.digDown()
					turtle.down()
				end
			end
		end
	end,

	shutdown = os.shutdown,
	reboot = os.reboot,
}

COMMANDS.pastebin = function(code, ...)
	return COMMANDS.shell("pastebin", "run", code, ...)
end

local function awaitController()
	local packet = {
		type = "connect",
		body = {
			fuel = turtle.getFuelLevel(),
			label = os.getComputerLabel(),
			position = CURRENT_POSITION,
			facing = CURRENT_FACING,
		},
	}

	rednet.broadcast(packet, REQUEST_PROTOCOL)

	local id = rednet.receive(RESPONSE_PROTOCOL, 5)

	if not id then
		return awaitController()
	end

	return id
end

local ACTIVE_CONTROLLER_ID = -1

---@param command command_packet|rednet.transmittable
local function processCommand(command)
	local key = command.key

	if not key then
		return
	end

	local func = COMMANDS[key]

	if not func then
		printError(ERR_UNKNOWN_COMMAND:format(key))

		return
	end

	local success, value = pcall(func, unpack(command.arguments))

	if not success then
		printError(ERR_PROCESS_COMMAND:format(key, value))

		return
	end
end

local function receiver()
	while true do
		local id, command = rednet.receive(COMMAND_PROTOCOL)

		if id == ACTIVE_CONTROLLER_ID then
			processCommand(command)
		end
	end
end

local function periodicStatusUpdate()
	while true do
		sleep(15)

		local packet = {
			type = "update",
			body = {
				fuel = turtle.getFuelLevel(),
				label = os.getComputerLabel(),
				position = CURRENT_POSITION,
				facing = CURRENT_FACING,
			},
		}

		rednet.send(ACTIVE_CONTROLLER_ID, packet, REQUEST_PROTOCOL)
	end
end

local function main()
	term.clear()
	term.setCursorPos(1, 1)

	peripheral.find("modem", rednet.open)

	CURRENT_POSITION = getPosition()
	CURRENT_FACING = getFacing()

	print("awaiting controller...")

	ACTIVE_CONTROLLER_ID = awaitController()

	print("got controller", ACTIVE_CONTROLLER_ID)

	parallel.waitForAll(periodicStatusUpdate, receiver)
end

main()
