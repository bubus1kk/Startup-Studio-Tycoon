--!strict

local FOOTPRINT_SIZE = Vector2.new(96, 96)
local MAX_HEIGHT = 64
local CENTER_SPACING = 128

local officeShell = {
	footprintSize = Vector2.new(48, 36),
	localOffset = CFrame.new(0, 0, -8),
	wallHeight = 14,
	wallThickness = 1,
	floorThickness = 1,
	entranceWidth = 20,
}

local function definition(id: string, x: number, z: number)
	return {
		id = id,
		origin = CFrame.new(x, 0, z),
		footprintSize = FOOTPRINT_SIZE,
		maxHeight = MAX_HEIGHT,
		spawnOffset = CFrame.lookAt(Vector3.new(0, 0, 22), Vector3.new(0, 0, -8)),
		officeShell = officeShell,
	}
end

return {
	maxPlayers = 6,
	centerSpacing = CENTER_SPACING,
	plotGap = 32,
	definitions = {
		definition("plot_01", -CENTER_SPACING, -CENTER_SPACING * 0.5),
		definition("plot_02", 0, -CENTER_SPACING * 0.5),
		definition("plot_03", CENTER_SPACING, -CENTER_SPACING * 0.5),
		definition("plot_04", -CENTER_SPACING, CENTER_SPACING * 0.5),
		definition("plot_05", 0, CENTER_SPACING * 0.5),
		definition("plot_06", CENTER_SPACING, CENTER_SPACING * 0.5),
	},
}
