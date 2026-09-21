@{
    # PSScriptAnalyzer configuration for this repository.
    #
    # Excluded rules, each with a written reason. Anything not listed here must pass clean.

    ExcludeRules = @(

        # These are interactive provisioning scripts, run by a human at a console. Coloured,
        # host-directed output is the intended behaviour; Write-Information or Write-Output would
        # strip the formatting and pollute the pipeline. The rule targets reusable cmdlets that may
        # execute with no host attached, which these are not.
        'PSAvoidUsingWriteHost'

        # Fires on the internal helper Set-UserPathVariable. The user-facing contract for state
        # changes in this repository is each script's own -DryRun switch, which is honoured before
        # any write occurs. The helper is never exported and never invoked outside that flow.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
