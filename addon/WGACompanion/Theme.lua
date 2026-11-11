-- WGA Companion: themes (dark, light, high contrast dark, high contrast light) and skinning helpers.
-- Every WGA window builds from these helpers, so switching theme restyles everything at once.
local _, CM = ...
local T = CM:NewModule("Theme")

T.order = { "dark", "light", "hcdark", "hclight" }
T.palettes = {
  dark = {
    name = "Dark", bg = { 0.055, 0.065, 0.10, 0.97 }, panel = { 0.09, 0.11, 0.165, 0.96 }, sidebar = { 0.07, 0.08, 0.125, 0.98 },
    border = { 0.22, 0.27, 0.40, 1 }, accent = { 0.30, 0.80, 1 }, accent2 = { 0.72, 0.38, 1 },
    text = { 0.92, 0.94, 0.98 }, muted = { 0.56, 0.61, 0.72 }, heading = { 0.45, 0.85, 1 },
    good = { 0.38, 0.95, 0.52 }, warn = { 1, 0.80, 0.28 }, bad = { 1, 0.42, 0.42 },
    hover = { 1, 1, 1, 0.06 }, select = { 0.30, 0.80, 1, 0.16 }, bar = { 0.16, 0.19, 0.27, 1 }, size = 0,
  },
  light = {
    name = "Light", bg = { 0.95, 0.955, 0.97, 0.98 }, panel = { 1, 1, 1, 0.98 }, sidebar = { 0.89, 0.90, 0.935, 0.99 },
    border = { 0.74, 0.77, 0.84, 1 }, accent = { 0.04, 0.46, 0.82 }, accent2 = { 0.52, 0.22, 0.86 },
    text = { 0.10, 0.11, 0.15 }, muted = { 0.40, 0.43, 0.51 }, heading = { 0.04, 0.38, 0.72 },
    good = { 0.04, 0.55, 0.22 }, warn = { 0.76, 0.46, 0 }, bad = { 0.80, 0.10, 0.10 },
    hover = { 0, 0, 0, 0.05 }, select = { 0.04, 0.46, 0.82, 0.14 }, bar = { 0.84, 0.86, 0.91, 1 }, size = 0,
  },
  hcdark = {
    name = "High contrast (dark)", bg = { 0, 0, 0, 1 }, panel = { 0, 0, 0, 1 }, sidebar = { 0, 0, 0, 1 },
    border = { 1, 1, 0, 1 }, accent = { 1, 1, 0 }, accent2 = { 0, 1, 1 },
    text = { 1, 1, 1 }, muted = { 0.88, 0.88, 0.88 }, heading = { 1, 1, 0 },
    good = { 0.2, 1, 0.2 }, warn = { 1, 0.65, 0 }, bad = { 1, 0.35, 0.35 },
    hover = { 1, 1, 1, 0.18 }, select = { 1, 1, 0, 0.30 }, bar = { 0.35, 0.35, 0.35, 1 }, size = 2, outline = true,
  },
  hclight = {
    name = "High contrast (light)", bg = { 1, 1, 1, 1 }, panel = { 1, 1, 1, 1 }, sidebar = { 1, 1, 1, 1 },
    border = { 0, 0, 0, 1 }, accent = { 0, 0, 0.75 }, accent2 = { 0.45, 0, 0.55 },
    text = { 0, 0, 0 }, muted = { 0.15, 0.15, 0.15 }, heading = { 0, 0, 0.70 },
    good = { 0, 0.42, 0 }, warn = { 0.55, 0.28, 0 }, bad = { 0.72, 0, 0 },
    hover = { 0, 0, 0, 0.12 }, select = { 0, 0, 0.75, 0.22 }, bar = { 0.75, 0.75, 0.75, 1 }, size = 2,
  },
}

local FONT = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local WHITE = "Interface\\Buttons\\WHITE8x8"
local listeners = {}
-- everything styled so far, restyled when the theme changes (weak, so hidden pools don't leak)
local reg = { skin = setmetatable({}, { __mode = "k" }), font = setmetatable({}, { __mode = "k" }),
  button = setmetatable({}, { __mode = "k" }), toggle = setmetatable({}, { __mode = "k" }), gradient = setmetatable({}, { __mode = "k" }) }

function T:Restyle()
  for f in pairs(reg.skin) do self:Skin(f, f.wgaBgKey, f.wgaBorderKey) end
  for fs in pairs(reg.font) do self:Font(fs, fs.wgaSize, fs.wgaColor, fs.wgaFlags) end
  for tex in pairs(reg.gradient) do self:Gradient(tex) end
  for b in pairs(reg.button) do self:PaintButton(b) end
  for b in pairs(reg.toggle) do b:Refresh() end
  for _, fn in ipairs(listeners) do pcall(fn, self:Get()) end
end

function T:Key() return (CM.db and CM.db.settings.theme) or "dark" end
function T:Get() return self.palettes[self:Key()] or self.palettes.dark end
function T:C(key) return unpack(self:Get()[key]) end

function T:Hex(key)
  local c = self:Get()[key]
  return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Older text uses fixed colour codes; map them onto the theme so light mode stays readable.
function T:Recolor(s)
  if not s then return s end
  return (s:gsub("|cff(%x%x%x%x%x%x)", function(code)
    code = code:lower()
    if code == "ffd100" then return self:Hex("heading")
    elseif code == "808080" or code == "aaaaaa" then return self:Hex("muted")
    elseif code == "ffffff" then return self:Hex("text")
    elseif code == "00ff00" or code == "40ff40" then return self:Hex("good")
    elseif code == "ff8000" then return self:Hex("warn")
    elseif code == "ff6060" then return self:Hex("bad") end
  end))
end

function T:Set(key)
  if not self.palettes[key] then
    CM:Print("Themes: %s", table.concat(self.order, ", "))
    return
  end
  CM.db.settings.theme = key
  self:Restyle()
  CM:Print("Theme: %s", self:Get().name)
end

function T:Cycle()
  local cur, nextKey = self:Key(), self.order[1]
  for i, k in ipairs(self.order) do if k == cur then nextKey = self.order[i % #self.order + 1] end end
  self:Set(nextKey)
end

function T:OnChange(fn) table.insert(listeners, fn) end

-- Flat background + 1px border built from plain textures (no template needed).
function T:Skin(frame, bgKey, borderKey)
  if not frame.wgaBg then
    frame.wgaBg = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
    frame.wgaBg:SetAllPoints()
    frame.wgaEdges = {}
    for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
      local e = frame:CreateTexture(nil, "BORDER", nil, 7)
      e:SetTexture(WHITE)
      e:SetPoint(pts[1]); e:SetPoint(pts[2])
      if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
      frame.wgaEdges[i] = e
    end
  end
  frame.wgaBgKey, frame.wgaBorderKey = bgKey or "bg", borderKey
  reg.skin[frame] = true
  local p = self:Get()
  local bg = p[frame.wgaBgKey]
  frame.wgaBg:SetColorTexture(bg[1], bg[2], bg[3], bg[4] or 1)
  for _, e in ipairs(frame.wgaEdges) do
    if borderKey then
      local c = p[borderKey]
      e:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
      e:Show()
    else
      e:Hide()
    end
  end
end

-- Cyan -> purple accent line, the WGA colours.
function T:Gradient(tex)
  local p = self:Get()
  reg.gradient[tex] = true
  tex:SetTexture(WHITE)
  local ok = pcall(function()
    tex:SetGradient("HORIZONTAL", CreateColor(p.accent[1], p.accent[2], p.accent[3], 1), CreateColor(p.accent2[1], p.accent2[2], p.accent2[3], 1))
  end)
  if not ok then tex:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 1) end
end

-- Themed font: size grows and gains an outline in high contrast modes.
function T:Font(fs, size, colorKey, flags)
  local p = self:Get()
  fs.wgaSize, fs.wgaColor, fs.wgaFlags = size, colorKey or fs.wgaColor or "text", flags
  reg.font[fs] = true
  local scale = CM.db and CM.db.settings.fontScale or 1
  fs:SetFont(FONT, math.floor((size + (p.size or 0)) * scale + 0.5), flags or (p.outline and "OUTLINE" or ""))
  local c = p[fs.wgaColor]
  fs:SetTextColor(c[1], c[2], c[3], 1)
  fs:SetShadowOffset(p.outline and 0 or 1, p.outline and 0 or -1)
  fs:SetShadowColor(0, 0, 0, (self:Key() == "dark") and 0.8 or 0)
end

function T:Text(parent, size, colorKey, layer)
  local fs = parent:CreateFontString(nil, layer or "OVERLAY")
  self:Font(fs, size, colorKey)
  fs:SetJustifyH("LEFT")
  return fs
end

-- Flat button with hover and selected states.
function T:Button(parent, label, size, onClick)
  local b = CreateFrame("Button", nil, parent)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetTexture(WHITE)
  b.text = self:Text(b, size or 12, "text")
  b.text:SetPoint("LEFT", 10, 0)
  b.text:SetText(label or "")
  b:SetScript("OnEnter", function(s) s.hover = true; T:PaintButton(s) end)
  b:SetScript("OnLeave", function(s) s.hover = false; T:PaintButton(s) end)
  if onClick then b:SetScript("OnClick", onClick) end
  self:PaintButton(b)
  return b
end

function T:PaintButton(b)
  reg.button[b] = true
  local p = self:Get()
  if b.primary then -- filled accent button
    local a = b.hover and p.accent2 or p.accent
    b.bg:SetVertexColor(a[1], a[2], a[3], 1); b.bg:Show()
    self:Font(b.text, b.text.wgaSize or 12, (self:Key() == "light" or self:Key() == "hclight") and "panel" or "bg")
    return
  end
  local c = (b.selected and p.select) or (b.hover and p.hover) or nil
  if c then b.bg:SetVertexColor(c[1], c[2], c[3], c[4]); b.bg:Show() else b.bg:Hide() end
  if b.bar then
    b.bar:SetShown(b.selected and true or false)
    b.bar:SetVertexColor(p.accent[1], p.accent[2], p.accent[3], 1)
  end
  self:Font(b.text, b.text.wgaSize or 12, b.selected and "heading" or (b.textKey or "text"))
end

-- Toggle row: a small switch + label, bound to a setting.
function T:Toggle(parent, label, get, set)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(24)
  b.box = b:CreateTexture(nil, "ARTWORK")
  b.box:SetSize(30, 14)
  b.box:SetPoint("LEFT", 2, 0)
  b.box:SetTexture(WHITE)
  b.knob = b:CreateTexture(nil, "OVERLAY")
  b.knob:SetSize(10, 10)
  b.knob:SetTexture(WHITE)
  b.text = self:Text(b, 12, "text")
  b.text:SetPoint("LEFT", b.box, "RIGHT", 10, 0)
  b.text:SetText(label)
  function b:Refresh()
    local p, on = T:Get(), get()
    local c = on and p.accent or p.bar
    self.box:SetVertexColor(c[1], c[2], c[3], 1)
    self.knob:ClearAllPoints()
    self.knob:SetPoint(on and "RIGHT" or "LEFT", self.box, on and "RIGHT" or "LEFT", on and -2 or 2, 0)
    local k = on and p.bg or p.muted
    self.knob:SetVertexColor(k[1], k[2], k[3], 1)
    T:Font(self.text, 12, "text")
  end
  b:SetScript("OnClick", function(s) set(not get()); s:Refresh() end)
  reg.toggle[b] = true
  b:Refresh()
  return b
end
