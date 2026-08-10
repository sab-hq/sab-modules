<#
.SYNOPSIS
    rollback-stage-patches — the declared rollback for stage-patches.
.DESCRIPTION
    Staging only downloads updates to Windows's own cache — it never
    installs anything and never changes the server's running behavior.
    The disk space used by cached-but-uninstalled updates is a normal,
    self-managed byproduct of Windows Update, not something that needs
    an urgent undo.

    This script exists anyway, rather than omitting a rollback entirely,
    to keep the orchestration engine's "call the module's declared
    rollback on failure" logic uniform across every module, no
    special-casing for modules whose action doesn't change system
    behavior. See docs/learn/modules.md in sab-engine for the reasoning,
    and pre-development-checklist.md, PD-14 (the same reasoning applied
    to pre-flight-check) and PD-15.

    If disk space consumed by cached updates ever becomes a real
    operational concern, a genuine rollback (clearing
    C:\Windows\SoftwareDistribution\Download) would be a reasonable
    future enhancement — not implemented now since it isn't required for
    correctness, and clearing that folder affects every cached update on
    the machine, not just the ones this specific run staged.
#>
Write-Output 'No-op rollback: stage-patches only downloads updates, it does not install or change anything, so there is nothing that needs undoing.'
