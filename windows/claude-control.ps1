# claude-control.ps1 - background computer use for Windows through UI Automation.
# Copyright (c) 2026 Kanishk Thakar. MIT License - https://github.com/KanishkThakar/claude-cursor
#
#   claude-control windows                                   list top-level windows
#   claude-control ui   --app APP [--title T] [--window HWND] [--max N] [--all]
#                                                            numbered UI elements (refs e1, e2, ...)
#   claude-control find --app APP [--name TEXT] [--type ControlType] [--id AutomationId]
#   claude-control click REF                                 invoke / toggle / select / expand
#   claude-control type  REF TEXT [--append]                 set the value of an edit field
#   claude-control read  [REF]                               text of an element, or of the window
#   claude-control focus REF                                 keyboard focus (may raise the window)
#
# Everything goes through UI Automation patterns: the user's pointer is never moved and no global
# keystrokes are sent. If the Claude Cursor is running, it glides to each element first and its
# label narrates the step. Refs are saved per window and go stale when the UI changes: run ui again.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
Add-Type @'
using System; using System.Runtime.InteropServices;
public static class CCDpi {
  [DllImport("user32.dll")] static extern IntPtr SetThreadDpiAwarenessContext(IntPtr v);
  public static void Set() { try { SetThreadDpiAwarenessContext(new IntPtr(-4)); } catch (Exception) { } }
}
'@
[CCDpi]::Set()

$A = [Windows.Automation.AutomationElement]
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cursor = Join-Path $Here 'claude-cursor.ps1'
$Dir = Join-Path $env:LOCALAPPDATA 'claude-ghost'
New-Item -ItemType Directory -Force $Dir | Out-Null
$RefsF = Join-Path $Dir 'refs.json'
$Dot = [char]0xB7

function Fail($msg) { Write-Output $msg; exit 1 }

function Parse([string[]]$a) {
  $o = @{ pos = @() }
  for ($i = 0; $i -lt $a.Count; $i++) {
    if ($a[$i] -like '--*') {
      $k = $a[$i].Substring(2)
      if ($k -in 'append', 'all') { $o[$k] = $true } else { $o[$k] = $a[++$i] }
    } else { $o.pos += $a[$i] }
  }
  return $o
}

function Windows-List {
  $root = $A::RootElement
  $kids = $root.FindAll([Windows.Automation.TreeScope]::Children, [Windows.Automation.Condition]::TrueCondition)
  foreach ($w in $kids) {
    try {
      $c = $w.Current
      if ($c.IsOffscreen -or -not $c.Name) { continue }
      $r = $c.BoundingRectangle
      if ($r.Width -lt 80 -or $r.Height -lt 60) { continue }
      $p = ''; try { $p = (Get-Process -Id $c.ProcessId -ErrorAction Stop).ProcessName } catch { }
      [pscustomobject]@{ El = $w; Hwnd = $c.NativeWindowHandle; Proc = $p; Title = $c.Name; R = $r }
    } catch { }
  }
}

function Resolve-Window($o) {
  if ($o.window) {
    $h = [IntPtr][long]$o.window
    try { return $A::FromHandle($h) } catch { Fail "window $($o.window) not found" }
  }
  if (-not $o.app) { Fail 'name the target: --app APP [--title T] or --window HWND' }
  $app = $o.app.ToLower() -replace '\.exe$', ''; $ns = $app -replace ' ', ''
  $t = if ($o.title) { $o.title.ToLower() } else { '' }
  $all = @(Windows-List | Where-Object { -not $t -or $_.Title.ToLower().Contains($t) })
  $m = $all | Where-Object { $_.Proc.ToLower() -eq $app -or $_.Proc.ToLower() -eq $ns } | Select-Object -First 1
  if (-not $m) { $m = $all | Where-Object { $_.Proc.ToLower().Contains($ns) -or $_.Title.ToLower().Contains($app) } | Select-Object -First 1 }
  if (-not $m) { Fail "no visible window for app `"$($o.app)`" (open it first)" }
  return $m.El
}

$PatternProps = [ordered]@{
  invoke = $A::IsInvokePatternAvailableProperty
  value  = $A::IsValuePatternAvailableProperty
  toggle = $A::IsTogglePatternAvailableProperty
  select = $A::IsSelectionItemPatternAvailableProperty
  expand = $A::IsExpandCollapsePatternAvailableProperty
  text   = $A::IsTextPatternAvailableProperty
}

function Walk($win, [int]$max, [bool]$all) {
  $cr = New-Object Windows.Automation.CacheRequest
  foreach ($p in $A::NameProperty, $A::ControlTypeProperty, $A::AutomationIdProperty, $A::BoundingRectangleProperty,
                 $A::IsOffscreenProperty, $A::IsEnabledProperty, $A::RuntimeIdProperty) { $cr.Add($p) }
  foreach ($p in $PatternProps.Values) { $cr.Add($p) }
  $cr.Add([Windows.Automation.ValuePattern]::ValueProperty)
  $cr.TreeFilter = [Windows.Automation.Automation]::ControlViewCondition
  $ctx = $cr.Activate()
  try { $els = $win.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Automation]::ControlViewCondition) }
  finally { $ctx.Dispose() }
  $out = @(); $n = 0
  foreach ($e in $els) {
    try {
      $c = $e.Cached
      $pats = @(); foreach ($k in $PatternProps.Keys) { if ($e.GetCachedPropertyValue($PatternProps[$k]) -eq $true) { $pats += $k } }
      $type = $c.ControlType.ProgrammaticName -replace '^ControlType\.', ''
      if (-not $all) {
        if ($c.IsOffscreen) { continue }
        if (-not $c.Name -and $pats.Count -eq 0) { continue }
      }
      $val = $null
      if ($pats -contains 'value') { try { $val = [string]$e.GetCachedPropertyValue([Windows.Automation.ValuePattern]::ValueProperty) } catch { } }
      $r = $c.BoundingRectangle
      $n++
      $out += [pscustomobject]@{
        Ref = "e$n"; Type = $type; Name = $c.Name; Id = $c.AutomationId; Value = $val; Pats = $pats
        X = [int]$r.X; Y = [int]$r.Y; W = [int]$r.Width; H = [int]$r.Height
        Rid = (($e.GetCachedPropertyValue($A::RuntimeIdProperty)) -join '.')
      }
      if ($n -ge $max) { break }
    } catch { }
  }
  return $out
}

function Show($x) {
  $s = "{0,-5} {1,-12} `"{2}`"" -f $x.Ref, $x.Type, (Short $x.Name 50)
  if ($x.Id) { $s += " [id=$($x.Id)]" }
  if ($null -ne $x.Value -and $x.Value -ne '') { $s += " = `"$(Short $x.Value 40)`"" }
  $s += " @$($x.X),$($x.Y) $($x.W)x$($x.H)"
  if ($x.Pats.Count) { $s += ' {' + ($x.Pats -join ',') + '}' }
  $s
}
function Short($s, $n) { if (-not $s) { return '' }; $s = $s -replace '\s+', ' '; if ($s.Length -gt $n) { $s.Substring(0, $n - 1) + '~' } else { $s } }

function Save-Refs($win, $items) {
  $c = $win.Current
  $data = @{ hwnd = $c.NativeWindowHandle; title = $c.Name; items = @($items | ForEach-Object {
    @{ ref = $_.Ref; rid = $_.Rid; type = $_.Type; name = $_.Name; id = $_.Id; x = $_.X; y = $_.Y; w = $_.W; h = $_.H } }) }
  [IO.File]::WriteAllText($RefsF, ($data | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
}

function Resolve-Ref([string]$ref) {
  if (-not (Test-Path $RefsF)) { Fail 'no refs yet: run  claude-control ui --app APP  first' }
  $d = Get-Content $RefsF -Raw | ConvertFrom-Json
  $it = $d.items | Where-Object { $_.ref -eq $ref } | Select-Object -First 1
  if (-not $it) { Fail "unknown ref $ref (run ui again)" }
  $win = $null; try { $win = $A::FromHandle([IntPtr][long]$d.hwnd) } catch { Fail 'that window is gone (run ui again)' }
  $el = $null
  try {
    $rid = [int[]]($it.rid -split '\.' | ForEach-Object { [int]$_ })
    $el = $win.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition($A::RuntimeIdProperty, $rid)))
  } catch { }
  if (-not $el -and $it.id) {
    $el = $win.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition($A::AutomationIdProperty, $it.id)))
  }
  if (-not $el -and $it.name) {
    $el = $win.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition($A::NameProperty, $it.name)))
  }
  if (-not $el) { Fail "$ref is stale (the UI changed): run ui again" }
  return @{ El = $el; Hwnd = $d.hwnd; Item = $it }
}

# ---- Claude Cursor integration (only if it is already running) ----
function Cursor-On { if (-not (Test-Path $Cursor)) { return $false }; return ((& $Cursor status) -like 'running*') }
function Point($t, [string]$label, [bool]$click) {
  if (-not (Cursor-On)) { return }
  $cur = (& $Cursor status) -replace '^running \(window (\d+)\)$', '$1'
  if ("$cur" -ne "$($t.Hwnd)") { & $Cursor attach --window "$($t.Hwnd)" | Out-Null }
  $r = $t.El.Current.BoundingRectangle
  $x = [int]($r.X + $r.Width / 2); $y = [int]($r.Y + $r.Height / 2)
  & $Cursor say "Claude $Dot $label" | Out-Null
  if ($click) { & $Cursor click $x $y | Out-Null } else { & $Cursor move $x $y | Out-Null }
}
function Cursor-Rest { if (Cursor-On) { & $Cursor say 'Claude' | Out-Null } }

function Try-Pattern($el, $pattern) {
  $p = $null
  if ($el.TryGetCurrentPattern($pattern, [ref]$p)) { return $p }
  return $null
}

$cmd = if ($args.Count) { $args[0] } else { 'help' }
$o = Parse @($args | Select-Object -Skip 1)

switch ($cmd) {
  'windows' {
    foreach ($w in Windows-List) { '{0,-10} {1,-18} "{2}" {3},{4} {5}x{6}' -f $w.Hwnd, $w.Proc, (Short $w.Title 60), [int]$w.R.X, [int]$w.R.Y, [int]$w.R.Width, [int]$w.R.Height }
  }
  { $_ -in 'ui', 'find' } {
    $win = Resolve-Window $o
    $max = if ($o.max) { [int]$o.max } else { 300 }
    $items = Walk $win ($(if ($cmd -eq 'find') { 2000 } else { $max })) ([bool]$o.all)
    if ($cmd -eq 'find') {
      if ($o.name) { $items = @($items | Where-Object { $_.Name -and $_.Name.ToLower().Contains($o.name.ToLower()) }) }
      if ($o.type) { $items = @($items | Where-Object { $_.Type -eq $o.type }) }
      if ($o.id)   { $items = @($items | Where-Object { $_.Id -eq $o.id }) }
    }
    Save-Refs $win $items
    $c = $win.Current
    "window $($c.NativeWindowHandle) `"$($c.Name)`" - $($items.Count) elements"
    foreach ($x in $items) { Show $x }
  }
  'click' {
    $t = Resolve-Ref $o.pos[0]
    Point $t 'clicking' $true
    $el = $t.El; $done = $null
    if ($p = Try-Pattern $el ([Windows.Automation.InvokePattern]::Pattern)) { $p.Invoke(); $done = 'invoked' }
    elseif ($p = Try-Pattern $el ([Windows.Automation.TogglePattern]::Pattern)) { $p.Toggle(); $done = "toggled ($($p.Current.ToggleState))" }
    elseif ($p = Try-Pattern $el ([Windows.Automation.SelectionItemPattern]::Pattern)) { $p.Select(); $done = 'selected' }
    elseif ($p = Try-Pattern $el ([Windows.Automation.ExpandCollapsePattern]::Pattern)) {
      if ($p.Current.ExpandCollapseState -eq 'Expanded') { $p.Collapse(); $done = 'collapsed' } else { $p.Expand(); $done = 'expanded' }
    }
    Cursor-Rest
    if (-not $done) { Fail "$($o.pos[0]) has no clickable pattern (invoke/toggle/select/expand); it can't be clicked in the background" }
    "$done $($o.pos[0]) $($t.Item.type) `"$($t.Item.name)`""
  }
  'type' {
    $t = Resolve-Ref $o.pos[0]
    $text = ($o.pos | Select-Object -Skip 1) -join ' '
    $p = Try-Pattern $t.El ([Windows.Automation.ValuePattern]::Pattern)
    if (-not $p) { Fail "$($o.pos[0]) is not an editable field (no ValuePattern)" }
    if ($p.Current.IsReadOnly) { Fail "$($o.pos[0]) is read-only" }
    Point $t 'typing' $false
    $new = if ($o.append) { $p.Current.Value + $text } else { $text }
    $p.SetValue($new)
    Cursor-Rest
    "typed into $($o.pos[0]): `"$(Short $p.Current.Value 80)`""
  }
  'read' {
    if ($o.pos.Count) {
      $t = Resolve-Ref $o.pos[0]
      Point $t 'reading' $false
      $txt = $null
      if ($p = Try-Pattern $t.El ([Windows.Automation.TextPattern]::Pattern)) { $txt = $p.DocumentRange.GetText(20000) }
      elseif ($p = Try-Pattern $t.El ([Windows.Automation.ValuePattern]::Pattern)) { $txt = $p.Current.Value }
      else { $txt = $t.El.Current.Name }
      Cursor-Rest
      $txt
    } else {
      $win = Resolve-Window $o
      foreach ($x in (Walk $win 600 $false)) {
        if ($x.Value) { "$($x.Type) `"$($x.Name)`": $($x.Value)" } elseif ($x.Name -and $x.Type -in 'Text', 'Document', 'Edit', 'Button', 'TabItem', 'ListItem', 'TreeItem', 'Hyperlink', 'MenuItem') { "$($x.Type): $($x.Name)" }
      }
    }
  }
  'focus' {
    $t = Resolve-Ref $o.pos[0]
    Point $t 'focusing' $false
    $t.El.SetFocus()
    Cursor-Rest
    "focused $($o.pos[0]) (this can bring its window to the front)"
  }
  default {
    'usage: claude-control windows | ui --app APP [--title T] [--window HWND] [--max N] [--all] | find --app APP [--name X] [--type T] [--id ID] | click REF | type REF TEXT [--append] | read [REF] | focus REF'
    if ($cmd -ne 'help') { exit 2 }
  }
}
