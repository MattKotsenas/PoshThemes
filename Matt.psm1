#requires -Version 2 -Modules posh-git

function Get-HistoryId
{
    $id = 1
    $item = (Get-History -Count 1)
    if ($item)
    {
        $id = $item.Id + 1
    }

    return $id
}

function Write-StatusAsync
{
    param
    (
        $LastColor
    )

    Set-StrictMode -Version 2
    $ErrorActionPreference = "Stop"

    $position = $Host.UI.RawUI.CursorPosition

    # Runspaces need to be disposed, so keep track of them
    if (-not (Test-Path Variable:GitStatusRunspaces))
    {
        $global:GitStatusRunspaces = [Collections.ArrayList]::new()
    }
    foreach ($gsr in $global:GitStatusRunspaces.ToArray())
    {
        if ($gsr.AsyncHandle.IsCompleted)
        {
            $gsr.Powershell.EndInvoke($gsr.AsyncHandle)
            $gsr.Powershell.Dispose()
            $gsr.Runspace.Dispose()
            $global:GitStatusRunspaces.Remove($gsr)
        }
        # TODO: Should we cancel running jobs, since we're about to start a new one?
    }

    $runspace = [RunspaceFactory]::CreateRunspace($Host)
    $powershell = [Powershell]::Create()
    $powershell.Runspace = $runspace
    $runspace.Open()
    [void]$powershell.AddScript(
    {
        param
        (
            $WorkingDir,
            $Position,
            $ThemeSettings,
            $LastColor
        )

        Set-StrictMode -Version 2
        $ErrorActionPreference = "Stop"

        Set-Location $WorkingDir

        $status = Get-VCSStatus

        if ($status)
        {
            $themeInfo = Get-VcsInfo -status ($status)

            $buffer = $Host.UI.RawUI.NewBufferCellArray($ThemeSettings.PromptSymbols.SegmentForwardSymbol, $LastColor, $themeInfo.BackgroundColor)
            $buffer += $Host.UI.RawUI.NewBufferCellArray(" $($themeInfo.VcInfo) ", $ThemeSettings.Colors.GitForegroundColor, $themeInfo.BackgroundColor)

            $buffer += $Host.UI.RawUI.NewBufferCellArray($ThemeSettings.PromptSymbols.SegmentForwardSymbol, $themeInfo.BackgroundColor, $ThemeSettings.Colors.PromptBackgroundColor)

            # Appending to buffer makes a flat object array; we need to turn it back into a 2-dimensional one
            $bufferCells2d = [Management.Automation.Host.BufferCell[,]]::new(1, $buffer.Length)
            for ($i = 0; $i -lt $buffer.Length; $i++)
            {
              $bufferCells2d[0,$i] = $buffer[$i] 
            }

            $host.UI.RawUI.SetBufferContents($Position, $bufferCells2d)
        }
    }).AddParameters(@{ Position = $position; ThemeSettings = $ThemeSettings; WorkingDir = (Get-Location); LastColor = $LastColor })

    [void]$global:GitStatusRunspaces.Add((New-Object -TypeName PSObject -Property @{ Powershell = $powershell; AsyncHandle = $powershell.BeginInvoke(); Runspace = $runspace }))
}

function Write-Theme
{
    param(
        [bool]
        $lastCommandFailed,
        [string]
        $with
    )

    $lastColor = $sl.Colors.PromptBackgroundColor

    Write-Prompt -Object $sl.PromptSymbols.StartSymbol -ForegroundColor $sl.Colors.SessionInfoForegroundColor -BackgroundColor $sl.Colors.SessionInfoBackgroundColor

    #check the last command state and indicate if failed
    If ($lastCommandFailed)
    {
        Write-Prompt -Object "$($sl.PromptSymbols.FailedCommandSymbol) " -ForegroundColor $sl.Colors.CommandFailedIconForegroundColor -BackgroundColor $sl.Colors.SessionInfoBackgroundColor
    }

    #check for elevated prompt
    If (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator'))
    {
        Write-Prompt -Object "$($sl.PromptSymbols.ElevatedSymbol) " -ForegroundColor $sl.Colors.AdminIconForegroundColor -BackgroundColor $sl.Colors.SessionInfoBackgroundColor
    }

    # Writes the time portion
    $time = ([DateTime]::Now.ToString("h:mm:ss") + " " + [char]::ConvertFromUtf32(0x1F553))
    Write-Prompt -Object "$time " -ForegroundColor $sl.Colors.SessionInfoForegroundColor -BackgroundColor $sl.Colors.SessionInfoBackgroundColor

    # Writes the history portion
    $historyForeground = $sl.Colors.PromptForegroundColor
    $historyBackground = [ConsoleColor]::Green
    Write-Prompt -Object "$($sl.PromptSymbols.SegmentForwardSymbol) " -ForegroundColor $sl.Colors.SessionInfoBackgroundColor -BackgroundColor $historyBackground
    Write-Prompt -Object "$(Get-HistoryId) " -ForegroundColor $historyForeground -BackgroundColor $historyBackground

    Write-Prompt -Object "$($sl.PromptSymbols.SegmentForwardSymbol) " -ForegroundColor $historyBackground -BackgroundColor $sl.Colors.PromptBackgroundColor

    # Writes the drive portion
    Write-Prompt -Object (Get-FullPath -dir $pwd) -ForegroundColor $sl.Colors.PromptForegroundColor -BackgroundColor $sl.Colors.PromptBackgroundColor
    Write-Prompt -Object ' ' -ForegroundColor $sl.Colors.PromptForegroundColor -BackgroundColor $sl.Colors.PromptBackgroundColor

    if ($with)
    {
        Write-Prompt -Object $sl.PromptSymbols.SegmentForwardSymbol -ForegroundColor $lastColor -BackgroundColor $sl.Colors.WithBackgroundColor
        Write-Prompt -Object " $($with.ToUpper()) " -BackgroundColor $sl.Colors.WithBackgroundColor -ForegroundColor $sl.Colors.WithForegroundColor
        $lastColor = $sl.Colors.WithBackgroundColor
    }

    Write-StatusAsync

    # Writes the postfix to the prompt
    Write-Prompt -Object $sl.PromptSymbols.SegmentForwardSymbol -ForegroundColor $lastColor
    Write-Host ''
    Write-Prompt -Object $sl.PromptSymbols.PromptIndicator -ForegroundColor $sl.Colors.PromptSymbolColor
}

$global:ThemeSettings.PromptSymbols.TruncatedFolderSymbol = '...'

$sl = $global:ThemeSettings #local settings
$sl.PromptSymbols.SegmentForwardSymbol = [char]::ConvertFromUtf32(0xE0B0)
$sl.Colors.PromptForegroundColor = [ConsoleColor]::White
$sl.Colors.PromptSymbolColor = [ConsoleColor]::White
$sl.Colors.PromptHighlightColor = [ConsoleColor]::DarkBlue
$sl.Colors.GitForegroundColor = [ConsoleColor]::Black
$sl.Colors.WithForegroundColor = [ConsoleColor]::White
$sl.Colors.WithBackgroundColor = [ConsoleColor]::DarkRed
