--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)

type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeRoleId = EmployeeTypes.EmployeeRoleId
type OfficeLayoutState = OfficeTypes.OfficeLayoutState
type WorkstationDefinition = EmployeeTypes.WorkstationDefinition

export type LogicalSlot = {
	workstationId: string,
	roleId: EmployeeRoleId,
	equipmentId: string,
	equipmentLevel: number,
	slot: EmployeeTypes.WorkstationSlotDefinition,
}

local WorkstationDefinitions = {}

function WorkstationDefinitions.Id(roleId: EmployeeRoleId, slotIndex: number): string
	return `workstation:{roleId}:{slotIndex}`
end

function WorkstationDefinitions.GetEquipmentLevel(
	config: EmployeeConfig,
	layout: OfficeLayoutState,
	definition: WorkstationDefinition
): number
	if not layout.purchasedEquipment[definition.logicalEquipmentId] then
		return 0
	end
	for _, role in config.roles do
		if role.id == definition.roleId then
			return layout.upgradeLevels[role.upgradeId] or 1
		end
	end
	return 1
end

function WorkstationDefinitions.Build(config: EmployeeConfig, layout: OfficeLayoutState): { LogicalSlot }
	local result = {}
	for _, definition in config.workstations do
		local level = WorkstationDefinitions.GetEquipmentLevel(config, layout, definition)
		if level > 0 then
			for _, slot in definition.slots do
				if slot.minimumEquipmentLevel <= level then
					table.insert(result, {
						workstationId = WorkstationDefinitions.Id(definition.roleId, slot.slotIndex),
						roleId = definition.roleId,
						equipmentId = definition.logicalEquipmentId,
						equipmentLevel = level,
						slot = slot,
					})
				end
			end
		end
	end
	table.sort(result, function(a: LogicalSlot, b: LogicalSlot): boolean
		return a.workstationId < b.workstationId
	end)
	return result
end

return table.freeze(WorkstationDefinitions)
