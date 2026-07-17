--!strict

return table.freeze({
	empty = table.freeze({}),
	invalidPrice = table.freeze({
		schemaVersion = 1,
		configVersion = 1,
		pageSize = 5,
		tiers = {},
		rooms = {},
		items = {},
		upgrades = {},
	}),
})
