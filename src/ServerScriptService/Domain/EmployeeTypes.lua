--!strict

export type EmployeeRoleId =
	"Developer"
	| "Designer"
	| "QAEngineer"
	| "Marketer"
	| "ProductManager"
	| "SystemAdministrator"
	| "HRSpecialist"
	| "Executive"
	| "Researcher"
export type EmployeeGrade = "Trainee" | "Junior" | "Specialist" | "Expert"
export type EmployeeTraitId =
	"FastLearner"
	| "Focused"
	| "TeamPlayer"
	| "Efficient"
	| "Perfectionist"
	| "Reliable"
	| "Workaholic"
	| "Creative"
	| "Independent"
	| "Mentor"
	| "Eager"
	| "Methodical"
export type EmployeeStatus = "Active" | "Unpaid" | "Inactive" | "Dismissed"
export type MovementState =
	"Spawning"
	| "WalkingToDesk"
	| "Working"
	| "WalkingToBreak"
	| "OnBreak"
	| "ReturningToDesk"
	| "Stuck"
	| "Repositioning"
	| "Despawning"

export type StatBlock = { speed: number, quality: number, reliability: number }
export type RoleDefinition = {
	id: EmployeeRoleId,
	displayName: string,
	roomId: string,
	equipmentId: string,
	upgradeId: string,
	statBias: StatBlock,
}
export type GradeDefinition = {
	id: EmployeeGrade,
	order: number,
	maxLevel: number,
	statMin: number,
	statMax: number,
	baseHiringCost: number,
	baseSalary: number,
}
export type TraitDefinition = {
	id: EmployeeTraitId,
	speedMultiplier: number,
	qualityMultiplier: number,
	reliabilityMultiplier: number,
	outputMultiplier: number,
	xpMultiplier: number,
	salaryMultiplier: number,
	positiveMoraleMultiplier: number,
	focusedMoraleMinimum: number?,
	teamOutputBonus: number,
	mentorXpBonus: number,
	hiringCostMultiplier: number,
	ignoresTeamBonuses: boolean,
}
export type WorkstationSlotDefinition = {
	slotIndex: number,
	minimumEquipmentLevel: number,
	workOffset: CFrame,
	approachOffset: CFrame,
}
export type WorkstationDefinition = {
	roleId: EmployeeRoleId,
	logicalEquipmentId: string,
	capacities: { [number]: number },
	slots: { WorkstationSlotDefinition },
}
export type EmployeeConfig = {
	schemaVersion: number,
	configVersion: number,
	roles: { RoleDefinition },
	grades: { GradeDefinition },
	traits: { TraitDefinition },
	gradeWeightsByTier: { [string]: { [EmployeeGrade]: number } },
	tierEmployeeCaps: { [string]: number },
	workstations: { WorkstationDefinition },
	statClamp: { minimum: number, maximum: number },
	candidate: {
		poolSize: number,
		ttlSeconds: number,
		refreshCooldownSeconds: number,
		costPowerCoefficient: number,
		minimumMultiplier: number,
		maximumMultiplier: number,
		names: { string },
	},
	payroll: { intervalSeconds: number, firstMissMorale: number, laterMissMorale: number, recoveryMorale: number },
	morale: {
		initial: number,
		minimum: number,
		maximum: number,
		bands: { { minimum: number, multiplier: number } },
		hrRecoveryPerMinute: number,
		recreationRecoveryPerMinute: number,
		teamRecoveryCapPerMinute: number,
	},
	productivity: {
		speedWeight: number,
		qualityWeight: number,
		reliabilityWeight: number,
		levelBonusPerLevel: number,
		equipmentMultipliers: { [number]: number },
		employmentMultipliers: { [EmployeeStatus]: number },
		teamPlayerStackCap: number,
		mentorStackCap: number,
		maximumDeltaSeconds: number,
	},
	progression: {
		xpPerWorkPoint: number,
		baseRequiredXp: number,
		requiredXpPerLevel: number,
		levelUpMorale: number,
		retainXpAtMaxLevel: boolean,
	},
	scheduler: { productivitySeconds: number, stuckSeconds: number, candidateSeconds: number },
	movement: {
		stuckAfterSeconds: number,
		minimumProgressStuds: number,
		minimumPathRequestSeconds: number,
		maxPathRequestsPerPlayerPerSecond: number,
		walkSpeed: number,
		agentRadius: number,
		agentHeight: number,
		animationIds: { idle: string, walk: string, work: string },
	},
	performance: { maxEmployeesPerPlayer: number, maxPlayers: number, maxNpcModelsPerPlayer: number },
	ui: { rosterPageSize: number },
}

export type Candidate = {
	candidateId: string,
	ownerUserId: number,
	slotIndex: number,
	generation: number,
	displayName: string,
	roleId: EmployeeRoleId,
	grade: EmployeeGrade,
	speed: number,
	quality: number,
	reliability: number,
	traitId: EmployeeTraitId,
	hiringCost: number,
	salaryPerCycle: number,
	createdAt: number,
	expiresAt: number,
}

export type Employee = {
	employeeId: string,
	ownerUserId: number,
	displayName: string,
	roleId: EmployeeRoleId,
	grade: EmployeeGrade,
	level: number,
	xp: number,
	speed: number,
	quality: number,
	reliability: number,
	traitId: EmployeeTraitId,
	hiringCost: number,
	salaryPerCycle: number,
	morale: number,
	status: EmployeeStatus,
	missedPayrollCount: number,
	assignedWorkstationId: string?,
	runtimeGeneration: number,
	createdSequence: number,
}

export type RoleWorkLedger = { [EmployeeRoleId]: number }
export type CandidateSnapshot = { candidate: Candidate, remainingTtl: number }
export type EmployeeSessionSnapshot = {
	schemaVersion: number,
	employees: { Employee },
	assignments: { [string]: string },
	roleWorkLedger: RoleWorkLedger,
	candidates: { CandidateSnapshot },
	refreshRemainingSeconds: number,
	payrollRemainingSeconds: number,
	nextEmployeeSequence: number,
}

export type WorkstationRuntime = {
	workstationId: string,
	ownerUserId: number,
	roleId: EmployeeRoleId,
	equipmentId: string,
	equipmentLevel: number,
	slotIndex: number,
	runtimeGeneration: number,
	workAttachment: Attachment,
	approachAttachment: Attachment,
	workCFrame: CFrame,
	approachCFrame: CFrame,
}

return table.freeze({})
