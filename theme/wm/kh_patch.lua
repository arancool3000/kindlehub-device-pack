-- kh_patch.lua -- builds KindleHub's patched window-manager modules from the
-- copies already on YOUR Kindle. Amazon's Lua is proprietary, so this pack does
-- not ship it; it ships only the lines KindleHub adds, and where they go.
--
--   luajit kh_patch.lua application <input.lua> <output.lua>
--   luajit kh_patch.lua dialog      <input.lua> <output.lua>
--
-- Every insertion must find its anchor EXACTLY once, or nothing is written and
-- the exit code is 1. An insertion whose text is already present is skipped, so
-- a module carrying the earlier (first-attempt) patch can be brought up to date.
-- The installer then md5-checks the output against the known-good result before
-- it goes anywhere near /etc, so a wrong result cannot be installed.

local INSERTIONS = {
  application = {
    {
      where  = "after",
      anchor = [=====[
    log("application is normal")

]=====],
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

local mode, inp, outp = arg[1], arg[2], arg[3]
local list = mode and INSERTIONS[mode]
if not list or not inp or not outp then
  fail("usage: kh_patch.lua application|dialog <input> <output>")
end

local f = io.open(inp, "rb"); if not f then fail("cannot read " .. inp) end
local src = f:read("*a"); f:close()
if src:find("\r\n", 1, true) then fail("input has CRLF line endings - not the device's file") end

local applied, skipped = 0, 0
for i, ins in ipairs(list) do
  if count(src, ins.block) > 0 then
    skipped = skipped + 1
  else
    local n = count(src, ins.anchor)
    if n ~= 1 then fail("insertion " .. i .. ": anchor found " .. n .. " times (need exactly 1) - not the expected module") end
    local a, b = string.find(src, ins.anchor, 1, true)
    if ins.where == "after" then
      src = src:sub(1, b) .. ins.block .. src:sub(b + 1)
    else
      src = src:sub(1, a - 1) .. ins.block .. src:sub(a)
    end
    applied = applied + 1
  end
end
if applied == 0 then fail("nothing to do - every insertion is already present") end

local o = io.open(outp, "wb"); if not o then fail("cannot write " .. outp) end
o:write(src); o:close()
io.write(string.format("kh_patch: %s: %d insertion(s) applied, %d already present\n", mode, applied, skipped))
os.exit(0)
