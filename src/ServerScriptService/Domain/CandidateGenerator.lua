--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)

type Candidate = EmployeeTypes.Candidate
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeGrade = EmployeeTypes.EmployeeGrade
type EmployeeRoleId = EmployeeTypes.EmployeeRoleId
type RoleDefinition = EmployeeTypes.RoleDefinition
type GradeDefinition = EmployeeTypes.GradeDefinition
type TraitDefinition = EmployeeTypes.TraitDefinition

export type RandomSource = (minimum: number, maximum: number) -> number
export type NameSource = (index: number, names: { string }) -> string
export type GenerateContext = {
	ownerUserId: number,
	slotIndex: number,
	generation: number,
	officeTierId: string,
	availableRoles: { EmployeeRoleId },
	now: number,
	forcedRoleId: EmployeeRoleId?,
	forcedGrade: EmployeeGrade?,
	forcedMinimumStats: boolean?,
	forcedTraitId: EmployeeTypes.EmployeeTraitId?,
}

type GeneratorData = {
	_config: EmployeeConfig,
	_random: RandomSource,
	_nameSource: NameSource,
	_roleById: { [EmployeeRoleId]: RoleDefinition },
	_gradeById: { [EmployeeGrade]: GradeDefinition },
	_traitById: { [EmployeeTypes.EmployeeTraitId]: TraitDefinition },
}

local CandidateGenerator = {}
CandidateGenerator.__index = CandidateGenerator
export type Generator = typeof(setmetatable({} :: GeneratorData, CandidateGenerator))

local function defaultNameSource(index: number, names: { string }): string
	return names[index]
end

local function roundNearest(value: number, quantum: number): number
	return math.floor(value / quantum + 0.5) * quantum
end

function CandidateGenerator.new(config: EmployeeConfig, randomSource: RandomSource, nameSource: NameSource?): Generator
	local roleById = {} :: { [EmployeeRoleId]: RoleDefinition }
	local gradeById = {} :: { [EmployeeGrade]: GradeDefinition }
	local traitById = {} :: { [EmployeeTypes.EmployeeTraitId]: TraitDefinition }
	for _, definition in config.roles do
		roleById[definition.id] = definition
	end
	for _, definition in config.grades do
		gradeById[definition.id] = definition
	end
	for _, definition in config.traits do
		traitById[definition.id] = definition
	end
	return setmetatable({
		_config = config,
		_random = randomSource,
		_nameSource = nameSource or defaultNameSource,
		_roleById = roleById,
		_gradeById = gradeById,
		_traitById = traitById,
	}, CandidateGenerator)
end

function CandidateGenerator._pickGrade(self: Generator, tierId: string): EmployeeGrade
	local weights = assert(self._config.gradeWeightsByTier[tierId], `Unknown employee tier {tierId}`)
	local roll = self._random(1, 100)
	local cursor = 0
	for _, grade in self._config.grades do
		cursor += weights[grade.id] or 0
		if roll <= cursor then
			return grade.id
		end
	end
	return self._config.grades[1].id
end

function CandidateGenerator.Generate(self: Generator, context: GenerateContext): Candidate
	assert(#context.availableRoles > 0, "Candidate generation requires an available role")
	local roleId = context.forcedRoleId or context.availableRoles[self._random(1, #context.availableRoles)]
	local role = assert(self._roleById[roleId], `Unknown employee role {roleId}`)
	local gradeId = context.forcedGrade or self:_pickGrade(context.officeTierId)
	local grade = assert(self._gradeById[gradeId], `Unknown employee grade {gradeId}`)
	local traitDefinition = if context.forcedTraitId ~= nil
		then assert(self._traitById[context.forcedTraitId], `Unknown employee trait {context.forcedTraitId}`)
		else self._config.traits[self._random(1, #self._config.traits)]
	local function stat(bias: number): number
		local base = if context.forcedMinimumStats then grade.statMin else self._random(grade.statMin, grade.statMax)
		return math.clamp(base + bias, self._config.statClamp.minimum, self._config.statClamp.maximum)
	end
	local speed = stat(role.statBias.speed)
	local quality = stat(role.statBias.quality)
	local reliability = stat(role.statBias.reliability)
	local statPower = (speed + quality + reliability) / 3
	local baseline = (grade.statMin + grade.statMax) / 2
	local multiplier = math.clamp(
		1 + (statPower - baseline) * self._config.candidate.costPowerCoefficient,
		self._config.candidate.minimumMultiplier,
		self._config.candidate.maximumMultiplier
	)
	local hiringCost =
		math.max(10, roundNearest(grade.baseHiringCost * multiplier * traitDefinition.hiringCostMultiplier, 10))
	local salary = math.max(1, roundNearest(grade.baseSalary * multiplier * traitDefinition.salaryMultiplier, 1))
	local nameIndex = self._random(1, #self._config.candidate.names)
	return {
		candidateId = `candidate-{context.ownerUserId}-{context.generation}-{context.slotIndex}`,
		ownerUserId = context.ownerUserId,
		slotIndex = context.slotIndex,
		generation = context.generation,
		displayName = self._nameSource(nameIndex, self._config.candidate.names),
		roleId = roleId,
		grade = gradeId,
		speed = speed,
		quality = quality,
		reliability = reliability,
		traitId = traitDefinition.id,
		hiringCost = hiringCost,
		salaryPerCycle = salary,
		createdAt = context.now,
		expiresAt = context.now + self._config.candidate.ttlSeconds,
	}
end

return table.freeze(CandidateGenerator)
