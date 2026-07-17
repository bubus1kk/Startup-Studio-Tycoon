--!strict

local FailureOfficeTemplates = {}

function FailureOfficeTemplates.missingPivot(): Folder
	local root = Instance.new("Folder")
	root.Name = "OfficeTemplates"
	for _, category in { "Tiers", "Rooms", "Equipment", "Furniture" } do
		local folder = Instance.new("Folder")
		folder.Name = category
		folder.Parent = root
	end
	local garage = Instance.new("Model")
	garage.Name = "Garage"
	garage.Parent = root.Tiers
	return root
end

return table.freeze(FailureOfficeTemplates)
