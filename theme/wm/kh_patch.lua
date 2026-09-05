-- kh_patch.lua -- builds KindleHub's patched window-manager modules from the
-- copies already on YOUR Kindle. Amazon's Lua is proprietary, so this pack does
-- not ship it; it ships only the lines KindleHub adds, and where they go.
--
--   luajit kh_patch.lua application <input.lua> <output.lua>
--   luajit kh_patch.lua dialog      <input.lua> <output.lua>
--   luajit kh_patch.lua verify application|dialog <original.lua> <patched.lua>
--
-- Every insertion must find its anchor EXACTLY once, or nothing is written and
-- the exit code is 1. An insertion whose text is already present is skipped, so
-- a module carrying the earlier (first-attempt) patch can be brought up to date.
--
-- `verify` is the check that makes this safe on a firmware nobody has tested:
-- it strips every KindleHub block back out of the patched file and demands the
-- result be byte-for-byte the original. If that holds, the only thing that
-- changed is the lines below -- and every one of those is wrapped in pcall, so
-- a runtime surprise inside them cannot stop awesome from starting.
--
-- ANCHORS ACROSS FIRMWARE. These were checked against three generations of the
-- module: 5.11.1.1 (Paperwhite 2), 5.13.2 (Paperwhite 4) and 5.19.2
-- (Paperwhite 11). The code is the same; only the whitespace on the blank line
-- after log("application is normal") differs (four spaces on the older two,
-- nothing on 5.19.2). So that anchor is matched by LINE, not by exact bytes:
-- the log line, then one blank-or-whitespace line. On 5.19.2 the output is
-- still byte-identical to the known-good module (md5 3472a42f...).

local INSERTIONS = {
  application = {
    {
      -- after the log line AND the blank line that follows it
      where  = "after_line_and_blank",
      anchor = 'log("application is normal")',
      block  = [=====[
    pcall(function()
        if appWindow.params.ID == "com.lab126.browser" then
            local kh = io.open("/mnt/us/kindlehub_fullscreen", "r")
            if kh then kh:close() appWindow.params.PC = "N" end
        end
    end)

]=====],
    },
    {
      where  = "before",
      anchor = [=====[
            if updatedWindow.params.ID == "blankBackground" then]=====],
      block  = [=====[
            -- ---- KindleHub fullscreen ------------------------------------
            -- Set PC here, in the UPDATE path, not later in positioning:
            -- chrome_set_app_chrome_state() reads params.PC to decide whether
            -- the bars are shown, and it runs BEFORE the geometry is computed.
            -- Setting it only inside prv_position_application (the first
            -- attempt) was too late -- the chrome had already been told to
            -- show, so nothing changed on screen.
            --
            -- PC == "N" makes chrome_get_persistent_top_offset() return 0
            -- instead of S.height + S.y (115 + 101 = 216), so the window gets
            -- the whole 1236x1648 panel.
            --
            -- Gated on a flag file on /mnt/us because /etc is not visible over
            -- USB: deleting that file from the Mac disables this with no root
            -- access. Wrapped in pcall so it can never stop awesome starting.
            pcall(function()
                local id = updatedWindow.params.ID
                local nm = updatedWindow.c and updatedWindow.c.name or ""
                if id == "com.lab126.browser" or string.find(nm, "com.lab126.browser", 1, true) then
                    local kh = io.open("/mnt/us/kindlehub_fullscreen", "r")
                    if kh then
                        kh:close()
                        updatedWindow.params.PC = "N"
                    end
                end
            end)
            -- ---- end KindleHub fullscreen -------------------------------

]=====],
    },
  },
  dialog = {
    {
      where  = "before",
      anchor = [=====[
        -- save current geometry
]=====],
      block  = [=====[
        -- ---- KindleHub: suppress Control Centre while fullscreen ----------
        -- The Control Centre is a dialog-layer overlay identified by
        --     A:QuickSettingsWindow   KIWI:com.lab126.kppQuickSettings
        -- (seen in the xwininfo dump at 1236x1331+0+0). Hiding it here, at the
        -- moment it is added, is the narrowest possible block.
        --
        -- Screenshots are UNAFFECTED: the two-corner tap is handled in
        -- lab126_button_handling.lua, an entirely separate path that this does
        -- not touch. That separation is why this can be blocked without also
        -- losing screenshots.
        --
        -- Gated on the same /mnt/us flag as fullscreen, so Control Centre comes
        -- straight back the moment fullscreen is off -- and can be restored
        -- over USB with no root access. pcall so it can never break awesome.
        local kh_block = false
        pcall(function()
            if updatedWindow.params and updatedWindow.params.A == "QuickSettingsWindow" then
                local kh = io.open("/mnt/us/kindlehub_fullscreen", "r")
                if kh then
                    kh:close()
                    kh_block = true
                end
            end
        end)
        if kh_block then
            if updatedWindow.c then updatedWindow.c.hidden = true end
            return
        end
        -- ---- end KindleHub -----------------------------------------------

]=====],
    },
  },
}

local function count(s, sub)
  local n, i = 0, 1
  while true do
    local a, b = string.find(s, sub, i, true)
    if not a then return n end
    n = n + 1; i = b + 1
  end
end

local function fail(msg) io.stderr:write("kh_patch: " .. msg .. "\n"); os.exit(1) end

local function readfile(p)
  local f = io.open(p, "rb"); if not f then fail("cannot read " .. p) end
  local s = f:read("*a"); f:close(); return s
end

-- Where does insertion `ins` go in `src`? Returns the byte offset the block
-- is inserted AT (the block goes before that offset), or nil + reason.
local function locate(src, ins)
  local n = count(src, ins.anchor)
  if n ~= 1 then return nil, "anchor found " .. n .. " times (need exactly 1)" end
  local a, b = string.find(src, ins.anchor, 1, true)
  if ins.where == "before" then return a end
  if ins.where == "after" then return b + 1 end
  if ins.where == "after_line_and_blank" then
    -- to the end of the anchor's line ...
    local eol = string.find(src, "\n", b, true)
    if not eol then return nil, "anchor is on the last line" end
    -- ... then over exactly one line that is empty or whitespace-only
    local nl2 = string.find(src, "\n", eol + 1, true)
    if not nl2 then return nil, "no line after the anchor" end
    local between = src:sub(eol + 1, nl2 - 1)
    if not between:match("^[ \t\r]*$") then
      return nil, "the line after the anchor is not blank"
    end
    return nl2 + 1
  end
  return nil, "unknown placement " .. tostring(ins.where)
end

local mode = arg[1]

-- ---------------------------------------------------------------- verify
if mode == "verify" then
  local which, orig_p, patched_p = arg[2], arg[3], arg[4]
  local list = which and INSERTIONS[which]
  if not list or not orig_p or not patched_p then
    fail("usage: kh_patch.lua verify application|dialog <original> <patched>")
  end
  local orig, patched = readfile(orig_p), readfile(patched_p)
  local stripped, removed = patched, 0
  for i, ins in ipairs(list) do
    local n = count(stripped, ins.block)
    if n > 1 then fail("verify: block " .. i .. " appears " .. n .. " times") end
    if n == 1 then
      local a, b = string.find(stripped, ins.block, 1, true)
      stripped = stripped:sub(1, a - 1) .. stripped:sub(b + 1)
      removed = removed + 1
    end
  end
  if removed == 0 then fail("verify: no KindleHub block found in " .. patched_p) end
  if stripped ~= orig then
    fail("verify: patched file minus KindleHub's blocks is NOT the original - something else changed")
  end
  io.write(string.format("kh_patch: verify %s: %d block(s) removed, remainder is byte-for-byte the original\n", which, removed))
  os.exit(0)
end

-- ------------------------------------------------------------------ patch
local inp, outp = arg[2], arg[3]
local list = mode and INSERTIONS[mode]
if not list or not inp or not outp then
  fail("usage: kh_patch.lua application|dialog <input> <output>  |  verify application|dialog <original> <patched>")
end

local src = readfile(inp)
if src:find("\r\n", 1, true) then fail("input has CRLF line endings - not the device's file") end

local applied, skipped = 0, 0
for i, ins in ipairs(list) do
  if count(src, ins.block) > 0 then
    skipped = skipped + 1
  else
    local at, why = locate(src, ins)
    if not at then fail("insertion " .. i .. ": " .. why .. " - not a module this patch understands") end
    src = src:sub(1, at - 1) .. ins.block .. src:sub(at)
    applied = applied + 1
  end
end
if applied == 0 then fail("nothing to do - every insertion is already present") end

local o = io.open(outp, "wb"); if not o then fail("cannot write " .. outp) end
o:write(src); o:close()
io.write(string.format("kh_patch: %s: %d insertion(s) applied, %d already present\n", mode, applied, skipped))
os.exit(0)
