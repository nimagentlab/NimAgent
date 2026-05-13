import ../../tools/registry
import ../../utils/async_compat
import std/[osproc, os, strutils, random, json]

proc getVisionTempDir*(): string =
  let envDir = getEnv("NIMAGENT_TMPDIR")
  if envDir != "":
    result = envDir
  else:
    result = getTempDir()
  if not dirExists(result):
    createDir(result)

proc requireBinary*(name: string): string =
  let path = findExe(name)
  if path == "":
    raise newException(OSError, "Binary '" & name & "' not found. Install it or check PATH.")
  return path

# Global stochastic seed initialization
randomize()

var stealthMode* = true ## If enabled, adds random noise (delays, trajectories)

proc sleepHuman(minMs: int = 20, maxMs: int = 150) =
  ## Stochastic pause to mimic a human
  if stealthMode:
    sleep(rand(maxMs - minMs) + minMs)

proc humanMouseMove(endX, endY: int) =
  ## Moves the mouse with a noisy interpolation (fake Bezier) to evade pattern detectors
  discard requireBinary("xdotool")
  if not stealthMode:
    discard execCmdEx("xdotool mousemove " & $endX & " " & $endY)
    return

  # Gets the current position
  let (outp, code) = execCmdEx("xdotool getmouselocation")
  var startX = endX
  var startY = endY
  if code == 0:
    let parts = outp.split(" ")
    if parts.len >= 2:
      try:
        startX = parseInt(parts[0].replace("x:", ""))
        startY = parseInt(parts[1].replace("y:", ""))
      except: discard

  # Random micro-step count
  let steps = rand(15..35)
  for i in 1..steps:
    let t = i.float / steps.float
    # Linear movement + Random noise (human tremor)
    var currX = int(float(startX) + t * float(endX - startX))
    var currY = int(float(startY) + t * float(endY - startY))

    if i < steps:
      currX += rand(-4..4)
      currY += rand(-4..4)

    discard execCmdEx("xdotool mousemove " & $currX & " " & $currY)
    sleepHuman(2, 12)

llmTool "Enable or disable the stochastic stealth mode.":
  proc enable_stealth*(enabled: bool): string =
    stealthMode = enabled
    return "Stochastic stealth mode (Anti-Bot) set to: " & $enabled


llmTool "Click at an exact screen position (X, Y) with a human-like trajectory if stealth is enabled.":
  proc mouse_click*(x: int, y: int, button: string = "left"): string =
    discard requireBinary("xdotool")
    humanMouseMove(x, y)
    sleepHuman(100, 400) # Human makes a micro-pause before clicking

    let btnCode = if button == "right": "3" elif button ==
        "middle": "2" else: "1"
    let cmd = "xdotool click " & btnCode
    let (outp, code) = execCmdEx(cmd)
    if code == 0:
      return "Successfully clicked at coordinates (" & $x & ", " & $y & ")."
    return "Click error: " & outp

llmTool "Type keyboard text with variable stochastic speed.":
  proc keyboard_type*(text: string, enter: bool = false): string =
    discard requireBinary("xdotool")
    let cleanText = text.replace("'", "'\\''")
    if not stealthMode:
      var cmd = "xdotool type --delay 10 '" & cleanText & "'"
      if enter: cmd &= " && xdotool key Return"
      discard execCmdEx(cmd)
    else:
      for i, c in cleanText:
        let charCmd = "xdotool type '" & $c & "'"
        discard execCmdEx(charCmd)
        if rand(1..10) == 1: sleepHuman(150, 300)
        else: sleepHuman(40, 110)
      if enter:
        sleepHuman(200, 600)
        discard execCmdEx("xdotool key Return")
    return "Text typed successfully."

llmTool "Press a special key (e.g. Return, Escape, Tab, ctrl+c, Page_Down).":
  proc keyboard_key*(key: string): string =
    discard requireBinary("xdotool")
    let cmd = "xdotool key " & key
    let (outp, code) = execCmdEx(cmd)
    if code == 0:
      return "Key pressed: " & key
    return "Typing error: " & outp

llmTool "Take a full screenshot. The file is saved.":
  proc take_screenshot*(savePath: string = getVisionTempDir() / "eve_vision.png"): string =
    discard requireBinary("scrot")
    let cmd = "scrot -z -o " & quoteShell(savePath)
    let (outp, code) = execCmdEx(cmd)
    if code == 0:
      return savePath
    return "Screenshot error: Is scrot installed? (" & outp & ")"

llmTool "Scroll the screen. direction: up or down.":
  proc mouse_scroll*(direction: string = "down", amount: int = 3): string =
    discard requireBinary("xdotool")
    let btn = if direction == "up": "4" else: "5"
    var cmd = "xdotool "
    for i in 1..amount:
      cmd &= "click " & btn & " "
    let (outp, code) = execCmdEx(cmd)
    if code == 0: return "Scroll " & direction & " performed."
    return "Scroll error: " & outp

llmTool "Return the current mouse coordinates (X, Y).":
  proc get_mouse_position*(): string =
    discard requireBinary("xdotool")
    let cmd = "xdotool getmouselocation"
    let (outp, code) = execCmdEx(cmd)
    if code == 0: return outp.strip()
    return "Position error: " & outp

llmTool "Click, hold, stochastically move the mouse to endX, endY and release.":
  proc mouse_drag*(startX: int, startY: int, endX: int, endY: int): string =
    humanMouseMove(startX, startY)
    sleepHuman(100, 300)

    discard execCmdEx("xdotool mousedown 1")
    sleepHuman(50, 150)

    humanMouseMove(endX, endY)
    sleepHuman(100, 300)

    discard execCmdEx("xdotool mouseup 1")
    return "Drag from (" & $startX & "," & $startY & ") to (" &
        $endX & "," & $endY & ")."

llmTool "Find a window by name (e.g. Chrome, Firefox, Terminal) and bring it to the foreground.":
  proc window_focus*(windowName: string): string =
    discard requireBinary("xdotool")
    let cmd = "xdotool search --name " & quoteShell(windowName) & " windowactivate"
    let (outp, code) = execCmdEx(cmd)
    if code == 0: return "Window " & windowName & " brought to foreground."
    return "Unable to find or activate window " & windowName & outp

llmTool "Macro-Action: Find a specific word or text on screen (via OCR) and click it.":
  proc click_text_on_screen*(textToFind: string): string =
    discard requireBinary("scrot")
    discard requireBinary("tesseract")
    let imgPath = getVisionTempDir() / "stealth_vision_click.png"
    discard execCmdEx("scrot -z -o " & quoteShell(imgPath))
    
    let tempOut = getTempDir() / "ocr_click"
    let cmd = "tesseract " & quoteShell(imgPath) & " " & quoteShell(tempOut) & " tsv"
    let (outp, exitCode) = execCmdEx(cmd)
    
    if exitCode != 0:
      return "Erreur OCR lors de la recherche du texte : " & outp
      
    let tsvFile = tempOut & ".tsv"
    if not fileExists(tsvFile):
      return "Error: TSV file not generated by Tesseract."
      
    let content = readFile(tsvFile)
    removeFile(tsvFile)
    
    # Tesseract TSV format (12 columns):
    # level page_num block_num par_num line_num word_num left top width height conf text
    
    let lines = content.splitLines()
    let searchLower = textToFind.toLowerAscii()
    
    var found = false
    var bestLeft, bestTop, bestWidth, bestHeight: int
    
    # Start at 1 to skip the header (level, page_num, ...)
    for i in 1..<lines.len:
      let parts = lines[i].split('\t')
      if parts.len >= 12:
        let word = parts[11].strip()
        if word.len > 0 and searchLower in word.toLowerAscii():
          try:
            bestLeft = parseInt(parts[6])
            bestTop = parseInt(parts[7])
            bestWidth = parseInt(parts[8])
            bestHeight = parseInt(parts[9])
            found = true
            break
          except:
            continue
            
    if found:
      let centerX = bestLeft + (bestWidth div 2)
      let centerY = bestTop + (bestHeight div 2)
      humanMouseMove(centerX, centerY)
      sleepHuman(100, 300)
      discard execCmdEx("xdotool click 1")
      return "Text '" & textToFind & "' found and successfully clicked at (" & $centerX & ", " & $centerY & ")."
    else:
      return "Text '" & textToFind & "' was not found on screen."

llmTool "Extract and return all visible text on screen. Useful for non-vision models to understand the current context.":
  proc scrape_screen_text*(): string =
    discard requireBinary("scrot")
    discard requireBinary("tesseract")
    let imgPath = getVisionTempDir() / "stealth_vision_scrape.png"
    discard execCmdEx("scrot -z -o " & quoteShell(imgPath))
    
    let tempOut = getTempDir() / "ocr_scrape"
    let cmd = "tesseract " & quoteShell(imgPath) & " " & quoteShell(tempOut)
    let (outp, exitCode) = execCmdEx(cmd)
    
    let txtFile = tempOut & ".txt"
    if fileExists(txtFile):
      result = readFile(txtFile).strip()
      removeFile(txtFile)
      if result == "": result = "No text detected on screen."
    else:
      result = "OCR error during scraping: " & outp
