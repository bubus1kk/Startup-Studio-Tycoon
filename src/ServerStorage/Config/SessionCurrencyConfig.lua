--!strict

return {
	initialCashByEnvironment = {
		Development = 250000,
		Test = 250000,
		Production = 250000,
	},
	snapshotTtlSeconds = 15 * 60,
	snapshotCapacity = 24,
}
