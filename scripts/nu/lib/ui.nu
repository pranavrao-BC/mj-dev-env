# Display helpers. Printing only, no state mutation.

export def info [msg: string] {
  print $"  (ansi green)✓(ansi reset) ($msg)"
}

export def warn [msg: string] {
  print $"  (ansi yellow)⚠(ansi reset) ($msg)"
}

export def err [msg: string] {
  print $"  (ansi red)✗(ansi reset) ($msg)"
}

export def step [msg: string] {
  print $"  (ansi cyan)›(ansi reset) ($msg)"
}

export def banner [text: string] {
  print ""
  print $"  (ansi cyan_bold)($text)(ansi reset)"
  let line = "─" | fill -c "─" -w ($text | str length)
  print $"  (ansi attr_dimmed)($line)(ansi reset)"
}

export def success-box [lines: list<string>] {
  print ""
  print $"  (ansi green_bold)┌─────────────────────────────────────┐(ansi reset)"
  for line in $lines {
    let padded = $line | fill -w 35
    print $"  (ansi green_bold)│(ansi reset) ($padded) (ansi green_bold)│(ansi reset)"
  }
  print $"  (ansi green_bold)└─────────────────────────────────────┘(ansi reset)"
  print ""
}
