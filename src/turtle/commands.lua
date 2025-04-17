-- commands.lua

local turtle = require("turtle")

local ERR_UNKNOWN_PROGRAM = "Unknown shell program '%s'"

local FACING_ENUM = {
	North = 0, -- negative Z
	East = 1, -- positive X
	South = 2, -- positive Z
	West = 3, -- negative X
}
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

---@param direction number
local function faceTowards(direction)
	while turtle.getFacing() ~= direction do
		turtle.turnRight()
	end
end

---@type table<string, fun(...: rednet.transmittable): nil>
local commandList = {
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

		-- i think multishell is advanced exclusive,
		-- i get an error when using regular turtles
		if multishell then
			local index = multishell.launch(env, program, ...)
			multishell.setTitle(index, "sub" .. index)
			multishell.setFocus(index)
		else
			os.run(env, program, ...)
		end
	end,
	-- download a file from the web
	download = function(url, path)
		if fs.exists(path) then
			fs.delete(path)
		end

		shell.execute("wget", url, path)
	end,
	-- delete a file
	delete = function(path)
		if not fs.exists(path) then
			return
		end

		fs.delete(path)
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
		local currentPos = turtle.getPosition()

		print("navigating to", target)

		-- east/west
		if target.x ~= currentPos.x then
			local difX = target.x - currentPos.x

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
		if target.z ~= currentPos.z then
			local difZ = target.z - currentPos.z

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
		if target.y ~= currentPos.y then
			local difY = target.y - currentPos.y

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

commandList.pastebin = function(code, ...)
	return commandList.shell("pastebin", "run", code, ...)
end

commandList.wrun = function(url, ...)
	return commandList.shell("wget", "run", url, ...)
end

return commandList
