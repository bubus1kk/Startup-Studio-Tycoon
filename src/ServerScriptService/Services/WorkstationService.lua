--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local OfficeTypes = require(ServerScriptService.Domain.OfficeTypes)
local WorkstationDefinitions = require(ServerScriptService.Domain.WorkstationDefinitions)
local OfficeBuildingService = require(ServerScriptService.Services.OfficeBuildingService)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type EmployeeRoleId = EmployeeTypes.EmployeeRoleId
type OfficeRuntimeChangedContext = OfficeTypes.OfficeRuntimeChangedContext
type OfficeService = OfficeBuildingService.Service
type Result<T> = AppTypes.Result<T>
type WorkstationRuntime = EmployeeTypes.WorkstationRuntime

export type ChangedContext = { userId: number, runtimeGeneration: number, releasedEmployeeIds: { string } }
export type ChangedCallback = (context: ChangedContext) -> ()

type Session = {
	userId: number,
	runtimeSessionId: string,
	officeTierId: string,
	runtimeGeneration: number,
	slots: { [string]: WorkstationRuntime },
	employeeToWorkstation: { [string]: string },
	workstationToEmployee: { [string]: string },
	connections: { RBXScriptConnection },
	hasRecreationLounge: boolean,
}

type ServiceData = {
	_config: EmployeeConfig,
	_officeService: OfficeService?,
	_sessions: { [number]: Session },
	_listeners: { [number]: ChangedCallback },
	_nextListenerId: number,
	_unsubscribeOffice: (() -> ())?,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local WorkstationService = {}
WorkstationService.__index = WorkstationService
export type Service = typeof(setmetatable({} :: ServiceData, WorkstationService))

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
end

function WorkstationService.new(config: EmployeeConfig): Service
	return setmetatable({
		_config = config,
		_officeService = nil,
		_sessions = {},
		_listeners = {},
		_nextListenerId = 0,
		_unsubscribeOffice = nil,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, WorkstationService)
end

function WorkstationService.Init(self: Service, dependencies: DependencyResolver)
	self._officeService = dependencies:Require("OfficeBuildingService") :: OfficeService
	self._isInitialized = true
end

function WorkstationService._publish(self: Service, session: Session, releasedEmployeeIds: { string })
	local context: ChangedContext = {
		userId = session.userId,
		runtimeGeneration = session.runtimeGeneration,
		releasedEmployeeIds = releasedEmployeeIds,
	}
	for _, listener in self._listeners do
		local ok, cause = pcall(listener, context)
		if not ok then
			warn(`[WorkstationService] listener failed: {tostring(cause)}`)
		end
	end
end

function WorkstationService.SubscribeChanged(self: Service, callback: ChangedCallback): () -> ()
	self._nextListenerId += 1
	local id = self._nextListenerId
	self._listeners[id] = callback
	local subscribed = true
	return function()
		if subscribed then
			subscribed = false
			self._listeners[id] = nil
		end
	end
end

function WorkstationService._handleLost(
	self: Service,
	userId: number,
	capturedGeneration: number,
	workstationIds: { string }
)
	local session = self._sessions[userId]
	local office = self._officeService
	if session == nil or office == nil then
		return
	end
	local current = office:GetRuntimeContext(userId)
	if current == nil then
		return
	end
	if current.runtimeGeneration == capturedGeneration then
		local released = {}
		for _, workstationId in workstationIds do
			local employeeId = session.workstationToEmployee[workstationId]
			if employeeId ~= nil then
				session.workstationToEmployee[workstationId] = nil
				session.employeeToWorkstation[employeeId] = nil
				table.insert(released, employeeId)
			end
		end
		if #released > 0 then
			self:_publish(session, released)
		end
	end
	self:_rebuild(current)
end

function WorkstationService._watch(self: Service, session: Session, instance: Instance, workstationIds: { string })
	local generation = session.runtimeGeneration
	table.insert(
		session.connections,
		instance.AncestryChanged:Connect(function(_, parent: Instance?)
			if parent == nil then
				task.defer(function()
					self:_handleLost(session.userId, generation, workstationIds)
				end)
			end
		end)
	)
end

function WorkstationService._rebuild(self: Service, context: OfficeRuntimeChangedContext): Result<true>
	local session = self._sessions[context.userId]
	if session == nil then
		return AppTypes.failure("WorkstationSessionNotReady", "Workstation session is not open", nil)
	end
	if
		context.runtimeSessionId ~= session.runtimeSessionId
		or context.runtimeGeneration < session.runtimeGeneration
		or context.root.Parent == nil
	then
		return AppTypes.success(true)
	end
	disconnectAll(session.connections)
	local oldEmployeeToWorkstation = table.clone(session.employeeToWorkstation)
	local oldSlots = session.slots
	for _, runtime in oldSlots do
		if runtime.workAttachment.Parent ~= nil then
			runtime.workAttachment:Destroy()
		end
		if runtime.approachAttachment.Parent ~= nil then
			runtime.approachAttachment:Destroy()
		end
	end
	session.runtimeGeneration = context.runtimeGeneration
	session.officeTierId = context.layout.officeTierId
	session.hasRecreationLounge = context.layout.purchasedFurniture.furniture_recreation == true
	session.slots = {}
	local equipmentFolder = context.root:FindFirstChild("Equipment")
	for _, logical in WorkstationDefinitions.Build(self._config, context.layout) do
		local equipmentModel = if equipmentFolder ~= nil
			then equipmentFolder:FindFirstChild(logical.equipmentId)
			else nil
		local pivot = if equipmentModel ~= nil then equipmentModel:FindFirstChild("Pivot") else nil
		if equipmentModel ~= nil and equipmentModel:IsA("Model") and pivot ~= nil and pivot:IsA("BasePart") then
			local approach = Instance.new("Attachment")
			approach.Name = `EmployeeApproach_{logical.slot.slotIndex}`
			approach.CFrame = logical.slot.approachOffset
			approach:SetAttribute("WorkstationId", logical.workstationId)
			approach.Parent = pivot
			local work = Instance.new("Attachment")
			work.Name = `EmployeeWork_{logical.slot.slotIndex}`
			work.CFrame = logical.slot.workOffset
			work:SetAttribute("WorkstationId", logical.workstationId)
			work.Parent = pivot
			session.slots[logical.workstationId] = {
				workstationId = logical.workstationId,
				ownerUserId = context.userId,
				roleId = logical.roleId,
				equipmentId = logical.equipmentId,
				equipmentLevel = logical.equipmentLevel,
				slotIndex = logical.slot.slotIndex,
				runtimeGeneration = context.runtimeGeneration,
				workAttachment = work,
				approachAttachment = approach,
				workCFrame = pivot.CFrame * logical.slot.workOffset,
				approachCFrame = pivot.CFrame * logical.slot.approachOffset,
			}
			self:_watch(session, work, { logical.workstationId })
			self:_watch(session, approach, { logical.workstationId })
		end
	end

	local idsByEquipment: { [string]: { string } } = {}
	for workstationId, runtime in session.slots do
		local ids = idsByEquipment[runtime.equipmentId]
		if ids == nil then
			ids = {}
			idsByEquipment[runtime.equipmentId] = ids
		end
		table.insert(ids, workstationId)
	end
	if equipmentFolder ~= nil then
		for equipmentId, workstationIds in idsByEquipment do
			local model = equipmentFolder:FindFirstChild(equipmentId)
			if model ~= nil then
				self:_watch(session, model, workstationIds)
			end
		end
	end

	local released = {}
	table.clear(session.employeeToWorkstation)
	table.clear(session.workstationToEmployee)
	for employeeId, workstationId in oldEmployeeToWorkstation do
		if session.slots[workstationId] ~= nil and session.workstationToEmployee[workstationId] == nil then
			session.employeeToWorkstation[employeeId] = workstationId
			session.workstationToEmployee[workstationId] = employeeId
		else
			table.insert(released, employeeId)
		end
	end
	self:_publish(session, released)
	return AppTypes.success(true)
end

function WorkstationService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("WorkstationService.Start requires one successful Init", 2)
	end
	self._unsubscribeOffice = (self._officeService :: OfficeService):SubscribeRuntimeChanged(function(context)
		if context.reason == "PurchaseCommitted" or context.reason == "Rebuilt" then
			self:_rebuild(context)
		end
	end)
	self._isStarted = true
end

function WorkstationService.PrepareSession(self: Service, userId: number): Result<true>
	if self._sessions[userId] ~= nil then
		return AppTypes.failure("WorkstationSessionAlreadyOpen", "Workstation session is already open", nil)
	end
	local context = (self._officeService :: OfficeService):GetRuntimeContext(userId)
	if context == nil then
		return AppTypes.failure("OfficeSessionNotReady", "Office runtime is unavailable", nil)
	end
	self._sessions[userId] = {
		userId = userId,
		runtimeSessionId = context.runtimeSessionId,
		officeTierId = context.layout.officeTierId,
		runtimeGeneration = context.runtimeGeneration,
		slots = {},
		employeeToWorkstation = {},
		workstationToEmployee = {},
		connections = {},
		hasRecreationLounge = context.layout.purchasedFurniture.furniture_recreation == true,
	}
	local result = self:_rebuild(context)
	if not result.ok then
		self._sessions[userId] = nil
	end
	return result
end

function WorkstationService.GetTierId(self: Service, userId: number): string?
	local session = self._sessions[userId]
	return if session ~= nil then session.officeTierId else nil
end

function WorkstationService.HasRecreationLounge(self: Service, userId: number): boolean
	local session = self._sessions[userId]
	return session ~= nil and session.hasRecreationLounge
end

function WorkstationService.GetSlot(self: Service, userId: number, workstationId: string): WorkstationRuntime?
	local session = self._sessions[userId]
	return if session ~= nil then session.slots[workstationId] else nil
end

function WorkstationService.FindOwner(self: Service, workstationId: string): number?
	for userId, session in self._sessions do
		if session.slots[workstationId] ~= nil then
			return userId
		end
	end
	return nil
end

function WorkstationService.GetCapacity(self: Service, userId: number): number
	local session = self._sessions[userId]
	local count = 0
	if session ~= nil then
		for _ in session.slots do
			count += 1
		end
	end
	return count
end

function WorkstationService.GetOccupiedCount(self: Service, userId: number): number
	local session = self._sessions[userId]
	local count = 0
	if session ~= nil then
		for _ in session.workstationToEmployee do
			count += 1
		end
	end
	return count
end

function WorkstationService.GetAvailableRoles(self: Service, userId: number): { EmployeeRoleId }
	local session = self._sessions[userId]
	local byRole = {} :: { [EmployeeRoleId]: boolean }
	if session ~= nil then
		for workstationId, runtime in session.slots do
			if session.workstationToEmployee[workstationId] == nil then
				byRole[runtime.roleId] = true
			end
		end
	end
	local result = {}
	for _, role in self._config.roles do
		if byRole[role.id] then
			table.insert(result, role.id)
		end
	end
	return result
end

function WorkstationService.FindFirstFree(self: Service, userId: number, roleId: EmployeeRoleId): WorkstationRuntime?
	local session = self._sessions[userId]
	if session == nil then
		return nil
	end
	local ids = {}
	for workstationId, runtime in session.slots do
		if runtime.roleId == roleId and session.workstationToEmployee[workstationId] == nil then
			table.insert(ids, workstationId)
		end
	end
	table.sort(ids)
	return if ids[1] ~= nil then session.slots[ids[1]] else nil
end

function WorkstationService.Assign(
	self: Service,
	userId: number,
	employeeId: string,
	roleId: EmployeeRoleId,
	workstationId: string
): Result<WorkstationRuntime>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.failure("WorkstationSessionNotReady", "Workstation session is not open", nil)
	end
	local slot = session.slots[workstationId]
	if slot == nil then
		return AppTypes.failure("WorkstationNotFound", "Workstation does not exist", nil)
	end
	if slot.ownerUserId ~= userId then
		return AppTypes.failure("ForeignWorkstation", "Workstation belongs to another player", nil)
	end
	if slot.roleId ~= roleId then
		return AppTypes.failure("WorkstationIncompatible", "Workstation role is incompatible", nil)
	end
	local occupant = session.workstationToEmployee[workstationId]
	if occupant ~= nil and occupant ~= employeeId then
		return AppTypes.failure("WorkstationOccupied", "Workstation is occupied", nil)
	end
	local previous = session.employeeToWorkstation[employeeId]
	if previous == workstationId then
		return AppTypes.success(slot)
	end
	if previous ~= nil then
		session.workstationToEmployee[previous] = nil
	end
	session.employeeToWorkstation[employeeId] = workstationId
	session.workstationToEmployee[workstationId] = employeeId
	return AppTypes.success(slot)
end

function WorkstationService.ReleaseEmployee(self: Service, userId: number, employeeId: string): boolean
	local session = self._sessions[userId]
	if session == nil then
		return false
	end
	local workstationId = session.employeeToWorkstation[employeeId]
	if workstationId == nil then
		return false
	end
	session.employeeToWorkstation[employeeId] = nil
	session.workstationToEmployee[workstationId] = nil
	return true
end

function WorkstationService.IsAssignmentValid(self: Service, userId: number, employeeId: string): boolean
	local session = self._sessions[userId]
	if session == nil then
		return false
	end
	local workstationId = session.employeeToWorkstation[employeeId]
	return workstationId ~= nil and session.slots[workstationId] ~= nil
end

function WorkstationService.ExportAssignments(self: Service, userId: number): { [string]: string }
	local session = self._sessions[userId]
	return if session ~= nil then table.clone(session.employeeToWorkstation) else {}
end

function WorkstationService.RestoreAssignments(
	self: Service,
	userId: number,
	employeesById: { [string]: EmployeeTypes.Employee },
	assignments: { [string]: string }
)
	local employeeIds = {}
	for employeeId in assignments do
		table.insert(employeeIds, employeeId)
	end
	table.sort(employeeIds)
	for _, employeeId in employeeIds do
		local employee = employeesById[employeeId]
		if employee ~= nil then
			local result = self:Assign(userId, employeeId, employee.roleId, assignments[employeeId])
			if result.ok then
				employee.assignedWorkstationId = assignments[employeeId]
			else
				employee.assignedWorkstationId = nil
			end
		end
	end
end

function WorkstationService.CloseSession(self: Service, userId: number): Result<boolean>
	local session = self._sessions[userId]
	if session == nil then
		return AppTypes.success(false)
	end
	disconnectAll(session.connections)
	for _, runtime in session.slots do
		if runtime.workAttachment.Parent ~= nil then
			runtime.workAttachment:Destroy()
		end
		if runtime.approachAttachment.Parent ~= nil then
			runtime.approachAttachment:Destroy()
		end
	end
	self._sessions[userId] = nil
	return AppTypes.success(true)
end

function WorkstationService.AbortSession(self: Service, userId: number): Result<boolean>
	return self:CloseSession(userId)
end

function WorkstationService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true
	if self._unsubscribeOffice ~= nil then
		self._unsubscribeOffice()
	end
	self._unsubscribeOffice = nil
	local userIds = {}
	for userId in self._sessions do
		table.insert(userIds, userId)
	end
	for _, userId in userIds do
		self:CloseSession(userId)
	end
	table.clear(self._listeners)
	self._officeService = nil
	self._isInitialized = false
	self._isStarted = false
end

return table.freeze(WorkstationService)
