--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local SessionCurrencyService = require(ServerScriptService.Services.SessionCurrencyService)
local TestHarness = require(script.Parent.Parent.TestHarness)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type TestCase = TestHarness.TestCase
local SessionCurrencyServiceSpec = {}

local resolver: DependencyResolver = {
	Get = function(_self: DependencyResolver, _name: string): unknown
		return nil
	end,
	Require = function(_self: DependencyResolver, name: string): unknown
		error(`Unexpected dependency {name}`)
	end,
}

local function reservationIdempotencyTest()
	local service = SessionCurrencyService.new(250000)
	service:Init(resolver)
	service:Start()
	TestHarness.assertTrue(service:OpenSession(1).ok)
	local reserve = service:ReserveDebit(1, "Cash", 1000, "test", "tx-1")
	TestHarness.assertTrue(reserve.ok)
	local duplicate = service:ReserveDebit(1, "Cash", 1000, "test", "tx-1")
	TestHarness.assertTrue(duplicate.ok)
	if reserve.ok and duplicate.ok then
		TestHarness.assertEqual(reserve.value.reservationId, duplicate.value.reservationId)
		TestHarness.assertTrue(service:CommitDebit(reserve.value.reservationId).ok)
		TestHarness.assertTrue(service:CommitDebit(reserve.value.reservationId).ok)
	end
	local conflict = service:ReserveDebit(1, "Cash", 999, "test", "tx-1")
	TestHarness.assertTrue(not conflict.ok and conflict.error.code == "TransactionIdConflict")
	local balance = service:GetBalance(1, "Cash")
	TestHarness.assertTrue(balance.ok and balance.value == 249000)
	local insufficient = service:ReserveDebit(1, "Cash", 300000, "test", "tx-2")
	TestHarness.assertTrue(not insufficient.ok and insufficient.error.code == "InsufficientFunds")
	service:Destroy()
end

local function committedCompensationTest()
	local service = SessionCurrencyService.new(250000)
	service:Init(resolver)
	service:Start()
	service:OpenSession(3)
	local reserve = service:ReserveDebit(3, "Cash", 1250, "visual-commit", "tx-compensate")
	TestHarness.assertTrue(reserve.ok)
	if reserve.ok then
		TestHarness.assertTrue(service:CommitDebit(reserve.value.reservationId).ok)
		local rollback = service:RollbackCommittedDebit(reserve.value.reservationId)
		TestHarness.assertTrue(rollback.ok and rollback.value.balances.Cash == 250000)
		local duplicate = service:RollbackCommittedDebit(reserve.value.reservationId)
		TestHarness.assertTrue(duplicate.ok and duplicate.value.balances.Cash == 250000)
		TestHarness.assertTrue(not service:CommitDebit(reserve.value.reservationId).ok)
	end
	service:Destroy()
end

local function releaseAndRestoreTest()
	local service = SessionCurrencyService.new(250000)
	service:Init(resolver)
	service:Start()
	service:OpenSession(2)
	local reserve = service:ReserveDebit(2, "Cash", 5000, "test", "tx-release")
	TestHarness.assertTrue(reserve.ok)
	if reserve.ok then
		TestHarness.assertTrue(service:ReleaseDebit(reserve.value.reservationId).ok)
		TestHarness.assertTrue(service:ReleaseDebit(reserve.value.reservationId).ok)
	end
	local snapshot = service:ExportSession(2)
	TestHarness.assertTrue(snapshot.ok and snapshot.value.balances.Cash == 250000)
	service:CloseSession(2)
	if snapshot.ok then
		TestHarness.assertTrue(service:RestoreSession(2, snapshot.value).ok)
	end
	service:Destroy()
end

function SessionCurrencyServiceSpec.tests(): { TestCase }
	return {
		{ name = "currency debit reservation is idempotent and conflict safe", run = reservationIdempotencyTest },
		{ name = "currency release and session restore preserve balance", run = releaseAndRestoreTest },
		{ name = "committed debit compensation is idempotent", run = committedCompensationTest },
	}
end
return table.freeze(SessionCurrencyServiceSpec)
