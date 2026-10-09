--!strict

local PathfindingService = game:GetService("PathfindingService")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local AppTypes = require(ReplicatedStorage.Shared.Types.AppTypes)
local LifecycleRegistry = require(ReplicatedStorage.Shared.Infrastructure.LifecycleRegistry)
local Logger = require(ReplicatedStorage.Shared.Infrastructure.Logger)
local EmployeeTypes = require(ServerScriptService.Domain.EmployeeTypes)
local PlotBounds = require(ServerScriptService.Domain.PlotBounds)
local OfficeBuildingService = require(ServerScriptService.Services.OfficeBuildingService)
local PlotService = require(ServerScriptService.Services.PlotService)

type DependencyResolver = LifecycleRegistry.DependencyResolver
type Employee = EmployeeTypes.Employee
type EmployeeConfig = EmployeeTypes.EmployeeConfig
type RootLogger = Logger.Logger
type MovementState = EmployeeTypes.MovementState
type OfficeService = OfficeBuildingService.Service
type PlotServiceType = PlotService.Service
type Result<T> = AppTypes.Result<T>
type WorkstationRuntime = EmployeeTypes.WorkstationRuntime

type AnimationJoints = {
	waist: Motor6D?,
	leftShoulder: Motor6D?,
	rightShoulder: Motor6D?,
	leftElbow: Motor6D?,
	rightElbow: Motor6D?,
	leftHip: Motor6D?,
	rightHip: Motor6D?,
	leftKnee: Motor6D?,
	rightKnee: Motor6D?,
}

type NpcRuntime = {
	employeeId: string,
	userId: number,
	model: Model,
	movementState: MovementState,
	targetWorkstationId: string?,
	targetCFrame: CFrame?,
	pathGeneration: number,
	runtimeGeneration: number,
	lastProgressAt: number,
	lastPosition: Vector3,
	lastPathRequestAt: number,
	recoveryAttempt: number,
	pathRetryScheduled: boolean,
	pathRequestCount: number,
	recoveryCount: number,
	recoveryTeleportCount: number,
	normalPathStepCount: number,
	normalPathDistance: number,
	minimumPathIntervalObserved: number,
	idleTrack: AnimationTrack?,
	walkTrack: AnimationTrack?,
	workTrack: AnimationTrack?,
	animationJoints: AnimationJoints,
	animationClock: number,
	animationRevision: number,
	animationGraceUntil: number,
	animationFailureLogged: { [string]: boolean },
	usingProceduralAnimation: boolean,
	logger: RootLogger,
}

type PlayerRuntime = {
	folder: Folder,
	npcs: { [string]: NpcRuntime },
	pathWindowStartedAt: number,
	pathRequestsInWindow: number,
	peakPathRequestsInWindow: number,
	totalPathRequests: number,
	totalRecoveries: number,
}

type ServiceData = {
	_config: EmployeeConfig,
	_logger: RootLogger,
	_plotService: PlotServiceType?,
	_officeService: OfficeService?,
	_players: { [number]: PlayerRuntime },
	_heartbeat: RBXScriptConnection?,
	_stuckAccumulator: number,
	_collisionGroupReady: boolean,
	_isInitialized: boolean,
	_isStarted: boolean,
	_isDestroyed: boolean,
}

local EmployeeMovementService = {}
EmployeeMovementService.__index = EmployeeMovementService
export type Service = typeof(setmetatable({} :: ServiceData, EmployeeMovementService))

export type Metrics = {
	npcModels: number,
	pathRequests: number,
	peakPathRequestsPerSecond: number,
	recoveries: number,
	centralSchedulers: number,
}

local EMPLOYEE_COLLISION_GROUP = "EmployeeNpcs"
local KINEMATIC_ROOT_ANCHORED_BY_STATE: { [MovementState]: boolean } = {
	Spawning = true,
	WalkingToDesk = true,
	Working = true,
	WalkingToBreak = true,
	OnBreak = true,
	ReturningToDesk = true,
	Stuck = true,
	Repositioning = true,
	Despawning = true,
}

local function updateTrack(track: AnimationTrack?, shouldPlay: boolean): (boolean, string?)
	if track == nil then
		return not shouldPlay, if shouldPlay then "animation track is unavailable" else nil
	end
	local ok, cause = pcall(function()
		if shouldPlay and not track.IsPlaying then
			track:Play(0.15)
		elseif not shouldPlay and track.IsPlaying then
			track:Stop(0.15)
		end
	end)
	return ok, if ok then nil else tostring(cause)
end

local function animationTrackForState(runtime: NpcRuntime, state: MovementState): (AnimationTrack?, string?)
	if state == "Despawning" then
		return nil, nil
	elseif state == "WalkingToDesk" then
		return runtime.walkTrack, "walk"
	elseif state == "Working" then
		return runtime.workTrack, "work"
	end
	return runtime.idleTrack, "idle"
end

local function reportAnimationFailure(runtime: NpcRuntime, animationName: string, cause: string)
	if runtime.animationFailureLogged[animationName] then
		return
	end
	runtime.animationFailureLogged[animationName] = true
	runtime.model:SetAttribute("AnimationLoadFailed", true)
	runtime.logger:Warn("employee_animation_unavailable", {
		employeeId = runtime.employeeId,
		animation = animationName,
		cause = cause,
	})
end

local function setMovementState(runtime: NpcRuntime, state: MovementState)
	if runtime.movementState ~= state then
		runtime.animationClock = 0
		runtime.animationRevision += 1
		runtime.model:SetAttribute("AnimationStateRevision", runtime.animationRevision)
	end
	runtime.movementState = state
	runtime.model:SetAttribute("MovementState", state)
	local root = runtime.model.PrimaryPart
	if root ~= nil then
		root.Anchored = KINEMATIC_ROOT_ANCHORED_BY_STATE[state]
		runtime.model:SetAttribute("HumanoidRootPartAnchored", root.Anchored)
	end
	local desiredTrack, animationName = animationTrackForState(runtime, state)
	updateTrack(runtime.idleTrack, false)
	updateTrack(runtime.walkTrack, false)
	updateTrack(runtime.workTrack, false)
	if animationName == nil then
		runtime.model:SetAttribute("AnimationMode", "None")
		runtime.usingProceduralAnimation = false
		return
	end
	local wasProcedural = runtime.usingProceduralAnimation
	local started, cause = updateTrack(desiredTrack, true)
	if not started then
		reportAnimationFailure(runtime, animationName, cause or "animation playback failed")
	end
	runtime.animationGraceUntil = os.clock() + 1
	runtime.usingProceduralAnimation = if started then wasProcedural else true
	runtime.model:SetAttribute("AnimationMode", if started then "Asset" else "ProceduralFallback")
	runtime.model:SetAttribute("AnimationFallbackActive", not started)
end

local function setJointTransform(joint: Motor6D?, transform: CFrame)
	if joint ~= nil then
		joint.Transform = transform
	end
end

local function resetProceduralPose(joints: AnimationJoints)
	setJointTransform(joints.waist, CFrame.identity)
	setJointTransform(joints.leftShoulder, CFrame.identity)
	setJointTransform(joints.rightShoulder, CFrame.identity)
	setJointTransform(joints.leftElbow, CFrame.identity)
	setJointTransform(joints.rightElbow, CFrame.identity)
	setJointTransform(joints.leftHip, CFrame.identity)
	setJointTransform(joints.rightHip, CFrame.identity)
	setJointTransform(joints.leftKnee, CFrame.identity)
	setJointTransform(joints.rightKnee, CFrame.identity)
end

local function applyProceduralPose(runtime: NpcRuntime, deltaSeconds: number)
	runtime.animationClock += deltaSeconds
	local joints = runtime.animationJoints
	resetProceduralPose(joints)
	if runtime.movementState == "WalkingToDesk" then
		local phase = math.sin(runtime.animationClock * 8)
		setJointTransform(joints.waist, CFrame.new(0, math.abs(phase) * 0.04, 0))
		setJointTransform(joints.leftShoulder, CFrame.Angles(phase * 0.55, 0, 0))
		setJointTransform(joints.rightShoulder, CFrame.Angles(-phase * 0.55, 0, 0))
		setJointTransform(joints.leftHip, CFrame.Angles(-phase * 0.45, 0, 0))
		setJointTransform(joints.rightHip, CFrame.Angles(phase * 0.45, 0, 0))
		setJointTransform(joints.leftKnee, CFrame.Angles(math.max(0, phase) * 0.35, 0, 0))
		setJointTransform(joints.rightKnee, CFrame.Angles(math.max(0, -phase) * 0.35, 0, 0))
	elseif runtime.movementState == "Working" then
		local tap = math.sin(runtime.animationClock * 7) * 0.12
		setJointTransform(joints.waist, CFrame.Angles(-0.1, 0, 0))
		setJointTransform(joints.leftShoulder, CFrame.Angles(-0.7 + tap, 0.12, 0.08))
		setJointTransform(joints.rightShoulder, CFrame.Angles(-0.7 - tap, -0.12, -0.08))
		setJointTransform(joints.leftElbow, CFrame.Angles(-0.65 - tap, 0, 0))
		setJointTransform(joints.rightElbow, CFrame.Angles(-0.65 + tap, 0, 0))
	else
		local breathe = math.sin(runtime.animationClock * 1.8)
		setJointTransform(joints.waist, CFrame.Angles(0, 0, breathe * 0.015))
		setJointTransform(joints.leftShoulder, CFrame.Angles(breathe * 0.025, 0, 0.04))
		setJointTransform(joints.rightShoulder, CFrame.Angles(-breathe * 0.025, 0, -0.04))
	end
end

local function findMotor(model: Model, name: string): Motor6D?
	local value = model:FindFirstChild(name, true)
	return if value ~= nil and value:IsA("Motor6D") then value else nil
end

local function animationJoints(model: Model): AnimationJoints
	return {
		waist = findMotor(model, "Waist"),
		leftShoulder = findMotor(model, "LeftShoulder"),
		rightShoulder = findMotor(model, "RightShoulder"),
		leftElbow = findMotor(model, "LeftElbow"),
		rightElbow = findMotor(model, "RightElbow"),
		leftHip = findMotor(model, "LeftHip"),
		rightHip = findMotor(model, "RightHip"),
		leftKnee = findMotor(model, "LeftKnee"),
		rightKnee = findMotor(model, "RightKnee"),
	}
end

local function part(name: string, size: Vector3, color: Color3, cframe: CFrame, collisionGroupReady: boolean): Part
	local value = Instance.new("Part")
	value.Name = name
	value.Size = size
	value.Color = color
	value.Material = Enum.Material.SmoothPlastic
	value.Anchored = false
	value.CanCollide = false
	value.CanTouch = false
	value.CanQuery = false
	value.CFrame = cframe
	if collisionGroupReady then
		value.CollisionGroup = EMPLOYEE_COLLISION_GROUP
	end
	return value
end

local function createNpc(employee: Employee, spawnCFrame: CFrame, collisionGroupReady: boolean): Model
	local model = Instance.new("Model")
	model.Name = employee.employeeId
	model:SetAttribute("EmployeeId", employee.employeeId)
	model:SetAttribute("OwnerUserId", employee.ownerUserId)
	model:SetAttribute("EmployeeRoleId", employee.roleId)
	model:SetAttribute("R15Compatible", true)
	model:SetAttribute("FloorAwareNavigation", true)
	model:SetAttribute("LocomotionMechanism", "KinematicPivotTo")
	model:SetAttribute("RootAnchoringContract", "AnchoredForKinematicPivotTo")
	model:SetAttribute("CollisionGroup", if collisionGroupReady then EMPLOYEE_COLLISION_GROUP else "Unavailable")
	model:SetAttribute("MovementState", "Spawning")
	local skin = Color3.fromRGB(226, 190, 153)
	local shirt = Color3.fromRGB(65, 108, 170)
	local trousers = Color3.fromRGB(33, 45, 68)
	local shoes = Color3.fromRGB(22, 27, 36)
	local partRows = {
		{ "HumanoidRootPart", Vector3.new(2, 2, 1), Color3.new(), Vector3.new(0, 0, 0) },
		{ "LowerTorso", Vector3.new(2, 1.5, 1), shirt, Vector3.new(0, 0, 0) },
		{ "UpperTorso", Vector3.new(2.2, 1.7, 1.1), shirt, Vector3.new(0, 1.55, 0) },
		{ "Head", Vector3.new(1.5, 1.5, 1.5), skin, Vector3.new(0, 3.15, 0) },
		{ "LeftUpperArm", Vector3.new(0.75, 1.35, 0.75), shirt, Vector3.new(-1.5, 1.65, 0) },
		{ "LeftLowerArm", Vector3.new(0.7, 1.2, 0.7), skin, Vector3.new(-1.5, 0.4, 0) },
		{ "LeftHand", Vector3.new(0.7, 0.65, 0.8), skin, Vector3.new(-1.5, -0.5, 0) },
		{ "RightUpperArm", Vector3.new(0.75, 1.35, 0.75), shirt, Vector3.new(1.5, 1.65, 0) },
		{ "RightLowerArm", Vector3.new(0.7, 1.2, 0.7), skin, Vector3.new(1.5, 0.4, 0) },
		{ "RightHand", Vector3.new(0.7, 0.65, 0.8), skin, Vector3.new(1.5, -0.5, 0) },
		{ "LeftUpperLeg", Vector3.new(0.85, 1.5, 0.85), trousers, Vector3.new(-0.55, -1.25, 0) },
		{ "LeftLowerLeg", Vector3.new(0.8, 1.4, 0.8), trousers, Vector3.new(-0.55, -2.65, 0) },
		{ "LeftFoot", Vector3.new(0.85, 0.55, 1.2), shoes, Vector3.new(-0.55, -3.55, -0.15) },
		{ "RightUpperLeg", Vector3.new(0.85, 1.5, 0.85), trousers, Vector3.new(0.55, -1.25, 0) },
		{ "RightLowerLeg", Vector3.new(0.8, 1.4, 0.8), trousers, Vector3.new(0.55, -2.65, 0) },
		{ "RightFoot", Vector3.new(0.85, 0.55, 1.2), shoes, Vector3.new(0.55, -3.55, -0.15) },
	}
	local parts = {} :: { [string]: Part }
	for _, row in partRows do
		local bodyPart = part(
			row[1] :: string,
			row[2] :: Vector3,
			row[3] :: Color3,
			spawnCFrame * CFrame.new(row[4] :: Vector3),
			collisionGroupReady
		)
		bodyPart.Parent = model
		parts[bodyPart.Name] = bodyPart
	end
	local root = parts.HumanoidRootPart
	root.Anchored = true
	root.Transparency = 1
	parts.Head.Shape = Enum.PartType.Ball
	local function motor(name: string, part0Name: string, part1Name: string)
		local joint = Instance.new("Motor6D")
		joint.Name = name
		joint.Part0 = parts[part0Name]
		joint.Part1 = parts[part1Name]
		joint.C0 = joint.Part0.CFrame:ToObjectSpace(joint.Part1.CFrame)
		joint.Parent = joint.Part0
	end
	for _, joint in
		{
			{ "Root", "HumanoidRootPart", "LowerTorso" },
			{ "Waist", "LowerTorso", "UpperTorso" },
			{ "Neck", "UpperTorso", "Head" },
			{ "LeftShoulder", "UpperTorso", "LeftUpperArm" },
			{ "LeftElbow", "LeftUpperArm", "LeftLowerArm" },
			{ "LeftWrist", "LeftLowerArm", "LeftHand" },
			{ "RightShoulder", "UpperTorso", "RightUpperArm" },
			{ "RightElbow", "RightUpperArm", "RightLowerArm" },
			{ "RightWrist", "RightLowerArm", "RightHand" },
			{ "LeftHip", "LowerTorso", "LeftUpperLeg" },
			{ "LeftKnee", "LeftUpperLeg", "LeftLowerLeg" },
			{ "LeftAnkle", "LeftLowerLeg", "LeftFoot" },
			{ "RightHip", "LowerTorso", "RightUpperLeg" },
			{ "RightKnee", "RightUpperLeg", "RightLowerLeg" },
			{ "RightAnkle", "RightLowerLeg", "RightFoot" },
		}
	do
		motor(joint[1], joint[2], joint[3])
	end
	local humanoid = Instance.new("Humanoid")
	humanoid.Name = "Humanoid"
	humanoid.DisplayName = employee.displayName
	humanoid.WalkSpeed = 0
	humanoid.AutoRotate = false
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model
	for _, state in
		{
			Enum.HumanoidStateType.Climbing,
			Enum.HumanoidStateType.FallingDown,
			Enum.HumanoidStateType.GettingUp,
			Enum.HumanoidStateType.Jumping,
			Enum.HumanoidStateType.Ragdoll,
			Enum.HumanoidStateType.Seated,
			Enum.HumanoidStateType.Swimming,
		}
	do
		humanoid:SetStateEnabled(state, false)
	end
	local animator = Instance.new("Animator")
	animator.Parent = humanoid
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BaseScript") then
			descendant:Destroy()
		end
	end
	model.PrimaryPart = root
	model:PivotTo(spawnCFrame)
	return model
end

local function loadTrack(
	animator: Animator?,
	animationId: string,
	priority: Enum.AnimationPriority
): (AnimationTrack?, string?)
	if animator == nil then
		return nil, "Animator is missing"
	end
	if animationId == "" then
		return nil, "animation ID is empty"
	end
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId
	local ok, trackValue = pcall(function(): AnimationTrack
		return animator:LoadAnimation(animation)
	end)
	animation:Destroy()
	if not ok then
		return nil, tostring(trackValue)
	end
	local track = trackValue :: AnimationTrack
	track.Looped = true
	track.Priority = priority
	return track, nil
end

function EmployeeMovementService.new(config: EmployeeConfig, logger: RootLogger): Service
	return setmetatable({
		_config = config,
		_logger = logger,
		_plotService = nil,
		_officeService = nil,
		_players = {},
		_heartbeat = nil,
		_stuckAccumulator = 0,
		_collisionGroupReady = false,
		_isInitialized = false,
		_isStarted = false,
		_isDestroyed = false,
	}, EmployeeMovementService)
end

function EmployeeMovementService.Init(self: Service, dependencies: DependencyResolver)
	self._plotService = dependencies:Require("PlotService") :: PlotServiceType
	self._officeService = dependencies:Require("OfficeBuildingService") :: OfficeService
	self._isInitialized = true
end

function EmployeeMovementService._insidePlot(self: Service, userId: number, cframe: CFrame): boolean
	local context = (self._plotService :: PlotServiceType):GetOwnedPlotContextForUserId(userId)
	return context.ok and PlotBounds.containsPoint(context.value.definition, cframe.Position)
end

function EmployeeMovementService._spawnCFrame(self: Service, userId: number): CFrame?
	local context = (self._officeService :: OfficeService):GetRuntimeContext(userId)
	if context == nil then
		return nil
	end
	local entrance = context.root:FindFirstChild("EntranceApproach", true)
	if entrance ~= nil and entrance:IsA("BasePart") then
		return entrance.CFrame * CFrame.new(0, entrance.Size.Y * 0.5 + 3, 0)
	end
	return context.root:GetPivot() * CFrame.new(0, 4, 0)
end

function EmployeeMovementService.PrepareSession(self: Service, userId: number): Result<true>
	if self._players[userId] ~= nil then
		return AppTypes.failure("EmployeeMovementSessionAlreadyOpen", "Movement session is already open", nil)
	end
	local folder = Instance.new("Folder")
	folder.Name = `EmployeeNpcs_{userId}`
	folder:SetAttribute("OwnerUserId", userId)
	folder.Parent = Workspace
	self._players[userId] = {
		folder = folder,
		npcs = {},
		pathWindowStartedAt = os.clock(),
		pathRequestsInWindow = 0,
		peakPathRequestsInWindow = 0,
		totalPathRequests = 0,
		totalRecoveries = 0,
	}
	folder:SetAttribute("ActiveNpcCount", 0)
	folder:SetAttribute("PathRequestCount", 0)
	folder:SetAttribute("PathRequestPeakPerSecond", 0)
	folder:SetAttribute("RecoveryCount", 0)
	folder:SetAttribute("CentralSchedulerCount", if self._heartbeat ~= nil then 1 else 0)
	return AppTypes.success(true)
end

function EmployeeMovementService._pathBudget(self: Service, runtime: NpcRuntime): boolean
	local playerRuntime = self._players[runtime.userId]
	if playerRuntime == nil then
		return false
	end
	local now = os.clock()
	if now - playerRuntime.pathWindowStartedAt >= 1 then
		playerRuntime.pathWindowStartedAt = now
		playerRuntime.pathRequestsInWindow = 0
	end
	if playerRuntime.pathRequestsInWindow >= self._config.movement.maxPathRequestsPerPlayerPerSecond then
		return false
	end
	playerRuntime.pathRequestsInWindow += 1
	playerRuntime.peakPathRequestsInWindow =
		math.max(playerRuntime.peakPathRequestsInWindow, playerRuntime.pathRequestsInWindow)
	playerRuntime.totalPathRequests += 1
	runtime.pathRequestCount += 1
	runtime.model:SetAttribute("PathRequestCount", runtime.pathRequestCount)
	playerRuntime.folder:SetAttribute("PathRequestCount", playerRuntime.totalPathRequests)
	playerRuntime.folder:SetAttribute("PathRequestPeakPerSecond", playerRuntime.peakPathRequestsInWindow)
	return true
end

function EmployeeMovementService._moveAlong(
	self: Service,
	runtime: NpcRuntime,
	pathGeneration: number,
	targetId: string,
	waypoints: { PathWaypoint }
)
	for _, waypoint in waypoints do
		local current = self._players[runtime.userId]
		local live = if current ~= nil then current.npcs[runtime.employeeId] else nil
		if
			live ~= runtime
			or runtime.pathGeneration ~= pathGeneration
			or runtime.targetWorkstationId ~= targetId
			or runtime.model.Parent == nil
		then
			return
		end
		local position = waypoint.Position + Vector3.new(0, 3, 0)
		if not self:_insidePlot(runtime.userId, CFrame.new(position)) then
			setMovementState(runtime, "Stuck")
			return
		end
		local beforePosition = runtime.model:GetPivot().Position
		runtime.model:PivotTo(CFrame.new(position))
		local actualPosition = runtime.model:GetPivot().Position
		local stepDistance = (actualPosition - beforePosition).Magnitude
		if stepDistance > 0 then
			if runtime.normalPathStepCount == 0 then
				runtime.model:SetAttribute("NormalPathStartWorldPosition", beforePosition)
			end
			runtime.normalPathStepCount += 1
			runtime.normalPathDistance += stepDistance
			runtime.model:SetAttribute("NormalPathStepCount", runtime.normalPathStepCount)
			runtime.model:SetAttribute("NormalPathDistance", runtime.normalPathDistance)
			runtime.model:SetAttribute("NormalPathLastWorldPosition", actualPosition)
		end
		runtime.lastPosition = actualPosition
		runtime.lastProgressAt = os.clock()
		task.wait(0.03)
	end
	setMovementState(runtime, "Working")
	runtime.recoveryAttempt = 0
end

function EmployeeMovementService._requestPath(self: Service, runtime: NpcRuntime)
	local target = runtime.targetCFrame
	local targetId = runtime.targetWorkstationId
	if target == nil or targetId == nil or not self:_insidePlot(runtime.userId, target) then
		setMovementState(runtime, "Stuck")
		return
	end
	local now = os.clock()
	local sinceLastRequest = now - runtime.lastPathRequestAt
	if sinceLastRequest < self._config.movement.minimumPathRequestSeconds then
		runtime.pathGeneration += 1
		setMovementState(runtime, "Stuck")
		runtime.lastProgressAt = now
		if not runtime.pathRetryScheduled then
			runtime.pathRetryScheduled = true
			local delaySeconds = self._config.movement.minimumPathRequestSeconds - sinceLastRequest
			task.delay(delaySeconds, function()
				local playerRuntime = self._players[runtime.userId]
				if playerRuntime == nil or playerRuntime.npcs[runtime.employeeId] ~= runtime then
					return
				end
				runtime.pathRetryScheduled = false
				self:_requestPath(runtime)
			end)
		end
		return
	end
	runtime.pathRetryScheduled = false
	if not self:_pathBudget(runtime) then
		setMovementState(runtime, "Stuck")
		return
	end
	if runtime.lastPathRequestAt > -math.huge then
		runtime.minimumPathIntervalObserved =
			math.min(runtime.minimumPathIntervalObserved, now - runtime.lastPathRequestAt)
		runtime.model:SetAttribute("MinimumPathInterval", runtime.minimumPathIntervalObserved)
	end
	runtime.lastPathRequestAt = now
	runtime.pathGeneration += 1
	local generation = runtime.pathGeneration
	local runtimeGeneration = runtime.runtimeGeneration
	local model = runtime.model
	setMovementState(runtime, "WalkingToDesk")
	task.spawn(function()
		local path = PathfindingService:CreatePath({
			AgentRadius = self._config.movement.agentRadius,
			AgentHeight = self._config.movement.agentHeight,
			AgentCanJump = false,
		})
		local ok = pcall(function()
			path:ComputeAsync(model:GetPivot().Position, target.Position)
		end)
		local playerRuntime = self._players[runtime.userId]
		if
			playerRuntime == nil
			or playerRuntime.npcs[runtime.employeeId] ~= runtime
			or runtime.pathGeneration ~= generation
			or runtime.runtimeGeneration ~= runtimeGeneration
			or runtime.targetWorkstationId ~= targetId
			or runtime.model ~= model
		then
			return
		end
		if not ok or path.Status ~= Enum.PathStatus.Success then
			setMovementState(runtime, "Stuck")
			return
		end
		self:_moveAlong(runtime, generation, targetId, path:GetWaypoints())
	end)
end

function EmployeeMovementService.Spawn(
	self: Service,
	employee: Employee,
	workstation: WorkstationRuntime?
): Result<true>
	local playerRuntime = self._players[employee.ownerUserId]
	if playerRuntime == nil then
		return AppTypes.failure("EmployeeMovementSessionNotReady", "Movement session is not open", nil)
	end
	if playerRuntime.npcs[employee.employeeId] ~= nil then
		return AppTypes.success(true)
	end
	if self:GetNpcCount(employee.ownerUserId) >= self._config.performance.maxNpcModelsPerPlayer then
		return AppTypes.failure("EmployeeCapacityReached", "NPC budget is exhausted", nil)
	end
	local spawnCFrame = self:_spawnCFrame(employee.ownerUserId)
	if spawnCFrame == nil or not self:_insidePlot(employee.ownerUserId, spawnCFrame) then
		return AppTypes.failure("EmployeeSpawnUnavailable", "Employee spawn is unavailable", nil)
	end
	local model = createNpc(employee, spawnCFrame, self._collisionGroupReady)
	model.Parent = playerRuntime.folder
	local animator = model:FindFirstChildWhichIsA("Animator", true)
	local idleTrack, idleFailure =
		loadTrack(animator, self._config.movement.animationIds.idle, Enum.AnimationPriority.Idle)
	local walkTrack, walkFailure =
		loadTrack(animator, self._config.movement.animationIds.walk, Enum.AnimationPriority.Movement)
	local workTrack, workFailure =
		loadTrack(animator, self._config.movement.animationIds.work, Enum.AnimationPriority.Action)
	local animationFailures = {
		idle = idleFailure ~= nil,
		walk = walkFailure ~= nil,
		work = workFailure ~= nil,
	}
	for animationName, cause in
		{
			idle = idleFailure,
			walk = walkFailure,
			work = workFailure,
		}
	do
		if cause ~= nil then
			self._logger:Warn("employee_animation_load_failed", {
				employeeId = employee.employeeId,
				animation = animationName,
				cause = cause,
			})
		end
	end
	model:SetAttribute("AnimationsConfigured", true)
	model:SetAttribute("AnimationLoadFailed", idleFailure ~= nil or walkFailure ~= nil or workFailure ~= nil)
	model:SetAttribute("AnimationFallbackActive", false)
	model:SetAttribute("NormalPathStepCount", 0)
	model:SetAttribute("NormalPathDistance", 0)
	model:SetAttribute("RecoveryTeleportCount", 0)
	local runtime: NpcRuntime = {
		employeeId = employee.employeeId,
		userId = employee.ownerUserId,
		model = model,
		movementState = "Spawning",
		targetWorkstationId = nil,
		targetCFrame = nil,
		pathGeneration = 0,
		runtimeGeneration = employee.runtimeGeneration,
		lastProgressAt = os.clock(),
		lastPosition = spawnCFrame.Position,
		lastPathRequestAt = -math.huge,
		recoveryAttempt = 0,
		pathRetryScheduled = false,
		pathRequestCount = 0,
		recoveryCount = 0,
		recoveryTeleportCount = 0,
		normalPathStepCount = 0,
		normalPathDistance = 0,
		minimumPathIntervalObserved = math.huge,
		idleTrack = idleTrack,
		walkTrack = walkTrack,
		workTrack = workTrack,
		animationJoints = animationJoints(model),
		animationClock = 0,
		animationRevision = 0,
		animationGraceUntil = 0,
		animationFailureLogged = animationFailures,
		usingProceduralAnimation = false,
		logger = self._logger,
	}
	playerRuntime.npcs[employee.employeeId] = runtime
	playerRuntime.folder:SetAttribute("ActiveNpcCount", self:GetNpcCount(employee.ownerUserId))
	setMovementState(runtime, "Spawning")
	if workstation ~= nil then
		self:MoveToWorkstation(employee.ownerUserId, employee.employeeId, workstation)
	end
	return AppTypes.success(true)
end

function EmployeeMovementService.MoveToWorkstation(
	self: Service,
	userId: number,
	employeeId: string,
	workstation: WorkstationRuntime
): Result<true>
	local playerRuntime = self._players[userId]
	local runtime = if playerRuntime ~= nil then playerRuntime.npcs[employeeId] else nil
	if runtime == nil then
		return AppTypes.failure("EmployeeNpcNotFound", "Employee NPC does not exist", nil)
	end
	if workstation.ownerUserId ~= userId or not self:_insidePlot(userId, workstation.approachCFrame) then
		return AppTypes.failure("ForeignWorkstation", "Movement target is outside the owned plot", nil)
	end
	runtime.targetWorkstationId = workstation.workstationId
	runtime.targetCFrame = workstation.approachCFrame
	runtime.runtimeGeneration = workstation.runtimeGeneration
	runtime.model:SetAttribute("WorkstationId", workstation.workstationId)
	runtime.model:SetAttribute("RuntimeGeneration", workstation.runtimeGeneration)
	runtime.recoveryAttempt = 0
	self:_requestPath(runtime)
	return AppTypes.success(true)
end

function EmployeeMovementService._recover(self: Service, runtime: NpcRuntime)
	local playerRuntime = self._players[runtime.userId]
	if playerRuntime ~= nil then
		playerRuntime.totalRecoveries += 1
		playerRuntime.folder:SetAttribute("RecoveryCount", playerRuntime.totalRecoveries)
	end
	runtime.recoveryCount += 1
	runtime.model:SetAttribute("RecoveryCount", runtime.recoveryCount)
	runtime.recoveryAttempt += 1
	if runtime.recoveryAttempt <= 2 then
		self:_requestPath(runtime)
	elseif
		runtime.recoveryAttempt == 3
		and runtime.targetCFrame ~= nil
		and self:_insidePlot(runtime.userId, runtime.targetCFrame)
	then
		setMovementState(runtime, "Repositioning")
		runtime.pathGeneration += 1
		local safeRootCFrame = runtime.targetCFrame * CFrame.new(0, 3, 0)
		runtime.model:PivotTo(safeRootCFrame)
		runtime.recoveryTeleportCount += 1
		runtime.model:SetAttribute("RecoveryTeleportCount", runtime.recoveryTeleportCount)
		runtime.lastPosition = safeRootCFrame.Position
		runtime.lastProgressAt = os.clock()
		setMovementState(runtime, "Working")
	else
		setMovementState(runtime, "Stuck")
	end
end

function EmployeeMovementService._stepStuck(self: Service)
	local now = os.clock()
	for _, playerRuntime in self._players do
		for _, runtime in playerRuntime.npcs do
			if runtime.movementState == "WalkingToDesk" or runtime.movementState == "Stuck" then
				local position = runtime.model:GetPivot().Position
				if (position - runtime.lastPosition).Magnitude >= self._config.movement.minimumProgressStuds then
					runtime.lastPosition = position
					runtime.lastProgressAt = now
				elseif now - runtime.lastProgressAt >= self._config.movement.stuckAfterSeconds then
					runtime.lastProgressAt = now
					self:_recover(runtime)
				end
			end
		end
	end
end

function EmployeeMovementService._stepAnimations(self: Service, deltaSeconds: number)
	local now = os.clock()
	for _, playerRuntime in self._players do
		for _, runtime in playerRuntime.npcs do
			local track, animationName = animationTrackForState(runtime, runtime.movementState)
			local isPlaying = false
			if track ~= nil then
				local ok, value = pcall(function(): boolean
					return track.IsPlaying
				end)
				isPlaying = ok and value
			end
			if animationName ~= nil and not isPlaying then
				if track ~= nil and now >= runtime.animationGraceUntil then
					reportAnimationFailure(runtime, animationName, "animation track stopped before state changed")
				end
				if not runtime.usingProceduralAnimation then
					runtime.model:SetAttribute("AnimationMode", "ProceduralFallback")
					runtime.model:SetAttribute("AnimationFallbackActive", true)
				end
				runtime.usingProceduralAnimation = true
				applyProceduralPose(runtime, deltaSeconds)
			elseif isPlaying then
				if runtime.usingProceduralAnimation then
					resetProceduralPose(runtime.animationJoints)
					runtime.model:SetAttribute("AnimationMode", "Asset")
					runtime.model:SetAttribute("AnimationFallbackActive", false)
				end
				runtime.usingProceduralAnimation = false
			end
		end
	end
end

function EmployeeMovementService.Start(self: Service)
	if not self._isInitialized or self._isStarted or self._isDestroyed then
		error("EmployeeMovementService.Start requires one successful Init", 2)
	end
	pcall(function()
		PhysicsService:RegisterCollisionGroup(EMPLOYEE_COLLISION_GROUP)
	end)
	self._collisionGroupReady = pcall(function()
		PhysicsService:CollisionGroupSetCollidable(EMPLOYEE_COLLISION_GROUP, EMPLOYEE_COLLISION_GROUP, false)
	end)
	self._heartbeat = RunService.Heartbeat:Connect(function(deltaSeconds: number)
		self:_stepAnimations(deltaSeconds)
		self._stuckAccumulator += deltaSeconds
		if self._stuckAccumulator >= self._config.scheduler.stuckSeconds then
			self._stuckAccumulator %= self._config.scheduler.stuckSeconds
			self:_stepStuck()
		end
	end)
	self._isStarted = true
end

function EmployeeMovementService.Remove(self: Service, userId: number, employeeId: string): boolean
	local playerRuntime = self._players[userId]
	local runtime = if playerRuntime ~= nil then playerRuntime.npcs[employeeId] else nil
	if playerRuntime == nil or runtime == nil then
		return false
	end
	setMovementState(runtime, "Despawning")
	runtime.pathGeneration += 1
	playerRuntime.npcs[employeeId] = nil
	updateTrack(runtime.idleTrack, false)
	updateTrack(runtime.walkTrack, false)
	updateTrack(runtime.workTrack, false)
	runtime.model:Destroy()
	playerRuntime.folder:SetAttribute("ActiveNpcCount", self:GetNpcCount(userId))
	return true
end

function EmployeeMovementService.GetNpcCount(self: Service, userId: number): number
	local playerRuntime = self._players[userId]
	local count = 0
	if playerRuntime ~= nil then
		for _ in playerRuntime.npcs do
			count += 1
		end
	end
	return count
end

function EmployeeMovementService.GetMetrics(self: Service, userId: number): Metrics
	local playerRuntime = self._players[userId]
	return {
		npcModels = self:GetNpcCount(userId),
		pathRequests = if playerRuntime ~= nil then playerRuntime.totalPathRequests else 0,
		peakPathRequestsPerSecond = if playerRuntime ~= nil then playerRuntime.peakPathRequestsInWindow else 0,
		recoveries = if playerRuntime ~= nil then playerRuntime.totalRecoveries else 0,
		centralSchedulers = if self._heartbeat ~= nil then 1 else 0,
	}
end

function EmployeeMovementService.CloseSession(self: Service, userId: number): Result<boolean>
	local playerRuntime = self._players[userId]
	if playerRuntime == nil then
		return AppTypes.success(false)
	end
	local employeeIds = {}
	for employeeId in playerRuntime.npcs do
		table.insert(employeeIds, employeeId)
	end
	for _, employeeId in employeeIds do
		self:Remove(userId, employeeId)
	end
	playerRuntime.folder:Destroy()
	self._players[userId] = nil
	return AppTypes.success(true)
end

function EmployeeMovementService.AbortSession(self: Service, userId: number): Result<boolean>
	return self:CloseSession(userId)
end

function EmployeeMovementService.Destroy(self: Service)
	if self._isDestroyed then
		return
	end
	self._isDestroyed = true
	if self._heartbeat ~= nil then
		self._heartbeat:Disconnect()
	end
	self._heartbeat = nil
	local userIds = {}
	for userId in self._players do
		table.insert(userIds, userId)
	end
	for _, userId in userIds do
		self:CloseSession(userId)
	end
	self._plotService = nil
	self._officeService = nil
	self._collisionGroupReady = false
	self._isStarted = false
	self._isInitialized = false
end

return table.freeze(EmployeeMovementService)
