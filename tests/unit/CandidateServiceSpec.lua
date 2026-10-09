--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local CandidateGenerator = require(ServerScriptService.Domain.CandidateGenerator)
local CandidateService = require(ServerScriptService.Services.CandidateService)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local EmployeeDefinitions = require(ServerStorage.Config.EmployeeDefinitions)
local TestHarness = require(script.Parent.Parent.TestHarness)

type EmployeeConfig = EmployeeTypes.EmployeeConfig
type TestCase = TestHarness.TestCase

local CandidateServiceSpec = {}

local function expirationAndConsumptionCodesTest()
	local now = 100
	local config = (EmployeeDefinitions :: unknown) :: EmployeeConfig
	local generator = CandidateGenerator.new(config, function(minimum: number, _maximum: number): number
		return minimum
	end)
	local service = CandidateService.new(config, generator, function(): number
		return now
	end, function(_userId: number)
		return {
			officeTierId = "tier_garage",
			availableRoles = { "Developer" },
			cash = 10000,
		}
	end)
	TestHarness.assertTrue(service:PrepareSession(91, nil, nil).ok)
	local first = service:EnsureFresh(91)
	TestHarness.assertTrue(first.ok)
	if not first.ok then
		return
	end
	local hireable = false
	for _, candidate in first.value do
		if candidate.roleId == "Developer" and candidate.hiringCost <= 10000 then
			hireable = true
		end
	end
	TestHarness.assertTrue(hireable, "A free compatible slot and Trainee Cash must guarantee a hireable candidate")
	TestHarness.assertTrue(service:Refresh(91).ok)
	local cooldown = service:Refresh(91)
	TestHarness.assertTrue(not cooldown.ok)
	if not cooldown.ok then
		TestHarness.assertEqual(cooldown.error.code, "CandidateRefreshCooldown")
	end
	now += config.candidate.refreshCooldownSeconds
	TestHarness.assertTrue(service:Refresh(91).ok)
	local refreshed = service:EnsureFresh(91)
	TestHarness.assertTrue(refreshed.ok)
	if not refreshed.ok then
		return
	end
	local expiredId = refreshed.value[1].candidateId
	now += config.candidate.ttlSeconds + 1
	local expired = service:Find(91, expiredId)
	TestHarness.assertTrue(not expired.ok)
	if not expired.ok then
		TestHarness.assertEqual(expired.error.code, "CandidateExpired")
	end
	local current = service:EnsureFresh(91)
	TestHarness.assertTrue(current.ok)
	if not current.ok then
		return
	end
	local consumedId = current.value[1].candidateId
	TestHarness.assertTrue(service:Consume(91, consumedId).ok)
	local consumed = service:Find(91, consumedId)
	TestHarness.assertTrue(not consumed.ok)
	if not consumed.ok then
		TestHarness.assertEqual(consumed.error.code, "CandidateAlreadyConsumed")
	end
	service:Destroy()
end

function CandidateServiceSpec.tests(): { TestCase }
	return {
		{
			name = "candidate service preserves expired and consumed rejection codes",
			run = expirationAndConsumptionCodesTest,
		},
	}
end

return table.freeze(CandidateServiceSpec)
