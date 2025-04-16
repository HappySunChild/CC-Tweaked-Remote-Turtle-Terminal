-- receiver.lua

local turtle = require("turtle")
local commandList = require("commands")

local COMMAND_PROTOCOL = "controller.command"
local REQUEST_PROTOCOL = "controller.request"
local RESPONSE_PROTOCOL = "controller.response"

local ERR_PROCESS_COMMAND = "Error running command '%s';\n%s"
local ERR_UNKNOWN_COMMAND = "Unknown command '%s'"

local FACING_ENUM = {
	North = 0, -- negative Z
	East = 1, -- positive X
	South = 2, -- positive Z
	West = 3, -- negative X
}

local GPS_ENABLED = gps.locate(1) ~= nil

---@return vector.Vector
local function getPosition()
	if not GPS_ENABLED then
		return turtle.getPosition()
	end

	return vector.new(gps.locate())
end

---@return number
local function getFacing()
	if not GPS_ENABLED then
		return turtle.getFacing()
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

	return turtle.getFacing()
end

local function awaitController()
	local packet = {
		type = "connect",
		body = {
			fuel = turtle.getFuelLevel(),
			label = os.getComputerLabel(),
			position = turtle.getPosition(),
			facing = turtle.getFacing(),
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

	local func = commandList[key]

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

local function commandReceiver()
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
				position = turtle.getPosition(),
				facing = turtle.getFacing(),
			},
		}

		rednet.send(ACTIVE_CONTROLLER_ID, packet, REQUEST_PROTOCOL)
	end
end

local function main()
	term.clear()
	term.setCursorPos(1, 1)

	peripheral.find("modem", rednet.open)

	turtle.updatePosition(getPosition())
	turtle.updateFacing(getFacing())

	print("awaiting controller...")

	ACTIVE_CONTROLLER_ID = awaitController()

	print("got controller", ACTIVE_CONTROLLER_ID)

	parallel.waitForAll(periodicStatusUpdate, commandReceiver)
end

main()
