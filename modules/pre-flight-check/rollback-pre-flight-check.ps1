<#
.SYNOPSIS
    rollback-pre-flight-check — the declared rollback for pre-flight-check.
.DESCRIPTION
    pre-flight-check only reads system state — disk space, registry
    keys, service status — and never modifies anything. There is
    genuinely nothing to undo.

    This script exists anyway, rather than omitting a rollback entirely,
    to keep the orchestration engine's "call the module's declared
    rollback on failure" logic uniform across every module, with no
    special-casing for read-only ones. See docs/learn/modules.md in
    sab-engine for the reasoning, and pre-development-checklist.md, PD-14.
#>
Write-Output 'No-op rollback: pre-flight-check makes no changes, so there is nothing to undo.'
