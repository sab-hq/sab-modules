<#
.SYNOPSIS
    rollback-validate — the declared rollback for validate.
.DESCRIPTION
    validate only reads system state — WUA search results, disk space,
    service status — and never modifies anything. There is genuinely
    nothing to undo, same reasoning as rollback-pre-flight-check.ps1.

    This script exists anyway, rather than omitting a rollback entirely,
    to keep the orchestration engine's "call the module's declared
    rollback on failure" logic uniform across every module, no
    special-casing for read-only ones. See docs/learn/modules.md in
    sab-engine, and pre-development-checklist.md, PD-14/PD-17.
#>
Write-Output 'No-op rollback: validate only reads system state, it does not change anything, so there is nothing that needs undoing.'
