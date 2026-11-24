Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$A = [Windows.Automation.AutomationElement]
$np = Get-Process notepad | Select-Object -First 1
$w = $A::FromHandle($np.MainWindowHandle)
$all = $w.FindAll('Descendants', [Windows.Automation.Condition]::TrueCondition)
"plain (no DPI call): $($all.Count) elements"
foreach ($e in $all) { "  $($e.Current.ControlType.ProgrammaticName) '$($e.Current.Name)' id=$($e.Current.AutomationId) class=$($e.Current.ClassName)" }
"apartment: $([Threading.Thread]::CurrentThread.ApartmentState)  ps: $($PSVersionTable.PSVersion)  os: $([Environment]::OSVersion.Version)"
"notepad path: $($np.Path)"
