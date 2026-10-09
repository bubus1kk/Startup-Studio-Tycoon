--!strict

export type EmployeeRemoteErrorCode =
	"InvalidPayload"
	| "RateLimited"
	| "RequestIdConflict"
	| "EmployeeMutationInProgress"
	| "EmployeeSessionNotReady"
	| "CandidateNotFound"
	| "CandidateExpired"
	| "CandidateAlreadyConsumed"
	| "CandidateRefreshCooldown"
	| "EmployeeCapacityReached"
	| "NoCompatibleWorkstation"
	| "InsufficientFunds"
	| "EmployeeNotFound"
	| "EmployeeDismissed"
	| "WorkstationNotFound"
	| "WorkstationOccupied"
	| "WorkstationIncompatible"
	| "EmployeeAlreadyAssigned"
	| "ForeignEmployee"
	| "ForeignWorkstation"
	| "TransactionFailed"
	| "InternalError"

export type EmployeeRemoteError = { code: EmployeeRemoteErrorCode, message: string }
export type EmployeeOverviewRequest = { rosterPage: number }
export type EmployeeHireRequest = { requestId: string, candidateId: string }
export type EmployeeAssignmentRequest = { requestId: string, employeeId: string, workstationId: string }
export type EmployeeDismissRequest = { requestId: string, employeeId: string }
export type CandidateRefreshRequest = { requestId: string }

export type CandidateView = {
	candidateId: string,
	displayName: string,
	roleId: string,
	grade: string,
	speed: number,
	quality: number,
	reliability: number,
	traitId: string,
	hiringCost: number,
	salaryPerCycle: number,
	expiresInSeconds: number,
}
export type EmployeeView = {
	employeeId: string,
	displayName: string,
	roleId: string,
	grade: string,
	level: number,
	xp: number,
	requiredXp: number,
	speed: number,
	quality: number,
	reliability: number,
	traitId: string,
	salaryPerCycle: number,
	morale: number,
	status: string,
	assignedWorkstationId: string?,
}
export type RoleWorkSummary = { roleId: string, workPoints: number }
export type EmployeeOverview = {
	candidates: { CandidateView },
	roster: { EmployeeView },
	rosterPage: number,
	rosterPageCount: number,
	rosterTotal: number,
	tierEmployeeCap: number,
	workstationCapacity: number,
	occupiedWorkstations: number,
	payrollRemainingSeconds: number,
	refreshRemainingSeconds: number,
	roleWorkSummary: { RoleWorkSummary },
	cash: number,
}
export type EmployeeOverviewResponse = EmployeeOverview & { ok: boolean, error: EmployeeRemoteError? }
export type EmployeeMutationResponse = {
	ok: boolean,
	requestId: string,
	overview: EmployeeOverview?,
	error: EmployeeRemoteError?,
}

return table.freeze({})
