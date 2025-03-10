function Out-PolicySetsDocumentationToFile {
    [CmdletBinding()]
    param (
        [string] $OutputPath,
        [string] $FileNameStem,
        [switch] $WindowsNewLineCells,
        [string] $Title,
        [array] $ItemList,
        [array] $EnvironmentColumnsInCsv,
        [hashtable] $PolicySetDetails,
        [hashtable] $FlatPolicyList
    )

    Write-Information "Generating Policy Set documentation for '$Title', files '$FileNameStem'."

    #region Markdown

    [System.Collections.Generic.List[string]] $allLines = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $headerAndToc = [System.Collections.Generic.List[string]]::new()
    [System.Collections.Generic.List[string]] $body = [System.Collections.Generic.List[string]]::new()

    $null = $headerAndToc.Add("# $Title`n")
    $null = $headerAndToc.Add("Auto-generated Policy effect documentation for PolicySets grouped by Effect and sorted by Policy category and Policy display name.`n")
    $null = $headerAndToc.Add("## Table of contents`n")

    $null = $headerAndToc.Add("- [PolicySets](#policySets)")
    $null = $body.Add("`n## <a id=`"policySets`"></a>PolicySets`n")
    $addedTableHeader = ""
    $addedTableDivider = ""
    foreach ($item in $ItemList) {
        $shortName = $item.shortName
        $policySetId = $item.policySetId
        $policySetDetail = $PolicySetDetails.$policySetId
        $null = $body.Add("### $($shortName)`n")
        $null = $body.Add("- Display name: $($policySetDetail.displayName)")
        $null = $body.Add("- Type: $($policySetDetail.policyType)")
        $null = $body.Add("- Category: $($policySetDetail.category)`n")
        $null = $body.Add("$($policySetDetail.description)`n")

        $addedTableHeader += " $shortName |"
        $addedTableDivider += " :-------- |"
    }
    $null = $headerAndToc.Add("- [Policies](#policies)")
    $null = $body.Add("`n<br/>`n`n## <a id='policies'></a>Policies`n`n<br/>`n")
    $null = $body.Add("| Category | Policy |$addedTableHeader")
    $null = $body.Add("| :------- | :----- |$addedTableDivider")

    $FlatPolicyList.Values | Sort-Object -Property { $_.category }, { $_.displayName } | ForEach-Object -Process {
        $policySetList = $_.policySetList
        $addedEffectColumns = ""
        $addedRows = ""
        foreach ($item in $ItemList) {
            $shortName = $item.shortName
            if ($policySetList.ContainsKey($shortName)) {
                $perPolicySet = $policySetList.$shortName
                $effectValue = $perPolicySet.effectValue
                $effectAllowedValues = $perPolicySet.effectAllowedValues
                $text = Convert-EffectToString `
                    -Effect $effectValue `
                    -AllowedValues $effectAllowedValues `
                    -Markdown
                $addedEffectColumns += " $text |"

                [array] $groupNames = $perPolicySet.groupNames
                $parameters = $perPolicySet.parameters
                if ($parameters.psbase.Count -gt 0 -or $groupNames.Count -gt 0) {
                    $addedRows += "<br/>*$($perPolicySet.displayName):*"
                    $text = Convert-ParametersToString -Parameters $parameters -OutputType "markdown"
                    $addedRows += $text
                    foreach ($groupName in $groupNames) {
                        $addedRows += "<br>&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;$groupName"
                    }
                }
            }
            else {
                $addedEffectColumns += "  |"
            }
        }
        $referencePathString = ""
        if ($_.referencePath -ne "") {
            $referencePathString = "&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;referencePath: ``$($_.referencePath)``<br/>"
        }
        $null = $body.Add("| $($_.category) | **$($_.displayName)**<br/>$($referencePathString)$($_.description)$($addedRows) |$addedEffectColumns")
    }
    $null = $headerAndToc.Add("`n<br/>")
    $null = $allLines.AddRange($headerAndToc)
    $null = $allLines.AddRange($body)

    # Output file
    $outputFilePath = "$($OutputPath -replace '[/\\]$','')/$FileNameStem.md"
    $allLines | Out-File $outputFilePath -Force

    #endregion Markdown

    #region CSV

    $outputEnvironmentColumns = $null -ne $EnvironmentColumnsInCsv -and $EnvironmentColumnsInCsv.Length -gt 0
    if (!$outputEnvironmentColumns) {
        $EnvironmentColumnsInCsv = @( "default" )
    }

    [System.Collections.ArrayList] $allRows = [System.Collections.ArrayList]::new()
    [System.Collections.ArrayList] $columnHeaders = [System.Collections.ArrayList]::new()

    # Create header rows for CSV
    $null = $columnHeaders.AddRange(@("name", "referencePath", "policyType", "category", "displayName", "description", "groupNames", "policySets", "allowedEffects" ))
    foreach ($environmentCategory in $EnvironmentColumnsInCsv) {
        $null = $columnHeaders.Add("$($environmentCategory)Effect")
    }
    foreach ($environmentCategory in $EnvironmentColumnsInCsv) {
        $null = $columnHeaders.Add("$($environmentCategory)Parameters")
    }

    # deal with multi value cells
    $inCellSeparator = ","
    if ($WindowsNewLineCells) {
        $inCellSeparator = ",`n"
    }

    $allRows.Clear()

    # Content rows
    $FlatPolicyList.Values | Sort-Object -Property { $_.category }, { $_.displayName } | ForEach-Object -Process {
        # Initialize row - with empty strings
        $rowObj = [ordered]@{}
        foreach ($key in $columnHeaders) {
            $null = $rowObj.Add($key, "")
        }

        # Cache loop values
        $effectAllowedValues = $_.effectAllowedValues
        $isEffectParameterized = $_.isEffectParameterized
        $effectAllowedOverrides = $_.effectAllowedOverrides
        $groupNamesList = $_.groupNamesList
        $effectDefault = $_.effectDefault
        $policySetEffectStrings = $_.policySetEffectStrings

        # Build common columns
        $rowObj.name = $_.name
        $rowObj.referencePath = $_.referencePath
        $rowObj.policyType = $_.policyType
        $rowObj.category = $_.category
        $rowObj.displayName = $_.displayName
        $rowObj.description = $_.description
        if ($groupNamesList.Count -gt 0) {
            $rowObj.groupNames = $groupNamesList -join $inCellSeparator
        }
        if ($policySetEffectStrings.Count -gt 0) {
            $rowObj.policySets = $policySetEffectStrings -join $inCellSeparator
        }
        if ($isEffectParameterized -and $effectAllowedValues.Count -gt 1) {
            $rowObj.allowedEffects = $effectAllowedValues.Keys -join $inCellSeparator
        }
        elseif ($effectAllowedOverrides.Count -gt 0) {
            $rowObj.allowedEffects = $effectAllowedOverrides -join $inCellSeparator
        }

        # Per environment columns
        $parameters = $_.parameters
        $parametersValueString = Convert-ParametersToString -Parameters $parameters -OutputType "csvValues"
        foreach ($environmentCategory in $EnvironmentColumnsInCsv) {
            $rowObj["$($environmentCategory)Effect"] = $effectDefault
            $rowObj["$($environmentCategory)Parameters"] = $parametersValueString
        }

        # Add row to spreadsheet
        $null = $allRows.Add($rowObj)
    }

    # Output file
    $outputFilePath = "$($OutputPath -replace '[/\\]$','')/$($FileNameStem).csv"
    if ($WindowsNewLineCells) {
        $allRows | ConvertTo-Csv | Out-File $outputFilePath -Force -Encoding utf8BOM
    }
    else {
        # Mac or Linux
        $allRows | ConvertTo-Csv | Out-File $outputFilePath -Force -Encoding utf8NoBOM
    }

    #endregion CSV

    #region Parameters JSON

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append("{")
    $null = $sb.Append("`n  `"parameters`": {")
    $FlatPolicyList.Values | Sort-Object -Property { $_.category }, { $_.displayName } | ForEach-Object -Process {
        if ($_.isEffectParameterized) {

            $policySetList = $_.policySetList
            $referencePath = $_.referencePath
            $displayName = $_.displayName
            $category = $_.category

            $null = $sb.Append("`n    // ")
            $null = $sb.Append("`n    // -----------------------------------------------------------------------------------------------------------------------------")
            $null = $sb.Append("`n    // $($category) -- $($displayName)")
            if ($referencePath -ne "") {
                $null = $sb.Append("`n    //     referencePath: $($referencePath)")
            }
            foreach ($item in $ItemList) {
                $shortName = $item.shortName
                if ($policySetList.ContainsKey($shortName)) {
                    $perPolicySet = $policySetList.$shortName
                    $policySetDisplayName = $perPolicySet.displayName
                    if ($perPolicySet.isEffectParameterized) {
                        $null = $sb.Append("`n    //   $($policySetDisplayName): $($perPolicySet.effectDefault) ($($perPolicySet.effectParameterName))")
                    }
                    else {
                        $null = $sb.Append("`n    //   $($policySetDisplayName): $($perPolicySet.effectDefault) ($($perPolicySet.effectReason))")
                    }
                }
            }
            $null = $sb.Append("`n    // -----------------------------------------------------------------------------------------------------------------------------")
            $parameterText = Convert-ParametersToString -Parameters $_.parameters -OutputType "jsonc"
            $null = $sb.Append($parameterText)
        }
    }
    $null = $sb.Append("`n  }")
    $null = $sb.Append("`n}")

    # Output file
    $outputFilePath = "$($OutputPath -replace '[/\\]$', '')/$FileNameStem.jsonc"
    $sb.ToString() | Out-File $outputFilePath -Force

    #endregion

}
