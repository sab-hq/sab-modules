# WSUS-Read Connector — Technical Spec (Draft v0.1)
### First partnership-oriented proof point (resolves `open-questions.md` PO-4)

**Status:** Draft — first pass, ready for review and revision once Phase 1 architecture work begins.
**Scope:** Read-only in this phase. This connector does not write approvals, change sync configuration, or modify anything in WSUS. Per Section 6 of the sab-engine design document, the goal is to work *with* an organization's existing WSUS deployment, not replace or control it.

---

## 1. Purpose

Let SAB read an organization's existing WSUS approval/catalog state so the AI agent and pre-flight-check modules can make informed recommendations without duplicating or conflicting with decisions already made in WSUS.

## 2. Access Method

**Use the native `UpdateServices` PowerShell module, not direct database access.**

WSUS ships with a built-in PowerShell module (available on Windows Server 2012 and later) that exposes the update catalog, approval state, and client/target group data through supported cmdlets. This is the right access path for three reasons:
- It's officially supported by Microsoft, unlike querying the underlying WSUS database directly, which is fragile and undocumented.
- It's PowerShell-native, which fits SAB's execution model directly — no separate protocol or driver needed beyond what the WinRM connector already provides.
- It reinforces the partnership positioning: building on Microsoft's own supported tooling, not working around it.

## 3. Data Read

| Data | Source Cmdlet | Purpose |
|---|---|---|
| WSUS server identity/connection info | `Get-WsusServer` | Establish the connection; needed before any other call |
| Update catalog with approval/classification/installation status | `Get-WsusUpdate` (filtered by `-Approval`, `-Classification`, `-Status`) | Core data — tells SAB what's already approved, pending, or declined in WSUS before proposing a patching plan |
| Client/target group membership | `Get-WsusComputer` | Lets SAB map a target server to its WSUS group, so recommendations respect existing WSUS grouping/policy |
| Product and classification metadata | `Get-WsusProduct`, `Get-WsusClassification` | Context for what kinds of updates exist and are enabled for sync — informs how the AI agent frames a recommendation |

**Explicitly not read in this phase:** WSUS sync configuration, upstream server settings, content file storage.

## 4. Polling vs. Event-Driven

WSUS has no native push/webhook mechanism for approval or sync changes. **Recommendation: polling on a configurable interval** (default suggestion: every 15–30 minutes, adjustable per deployment).

## 5. What SAB Does With This Data

1. Feeds the **pre-flight check** step of the patching workflow — before proposing a patch run, the AI agent checks whether WSUS has already approved/declined the relevant updates for the target's group.
2. Feeds **SAB-KB** as part of target system state — WSUS approval status becomes part of what the AI agent and future workflows can query about a given server.
3. Surfaced to the human approver as context in the recommendation.

## 6. Permissions Required

Reading via the `UpdateServices` module requires the calling account to have **WSUS Reporters** or **WSUS Administrators** group membership (or equivalent delegated rights) on the target WSUS server. This credential should be resolved by the execution environment layer at connection time and never passed through to modules or the AI agent directly.

## 7. Explicitly Out of Scope (This Phase)

- **Writing approvals back to WSUS** — a natural Phase 2+ extension, kept out of scope here to keep this first proof point narrow, low-risk, and unambiguously "working with," not "taking over."
- **Modifying WSUS sync/configuration.**
- **Direct SQL access to the WSUS database.**

## 8. Open Sub-Questions (Not Yet Resolved)

- Exact polling interval default and whether it should be configurable per-workflow or system-wide
- Whether WSUS Reporters (lower-privilege, read-focused) is sufficient, or whether WSUS Administrators ends up necessary for some data
- How to handle organizations running multiple WSUS servers/hierarchies (upstream/downstream) — this spec assumes a single WSUS server for v0.1

---

*This is a first-pass draft meant to unblock Phase 1 planning, not a final spec. Revise once actual implementation surfaces real constraints the documentation-level pass couldn't predict.*
