-- turtle.lua
-- a version of the turtle API with some overridden methods.
-- also has some extra methods for getting and updating the internal facing and position values.

local CURRENT_POSITION = vector.new(0, 0, 0)
local CURRENT_FACING = 0

local FACING_VECTOR_LOOKUP = {
	[0] = vector.new(0, 0, -1),
	[1] = vector.new(1, 0, 0),
	[2] = vector.new(0, 0, 1),
	[3] = vector.new(-1, 0, 0),
}

local turtle = setmetatable({
	---Returns the direction the turtle is currently facing.
	---@return number
	getFacing = function()
		return CURRENT_FACING
	end,
	---Updates the internal direction the turtle is currently facing.
	---@param newFacing number
	updateFacing = function(newFacing)
		CURRENT_FACING = newFacing
	end,
	---Returns the current position of the turtle.
	---@return vector.Vector
	getPosition = function()
		return CURRENT_POSITION
	end,
	---Updates the internal position value of the turtle.
	---@param newPosition vector.Vector
	updatePosition = function(newPosition)
		CURRENT_POSITION = newPosition
	end,

	-- override methods
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

return turtle
