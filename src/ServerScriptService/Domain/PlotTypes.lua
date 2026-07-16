--!strict

export type OfficeShellDefinition = {
	footprintSize: Vector2,
	localOffset: CFrame,
	wallHeight: number,
	wallThickness: number,
	floorThickness: number,
	entranceWidth: number,
}

export type PlotDefinition = {
	id: string,
	origin: CFrame,
	footprintSize: Vector2,
	maxHeight: number,
	spawnOffset: CFrame,
	officeShell: OfficeShellDefinition,
}

export type PlotConfig = {
	maxPlayers: number,
	centerSpacing: number,
	plotGap: number,
	definitions: { PlotDefinition },
}

export type AllocationState = "Reserved" | "Active" | "Releasing"

export type PlotAllocation = {
	plotId: string,
	userId: number,
	state: AllocationState,
	generationToken: number,
	model: Model?,
}

export type PlotAllocationSnapshot = {
	plotId: string,
	userId: number,
	state: AllocationState,
}

export type PlotSpawnContext = {
	plotId: string,
	userId: number,
	generationToken: number,
	spawnCFrame: CFrame,
	spawnLocation: SpawnLocation,
}

export type PlotContext = {
	definition: PlotDefinition,
	model: Model,
}

return table.freeze({})
