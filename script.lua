--[[
    Self-contained UI Library — full visual match to the supplied design
    Components: Toggle (with optional Keybind / Colorpicker / Settings chip),
                Button, Slider, Textbox, Dropdown (single + multi), Keybind, Label
    Smooth tweens on every interaction · self-contained · live example below
--]]

--// ============================================================
--// Services
--// ============================================================
local CoreGui          = game:GetService("CoreGui")
local UserInputService = game:GetService("UserInputService")
local TweenService     = game:GetService("TweenService")
local RunService       = game:GetService("RunService")
local Players          = game:GetService("Players")
local GuiService       = game:GetService("GuiService")
local HttpService      = game:GetService("HttpService")
local LocalPlayer      = Players.LocalPlayer

if getgenv and getgenv().UILibrary then
    pcall(function() getgenv().UILibrary:Unload() end)
end

local Library = {}
Library.__index = Library
if getgenv then getgenv().UILibrary = Library end

--// ============================================================
--// Theme tokens (matched to the supplied design)
--// ============================================================
local Theme = {
    Background    = Color3.fromRGB(5, 7, 9),       -- main page bg
    BgDark        = Color3.fromRGB(11, 13, 15),    -- section bg
    BgHeader      = Color3.fromRGB(21, 25, 30),    -- section header + component bg
    BgSearch      = Color3.fromRGB(13, 15, 19),    -- header search
    Accent        = Color3.fromRGB(10, 157, 255),
    Text          = Color3.fromRGB(255, 255, 255),
    TextInactive  = Color3.fromRGB(132, 132, 132),
    TextDisabled  = Color3.fromRGB(103, 103, 104),
    TextDim       = Color3.fromRGB(66, 68, 86),
    TextSub       = Color3.fromRGB(70, 73, 81),
    TextPH        = Color3.fromRGB(178, 178, 178),
    Stroke        = Color3.fromRGB(27, 27, 27),
    CheckIcon     = Color3.fromRGB(21, 21, 23),    -- dark check inside on-toggle
    Hover         = Color3.fromRGB(28, 32, 38),    -- bg under cursor on toggle/btn/slider/dropdown
    Selected      = Color3.fromRGB(31, 37, 44),    -- bg on selected dropdown option
}

-- Theme subscription system — lets widgets live-update when a theme color
-- changes. subscribeTheme(key, fn) registers a callback that fires once
-- immediately with the current value and again whenever Library:SetTheme
-- is called for that key. themed(inst, prop, key) is the common shortcut.
local themeSubs = {}

local function subscribeTheme(key, fn)
    themeSubs[key] = themeSubs[key] or {}
    table.insert(themeSubs[key], fn)
    pcall(fn, Theme[key])
end

local function themed(inst, prop, key)
    subscribeTheme(key, function(value)
        pcall(function() inst[prop] = value end)
    end)
end

-- Wire a UIGradient's Color to a theme key. Needs special handling because
-- UIGradient.Color is a ColorSequence, not a Color3 — has to be rebuilt.
local function themedGradient(grad, key)
    subscribeTheme(key, function(value)
        pcall(function() grad.Color = ColorSequence.new(value) end)
    end)
end

function Library:SetTheme(key, value)
    Theme[key] = value
    local subs = themeSubs[key]
    if subs then
        for _, fn in ipairs(subs) do pcall(fn, value) end
    end
end

Library.Theme = Theme
Library.Flags = {}
Library.MenuKeybind = Enum.KeyCode.RightControl
Library.Windows = {}
Library._connections = {}

-- Config persistence (samet-style). Folders auto-created on load; SetFlags
-- is a per-flag setter registry — each component populates it when it
-- builds (Library.SetFlags[flag] = function(value) component:Set(value) end)
-- so LoadConfig can re-apply a saved value without knowing the component
-- type. Override Library.Folders BEFORE loading the lib if you want a
-- different on-disk layout (e.g. per-game configs).
Library.Folders = {
    Directory = "SametLib",
    Configs   = "SametLib/Configs",
}
Library.SetFlags = {}

-- File-IO helpers — gracefully no-op in environments without the exploit
-- file APIs (e.g. Studio). Wrap in pcall so a missing function or
-- permission error never breaks the lib's load path. Reference globals
-- directly — in Luau, undefined globals resolve to nil rather than
-- erroring, which makes the simple form safe.
do
    local function safe(fn)
        if type(fn) ~= "function" then return function() return false end end
        return function(...)
            local ok, result = pcall(fn, ...)
            if not ok then return false end
            return result
        end
    end
    Library._isfolder   = safe(isfolder)
    Library._makefolder = safe(makefolder)
    Library._isfile     = safe(isfile)
    Library._readfile   = safe(readfile)
    Library._writefile  = safe(writefile)
    Library._delfile    = safe(delfile)
    Library._listfiles  = safe(listfiles)

    for _, path in pairs(Library.Folders) do
        if not Library._isfolder(path) then Library._makefolder(path) end
    end
end

-- Bundled theme presets. Each is a full Theme snapshot — swapping a preset
-- swaps ALL the slots in one go (via Library:ApplyTheme), so changes stay
-- coherent (e.g. light mode flips backgrounds AND text AND stroke together,
-- not just one slot at a time). Users can register their own via
-- Library:RegisterThemePreset(name, data).
local ThemePresets = {
    Dark = {
        Background    = Color3.fromRGB(5, 7, 9),
        BgDark        = Color3.fromRGB(11, 13, 15),
        BgHeader      = Color3.fromRGB(21, 25, 30),
        BgSearch      = Color3.fromRGB(13, 15, 19),
        Accent        = Color3.fromRGB(10, 157, 255),
        Text          = Color3.fromRGB(255, 255, 255),
        TextInactive  = Color3.fromRGB(132, 132, 132),
        TextDisabled  = Color3.fromRGB(103, 103, 104),
        TextDim       = Color3.fromRGB(66, 68, 86),
        TextSub       = Color3.fromRGB(70, 73, 81),
        TextPH        = Color3.fromRGB(178, 178, 178),
        Stroke        = Color3.fromRGB(27, 27, 27),
        CheckIcon     = Color3.fromRGB(21, 21, 23),
        Hover         = Color3.fromRGB(28, 32, 38),
        Selected      = Color3.fromRGB(31, 37, 44),
    },
    Light = {
        Background    = Color3.fromRGB(250, 250, 252),
        BgDark        = Color3.fromRGB(255, 255, 255),
        BgHeader      = Color3.fromRGB(238, 240, 244),
        BgSearch      = Color3.fromRGB(245, 246, 250),
        Accent        = Color3.fromRGB(0, 122, 255),
        Text          = Color3.fromRGB(25, 28, 35),
        TextInactive  = Color3.fromRGB(125, 130, 140),
        TextDisabled  = Color3.fromRGB(165, 170, 180),
        TextDim       = Color3.fromRGB(175, 180, 190),
        TextSub       = Color3.fromRGB(95, 100, 115),
        TextPH        = Color3.fromRGB(165, 170, 180),
        Stroke        = Color3.fromRGB(218, 222, 228),
        CheckIcon     = Color3.fromRGB(255, 255, 255),
        Hover         = Color3.fromRGB(228, 232, 238),
        Selected      = Color3.fromRGB(218, 222, 230),
    },
    Ocean = {
        Background    = Color3.fromRGB(6, 12, 22),
        BgDark        = Color3.fromRGB(10, 18, 32),
        BgHeader      = Color3.fromRGB(16, 28, 48),
        BgSearch      = Color3.fromRGB(8, 16, 28),
        Accent        = Color3.fromRGB(0, 220, 255),
        Text          = Color3.fromRGB(220, 235, 250),
        TextInactive  = Color3.fromRGB(110, 140, 175),
        TextDisabled  = Color3.fromRGB(75, 95, 120),
        TextDim       = Color3.fromRGB(60, 85, 115),
        TextSub       = Color3.fromRGB(90, 115, 145),
        TextPH        = Color3.fromRGB(140, 165, 190),
        Stroke        = Color3.fromRGB(25, 45, 75),
        CheckIcon     = Color3.fromRGB(8, 16, 28),
        Hover         = Color3.fromRGB(22, 38, 62),
        Selected      = Color3.fromRGB(30, 50, 80),
    },
    Sunset = {
        Background    = Color3.fromRGB(22, 10, 18),
        BgDark        = Color3.fromRGB(32, 14, 24),
        BgHeader      = Color3.fromRGB(45, 22, 35),
        BgSearch      = Color3.fromRGB(28, 12, 22),
        Accent        = Color3.fromRGB(255, 110, 85),
        Text          = Color3.fromRGB(255, 230, 220),
        TextInactive  = Color3.fromRGB(190, 145, 140),
        TextDisabled  = Color3.fromRGB(140, 100, 95),
        TextDim       = Color3.fromRGB(115, 80, 80),
        TextSub       = Color3.fromRGB(155, 115, 110),
        TextPH        = Color3.fromRGB(175, 135, 130),
        Stroke        = Color3.fromRGB(65, 30, 45),
        CheckIcon     = Color3.fromRGB(35, 15, 22),
        Hover         = Color3.fromRGB(56, 30, 44),
        Selected      = Color3.fromRGB(68, 36, 52),
    },
    Forest = {
        Background    = Color3.fromRGB(8, 16, 12),
        BgDark        = Color3.fromRGB(14, 24, 18),
        BgHeader      = Color3.fromRGB(22, 36, 28),
        BgSearch      = Color3.fromRGB(12, 22, 16),
        Accent        = Color3.fromRGB(120, 220, 110),
        Text          = Color3.fromRGB(225, 240, 220),
        TextInactive  = Color3.fromRGB(125, 160, 130),
        TextDisabled  = Color3.fromRGB(90, 115, 95),
        TextDim       = Color3.fromRGB(75, 100, 85),
        TextSub       = Color3.fromRGB(95, 125, 105),
        TextPH        = Color3.fromRGB(150, 175, 155),
        Stroke        = Color3.fromRGB(35, 55, 42),
        CheckIcon     = Color3.fromRGB(18, 28, 20),
        Hover         = Color3.fromRGB(30, 48, 38),
        Selected      = Color3.fromRGB(40, 60, 48),
    },
    Neon = {
        Background    = Color3.fromRGB(10, 8, 18),
        BgDark        = Color3.fromRGB(16, 12, 26),
        BgHeader      = Color3.fromRGB(26, 20, 40),
        BgSearch      = Color3.fromRGB(14, 10, 22),
        Accent        = Color3.fromRGB(220, 80, 255),
        Text          = Color3.fromRGB(240, 230, 255),
        TextInactive  = Color3.fromRGB(150, 130, 180),
        TextDisabled  = Color3.fromRGB(110, 95, 135),
        TextDim       = Color3.fromRGB(95, 80, 115),
        TextSub       = Color3.fromRGB(115, 100, 140),
        TextPH        = Color3.fromRGB(170, 150, 195),
        Stroke        = Color3.fromRGB(45, 30, 65),
        CheckIcon     = Color3.fromRGB(20, 14, 30),
        Hover         = Color3.fromRGB(34, 26, 52),
        Selected      = Color3.fromRGB(44, 34, 64),
    },
    Mocha = {
        Background    = Color3.fromRGB(20, 16, 14),
        BgDark        = Color3.fromRGB(28, 22, 20),
        BgHeader      = Color3.fromRGB(40, 32, 28),
        BgSearch      = Color3.fromRGB(24, 18, 16),
        Accent        = Color3.fromRGB(210, 165, 110),
        Text          = Color3.fromRGB(245, 235, 220),
        TextInactive  = Color3.fromRGB(160, 145, 130),
        TextDisabled  = Color3.fromRGB(120, 105, 95),
        TextDim       = Color3.fromRGB(100, 90, 80),
        TextSub       = Color3.fromRGB(130, 115, 100),
        TextPH        = Color3.fromRGB(170, 155, 140),
        Stroke        = Color3.fromRGB(55, 45, 38),
        CheckIcon     = Color3.fromRGB(30, 22, 18),
        Hover         = Color3.fromRGB(50, 40, 34),
        Selected      = Color3.fromRGB(60, 48, 40),
    },
    Halloween = {
        Background    = Color3.fromRGB(14, 8, 16),
        BgDark        = Color3.fromRGB(20, 12, 22),
        BgHeader      = Color3.fromRGB(32, 18, 36),
        BgSearch      = Color3.fromRGB(16, 10, 20),
        Accent        = Color3.fromRGB(255, 125, 25),
        Text          = Color3.fromRGB(255, 230, 200),
        TextInactive  = Color3.fromRGB(180, 140, 120),
        TextDisabled  = Color3.fromRGB(125, 95, 85),
        TextDim       = Color3.fromRGB(95, 70, 85),
        TextSub       = Color3.fromRGB(140, 105, 115),
        TextPH        = Color3.fromRGB(190, 150, 140),
        Stroke        = Color3.fromRGB(58, 30, 58),
        CheckIcon     = Color3.fromRGB(25, 12, 22),
        Hover         = Color3.fromRGB(45, 25, 50),
        Selected      = Color3.fromRGB(58, 32, 62),
    },
    Cyberpunk = {
        Background    = Color3.fromRGB(8, 6, 18),
        BgDark        = Color3.fromRGB(14, 10, 24),
        BgHeader      = Color3.fromRGB(24, 18, 40),
        BgSearch      = Color3.fromRGB(12, 8, 22),
        Accent        = Color3.fromRGB(255, 50, 200),
        Text          = Color3.fromRGB(220, 240, 255),
        TextInactive  = Color3.fromRGB(140, 155, 200),
        TextDisabled  = Color3.fromRGB(95, 110, 145),
        TextDim       = Color3.fromRGB(75, 90, 125),
        TextSub       = Color3.fromRGB(115, 135, 175),
        TextPH        = Color3.fromRGB(160, 175, 215),
        Stroke        = Color3.fromRGB(48, 30, 80),
        CheckIcon     = Color3.fromRGB(15, 10, 25),
        Hover         = Color3.fromRGB(32, 24, 52),
        Selected      = Color3.fromRGB(42, 32, 65),
    },
    Vampire = {
        Background    = Color3.fromRGB(12, 5, 8),
        BgDark        = Color3.fromRGB(20, 8, 12),
        BgHeader      = Color3.fromRGB(32, 14, 20),
        BgSearch      = Color3.fromRGB(14, 6, 10),
        Accent        = Color3.fromRGB(200, 35, 60),
        Text          = Color3.fromRGB(250, 230, 230),
        TextInactive  = Color3.fromRGB(170, 130, 130),
        TextDisabled  = Color3.fromRGB(120, 90, 95),
        TextDim       = Color3.fromRGB(95, 70, 78),
        TextSub       = Color3.fromRGB(135, 100, 110),
        TextPH        = Color3.fromRGB(180, 145, 150),
        Stroke        = Color3.fromRGB(55, 22, 30),
        CheckIcon     = Color3.fromRGB(25, 8, 14),
        Hover         = Color3.fromRGB(42, 18, 28),
        Selected      = Color3.fromRGB(55, 24, 36),
    },
    Solar = {
        Background    = Color3.fromRGB(16, 12, 5),
        BgDark        = Color3.fromRGB(24, 18, 10),
        BgHeader      = Color3.fromRGB(38, 28, 15),
        BgSearch      = Color3.fromRGB(20, 14, 8),
        Accent        = Color3.fromRGB(255, 185, 50),
        Text          = Color3.fromRGB(255, 245, 220),
        TextInactive  = Color3.fromRGB(180, 160, 120),
        TextDisabled  = Color3.fromRGB(130, 115, 85),
        TextDim       = Color3.fromRGB(105, 95, 70),
        TextSub       = Color3.fromRGB(145, 130, 100),
        TextPH        = Color3.fromRGB(190, 170, 130),
        Stroke        = Color3.fromRGB(60, 42, 18),
        CheckIcon     = Color3.fromRGB(30, 22, 10),
        Hover         = Color3.fromRGB(48, 36, 18),
        Selected      = Color3.fromRGB(60, 46, 24),
    },
    Inferno = {
        Background    = Color3.fromRGB(16, 6, 4),
        BgDark        = Color3.fromRGB(24, 10, 6),
        BgHeader      = Color3.fromRGB(40, 18, 12),
        BgSearch      = Color3.fromRGB(20, 8, 5),
        Accent        = Color3.fromRGB(255, 90, 40),
        Text          = Color3.fromRGB(255, 235, 220),
        TextInactive  = Color3.fromRGB(185, 140, 125),
        TextDisabled  = Color3.fromRGB(135, 100, 90),
        TextDim       = Color3.fromRGB(108, 78, 72),
        TextSub       = Color3.fromRGB(145, 110, 100),
        TextPH        = Color3.fromRGB(190, 152, 140),
        Stroke        = Color3.fromRGB(62, 28, 18),
        CheckIcon     = Color3.fromRGB(28, 12, 8),
        Hover         = Color3.fromRGB(52, 22, 14),
        Selected      = Color3.fromRGB(64, 30, 20),
    },
    Phantom = {
        Background    = Color3.fromRGB(10, 8, 18),
        BgDark        = Color3.fromRGB(16, 14, 28),
        BgHeader      = Color3.fromRGB(26, 22, 44),
        BgSearch      = Color3.fromRGB(14, 12, 24),
        Accent        = Color3.fromRGB(170, 130, 255),
        Text          = Color3.fromRGB(240, 235, 255),
        TextInactive  = Color3.fromRGB(160, 150, 200),
        TextDisabled  = Color3.fromRGB(120, 110, 155),
        TextDim       = Color3.fromRGB(100, 90, 130),
        TextSub       = Color3.fromRGB(130, 120, 165),
        TextPH        = Color3.fromRGB(175, 165, 215),
        Stroke        = Color3.fromRGB(52, 42, 82),
        CheckIcon     = Color3.fromRGB(20, 16, 32),
        Hover         = Color3.fromRGB(38, 32, 62),
        Selected      = Color3.fromRGB(50, 42, 75),
    },
    Frost = {
        Background    = Color3.fromRGB(10, 14, 18),
        BgDark        = Color3.fromRGB(16, 22, 28),
        BgHeader      = Color3.fromRGB(28, 38, 48),
        BgSearch      = Color3.fromRGB(14, 20, 24),
        Accent        = Color3.fromRGB(130, 220, 255),
        Text          = Color3.fromRGB(230, 245, 255),
        TextInactive  = Color3.fromRGB(150, 175, 195),
        TextDisabled  = Color3.fromRGB(105, 125, 145),
        TextDim       = Color3.fromRGB(85, 105, 125),
        TextSub       = Color3.fromRGB(115, 140, 160),
        TextPH        = Color3.fromRGB(170, 195, 215),
        Stroke        = Color3.fromRGB(45, 65, 80),
        CheckIcon     = Color3.fromRGB(15, 22, 30),
        Hover         = Color3.fromRGB(36, 50, 62),
        Selected      = Color3.fromRGB(46, 62, 78),
    },
    Toxic = {
        Background    = Color3.fromRGB(8, 12, 6),
        BgDark        = Color3.fromRGB(14, 20, 10),
        BgHeader      = Color3.fromRGB(22, 32, 18),
        BgSearch      = Color3.fromRGB(12, 16, 8),
        Accent        = Color3.fromRGB(180, 255, 30),
        Text          = Color3.fromRGB(230, 250, 220),
        TextInactive  = Color3.fromRGB(140, 165, 125),
        TextDisabled  = Color3.fromRGB(105, 125, 95),
        TextDim       = Color3.fromRGB(85, 105, 80),
        TextSub       = Color3.fromRGB(115, 135, 100),
        TextPH        = Color3.fromRGB(160, 180, 145),
        Stroke        = Color3.fromRGB(40, 58, 28),
        CheckIcon     = Color3.fromRGB(18, 26, 12),
        Hover         = Color3.fromRGB(32, 44, 22),
        Selected      = Color3.fromRGB(42, 56, 30),
    },
    Twilight = {
        Background    = Color3.fromRGB(14, 10, 22),
        BgDark        = Color3.fromRGB(22, 16, 32),
        BgHeader      = Color3.fromRGB(36, 26, 50),
        BgSearch      = Color3.fromRGB(18, 12, 26),
        Accent        = Color3.fromRGB(255, 130, 200),
        Text          = Color3.fromRGB(245, 235, 250),
        TextInactive  = Color3.fromRGB(170, 150, 185),
        TextDisabled  = Color3.fromRGB(125, 110, 145),
        TextDim       = Color3.fromRGB(100, 88, 120),
        TextSub       = Color3.fromRGB(135, 115, 150),
        TextPH        = Color3.fromRGB(180, 160, 195),
        Stroke        = Color3.fromRGB(58, 38, 80),
        CheckIcon     = Color3.fromRGB(22, 16, 32),
        Hover         = Color3.fromRGB(46, 32, 62),
        Selected      = Color3.fromRGB(58, 40, 76),
    },
    Obsidian = {
        Background    = Color3.fromRGB(3, 3, 5),
        BgDark        = Color3.fromRGB(8, 8, 12),
        BgHeader      = Color3.fromRGB(18, 18, 24),
        BgSearch      = Color3.fromRGB(6, 6, 10),
        Accent        = Color3.fromRGB(130, 180, 255),
        Text          = Color3.fromRGB(240, 240, 245),
        TextInactive  = Color3.fromRGB(125, 125, 140),
        TextDisabled  = Color3.fromRGB(90, 90, 100),
        TextDim       = Color3.fromRGB(70, 70, 85),
        TextSub       = Color3.fromRGB(100, 100, 120),
        TextPH        = Color3.fromRGB(160, 160, 180),
        Stroke        = Color3.fromRGB(22, 22, 32),
        CheckIcon     = Color3.fromRGB(10, 10, 15),
        Hover         = Color3.fromRGB(24, 24, 34),
        Selected      = Color3.fromRGB(32, 32, 45),
    },
}
Library.ThemePresets = ThemePresets

-- Apply a full theme table — fires SetTheme for each known key so all
-- subscribers update. Unknown keys are ignored.
function Library:ApplyTheme(themeData)
    for key, value in pairs(themeData) do
        if Theme[key] ~= nil then
            self:SetTheme(key, value)
        end
    end
end

function Library:LoadPreset(name)
    local preset = ThemePresets[name]
    if not preset then return false end
    self:ApplyTheme(preset)
    return true
end

function Library:SnapshotTheme()
    local out = {}
    for k, v in pairs(Theme) do out[k] = v end
    return out
end

function Library:RegisterThemePreset(name, data)
    ThemePresets[name] = data
end

function Library:ListThemePresets()
    local names = {}
    for k in pairs(ThemePresets) do table.insert(names, k) end
    table.sort(names)
    return names
end

-- Public alias for subscribeTheme so user code can subscribe to theme
-- changes without poking the internal helper.
function Library:OnThemeChange(key, fn)
    subscribeTheme(key, fn)
end

--// ============================================================
--// Config (samet-style save/load)
--// ============================================================
-- Values that live in Library.Flags are mostly plain JSON-friendly types
-- (bool, number, string, plain table). The two exceptions are KeyCode
-- enums and Color3 values — those get wrapped in a small tagged table on
-- serialize and unwrapped on deserialize so the round-trip is lossless.
-- Component types tag their serialized form via the __type field so we
-- never have to guess from shape.
-- EnumType.Name returns just the enum's short name (e.g. "KeyCode") in
-- modern Luau, which round-trips cleanly via Enum[Name][Item]. Avoiding
-- tostring() here because its output format isn't formally guaranteed.
local function serializeFlag(v)
    local t = typeof(v)
    if t == "EnumItem" then
        local enumName
        pcall(function() enumName = v.EnumType.Name end)
        return {__type = "EnumItem", Enum = enumName or "KeyCode", Name = v.Name}
    elseif t == "Color3" then
        return {__type = "Color3", R = v.R, G = v.G, B = v.B}
    elseif t == "Vector2" then
        return {__type = "Vector2", X = v.X, Y = v.Y}
    end
    return v
end

local function deserializeFlag(v)
    if type(v) ~= "table" then return v end
    if v.__type == "EnumItem" then
        local enumName = v.Enum or "KeyCode"
        local ok, item = pcall(function() return Enum[enumName][v.Name] end)
        if ok and item then return item end
        return nil
    elseif v.__type == "Color3" then
        return Color3.new(v.R or 0, v.G or 0, v.B or 0)
    elseif v.__type == "Vector2" then
        return Vector2.new(v.X or 0, v.Y or 0)
    end
    return v
end

-- Snapshot every registered flag into a JSON-encodable table. Returns
-- the table AND the encoded string — caller picks whichever they need.
function Library:GetConfig()
    local out = {}
    for k, v in pairs(self.Flags) do
        out[k] = serializeFlag(v)
    end
    return out, HttpService:JSONEncode(out)
end

-- Apply a config table OR a JSON string. Iterates the entries and calls
-- the matching SetFlags setter — flags whose components weren't built
-- this session are silently ignored. Returns (true, appliedCount) on
-- success, (false, error) otherwise.
function Library:LoadConfig(config)
    if type(config) == "string" then
        local ok, decoded = pcall(function() return HttpService:JSONDecode(config) end)
        if not ok then return false, decoded end
        config = decoded
    end
    if type(config) ~= "table" then return false, "expected table or JSON string" end
    local applied = 0
    for flag, raw in pairs(config) do
        local setter = self.SetFlags[flag]
        if setter then
            local value = deserializeFlag(raw)
            pcall(setter, value)
            applied = applied + 1
        end
    end
    return true, applied
end

-- File-IO wrappers. All return (true, ...) on success or (false, error)
-- on failure — including "file APIs missing" if the executor doesn't
-- expose writefile/readfile/etc.
local function configPath(name)
    return Library.Folders.Configs .. "/" .. name .. ".json"
end

function Library:SaveConfig(name)
    if not name or name == "" then return false, "name required" end
    local _, json = self:GetConfig()
    local ok = self._writefile(configPath(name), json)
    if ok == false then return false, "writefile failed" end
    return true
end

function Library:LoadConfigFile(name)
    if not name or name == "" then return false, "name required" end
    local path = configPath(name)
    if not self._isfile(path) then return false, "file not found" end
    local src = self._readfile(path)
    if not src or src == false then return false, "readfile failed" end
    return self:LoadConfig(src)
end

function Library:DeleteConfig(name)
    if not name or name == "" then return false, "name required" end
    local path = configPath(name)
    if not self._isfile(path) then return false, "file not found" end
    self._delfile(path)
    return true
end

-- Returns an array of config names (no path, no .json extension) found
-- in Library.Folders.Configs. Empty array if the dir doesn't exist or
-- listfiles isn't available in this environment.
function Library:ListConfigs()
    local out = {}
    local files = self._listfiles(self.Folders.Configs)
    if type(files) ~= "table" then return out end
    for _, file in ipairs(files) do
        if type(file) == "string" and file:sub(-5) == ".json" then
            -- Strip trailing .json AND everything up to the last path
            -- separator. Works for both / and \ separators since
            -- different executors return different paths styles.
            local name = file:sub(1, -6)
            local slash = name:find("[/\\][^/\\]*$")
            if slash then name = name:sub(slash + 1) end
            table.insert(out, name)
        end
    end
    table.sort(out)
    return out
end

-- Convenience for dropdown rebuild — pass a dropdown component built by
-- Section:AddDropdown and it'll fire :Refresh(names) with the live list.
function Library:RefreshConfigsList(element)
    if element and type(element.Refresh) == "function" then
        element:Refresh(self:ListConfigs())
    end
end

local FONT_REG = Font.new("rbxassetid://12187365364", Enum.FontWeight.Regular)
local FONT_MED = Font.new("rbxassetid://12187365364", Enum.FontWeight.Medium)
Library.Font = FONT_REG
Library.FontMedium = FONT_MED

--// ============================================================
--// Icon registry (string → assetId)
--// ============================================================
local ICONS = {
    default   = "rbxassetid://97721617837853",
    home      = "rbxassetid://97721617837853",
    sword     = "rbxassetid://93304996704818",
    crosshair = "rbxassetid://93304996704818",
    house     = "rbxassetid://130759950226435",
    settings  = "rbxassetid://94972186953281",
    cog       = "rbxassetid://100512440418335",
    flame     = "rbxassetid://93304996704818",
    eye       = "rbxassetid://130759950226435",
    shield    = "rbxassetid://93304996704818",
    user      = "rbxassetid://130759950226435",
    bolt      = "rbxassetid://93304996704818",
    search    = "rbxassetid://94972186953281",
    -- Component icons (from the supplied dump)
    check       = "rbxassetid://80408732868542",
    edit        = "rbxassetid://74579954889308",
    chevron     = "rbxassetid://135052919879796",  -- multi-dropdown icon (3-line hamburger)
    chevronDown = "rbxassetid://130094546997037",  -- single-dropdown icon
    cppattern   = "rbxassetid://70964617193772",
}

local function resolveIcon(icon)
    if not icon then return ICONS.default end
    if type(icon) ~= "string" then return ICONS.default end
    local lower = icon:lower()
    if lower:sub(1, 5) == "rbxas" or lower:sub(1, 7) == "http://" or lower:sub(1, 8) == "https://" then
        return icon
    end
    return ICONS[lower] or ICONS.default
end

function Library:RegisterIcon(name, assetId)
    ICONS[name:lower()] = assetId
end

--// ============================================================
--// Helpers
--// ============================================================
local function new(class, props)
    local inst = Instance.new(class)
    for k, v in pairs(props or {}) do inst[k] = v end
    return inst
end

local TI_SMOOTH = TweenInfo.new(0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
local TI_QUICK  = TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local TI_POP    = TweenInfo.new(0.32, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
local TI_SLIDE  = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)

local function tween(obj, props, info)
    local t = TweenService:Create(obj, info or TI_SMOOTH, props)
    t:Play()
    return t
end

local function connect(signal, callback)
    local c = signal:Connect(callback)
    table.insert(Library._connections, c)
    return c
end

--// ============================================================
--// Unload
--// ============================================================
function Library:Unload()
    for _, c in ipairs(self._connections) do pcall(function() c:Disconnect() end) end
    self._connections = {}
    for _, w in ipairs(self.Windows) do
        if w.ScreenGui then pcall(function() w.ScreenGui:Destroy() end) end
        if w.PopupGui  then pcall(function() w.PopupGui:Destroy()  end) end
        if w.Watermark and w.Watermark.Gui then
            pcall(function() w.Watermark.Gui:Destroy() end)
        end
        if w.KeybindList and w.KeybindList.Gui then
            pcall(function() w.KeybindList.Gui:Destroy() end)
        end
        if w.Notifications and w.Notifications.Gui then
            pcall(function() w.Notifications.Gui:Destroy() end)
        end
        if w.BlurController then
            pcall(function() w.BlurController:Destroy() end)
        end
    end
    self.Windows = {}
    table.clear(themeSubs)
    table.clear(self.SetFlags)
    if getgenv then getgenv().UILibrary = nil end
end

--// ============================================================
--// Section builder + settings popup (forward declared)
--// ============================================================
local createSettingsPopup
local buildSection

--// ============================================================
--// Tooltip widget — one shared instance per window, lives in the
--// PopupGui above all popups. Components register via :Tooltip(text)
--// or cfg.Tooltip; hover fires Show, leave fires Hide. The body
--// follows the cursor each RenderStepped while visible, clamped to
--// the viewport so it never spills off-screen. RichText is enabled
--// so callers can do e.g. `<font color="#0a9dff">[TAG]</font> body`.
--// ============================================================
local function createTooltip(window)
    local tooltip = new("Frame", {
        Name = "Tooltip", Parent = window.PopupGui,
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, 1, 0, 23),
        AutomaticSize = Enum.AutomaticSize.XY,
        Visible = false,
        ZIndex = 50000,
    })
    new("UICorner", {Parent = tooltip, CornerRadius = UDim.new(0, 2)})
    themed(tooltip, "BackgroundColor3", "Background")
    new("UIListLayout", {
        Parent = tooltip,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    new("UIPadding", {Parent = tooltip, PaddingRight = UDim.new(0, 12)})

    -- Icon column — 35px-wide holder with a centered 20x20 accent image.
    local iconHolder = new("Frame", {
        Name = "IconHolder", Parent = tooltip, LayoutOrder = 0,
        Size = UDim2.new(0, 35, 0, 23),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    })
    local icon = new("ImageLabel", {
        Name = "Icon", Parent = iconHolder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 20, 0, 20),
        BackgroundTransparency = 1,
        Image = "rbxassetid://97923916397585",
        ImageColor3 = Theme.Accent,
        BorderSizePixel = 0,
        ZIndex = 50001,
    })
    themed(icon, "ImageColor3", "Accent")

    -- Text column — wrapped in its own list-layout box so the label is
    -- centered vertically and the outer Tooltip's horizontal layout sees
    -- a clean atomic child.
    local textHolder = new("Frame", {
        Name = "TextHolder", Parent = tooltip, LayoutOrder = 1,
        Size = UDim2.new(0, 1, 0, 23),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
    })
    new("UIListLayout", {
        Parent = textHolder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local label = new("TextLabel", {
        Name = "Option", Parent = textHolder,
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Text = "",
        RichText = true,
        TextWrapped = true,
        TextColor3 = Theme.Text,
        FontFace = FONT_MED, TextSize = 14,
        TextXAlignment = Enum.TextXAlignment.Left,
        BorderSizePixel = 0,
        ZIndex = 50001,
    })
    themed(label, "TextColor3", "Text")
    -- Cap the label width at 320px. Combined with TextWrapped + AutomaticSize
    -- XY: short text hugs its natural width, long text caps at 320 and wraps
    -- onto multiple lines (height grows via AutomaticSize.Y).
    new("UISizeConstraint", {Parent = label, MaxSize = Vector2.new(320, math.huge)})

    local TT = {Frame = tooltip, Label = label, Icon = icon}
    local followConn

    -- Same accent-substitution pattern as the notification widget: tooltip
    -- bodies are user-supplied RichText with hardcoded `#0a9dff`. Swap that
    -- for the live accent hex on every Show, and re-render the visible
    -- tooltip when Accent changes mid-hover.
    local function colorHex(c)
        return string.format("%02x%02x%02x",
            math.floor(c.R * 255 + 0.5),
            math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5))
    end
    local function applyAccent(text)
        if not text or text == "" then return "" end
        return (text:gsub("#0a9dff", "#" .. colorHex(Theme.Accent)))
    end

    -- followCursor pins the tooltip's top-left exactly to the cursor.
    -- If the tooltip would spill off the right/bottom edge, flip it so
    -- the bottom-right edge sits on the cursor instead for that axis.
    -- GetMouseLocation() and AbsolutePosition share a coord space here
    -- (PopupGui has IgnoreGuiInset = true), so no inset adjustment needed.
    local function followCursor()
        local m = UserInputService:GetMouseLocation()
        local sz = tooltip.AbsoluteSize
        local screen = window.PopupGui.AbsoluteSize
        local x = m.X
        local y = m.Y
        if x + sz.X > screen.X - 4 then x = m.X - sz.X end
        if y + sz.Y > screen.Y - 4 then y = m.Y - sz.Y end
        tooltip.Position = UDim2.fromOffset(math.max(4, x), math.max(4, y))
    end

    function TT:Show(text)
        if not text or text == "" then return end
        self._rawText = text
        label.Text = applyAccent(text)
        followCursor()
        tooltip.Visible = true
        if followConn then followConn:Disconnect() end
        followConn = RunService.RenderStepped:Connect(followCursor)
    end

    function TT:Hide()
        tooltip.Visible = false
        if followConn then followConn:Disconnect(); followConn = nil end
    end

    -- If the user flips theme while a tooltip is visible, re-apply the
    -- substitution against the stashed raw text so the [TAG] color tracks.
    subscribeTheme("Accent", function()
        if tooltip.Visible and TT._rawText then
            pcall(function() label.Text = applyAccent(TT._rawText) end)
        end
    end)

    return TT
end

--// ============================================================
--// Watermark widget — independent ScreenGui anchored to the
--// top-left of the screen. Brand label on the left, then one
--// icon+text segment per metric (FPS / Ping / User). Each segment
--// can be individually shown/hidden via :SetSegmentVisible or
--// :SetActiveSegments. Bg follows Theme.Background, stroke follows
--// BgHeader, every icon + accent text re-renders when Accent
--// changes (RichText hex needs string rebuild, not a property tween).
--// ============================================================
local function createWatermark(window, opts)
    opts = opts or {}
    local wmGui = new("ScreenGui", {
        Name = "\0UI_Watermark",
        Parent = (gethui and gethui()) or CoreGui,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 5000,
    })

    local frame = new("Frame", {
        Name = "Watermark", Parent = wmGui,
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.new(0, 1, 0, 35),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Active = true,  -- needed so InputBegan fires on the drag handler
    })
    new("UICorner", {Parent = frame, CornerRadius = UDim.new(0, 2)})
    themed(frame, "BackgroundColor3", "Background")

    -- Draggable while the main UI is visible (so users can reposition without
    -- accidentally grabbing it during gameplay). Same offset-tracking pattern
    -- as the MainPage header drag.
    do
        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not window.Visible then return end
            dragging = true
            dragStart = input.Position
            startPos = frame.Position
        end)
        connect(UserInputService.InputChanged, function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local d = input.Position - dragStart
            frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end
    new("UIListLayout", {
        Parent = frame,
        FillDirection = Enum.FillDirection.Horizontal,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    new("UIPadding", {Parent = frame, PaddingRight = UDim.new(0, 12)})
    local wmStroke = new("UIStroke", {Parent = frame, Color = Theme.BgHeader, Thickness = 1})
    themed(wmStroke, "Color", "BgHeader")

    local WM = {
        Gui = wmGui, Frame = frame, Segments = {},
        Visible = true, _segOrder = 0, _fps = 60, _ping = 0,
    }

    -- Convert a Color3 to a 6-digit hex (no #) for embedding in RichText.
    local function colorHex(c)
        return string.format("%02x%02x%02x",
            math.floor(c.R * 255 + 0.5),
            math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5))
    end

    -- Create one [icon + text] pair as siblings under the watermark frame.
    -- `builder` is called on every refresh and returns the RichText body
    -- (so it can read current Theme.Accent + live _fps/_ping values).
    local function makeSegment(name, iconAsset, builder)
        WM._segOrder = WM._segOrder + 1
        local iconHolder = new("Frame", {
            Name = "IconHolder_" .. name, Parent = frame, LayoutOrder = WM._segOrder,
            Size = UDim2.new(0, 35, 0, 35),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        })
        local icon = new("ImageLabel", {
            Name = "Icon", Parent = iconHolder,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 20, 0, 20),
            BackgroundTransparency = 1,
            Image = iconAsset,
            ImageColor3 = Theme.Accent,
        })
        themed(icon, "ImageColor3", "Accent")

        WM._segOrder = WM._segOrder + 1
        local textHolder = new("Frame", {
            Name = "TextHolder_" .. name, Parent = frame, LayoutOrder = WM._segOrder,
            Size = UDim2.new(0, 35, 0, 35),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1, BorderSizePixel = 0,
        })
        new("UIListLayout", {
            Parent = textHolder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        local label = new("TextLabel", {
            Name = "Option", Parent = textHolder,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            RichText = true, Text = "",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
        })
        themed(label, "TextColor3", "Text")

        WM.Segments[name] = {
            Name = name,
            IconHolder = iconHolder, TextHolder = textHolder,
            Icon = icon, Label = label,
            Build = builder, Visible = true,
        }
    end

    -- Brand text builder — splits the name on the first space or period
    -- and renders the leading part (including the separator) in accent
    -- color, the trailing part plain. So "LUMIE.WTF" → "LUMIE." accent +
    -- "WTF" plain; "ENI Hub" → "ENI " accent + "Hub" plain; a single
    -- word like "ENI" goes entirely in accent.
    WM._brandName = opts.name or "Brand"
    WM._brandIcon = opts.icon or "rbxassetid://133489527524318"
    local function buildBrand()
        local name = WM._brandName or ""
        local accentHex = colorHex(Theme.Accent)
        local sepStart, sepEnd = name:find("[%. ]")
        if sepStart then
            local head = name:sub(1, sepEnd)
            local tail = name:sub(sepEnd + 1)
            return string.format('<font color="#%s">%s</font>%s', accentHex, head, tail)
        end
        return string.format('<font color="#%s">%s</font>', accentHex, name)
    end

    -- Segment definitions match the supplied dump's icons + text format.
    makeSegment("Logo", WM._brandIcon, buildBrand)
    makeSegment("FPS", "rbxassetid://131275369407636", function()
        return string.format('fps <font color="#%s">%d</font>',
            colorHex(Theme.Accent), math.floor((WM._fps or 0) + 0.5))
    end)
    makeSegment("Ping", "rbxassetid://111743581572887", function()
        return string.format('ping <font color="#%s">%dms</font>',
            colorHex(Theme.Accent), math.floor((WM._ping or 0) + 0.5))
    end)
    makeSegment("User", "rbxassetid://135381388397413", function()
        local n = (LocalPlayer and LocalPlayer.Name) or "Unknown"
        return string.format('user <font color="#%s">%s</font>', colorHex(Theme.Accent), n)
    end)

    function WM:Refresh()
        for _, seg in pairs(self.Segments) do
            if seg.Visible and seg.Build then
                pcall(function() seg.Label.Text = seg.Build() end)
            end
        end
    end

    function WM:SetVisible(v)
        self.Visible = v and true or false
        self.Frame.Visible = self.Visible
    end

    function WM:SetSegmentVisible(name, v)
        local seg = self.Segments[name]
        if not seg then return end
        seg.Visible = v and true or false
        seg.IconHolder.Visible = seg.Visible
        seg.TextHolder.Visible = seg.Visible
    end

    -- Accepts either an array of names {"FPS","Ping"} or a map form
    -- {FPS=true,Ping=true} (which is what the multi-dropdown produces).
    function WM:SetActiveSegments(picked)
        local set = {}
        if type(picked) == "table" then
            for k, v in pairs(picked) do
                if type(v) == "boolean" then
                    if v then set[k] = true end
                else
                    set[v] = true
                end
            end
        end
        for name in pairs(self.Segments) do
            self:SetSegmentVisible(name, set[name] == true)
        end
    end

    -- Live FPS via exponential moving average (raw 1/dt is jittery).
    -- Ping via Player:GetNetworkPing() — returns seconds, *1000 for ms.
    local fpsAvg = 60
    connect(RunService.RenderStepped, function(dt)
        fpsAvg = fpsAvg * 0.9 + (1 / math.max(dt, 1e-6)) * 0.1
        WM._fps = fpsAvg
        if LocalPlayer then
            local ok, p = pcall(function() return LocalPlayer:GetNetworkPing() end)
            WM._ping = ok and (p * 1000) or 0
        end
        if WM.Visible then WM:Refresh() end
    end)

    -- Accent change → rebuild every label so the embedded hex updates.
    subscribeTheme("Accent", function() WM:Refresh() end)

    -- Runtime brand customization. SetName rebuilds the Logo segment's
    -- text via the brand builder (smart split on first space/period).
    -- SetIcon swaps the asset on the Logo segment's ImageLabel directly.
    function WM:SetName(name)
        self._brandName = name or ""
        self:Refresh()
    end

    function WM:SetIcon(icon)
        local resolved = resolveIcon(icon)
        self._brandIcon = resolved
        local seg = self.Segments and self.Segments.Logo
        if seg and seg.Icon then seg.Icon.Image = resolved end
    end

    WM:Refresh()
    return WM
end

--// ============================================================
--// Keybind list widget — top-right floating panel listing active
--// bindings. Each row: name + Hold/Toggle mode badge + key badge.
--// Spring-loaded entrance and choreographed exit. Bg follows
--// BgDark, stroke follows BgHeader, mode badge bg follows Accent,
--// key badge bg follows BgHeader. Components opt in by passing
--// ShowInList = true (and optional Mode = "Hold"/"Toggle") to
--// their keybind cfg; the component then keeps the list synced
--// with its current Key as the user rebinds.
--// ============================================================
local function createKeybindList(window)
    local gui = new("ScreenGui", {
        Name = "\0UI_Keybinds",
        Parent = (gethui and gethui()) or CoreGui,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 4000,
    })

    -- Hidden measure labels — `AutomaticSize` only resolves AFTER the next
    -- Heartbeat, so we set Text then yield once to read AbsoluteSize.X.
    local measure = new("TextLabel", {
        Parent = gui, FontFace = FONT_MED, TextSize = 14,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, 20),
        BackgroundTransparency = 1, Visible = false,
    })
    local badgeMeasure = new("TextLabel", {
        Parent = gui, FontFace = FONT_MED, TextSize = 13,
        AutomaticSize = Enum.AutomaticSize.X,
        Size = UDim2.new(0, 0, 0, 20),
        BackgroundTransparency = 1, Visible = false,
    })

    local function textWidth(s)
        measure.Text = s
        RunService.Heartbeat:Wait()
        return measure.AbsoluteSize.X
    end
    local function badgeWidth(s)
        badgeMeasure.Text = s
        RunService.Heartbeat:Wait()
        return badgeMeasure.AbsoluteSize.X + 10  -- 5px L+R padding
    end

    -- Container
    local box = new("Frame", {
        Name = "KeybindOptions", Parent = gui,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -14, 0.22, 0),
        BackgroundColor3 = Theme.BgDark,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.new(0, 185, 0, 35),
        Active = true,  -- needed so InputBegan fires on the drag handler
    })
    new("UICorner", {Parent = box, CornerRadius = UDim.new(0, 4)})
    themed(box, "BackgroundColor3", "BgDark")
    local boxStroke = new("UIStroke", {Parent = box, Color = Theme.BgHeader, Thickness = 1})
    themed(boxStroke, "Color", "BgHeader")

    -- Draggable while the main UI is visible. Preserves the (1, -X, 0.22, 0)
    -- mixed scale/offset layout — only the offsets get updated per drag delta.
    do
        local dragging, dragStart, startPos
        box.InputBegan:Connect(function(input)
            if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
            if not window.Visible then return end
            dragging = true
            dragStart = input.Position
            startPos = box.Position
        end)
        connect(UserInputService.InputChanged, function(input)
            if not dragging then return end
            if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
            local d = input.Position - dragStart
            box.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + d.X,
                startPos.Y.Scale, startPos.Y.Offset + d.Y
            )
        end)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    local inner = new("Frame", {
        Name = "Inner", Parent = box,
        Size = UDim2.new(1, 0, 0, 9999),
        BackgroundTransparency = 1,
    })
    new("UIListLayout", {
        Parent = inner,
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding = UDim.new(0, 4),
    })

    -- Header
    local hdr = new("Frame", {
        Name = "Header", Parent = inner,
        Size = UDim2.new(1, 0, 0, 35),
        BackgroundColor3 = Theme.BgDark,
        BorderSizePixel = 0, LayoutOrder = 0,
    })
    themed(hdr, "BackgroundColor3", "BgDark")
    new("UIListLayout", {
        Parent = hdr,
        FillDirection = Enum.FillDirection.Horizontal,
        VerticalAlignment = Enum.VerticalAlignment.Center,
    })
    local hdrIcon = new("Frame", {
        Parent = hdr, LayoutOrder = 0,
        Size = UDim2.new(0, 35, 0, 35),
        BackgroundTransparency = 1,
    })
    local hdrImg = new("ImageLabel", {
        Parent = hdrIcon,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 15, 0, 15),
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        Image = "rbxassetid://79554098175447",
        ScaleType = Enum.ScaleType.Fit,
    })
    themed(hdrImg, "ImageColor3", "Accent")
    local hdrTextWrap = new("Frame", {
        Parent = hdr, LayoutOrder = 1,
        Size = UDim2.new(0, 1, 0, 35),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
    })
    local hdrText = new("TextLabel", {
        Parent = hdrTextWrap,
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundTransparency = 1,
        Text = "Keybinds",
        TextColor3 = Theme.Text,
        FontFace = FONT_MED, TextSize = 14,
    })
    themed(hdrText, "TextColor3", "Text")

    local KL = {Gui = gui, Frame = box, _binds = {}, _seq = 0}

    local function calcWidth()
        local mx = 185
        for _, b in pairs(KL._binds) do
            local w = 12 + b._nameW + 16 + b._modeW + 6 + b._keyW + 12
            if w > mx then mx = w end
        end
        return math.min(mx, 340)
    end
    local function calcHeight()
        local n = 0
        for _ in pairs(KL._binds) do n = n + 1 end
        if n == 0 then return 35 end
        return 35 + 4 + n * 35 + (n - 1) * 4
    end
    local function resize()
        tween(box, {Size = UDim2.new(0, calcWidth(), 0, calcHeight())},
            TweenInfo.new(0.42, Enum.EasingStyle.Quint, Enum.EasingDirection.Out))
    end

    -- Badge factory — pass themeKey to wire bg to a theme slot.
    local function makeBadge(parent, text, bgTrans, ord, themeKey)
        local b = new("TextLabel", {
            Parent = parent,
            FontFace = FONT_MED, TextColor3 = Theme.Text, TextSize = 13,
            Text = text, AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.new(0, 0, 0, 0),
            BackgroundColor3 = themeKey and Theme[themeKey] or Theme.BgHeader,
            BackgroundTransparency = bgTrans,
            BorderSizePixel = 0, LayoutOrder = ord or 0,
            TextTransparency = 1,
        })
        new("UIPadding", {Parent = b,
            PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5),
            PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5)})
        new("UICorner", {Parent = b, CornerRadius = UDim.new(0, 4)})
        themed(b, "TextColor3", "Text")
        if themeKey then themed(b, "BackgroundColor3", themeKey) end
        return b
    end

    function KL:Add(name, mode, key)
        if not name then return end
        key = tostring(key or "?")
        -- Already in list — retarget the key badge (and the mode badge if
        -- the caller passed a new mode). Lets the right-click state menu
        -- swap H↔T live without removing/re-adding the entry.
        if self._binds[name] then
            local b = self._binds[name]
            b.kb.Text = key
            b.key = key
            b._keyW = badgeWidth(key)
            if mode and mode ~= b.mode then
                b.mode = mode
                local newMc = mode == "Hold" and "H" or "T"
                b.mc = newMc
                b.mb.Text = newMc
                b._modeW = badgeWidth(newMc)
            end
            resize()
            return
        end

        self._seq = self._seq + 1
        local mc = mode == "Hold" and "H" or "T"
        local nw = textWidth(name)
        local mw = badgeWidth(mc)
        local kw = badgeWidth(key)

        local entry = new("Frame", {
            Name = name, Parent = inner,
            Size = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1, BorderSizePixel = 0,
            LayoutOrder = self._seq,
            ClipsDescendants = true,
        })
        local row = new("Frame", {
            Name = "Row", Parent = entry,
            Size = UDim2.new(1, 0, 0, 35),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        })
        local rowScale = new("UIScale", {Parent = row, Scale = 0.94})

        local nl = new("TextLabel", {
            Parent = row,
            FontFace = FONT_MED, TextColor3 = Theme.Text, TextSize = 14,
            Text = name, BackgroundTransparency = 1,
            Size = UDim2.new(1, -(12 + mw + 6 + kw + 12), 1, 0),
            Position = UDim2.new(0, 6, 0, 0),  -- 12 - 6 for slide-in
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTransparency = 1,
        })
        themed(nl, "TextColor3", "Text")

        local bh = new("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -4, 0.5, 0),  -- starts +8 of final -12
            Size = UDim2.new(0, 0, 0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
        })
        new("UIListLayout", {
            Parent = bh,
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6),
        })

        local mb = makeBadge(bh, mc, 0.9, 0, "Accent")
        local kb = makeBadge(bh, key, 0, 1, "BgHeader")
        local mbScale = new("UIScale", {Parent = mb, Scale = 0.55})
        local kbScale = new("UIScale", {Parent = kb, Scale = 0.55})

        self._binds[name] = {
            name = name, mode = mode, mc = mc, key = key,
            frame = entry, row = row, nl = nl, mb = mb, kb = kb, bh = bh,
            rowScale = rowScale, mbScale = mbScale, kbScale = kbScale,
            _nameW = nw, _modeW = mw, _keyW = kw, ord = self._seq,
        }
        resize()

        -- Choreographed entrance — height expands, row spring-pops, badges
        -- slide right, name slides+fades, mode badge pops, key badge pops.
        local softOut   = TweenInfo.new(0.42, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        local springOut = TweenInfo.new(0.55, Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
        local smoothOut = TweenInfo.new(0.4,  Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        tween(entry, {Size = UDim2.new(1, 0, 0, 35)}, softOut)
        tween(rowScale, {Scale = 1}, springOut)
        tween(bh, {Position = UDim2.new(1, -12, 0.5, 0)}, smoothOut)
        task.delay(0.05, function()
            if not entry.Parent then return end
            tween(nl, {TextTransparency = 0, Position = UDim2.new(0, 12, 0, 0)}, smoothOut)
        end)
        task.delay(0.13, function()
            if not entry.Parent then return end
            tween(mb, {TextTransparency = 0}, softOut)
            tween(mbScale, {Scale = 1}, springOut)
        end)
        task.delay(0.19, function()
            if not entry.Parent then return end
            tween(kb, {TextTransparency = 0}, softOut)
            tween(kbScale, {Scale = 1}, springOut)
        end)
    end

    function KL:Remove(name)
        if not name then return end
        local b = self._binds[name]
        if not b then return end
        self._binds[name] = nil
        local entry = b.frame
        local softIn   = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
        local springIn = TweenInfo.new(0.23, Enum.EasingStyle.Back,  Enum.EasingDirection.In)
        local heightIn = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.In)

        tween(b.kb, {TextTransparency = 1}, softIn)
        tween(b.kbScale, {Scale = 0.55}, springIn)
        task.delay(0.05, function()
            tween(b.mb, {TextTransparency = 1}, softIn)
            tween(b.mbScale, {Scale = 0.55}, springIn)
        end)
        task.delay(0.05, function()
            tween(b.bh, {Position = UDim2.new(1, -4, 0.5, 0)}, softIn)
        end)
        task.delay(0.09, function()
            tween(b.nl, {TextTransparency = 1, Position = UDim2.new(0, 6, 0, 0)}, softIn)
        end)
        task.delay(0.08, function()
            tween(b.rowScale, {Scale = 0.94}, softIn)
        end)
        task.delay(0.16, function()
            tween(entry, {Size = UDim2.new(1, 0, 0, 0)}, heightIn)
            resize()
        end)
        task.delay(0.55, function()
            if entry.Parent then entry:Destroy() end
        end)
    end

    function KL:Toggle(name, mode, key)
        if self._binds[name] then self:Remove(name) else self:Add(name, mode, key) end
    end

    function KL:Has(name) return self._binds[name] ~= nil end

    return KL
end

--// ============================================================
--// Notification widget — bottom-center stacking toasts. Each
--// notif: icon (themed Accent) + RichText body (themed Text).
--// Choreographed entrance/exit. Bg follows Background, accent
--// icon follows Accent. Call Window.Notifications:Notify(text,
--// opts) where opts = {icon=string, duration=number}.
--// ============================================================
local function createNotifications(window)
    local gui = new("ScreenGui", {
        Name = "\0UI_Notifs",
        Parent = (gethui and gethui()) or CoreGui,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 6000,
    })

    local container = new("Frame", {
        Name = "Container", Parent = gui,
        AnchorPoint = Vector2.new(0.5, 1),
        Position = UDim2.new(0.5, 0, 1, -150),
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    new("UIListLayout", {
        Parent = container,
        Padding = UDim.new(0, 8),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
        VerticalAlignment = Enum.VerticalAlignment.Bottom,
    })

    -- Separate top-left container for rich prompts. Prompts can't share
    -- the bottom-center stack because (a) they're persistent until user
    -- action and (b) MAX_VIS eviction on regular toasts would lose them.
    local promptHolder = new("Frame", {
        Name = "PromptHolder", Parent = gui,
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(12, 12),
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    new("UIListLayout", {
        Parent = promptHolder,
        Padding = UDim.new(0, 12),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local ICON_MAP = {
        hit      = "rbxassetid://95956300578145",
        reload   = "rbxassetid://133489527524318",
        cart     = "rbxassetid://133489527524318",
        info     = "rbxassetid://79554098175447",
        warning  = "rbxassetid://70479764730792",
        collapse = "rbxassetid://118645616697622",
        close    = "rbxassetid://124971904960139",
        default  = "rbxassetid://95956300578145",
    }
    local MAX_VIS = 6

    local N = {Gui = gui, Container = container, _queue = {}, _seq = 0}

    -- Notif bodies are user-supplied RichText with hardcoded accent hex
    -- (`<font color="#0a9dff">`). Swap that literal for the live accent hex
    -- at render time, and re-render every visible notif when Accent changes.
    local function colorHex(c)
        return string.format("%02x%02x%02x",
            math.floor(c.R * 255 + 0.5),
            math.floor(c.G * 255 + 0.5),
            math.floor(c.B * 255 + 0.5))
    end
    local function applyAccent(text)
        if not text or text == "" then return "" end
        return (text:gsub("#0a9dff", "#" .. colorHex(Theme.Accent)))
    end

    local function dismiss(entry)
        if entry._dismissed then return end
        entry._dismissed = true
        for i, e in ipairs(N._queue) do
            if e == entry then table.remove(N._queue, i); break end
        end
        local softIn = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
        local scaleIn = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
        local fadeIn = TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
        tween(entry.label, {TextTransparency = 1}, softIn)
        tween(entry.iconImg, {ImageTransparency = 1}, softIn)
        tween(entry.notifScale, {Scale = 0.95}, scaleIn)
        tween(entry.notif, {BackgroundTransparency = 1}, fadeIn)
        task.delay(0.12, function()
            local w = entry.wrapper.AbsoluteSize.X
            tween(entry.wrapper, {Size = UDim2.new(0, w, 0, 0)}, scaleIn)
        end)
        task.delay(0.42, function()
            if entry.wrapper.Parent then entry.wrapper:Destroy() end
        end)
    end

    function N:Notify(text, opts)
        opts = opts or {}
        local iconKey = opts.icon or "default"
        local iconId = ICON_MAP[iconKey] or ICON_MAP.default
        local duration = opts.duration or 3
        N._seq = N._seq + 1

        while #N._queue >= MAX_VIS do dismiss(N._queue[1]) end

        local wrapper = new("Frame", {
            Name = "Wrap", Parent = container,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            AutomaticSize = Enum.AutomaticSize.XY,
            Size = UDim2.new(0, 0, 0, 0),
            LayoutOrder = N._seq,
            ClipsDescendants = true,
        })

        local notif = new("Frame", {
            Name = "Notification", Parent = wrapper,
            Size = UDim2.new(0, 1, 0, 35),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundColor3 = Theme.Background,
            BackgroundTransparency = 1, BorderSizePixel = 0,
        })
        themed(notif, "BackgroundColor3", "Background")
        new("UICorner", {Parent = notif, CornerRadius = UDim.new(0, 2)})

        local notifScale = new("UIScale", {Parent = notif, Scale = 0.9})

        new("UIListLayout", {
            Parent = notif,
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        new("UIPadding", {Parent = notif, PaddingRight = UDim.new(0, 12)})

        local iconFrame = new("Frame", {
            Parent = notif, LayoutOrder = 0,
            Size = UDim2.new(0, 35, 0, 35),
            BackgroundTransparency = 1,
        })
        local iconImg = new("ImageLabel", {
            Parent = iconFrame,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 20, 0, 20),
            BackgroundTransparency = 1,
            ImageColor3 = Theme.Accent,
            Image = iconId,
            ScaleType = Enum.ScaleType.Fit,
            ImageTransparency = 1,
        })
        themed(iconImg, "ImageColor3", "Accent")
        local iconScale = new("UIScale", {Parent = iconImg, Scale = 0.6})

        local textWrap = new("Frame", {
            Parent = notif, LayoutOrder = 1,
            Size = UDim2.new(0, 1, 0, 35),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
        })
        local label = new("TextLabel", {
            Parent = textWrap,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            BackgroundTransparency = 1,
            Text = applyAccent(text),
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            RichText = true,
            TextTransparency = 1,
        })
        themed(label, "TextColor3", "Text")

        local entry = {
            wrapper = wrapper, notif = notif, notifScale = notifScale,
            iconImg = iconImg, iconScale = iconScale, label = label,
            _rawText = text, _dismissed = false,
        }
        table.insert(N._queue, entry)

        local springOut = TweenInfo.new(0.5,  Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
        local softOut   = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        local iconOut   = TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        local smoothOut = TweenInfo.new(0.4,  Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        tween(notifScale, {Scale = 1}, springOut)
        tween(notif, {BackgroundTransparency = 0.35}, softOut)
        task.delay(0.06, function()
            if entry._dismissed then return end
            tween(iconImg, {ImageTransparency = 0}, iconOut)
            tween(iconScale, {Scale = 1}, springOut)
        end)
        task.delay(0.12, function()
            if entry._dismissed then return end
            tween(label, {TextTransparency = 0}, smoothOut)
        end)
        task.delay(duration, function() dismiss(entry) end)

        return entry
    end

    -- Rich confirmation prompt — header (icon + title + collapse + close),
    -- body (description text + optional action buttons), optional progress
    -- bar with click-to-stop affordance. Lives in the top-left stacking
    -- container, not the bottom-center toast queue (prompts wait for user
    -- action and shouldn't get evicted by passing toasts).
    --
    -- opts = {
    --   Title         (string, RichText supported)
    --   Description   (string, RichText supported)
    --   Icon          (registered icon name or asset id; default "warning")
    --   Color         (Color3 accent override; default Theme.Accent)
    --   Buttons       (array of {Text, Style="primary"|"secondary", Callback})
    --   Duration      (seconds for auto-dismiss + progress bar; nil = persist)
    --   ProgressText  (string, default "click to <b>stop</b>")
    --   Collapsible   (bool, default true — show collapse button)
    --   OnDismiss     (function called on any dismissal path)
    -- }
    function N:Prompt(opts)
        opts = opts or {}
        local accent = opts.Color or Theme.Accent
        local accentHex = colorHex(accent)
        -- Per-prompt accent substitution — if the user passed an override
        -- Color, RichText `#0a9dff` literals in Title/Description should
        -- adopt THAT color, not the global Theme.Accent. Local helper
        -- shadows the outer applyAccent for this prompt only.
        local function applyPromptAccent(text)
            if not text or text == "" then return "" end
            return (text:gsub("#0a9dff", "#" .. accentHex))
        end
        -- Icon resolution: check notification-specific ICON_MAP first
        -- (warning/info/hit/cart/etc), then fall through to the global icon
        -- registry so users can pass "flame"/"shield"/etc OR raw asset URLs.
        local iconAsset
        if opts.Icon then
            iconAsset = ICON_MAP[opts.Icon] or resolveIcon(opts.Icon)
        else
            iconAsset = ICON_MAP.warning
        end
        local duration = opts.Duration
        local showProgress = duration ~= nil
        local promptObj = {_dismissed = false}
        local PROMPT_WIDTH = opts.Width or 380

        -- Wrapper is fixed-width + auto-height. ClipsDescendants is set so
        -- the entrance/exit height tween cleanly clips the contents. Fixed
        -- width avoids the AutomaticSize loop where Scale=1 children
        -- (progress bar) would force the parent to grow indefinitely.
        local wrapper = new("Frame", {
            Name = "PromptWrap", Parent = promptHolder,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            AutomaticSize = Enum.AutomaticSize.Y,
            Size = UDim2.new(0, PROMPT_WIDTH, 0, 0),
            ClipsDescendants = true,
        })

        local notif = new("Frame", {
            Name = "Prompt", Parent = wrapper,
            BackgroundColor3 = Theme.Background,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
            AutomaticSize = Enum.AutomaticSize.Y,
        })
        themed(notif, "BackgroundColor3", "Background")
        new("UICorner", {Parent = notif, CornerRadius = UDim.new(0, 6)})
        new("UIListLayout", {Parent = notif, SortOrder = Enum.SortOrder.LayoutOrder})

        local notifScale = new("UIScale", {Parent = notif, Scale = 0.92})

        -- ── Header (icon + title on left, collapse + close on right).
        -- No UIListLayout — left/right alignment is done via AnchorPoint
        -- so the title can sit on the left edge while the close button
        -- sticks to the right regardless of how short the title is.
        local header = new("Frame", {
            Name = "Header", Parent = notif, LayoutOrder = 0,
            BackgroundColor3 = Theme.BgDark,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 30),
            AutomaticSize = Enum.AutomaticSize.Y,
        })
        themed(header, "BackgroundColor3", "BgDark")
        new("UICorner", {Parent = header, CornerRadius = UDim.new(0, 6)})
        new("UIPadding", {
            Parent = header,
            PaddingTop = UDim.new(0, 4), PaddingRight = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 6),
        })

        local leftHolder = new("Frame", {
            Name = "Holder", Parent = header,
            AnchorPoint = Vector2.new(0, 0),
            Position = UDim2.new(0, 0, 0, 0),
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, 64, 0, 30),
            AutomaticSize = Enum.AutomaticSize.XY,
        })
        new("UIListLayout", {
            Parent = leftHolder,
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        local iconHolder = new("Frame", {
            Name = "IconHolder", Parent = leftHolder, LayoutOrder = 0,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, 30, 0, 30),
        })
        local iconImg = new("ImageLabel", {
            Parent = iconHolder,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 20, 0, 20),
            BackgroundTransparency = 1,
            Image = iconAsset,
            ImageColor3 = accent,
            ImageTransparency = 1,
        })
        local iconScale = new("UIScale", {Parent = iconImg, Scale = 0.6})

        local titleHolder = new("Frame", {
            Name = "TitleHolder", Parent = leftHolder, LayoutOrder = 1,
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, 1, 0, 30),
            AutomaticSize = Enum.AutomaticSize.XY,
        })
        new("UIListLayout", {
            Parent = titleHolder,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            FillDirection = Enum.FillDirection.Horizontal,
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        local titleLbl = new("TextLabel", {
            Name = "Title", Parent = titleHolder,
            BackgroundTransparency = 1,
            Text = applyPromptAccent(opts.Title or "Notification"),
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            RichText = true,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            TextTransparency = 1,
        })
        themed(titleLbl, "TextColor3", "Text")

        -- ── Control buttons (right side)
        local controlHolder = new("Frame", {
            Name = "ControlHolder", Parent = header,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, 0, 0, 0),
            BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.new(0, 1, 0, 30),
            AutomaticSize = Enum.AutomaticSize.XY,
        })
        new("UIListLayout", {
            Parent = controlHolder,
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 2),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        -- Render the description body BEFORE wiring the collapse button so
        -- it can reference the body's Visible state.
        local descHolder
        if opts.Description or (opts.Buttons and #opts.Buttons > 0) then
            descHolder = new("Frame", {
                Name = "DescriptionHolder", Parent = notif, LayoutOrder = 1,
                BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 10),
                AutomaticSize = Enum.AutomaticSize.Y,
            })
            new("UIListLayout", {
                Parent = descHolder,
                Padding = UDim.new(0, 8),
                SortOrder = Enum.SortOrder.LayoutOrder,
            })
            new("UIPadding", {
                Parent = descHolder,
                PaddingBottom = UDim.new(0, 12),
                PaddingLeft = UDim.new(0, 12),
            })
        end

        local descLbl
        if descHolder and opts.Description then
            local textHolder = new("Frame", {
                Name = "TextHolder", Parent = descHolder, LayoutOrder = 0,
                BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 10),
                AutomaticSize = Enum.AutomaticSize.Y,
            })
            new("UIPadding", {Parent = textHolder, PaddingLeft = UDim.new(0, 26)})
            new("UIListLayout", {Parent = textHolder, SortOrder = Enum.SortOrder.LayoutOrder})
            descLbl = new("TextLabel", {
                Parent = textHolder,
                BackgroundTransparency = 1,
                Text = applyPromptAccent(opts.Description),
                TextColor3 = Theme.TextDim,
                FontFace = FONT_MED, TextSize = 14,
                RichText = true,
                TextWrapped = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                Size = UDim2.new(1, 0, 0, 1),
                AutomaticSize = Enum.AutomaticSize.Y,
                TextTransparency = 1,
            })
            themed(descLbl, "TextColor3", "TextDim")
        end

        -- Action buttons (Continue / Cancel etc).
        local buttonRefs = {}
        if descHolder and opts.Buttons and #opts.Buttons > 0 then
            local btnHolder = new("Frame", {
                Name = "ButtonHolder", Parent = descHolder, LayoutOrder = 1,
                BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 10),
                AutomaticSize = Enum.AutomaticSize.Y,
            })
            new("UIPadding", {Parent = btnHolder, PaddingLeft = UDim.new(0, 26)})
            new("UIListLayout", {
                Parent = btnHolder,
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 8),
                SortOrder = Enum.SortOrder.LayoutOrder,
            })
            for i, btnCfg in ipairs(opts.Buttons) do
                local isPrimary = (btnCfg.Style or "primary") == "primary"
                local btn = new("TextButton", {
                    Name = "Button", Parent = btnHolder, LayoutOrder = i,
                    BackgroundColor3 = isPrimary and accent or Theme.BgDark,
                    BackgroundTransparency = isPrimary and 0.95 or 1,
                    BorderSizePixel = 0,
                    Size = UDim2.new(0, 1, 0, 1),
                    AutomaticSize = Enum.AutomaticSize.XY,
                    Text = "",
                    AutoButtonColor = false,
                })
                new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 6)})
                if not isPrimary then
                    local stroke = new("UIStroke", {Parent = btn, Color = Theme.TextSub, Thickness = 1})
                    themed(stroke, "Color", "TextSub")
                end
                local txt = new("TextLabel", {
                    Parent = btn,
                    BackgroundTransparency = 1,
                    Text = btnCfg.Text or "Button",
                    TextColor3 = isPrimary and accent or Theme.TextSub,
                    FontFace = FONT_MED, TextSize = 14,
                    Size = UDim2.new(0, 1, 0, 1),
                    AutomaticSize = Enum.AutomaticSize.XY,
                    TextTransparency = 1,
                })
                if not isPrimary then themed(txt, "TextColor3", "TextSub") end
                new("UIPadding", {
                    Parent = txt,
                    PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
                    PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
                })
                btn.MouseEnter:Connect(function()
                    tween(btn, {BackgroundTransparency = isPrimary and 0.85 or 0.9}, TI_QUICK)
                end)
                btn.MouseLeave:Connect(function()
                    tween(btn, {BackgroundTransparency = isPrimary and 0.95 or 1}, TI_QUICK)
                end)
                btn.MouseButton1Click:Connect(function()
                    if btnCfg.Callback then pcall(btnCfg.Callback) end
                    promptObj:Dismiss()
                end)
                buttonRefs[i] = {btn = btn, txt = txt, primary = isPrimary}
            end
        end

        -- ── Control buttons (collapse + close) — built AFTER body so the
        -- collapse handler can toggle descHolder visibility.
        local function makeControlBtn(asset, name, order)
            local btn = new("TextButton", {
                Name = name, Parent = controlHolder, LayoutOrder = order,
                AnchorPoint = Vector2.new(0.5, 0.5),
                BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(0, 30, 0, 30),
                Text = "", AutoButtonColor = false,
            })
            local img = new("ImageLabel", {
                Name = name .. "Icon", Parent = btn,
                AnchorPoint = Vector2.new(0.5, 0.5),
                Position = UDim2.new(0.5, 0, 0.5, 0),
                Size = UDim2.new(0, 20, 0, 20),
                BackgroundTransparency = 1,
                Image = asset,
                ImageColor3 = Theme.TextSub,
                ImageTransparency = 1,
            })
            themed(img, "ImageColor3", "TextSub")
            btn.MouseEnter:Connect(function() tween(img, {ImageColor3 = Theme.Text}, TI_QUICK) end)
            btn.MouseLeave:Connect(function() tween(img, {ImageColor3 = Theme.TextSub}, TI_QUICK) end)
            return btn, img
        end

        local collapsed = false
        if opts.Collapsible ~= false and descHolder then
            local collapseBtn = makeControlBtn(ICON_MAP.collapse, "CollapseButton", 0)
            collapseBtn.MouseButton1Click:Connect(function()
                collapsed = not collapsed
                descHolder.Visible = not collapsed
            end)
        end
        local closeBtn = makeControlBtn(ICON_MAP.close, "CloseButton", 1)
        closeBtn.MouseButton1Click:Connect(function() promptObj:Dismiss() end)

        -- ── Progress bar (optional)
        local progFill, progStopBtn, progHolder
        if showProgress then
            progHolder = new("Frame", {
                Name = "ProgressHolder", Parent = notif, LayoutOrder = 2,
                BackgroundColor3 = Theme.BgDark,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 30),
                AutomaticSize = Enum.AutomaticSize.Y,
            })
            themed(progHolder, "BackgroundColor3", "BgDark")
            new("UICorner", {Parent = progHolder, CornerRadius = UDim.new(0, 6)})
            new("UIPadding", {
                Parent = progHolder,
                PaddingRight = UDim.new(0, 12),
                PaddingLeft = UDim.new(0, 12),
                PaddingTop = UDim.new(0, 6),
                PaddingBottom = UDim.new(0, 8),
            })
            new("UIListLayout", {
                Parent = progHolder,
                Padding = UDim.new(0, 6),
                SortOrder = Enum.SortOrder.LayoutOrder,
            })

            progStopBtn = new("TextButton", {
                Name = "Stop", Parent = progHolder, LayoutOrder = 0,
                BackgroundTransparency = 1,
                Text = opts.ProgressText or 'click to <b>stop</b>',
                TextColor3 = Theme.TextSub,
                FontFace = FONT_MED, TextSize = 14,
                RichText = true,
                Size = UDim2.new(0, 1, 0, 14),
                AutomaticSize = Enum.AutomaticSize.X,
                AutoButtonColor = false,
                TextXAlignment = Enum.TextXAlignment.Left,
                TextTransparency = 1,
            })
            themed(progStopBtn, "TextColor3", "TextSub")
            progStopBtn.MouseButton1Click:Connect(function() promptObj:Dismiss() end)

            local barRow = new("Frame", {
                Name = "Progressbar", Parent = progHolder, LayoutOrder = 1,
                BackgroundTransparency = 1, BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 5),
            })
            progFill = new("Frame", {
                Name = "Fill", Parent = barRow,
                Size = UDim2.new(1, 0, 0, 5),
                BackgroundColor3 = accent,
                BorderSizePixel = 0,
            })
            new("UICorner", {Parent = progFill, CornerRadius = UDim.new(0, 4)})
        end

        -- Accent reactivity. All accent-tinted elements (icon, title/desc
        -- RichText, primary buttons, progress fill) are re-painted from
        -- ONE helper. The helper picks the live accent — opts.Color if
        -- the caller locked one in, otherwise the current Theme.Accent.
        -- It's invoked once explicitly RIGHT NOW (so the initial paint
        -- always reflects the current theme, no matter what stale values
        -- the constructors captured) and then again on every Theme.Accent
        -- change (when not locked).
        local rawTitle = opts.Title or "Notification"
        local rawDesc = opts.Description
        local function applyAccent()
            if promptObj._dismissed then return end
            local a = opts.Color or Theme.Accent
            accent = a
            accentHex = colorHex(a)
            pcall(function() iconImg.ImageColor3 = a end)
            pcall(function() titleLbl.Text = applyPromptAccent(rawTitle) end)
            if descLbl then pcall(function() descLbl.Text = applyPromptAccent(rawDesc) end) end
            for _, ref in ipairs(buttonRefs) do
                if ref.primary then
                    pcall(function() ref.btn.BackgroundColor3 = a end)
                    pcall(function() ref.txt.TextColor3 = a end)
                end
            end
            if progFill then pcall(function() progFill.BackgroundColor3 = a end) end
        end
        applyAccent()
        if opts.Color == nil then
            subscribeTheme("Accent", applyAccent)
        end

        -- Choreographed entrance.
        local springOut = TweenInfo.new(0.5,  Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
        local softOut   = TweenInfo.new(0.32, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
        local smoothOut = TweenInfo.new(0.4,  Enum.EasingStyle.Quint, Enum.EasingDirection.Out)

        tween(notifScale, {Scale = 1}, springOut)
        tween(notif, {BackgroundTransparency = 0}, softOut)
        -- Header and progress bar share the same fade-in window as the
        -- main body so the layered bg/header design becomes visible. Both
        -- followed `themed(..., "BgDark")` but were stuck at transparency 1.
        tween(header, {BackgroundTransparency = 0}, softOut)
        if progHolder then tween(progHolder, {BackgroundTransparency = 0}, softOut) end
        task.delay(0.06, function()
            if promptObj._dismissed then return end
            tween(iconImg, {ImageTransparency = 0}, softOut)
            tween(iconScale, {Scale = 1}, springOut)
        end)
        task.delay(0.12, function()
            if promptObj._dismissed then return end
            tween(titleLbl, {TextTransparency = 0}, smoothOut)
            if descLbl then tween(descLbl, {TextTransparency = 0}, smoothOut) end
            for _, ref in ipairs(buttonRefs) do
                tween(ref.txt, {TextTransparency = 0}, smoothOut)
            end
            if progStopBtn then tween(progStopBtn, {TextTransparency = 0}, smoothOut) end
        end)

        function promptObj:Dismiss()
            if self._dismissed then return end
            self._dismissed = true
            if opts.OnDismiss then pcall(opts.OnDismiss) end
            local softIn = TweenInfo.new(0.2, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
            tween(notifScale, {Scale = 0.95}, softIn)
            tween(notif, {BackgroundTransparency = 1}, softIn)
            tween(header, {BackgroundTransparency = 1}, softIn)
            if progHolder then tween(progHolder, {BackgroundTransparency = 1}, softIn) end
            for _, child in ipairs({titleLbl, descLbl, progStopBtn}) do
                if child then pcall(function() tween(child, {TextTransparency = 1}, softIn) end) end
            end
            for _, ref in ipairs(buttonRefs) do
                pcall(function() tween(ref.txt, {TextTransparency = 1}, softIn) end)
                pcall(function() tween(ref.btn, {BackgroundTransparency = 1}, softIn) end)
            end
            tween(iconImg, {ImageTransparency = 1}, softIn)
            task.delay(0.12, function()
                local w = wrapper.AbsoluteSize.X
                tween(wrapper, {Size = UDim2.new(0, w, 0, 0)}, softIn)
            end)
            task.delay(0.42, function()
                if wrapper.Parent then wrapper:Destroy() end
            end)
        end

        -- Progress bar drains over `duration` seconds; expiration dismisses
        -- the prompt unless the user already clicked something.
        if showProgress and progFill and duration and duration > 0 then
            tween(progFill, {Size = UDim2.new(0, 0, 0, 5)},
                TweenInfo.new(duration, Enum.EasingStyle.Linear, Enum.EasingDirection.Out))
            task.delay(duration, function() promptObj:Dismiss() end)
        end

        return promptObj
    end

    function N:RegisterIcon(key, assetId) ICON_MAP[key] = assetId end
    function N:Hit(target, part, dmg)
        self:Notify(string.format(
            'Hit <font color="#0a9dff">[%s]</font> in %s for %d dmg',
            tostring(target), part or "body", dmg or 0), {icon = "hit", duration = 2.5})
    end
    function N:Info(text, dur)
        self:Notify(text, {icon = "info", duration = dur or 3})
    end

    -- Re-run accent substitution on every queued notif when Accent changes.
    -- Already-dismissed ones get skipped (label gone). Each notif's
    -- _rawText is the unsubstituted source so we can re-apply cleanly.
    subscribeTheme("Accent", function()
        for _, entry in ipairs(N._queue) do
            if entry.label and entry._rawText and not entry._dismissed then
                pcall(function() entry.label.Text = applyAccent(entry._rawText) end)
            end
        end
    end)

    return N
end

--// ============================================================
--// Blur controller — UI-overlay frosted glass. Each registered
--// target gets a child Frame with the parent's rounded shape and
--// a translucent dark gradient. Because the overlay is a child of
--// the target, it's naturally clipped to the element's bounds
--// (and its UICorner) — no DOF kernel bleed, no glass refraction
--// artifacts, no per-frame projection math.
--// Built-in targets by name: "Sidebar", "Keybinds", "Notifications".
--// Pass an explicit Frame to :Add(name, frame) to blur an arbitrary
--// element. :SetIntensity controls overlay opacity (0..1).
--// ============================================================
local function createBlurController(window)
    local BC = {Targets = {}, Window = window, Intensity = 0}

    -- Built-in target resolvers — names that map to library-owned frames.
    -- Late-bound (called at :Add time) so MainPage / KeybindList / Notifications
    -- don't have to exist when createBlurController runs.
    local builtins = {
        Sidebar = function() return window.MainPage and window.MainPage:FindFirstChild("SideBar") end,
        Keybinds = function() return window.KeybindList and window.KeybindList.Frame end,
        Notifications = function() return window.Notifications and window.Notifications.Container end,
    }

    -- Clone the host frame's UICorner shape onto the overlay so the
    -- frosted layer follows the element's rounded edges instead of
    -- painting a sharp rectangle inside a pill.
    local function matchCorner(overlay, host)
        local hostCorner = host:FindFirstChildOfClass("UICorner")
        if hostCorner then
            new("UICorner", {Parent = overlay, CornerRadius = hostCorner.CornerRadius})
        end
    end

    function BC:Add(name, frame)
        if self.Targets[name] then return self.Targets[name] end
        if not frame and builtins[name] then frame = builtins[name]() end
        if not frame then return nil end

        -- Child overlay: light translucent base + gradient for the frosted
        -- look. ZIndex -1 so it sits behind the host's other children but
        -- in front of the host's own background. Transparency is 1-Intensity
        -- so Intensity=0 hides it and Intensity=1 makes it fully opaque.
        local overlay = new("Frame", {
            Name = "\0BlurOverlay", Parent = frame,
            Size = UDim2.fromScale(1, 1),
            Position = UDim2.fromScale(0, 0),
            BackgroundColor3 = Color3.fromRGB(70, 85, 115),
            BackgroundTransparency = 1 - BC.Intensity,
            BorderSizePixel = 0,
            ZIndex = -1,
        })
        matchCorner(overlay, frame)
        new("UIGradient", {
            Parent = overlay,
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.fromRGB(140, 155, 190)),
                ColorSequenceKeypoint.new(1, Color3.fromRGB(35, 45, 65)),
            }),
            Transparency = NumberSequence.new(0.15),
            Rotation = 135,
        })

        local t = {Frame = frame, Overlay = overlay}
        self.Targets[name] = t
        return t
    end

    function BC:Remove(name)
        local t = self.Targets[name]
        if not t then return end
        pcall(function() t.Overlay:Destroy() end)
        self.Targets[name] = nil
    end

    function BC:Has(name) return self.Targets[name] ~= nil end

    function BC:SetIntensity(v)
        self.Intensity = v
        for _, t in pairs(self.Targets) do
            if t.Overlay then
                t.Overlay.BackgroundTransparency = 1 - v
            end
        end
    end

    function BC:Destroy()
        for name in pairs(self.Targets) do self:Remove(name) end
    end

    return BC
end

--// ============================================================
--// Keybind state context menu — right-click any keybind pill to
-- open this; lets the user swap between Hold and Toggle runtime
-- modes. Header + two stacked Hold/Toggle buttons. UIScale 0→1
-- on open (Back) and 1→0 on close (Quart) — same choreography as
-- the settings popup. Theme-reactive throughout (BgDark / BgHeader
-- / Accent / Text). Caller wires getMode/setMode closures so this
-- menu doesn't care WHERE the mode state lives.
--// ============================================================
local function createKeybindStateMenu(window, anchor, getMode, setMode)
    local popup = new("TextButton", {
        Name = "KeybindState",
        Parent = window.PopupGui,
        AnchorPoint = Vector2.new(0, 0),
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, 137, 0, 1),
        AutomaticSize = Enum.AutomaticSize.Y,
        BackgroundColor3 = Theme.BgDark,
        BorderSizePixel = 0,
        Visible = false,
        ZIndex = 25,
        Text = "",
        AutoButtonColor = false,
        Selectable = false,
        Active = true,  -- absorbs clicks inside the menu so modal blocker doesn't fire
    })
    new("UICorner", {Parent = popup, CornerRadius = UDim.new(0, 4)})
    themed(popup, "BackgroundColor3", "BgDark")
    local stroke = new("UIStroke", {
        Parent = popup, Color = Theme.BgHeader, Thickness = 1.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Round,
    })
    themed(stroke, "Color", "BgHeader")
    new("UIListLayout", {Parent = popup, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = popup, PaddingBottom = UDim.new(0, 6)})
    local scale = new("UIScale", {Parent = popup, Scale = 0})

    -- Header (35h): cog-style icon at x=15, "Keybind State" at x=40
    local header = new("Frame", {
        Name = "Header", Parent = popup, LayoutOrder = 0,
        Size = UDim2.new(0, 135, 0, 35),
        BackgroundTransparency = 1, BorderSizePixel = 0,
    })
    local headerIcon = new("ImageLabel", {
        Name = "Icon", Parent = header,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 15, 0.5, 0),
        Size = UDim2.new(0, 15, 0, 15),
        BackgroundTransparency = 1,
        ScaleType = Enum.ScaleType.Fit,
        Image = "rbxassetid://128977408453752",
        ImageColor3 = Theme.Accent,
    })
    themed(headerIcon, "ImageColor3", "Accent")
    local headerLbl = new("TextLabel", {
        Name = "Label", Parent = header,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 40, 0.5, 0),
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Text = "Keybind State",
        TextColor3 = Theme.Text,
        FontFace = FONT_MED, TextSize = 14,
    })
    themed(headerLbl, "TextColor3", "Text")

    -- Row factory — outer wrapper (137x27) + centered TextButton (125x27).
    local function makeRow(label, order)
        local rowFrame = new("Frame", {
            Name = "Button_Component", Parent = popup, LayoutOrder = order,
            Size = UDim2.new(0, 137, 0, 27),
            BackgroundTransparency = 1, BorderSizePixel = 0,
        })
        local btn = new("TextButton", {
            Parent = rowFrame,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 125, 0, 27),
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            Text = label,
            TextColor3 = Theme.Text,
            FontFace = FONT_REG, TextSize = 14,
            AutoButtonColor = false,
        })
        new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 2)})
        themed(btn, "TextColor3", "Text")
        return btn
    end

    local btnHold = makeRow("Hold", 1)
    local btnToggle = makeRow("Toggle", 2)

    -- Active button reads the live mode from getMode() and lights up Accent;
    -- the other one stays BgHeader. Subscribes to Accent + BgHeader so the
    -- swap stays in sync when the theme changes.
    local function applyButtonState()
        local current = getMode()
        tween(btnHold, {BackgroundColor3 = current == "Hold" and Theme.Accent or Theme.BgHeader}, TI_QUICK)
        tween(btnToggle, {BackgroundColor3 = current == "Toggle" and Theme.Accent or Theme.BgHeader}, TI_QUICK)
    end
    subscribeTheme("Accent", applyButtonState)
    subscribeTheme("BgHeader", applyButtonState)

    btnHold.MouseEnter:Connect(function()
        if getMode() ~= "Hold" then tween(btnHold, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end
    end)
    btnHold.MouseLeave:Connect(applyButtonState)
    btnToggle.MouseEnter:Connect(function()
        if getMode() ~= "Toggle" then tween(btnToggle, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end
    end)
    btnToggle.MouseLeave:Connect(applyButtonState)

    btnHold.MouseButton1Click:Connect(function()
        setMode("Hold")
        applyButtonState()
    end)
    btnToggle.MouseButton1Click:Connect(function()
        setMode("Toggle")
        applyButtonState()
    end)

    local KS = {Popup = popup, IsOpen = false}

    -- Position: top-left of the menu aligns with the bottom-right of the
    -- anchor pill (right edges align). Clamped 8px from the screen's left.
    local function updatePos()
        local abs = anchor.AbsolutePosition
        local sz = anchor.AbsoluteSize
        popup.Position = UDim2.fromOffset(
            math.max(8, abs.X + sz.X - 137),
            abs.Y + sz.Y + 6
        )
    end

    local followConn
    function KS:Open()
        if self.IsOpen then return end
        self.IsOpen = true
        updatePos()
        popup.Visible = true
        scale.Scale = 0
        applyButtonState()
        tween(scale, {Scale = 1}, TI_SMOOTH)
        followConn = RunService.RenderStepped:Connect(updatePos)
        if window.OpenPopup then
            window:OpenPopup(popup, function() self:Close() end)
        end
    end
    function KS:Close()
        if not self.IsOpen then return end
        self.IsOpen = false
        if followConn then followConn:Disconnect(); followConn = nil end
        tween(scale, {Scale = 0}, TI_QUICK)
        if window.ClosePopup then window:ClosePopup(popup) end
        task.delay(0.16, function()
            if not self.IsOpen then popup.Visible = false end
        end)
    end
    function KS:Toggle()
        if self.IsOpen then self:Close() else self:Open() end
    end

    return KS
end

--// ============================================================
--// CreateWindow
--// ============================================================
function Library:CreateWindow(config)
    config = config or {}

    -- Icon resolution: `Icon` (preferred) and `Logo` (legacy alias) both
    -- work. `Icon` runs through resolveIcon so registered names like
    -- "sword"/"flame"/"shield" work alongside raw rbxassetid:// strings.
    -- `Logo` passes through verbatim for backward compat with old configs.
    local resolvedIcon = (config.Icon and resolveIcon(config.Icon))
        or config.Logo
        or "rbxassetid://134383698243842"

    local Window = {
        Name    = config.Name or "UI Library",
        SubName = config.SubName or "",
        Logo    = resolvedIcon,
        Icon    = resolvedIcon,  -- exposed under both names for API consistency
        Tabs    = {},
        CurrentTab = nil,
        Visible = true,
    }

    -- Root ScreenGui
    local gui = new("ScreenGui", {
        Name = "\0UI",
        Parent = (gethui and gethui()) or CoreGui,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
    })
    Window.ScreenGui = gui

    -- High-ZIndex popup layer (dropdowns / colorpickers / keybind popouts)
    -- Separate ScreenGui with very high DisplayOrder so it floats above all
    -- other GUIs in the game.
    local popupGui = new("ScreenGui", {
        Name = "\0UI_Popups",
        Parent = (gethui and gethui()) or CoreGui,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        ResetOnSpawn = false,
        IgnoreGuiInset = true,
        DisplayOrder = 10000,
    })
    Window.PopupGui = popupGui

    -- Shared tooltip widget — single instance per window, shown/hidden on
    -- demand by components via Window.Tooltip:Show/:Hide.
    Window.Tooltip = createTooltip(Window)

    -- On-screen watermark in the top-left. Independent of the main UI's
    -- visibility (lives in its own ScreenGui) — show/hide via
    -- Window.Watermark:SetVisible and toggle individual chunks via
    -- :SetSegmentVisible / :SetActiveSegments. Brand name + icon
    -- default to the window's, override via WatermarkName/WatermarkIcon.
    Window.Watermark = createWatermark(Window, {
        name = config.WatermarkName or Window.Name,
        icon = (config.WatermarkIcon and resolveIcon(config.WatermarkIcon))
            or resolvedIcon,
    })

    -- Keybind list (top-right) — components with ShowInList=true on their
    -- keybind cfg auto-register here. Manual API: :Add / :Remove / :Toggle.
    Window.KeybindList = createKeybindList(Window)

    -- Notification stack (bottom-center). API: :Notify(text, opts).
    Window.Notifications = createNotifications(Window)

    -- Blur controller — UI-overlay frosted glass, clipped to each target's
    -- bounds (and its UICorner). API:
    -- :Add("Sidebar"|"Keybinds"|"Notifications"|name, frame?), :Remove(name),
    -- :SetIntensity(0..1), :Has(name), :Destroy(). Resolves built-in names
    -- lazily so MainPage doesn't have to exist yet.
    Window.BlurController = createBlurController(Window)

    -- Modal click-blocker. Invisible full-screen TextButton sitting under any
    -- open popup. While a popup is up, this absorbs every click that *isn't*
    -- on the popup itself, and clicking it fires the current popup's close
    -- callback. Guarantees: (a) you can't interact with anything besides
    -- the popup, (b) clicks behind the popup never leak through.
    local modalBlocker = new("TextButton", {
        Name = "ModalBlocker",
        Parent = popupGui,
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0, 0),
        BackgroundTransparency = 1,
        Text = "",
        AutoButtonColor = false,
        Selectable = false,
        Active = true,
        Visible = false,
        ZIndex = 1,
    })
    Window.ModalBlocker = modalBlocker

    -- Popup manager — STACK based. Nested popups (e.g. a dropdown opened
    -- inside a settings popup) push onto the stack instead of evicting the
    -- parent. Each entry is {id, closeFn}.
    -- - OpenPopup: push (or refresh closeFn if id already in stack)
    -- - ClosePopup(id): pop everything above this id, then remove this entry
    --   (caller is closing themselves, so no closeFn call on them)
    -- - Blocker click: pop just the topmost popup, fire its closeFn
    Window._popupStack = {}

    function Window:OpenPopup(id, closeFn)
        for _, entry in ipairs(self._popupStack) do
            if entry.id == id then
                entry.closeFn = closeFn
                return
            end
        end
        table.insert(self._popupStack, {id = id, closeFn = closeFn})
        self.ModalBlocker.Visible = true
    end

    function Window:ClosePopup(id)
        if not id then return end
        local idx
        for i = #self._popupStack, 1, -1 do
            if self._popupStack[i].id == id then idx = i; break end
        end
        if not idx then return end
        -- Close anything ABOVE this popup first (they shouldn't be left orphaned).
        while #self._popupStack > idx do
            local entry = table.remove(self._popupStack)
            if entry.closeFn then pcall(entry.closeFn) end
        end
        -- Remove this entry. Don't call its closeFn — the caller is closing it.
        table.remove(self._popupStack, idx)
        self.ModalBlocker.Visible = #self._popupStack > 0
    end

    modalBlocker.MouseButton1Click:Connect(function()
        if #Window._popupStack == 0 then return end
        local top = Window._popupStack[#Window._popupStack]
        -- Defensive guard: if Roblox routed this click to the blocker even
        -- though the cursor is inside the topmost popup's bounds (rare
        -- hit-test quirk), refuse to close.
        if typeof(top.id) == "Instance" and top.id:IsA("GuiObject") then
            local m   = UserInputService:GetMouseLocation()
            local abs = top.id.AbsolutePosition
            local sz  = top.id.AbsoluteSize
            if m.X >= abs.X and m.X <= abs.X + sz.X
               and m.Y >= abs.Y and m.Y <= abs.Y + sz.Y then
                return
            end
        end
        table.remove(Window._popupStack)
        Window.ModalBlocker.Visible = #Window._popupStack > 0
        if top.closeFn then pcall(top.closeFn) end
    end)

    -- Main page
    local mainPage = new("Frame", {
        Name = "MainPage",
        Parent = gui,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 608, 0, 526),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        Active = true,
    })
    Window.MainPage = mainPage
    new("UICorner", {Parent = mainPage, CornerRadius = UDim.new(0, 8)})
    themed(mainPage, "BackgroundColor3", "Background")
    -- UIScale drives the open/close animation. AnchorPoint is (0.5, 0.5)
    -- so Scale 0 → 1 collapses to / expands from the center of the screen.
    -- Sidebar is a child of MainPage so it scales together.
    -- Initial Scale = 0 collapses the window before the first-load entrance
    -- pop. The tween is fired via task.defer at the end of CreateWindow so
    -- the user's synchronous AddTab/AddSection setup completes first —
    -- otherwise the spring would play to an empty/half-built window.
    local rootScale = new("UIScale", {Parent = mainPage, Scale = 0})
    Window._rootScale = rootScale

    -- Sidebar
    local sideBar = new("Frame", {
        Name = "SideBar",
        Parent = mainPage,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, -70, 0.5, 0),
        Size = UDim2.new(0, 75, 0, 526),
        BackgroundColor3 = Theme.Background,
        BackgroundTransparency = 0.35,
        BorderSizePixel = 0, 
    })
    new("UICorner", {Parent = sideBar, CornerRadius = UDim.new(0, 8)})
    themed(sideBar, "BackgroundColor3", "Background")
    -- PaddingRight = 5 accounts for the SBLiner overlap at the sidebar's
    -- right edge — the rightmost 5px of the sidebar is hidden behind the
    -- liner that masks the seam with MainPage. Subtracting it from the
    -- layout's available area means HorizontalAlignment.Center actually
    -- centers in the VISIBLE 70px column, not the full 75px frame.
    new("UIPadding", {
        Parent = sideBar,
        PaddingTop = UDim.new(0, 18),
        PaddingRight = UDim.new(0, 5),
    })
    new("UIListLayout", {
        Parent = sideBar, Padding = UDim.new(0, 16),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    -- Resolve a flexible IconSize value into a UDim2. Accepts:
    --   nil          → default 55x55
    --   number n     → UDim2.new(0, n, 0, n)  (square)
    --   {w, h}       → UDim2.new(0, w, 0, h)
    --   UDim2        → as-is
    local function resolveIconSize(value)
        if value == nil then return UDim2.new(0, 55, 0, 55) end
        if typeof(value) == "UDim2" then return value end
        if type(value) == "number" then return UDim2.new(0, value, 0, value) end
        if type(value) == "table" and value[1] and value[2] then
            return UDim2.new(0, value[1], 0, value[2])
        end
        return UDim2.new(0, 55, 0, 55)
    end

    Window.IconSize = resolveIconSize(config.IconSize)
    Window.SidebarLogo = new("ImageLabel", {
        Name = "Logo", Parent = sideBar,
        Image = Window.Logo,
        BackgroundTransparency = 1,
        ImageColor3 = Theme.Accent,
        Size = Window.IconSize,
        LayoutOrder = 0,
    })
    -- Logo is themed against Accent — works correctly for grayscale/white
    -- source assets (the tint multiplies cleanly). Colored source assets
    -- will multiply too and look off; pass an already-grayscale icon if
    -- you want clean accent tinting. Opt out with Window:UntintLogo() if
    -- the caller's icon is intentionally colored.
    themed(Window.SidebarLogo, "ImageColor3", "Accent")

    function Window:UntintLogo()
        if self.SidebarLogo then self.SidebarLogo.ImageColor3 = Color3.new(1, 1, 1) end
    end

    -- Swap the sidebar icon at runtime. Accepts the same forms as the
    -- Icon config field: registered icon name ("sword"/"flame"/etc) OR a
    -- raw rbxassetid:// / http(s):// URL. Also propagates to the
    -- watermark's Logo segment so both stay in sync — pass `false` for
    -- watermark if you want to keep the watermark icon independent.
    function Window:SetIcon(icon, watermark)
        local resolved = resolveIcon(icon)
        self.Logo = resolved
        self.Icon = resolved
        if self.SidebarLogo then self.SidebarLogo.Image = resolved end
        if watermark ~= false and self.Watermark and self.Watermark.SetIcon then
            self.Watermark:SetIcon(resolved)
        end
    end

    -- Update the sidebar icon's dimensions at runtime. Same flexible input
    -- as the IconSize config field — number for square, {w, h} for rect,
    -- UDim2 for exact control.
    function Window:SetIconSize(size)
        local resolved = resolveIconSize(size)
        self.IconSize = resolved
        if self.SidebarLogo then self.SidebarLogo.Size = resolved end
    end

    -- Update the breadcrumb label AND, by default, the watermark brand
    -- text. Pass watermark=false to keep them independent (e.g. when the
    -- watermark should display a shorter "ENI" while the window header
    -- shows the full "ENI Hub").
    function Window:SetName(name, watermark)
        self.Name = name
        if self.BreadcrumbText then self.BreadcrumbText.Text = name end
        if watermark ~= false and self.Watermark and self.Watermark.SetName then
            self.Watermark:SetName(name)
        end
    end

    local tabsHolder = new("Frame", {
        Name = "TabsHolder", Parent = sideBar,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 69, 0, 420),
        LayoutOrder = 1,
    })
    Window.TabsHolder = tabsHolder
    new("UIPadding", {Parent = tabsHolder, PaddingRight = UDim.new(0, 4)})
    new("UIListLayout", {
        Parent = tabsHolder, Padding = UDim.new(0, 12),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    -- SBLiner — 12px strip on MainPage's left edge in Theme.Background.
    -- Sidebar lives at x=-70 size 75 so its right edge pokes 5px into
    -- MainPage; this liner sits in front (ZIndex=3, above sidebar Z=1 and
    -- shadow Z=2) and masks that overlap with the page bg color so the
    -- translucent sidebar gets a clean opaque seam against the page.
    local sbLiner = new("Frame", {
        Name = "SBLiner", Parent = mainPage,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.new(0, 12, 1, 0),
        BackgroundColor3 = Theme.Background,
        BorderSizePixel = 0,
        ZIndex = 3,
    })
    themed(sbLiner, "BackgroundColor3", "Background")

    -- Header (breadcrumb + search)
    local header = new("Frame", {
        Name = "Header", Parent = mainPage,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -12, 0, 73),
    })
    Window.Header = header

    -- Breadcrumb (matches supplied design exactly)
    local breadcrumb = new("Frame", {
        Name = "Breadcrumb",
        Parent = header,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 13, 0.5, 0),   -- +12 of header offset = 25 abs
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 25, 0, 25),
        AutomaticSize = Enum.AutomaticSize.XY,
        BorderSizePixel = 0,
    })
    new("UIListLayout", {
        Parent = breadcrumb,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Padding = UDim.new(0, 8),
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local bcIconHolder = new("Frame", {
        Name = "IconHolder",
        Parent = breadcrumb,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 25, 0, 25),
        BorderSizePixel = 0,
        LayoutOrder = 0,
    })
    local bcIcon = new("ImageLabel", {
        Name = "ActiveTabIcon",
        Parent = bcIconHolder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 22, 0, 22),
        BackgroundTransparency = 1,
        Image = resolveIcon("default"),
        ImageColor3 = Theme.TextInactive,
        BorderSizePixel = 0,
    })
    Window.BreadcrumbIcon = bcIcon
    themed(bcIcon, "ImageColor3", "TextInactive")

    local bcTextHolder = new("Frame", {
        Name = "TextHolder",
        Parent = breadcrumb,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 1, 0, 25),
        AutomaticSize = Enum.AutomaticSize.XY,
        BorderSizePixel = 0,
        LayoutOrder = 1,
    })
    new("UIListLayout", {
        Parent = bcTextHolder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    local bcText = new("TextLabel", {
        Name = "ActiveTabValue",
        Parent = bcTextHolder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Text = Window.Name,
        TextColor3 = Theme.TextInactive,
        FontFace = FONT_MED,
        TextSize = 16,
        BorderSizePixel = 0,
    })
    Window.BreadcrumbText = bcText
    themed(bcText, "TextColor3", "TextInactive")

    -- Header right (search + cog) — 1:1 with supplied dump.
    -- Outer box hugs its content (AutomaticSize XY), positioned 36px from the
    -- right edge of the header. Children are a search holder (centered TextBox)
    -- on the left and the cog icon holder on the right, laid out horizontally.
    local headerRight = new("Frame", {
        Parent = header,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -36, 0.5, 0),
        Size = UDim2.new(0, 1, 0, 41),
        BackgroundColor3 = Theme.BgSearch,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.XY,
    })
    new("UICorner", {Parent = headerRight, CornerRadius = UDim.new(0, 8)})
    themed(headerRight, "BackgroundColor3", "BgSearch")
    local headerRightStroke = new("UIStroke", {Parent = headerRight, Color = Theme.Stroke, Thickness = 1})
    themed(headerRightStroke, "Color", "Stroke")
    new("UIPadding", {Parent = headerRight, PaddingLeft = UDim.new(0, 12)})
    new("UIListLayout", {
        Parent = headerRight,
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = Enum.HorizontalAlignment.Right,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })

    -- Search input holder — transparent wrapper whose inner UIListLayout
    -- centers the auto-sizing TextBox both axes.
    local searchHolder = new("Frame", {
        Parent = headerRight, LayoutOrder = 0,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 56, 0, 42),
        AutomaticSize = Enum.AutomaticSize.XY,
        BorderSizePixel = 0,
    })
    new("UIListLayout", {
        Parent = searchHolder,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder,
    })
    local searchBox = new("TextBox", {
        Parent = searchHolder,
        BackgroundTransparency = 1,
        Text = "",
        PlaceholderText = "Search Items...",
        PlaceholderColor3 = Theme.TextDim,
        TextColor3 = Color3.fromRGB(230, 230, 230),
        FontFace = FONT_REG, TextSize = 16,
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BorderSizePixel = 0,
        ClearTextOnFocus = false,
    })
    themed(searchBox, "PlaceholderColor3", "TextDim")
    Window.SearchBox = searchBox

    -- Cog/icon holder (42x42) — sits to the right of the search input.
    local settingsHolder = new("Frame", {
        Parent = headerRight, LayoutOrder = 1,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 42, 0, 42),
        BorderSizePixel = 0,
    })
    local settingsHolderIcon = new("ImageLabel", {
        Parent = settingsHolder,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(0, 15, 0, 15),
        BackgroundTransparency = 1,
        Image = resolveIcon("settings"),
        ImageColor3 = Theme.TextSub,
    })
    themed(settingsHolderIcon, "ImageColor3", "TextSub")

    -- Pages
    local pages = new("Frame", {
        Name = "Pages", Parent = mainPage,
        BackgroundTransparency = 1,
        Position = UDim2.new(0, 12, 0, 73),
        Size = UDim2.new(1, -12, 1, -73),
    })
    Window.Pages = pages

    -- Bottom shadow
    local shadow = new("Frame", {
        Parent = pages,
        AnchorPoint = Vector2.new(0, 1),
        Position = UDim2.new(0, 0, 1, 0),
        Size = UDim2.new(1, 0, 0, 90),
        BackgroundColor3 = Color3.new(0, 0, 0),
        BorderSizePixel = 0,
        ZIndex = 2,
    })
    -- Match the main page's corner radius so the opaque bottom edge of the
    -- shadow doesn't cover the rounded bottom-right corner of MainPage.
    new("UICorner", {Parent = shadow, CornerRadius = UDim.new(0, 8)})
    new("UIGradient", {
        Parent = shadow, Rotation = 90,
        Color = ColorSequence.new(Color3.new(0, 0, 0)),
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.5, 0.55),
            NumberSequenceKeypoint.new(1, 0),
        }),
    })

    -- Entrance animation — one section at a time, staggered. Each section
    -- fades in via its CanvasGroup's GroupTransparency (Quint Out, smooth)
    -- AND pops up via its UIScale (Back Out, slight overshoot). The two
    -- easings playing simultaneously give the cascade a "designed" feel.
    function Window:_animateSectionEntrance(Section, delaySeconds)
        local sf = Section.Frame
        if not sf then return end
        -- Snap to start state immediately so the section is visually absent
        -- until its delayed tween fires.
        if sf:IsA("CanvasGroup") then sf.GroupTransparency = 1 end
        if Section._entranceScale then Section._entranceScale.Scale = 0.94 end

        local targetTab = Section.Tab
        task.delay(delaySeconds or 0, function()
            -- Skip if user has already switched away from this tab.
            if self.CurrentTab ~= targetTab then return end
            local fadeInfo  = TweenInfo.new(0.45, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
            local scaleInfo = TweenInfo.new(0.5,  Enum.EasingStyle.Back,  Enum.EasingDirection.Out)
            if sf:IsA("CanvasGroup") then
                tween(sf, {GroupTransparency = 0}, fadeInfo)
            end
            if Section._entranceScale then
                tween(Section._entranceScale, {Scale = 1}, scaleInfo)
            end
        end)
    end

    function Window:_animateTabIn(Tab)
        for i, Section in ipairs(Tab.Sections) do
            self:_animateSectionEntrance(Section, (i - 1) * 0.05)
        end
    end

    -- Search filter — case-insensitive substring match against each
    -- component's _searchKey (set during AddXxx construction).
    -- Hidden components get Visible=false AND Size collapsed to (0,0,0,0)
    -- (with original size stashed for restore). UIListLayout sees the zero
    -- size and packs remaining visible components tight together, and the
    -- AutomaticSize.Y chain shrinks the section to match. Sections with no
    -- visible children also hide so we don't see empty headers.
    function Window:_runSearch(query)
        query = (query or ""):lower()
        local empty = query == ""
        for _, tab in ipairs(self.Tabs) do
            for _, section in ipairs(tab.Sections) do
                local anyMatch = false
                for _, comp in ipairs(section.Components) do
                    local match = empty
                        or (comp._searchKey and string.find(comp._searchKey, query, 1, true) ~= nil)
                    if comp.Frame then
                        if match then
                            comp.Frame.Visible = true
                            if comp._origSize then
                                comp.Frame.Size = comp._origSize
                                comp._origSize = nil
                            end
                        else
                            if not comp._origSize then
                                comp._origSize = comp.Frame.Size
                            end
                            comp.Frame.Size = UDim2.new(0, 0, 0, 0)
                            comp.Frame.Visible = false
                        end
                    end
                    if match then anyMatch = true end
                end
                if section.Frame then
                    section.Frame.Visible = empty or anyMatch
                end
            end
        end
    end

    searchBox:GetPropertyChangedSignal("Text"):Connect(function()
        Window:_runSearch(searchBox.Text)
    end)

    -- Tab switching
    function Window:SwitchTab(target)
        for _, t in ipairs(self.Tabs) do
            local active = t == target
            t.Page.Visible = active
            tween(t.Icon, {ImageColor3 = active and Theme.Accent or Theme.TextInactive})
            tween(t.Label, {TextColor3 = active and Theme.Text or Theme.TextInactive})
            t.Active = active
        end
        self.CurrentTab = target
        -- Breadcrumb stays in the dim/gray state per the design — only the icon
        -- and text content swap to reflect the current tab.
        self.BreadcrumbIcon.Image = target.IconAsset
        tween(self.BreadcrumbIcon, {ImageColor3 = Theme.TextInactive}, TI_QUICK)
        tween(self.BreadcrumbText, {TextColor3 = Theme.TextInactive}, TI_QUICK)
        self.BreadcrumbText.Text = target.Name

        -- Staggered cascade entrance for sections in the new tab.
        self:_animateTabIn(target)
    end

    -- AddTab
    function Window:AddTab(tabConfig)
        tabConfig = tabConfig or {}
        local Tab = {
            Name = tabConfig.Name or "Tab",
            IconAsset = resolveIcon(tabConfig.Icon),
            Sections = {},
            _columnFlip = false,
            Active = false,
            Window = self,  -- so buildSection / components can reach PopupGui
        }

        local tabBtn = new("TextButton", {
            Name = Tab.Name, Parent = self.TabsHolder,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 45, 0, 45),
            AutoButtonColor = false, Text = "",
        })

        Tab.Icon = new("ImageLabel", {
            Parent = tabBtn,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 0, 6),
            Size = UDim2.new(0, 20, 0, 20),
            BackgroundTransparency = 1,
            Image = Tab.IconAsset,
            ImageColor3 = Theme.TextInactive,
            ScaleType = Enum.ScaleType.Fit,
        })

        Tab.Label = new("TextLabel", {
            Parent = Tab.Icon,
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, 18),
            BackgroundTransparency = 1,
            Text = Tab.Name,
            TextColor3 = Theme.TextInactive,
            FontFace = FONT_REG, TextSize = 14,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
        })

        -- Live theme update — state-dependent. Subscribes to the keys that
        -- could change the tab's idle/active appearance and recomputes from
        -- the current Tab.Active state.
        local function applyTabColors()
            Tab.Icon.ImageColor3 = Tab.Active and Theme.Accent or Theme.TextInactive
            Tab.Label.TextColor3 = Tab.Active and Theme.Text or Theme.TextInactive
        end
        subscribeTheme("Accent", applyTabColors)
        subscribeTheme("TextInactive", applyTabColors)
        subscribeTheme("Text", applyTabColors)

        -- Hover lift
        tabBtn.MouseEnter:Connect(function()
            if not Tab.Active then tween(Tab.Icon, {ImageColor3 = Color3.fromRGB(200, 200, 200)}, TI_QUICK) end
        end)
        tabBtn.MouseLeave:Connect(function()
            if not Tab.Active then tween(Tab.Icon, {ImageColor3 = Theme.TextInactive}, TI_QUICK) end
        end)

        -- Tab page
        local page = new("Frame", {
            Name = Tab.Name .. "_Page", Parent = self.Pages,
            BackgroundTransparency = 1,
            Size = UDim2.new(1, 0, 1, 0),
            Visible = false,
        })
        Tab.Page = page

        local scroll = new("ScrollingFrame", {
            Parent = page,
            BackgroundTransparency = 1,
            Position = UDim2.new(0, 0, 0, 4),
            Size = UDim2.new(1, 0, 1, -4),
            BorderSizePixel = 0,
            ScrollBarThickness = 2,
            ScrollBarImageColor3 = Theme.Accent,
            CanvasSize = UDim2.new(0, 0, 0, 0),
            AutomaticCanvasSize = Enum.AutomaticSize.Y,
            Active = true,
        })
        themed(scroll, "ScrollBarImageColor3", "Accent")
        new("UIPadding", {Parent = scroll, PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8)})
        new("UIListLayout", {
            Parent = scroll,
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 12),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        Tab.LeftHolder = new("Frame", {
            Name = "LeftHolder", Parent = scroll,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            LayoutOrder = 0,
        })
        new("UIListLayout", {Parent = Tab.LeftHolder, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder})

        Tab.RightHolder = new("Frame", {
            Name = "RightHolder", Parent = scroll,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            LayoutOrder = 1,
        })
        new("UIListLayout", {Parent = Tab.RightHolder, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder})

        tabBtn.MouseButton1Click:Connect(function() self:SwitchTab(Tab) end)

        function Tab:AddSection(secConfig)
            return buildSection(self, secConfig)
        end

        table.insert(self.Tabs, Tab)
        if #self.Tabs == 1 then self:SwitchTab(Tab) end
        return Tab
    end

    -- Drag (header area only)
    do
        local dragging, dragStart, startPos
        mainPage.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                local mp = UserInputService:GetMouseLocation()
                local mpAbs = mainPage.AbsolutePosition
                if mp.Y - mpAbs.Y < 73 then
                    dragging = true
                    dragStart = input.Position
                    startPos = mainPage.Position
                end
            end
        end)
        connect(UserInputService.InputChanged, function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local d = input.Position - dragStart
                mainPage.Position = UDim2.new(
                    startPos.X.Scale, startPos.X.Offset + d.X,
                    startPos.Y.Scale, startPos.Y.Offset + d.Y
                )
            end
        end)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
    end

    -- Menu toggle — animated. Opening: enable both ScreenGuis, then tween
    -- Scale 0 → 1 with Back easing (springy pop). Closing: tween Scale 1 → 0
    -- with Quart (fast snap), then disable the ScreenGuis after the tween.
    connect(UserInputService.InputBegan, function(input, gpe)
        if gpe then return end
        if input.KeyCode == Library.MenuKeybind then
            Window.Visible = not Window.Visible
            if Window.Visible then
                gui.Enabled = true
                popupGui.Enabled = true
                rootScale.Scale = 0
                tween(rootScale, {Scale = 1}, TI_POP)
            else
                -- Force-hide the tooltip on close — MouseLeave doesn't fire
                -- when the ScreenGui gets disabled mid-hover, so without
                -- this the next open would briefly show a stale tooltip.
                if Window.Tooltip then Window.Tooltip:Hide() end
                tween(rootScale, {Scale = 0}, TI_QUICK)
                task.delay(0.18, function()
                    if not Window.Visible then
                        gui.Enabled = false
                        popupGui.Enabled = false
                    end
                end)
            end
        end
    end)

    table.insert(Library.Windows, Window)

    -- First-load entrance animation. Deferred so the user's AddTab /
    -- AddSection chain runs synchronously first — by the time this fires
    -- on the next frame, the UI is fully built and the spring plays to a
    -- complete window. Back-Out easing matches the menu-toggle pop but
    -- slightly longer (0.55s vs 0.32s) so the first impression lands.
    task.defer(function()
        tween(rootScale, {Scale = 1},
            TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out))
    end)

    return Window
end

--// ============================================================
--// Section builder
--// ============================================================
buildSection = function(Tab, config)
    config = config or {}
    local Section = {
        Name = config.Name or "Section",
        IconAsset = resolveIcon(config.Icon),
        SubText = config.Subtext or "",
        Components = {},
        Tab = Tab,
        ComponentWidth = config.ComponentWidth or 287,
    }

    -- Wire a component's row to the window's shared tooltip. Idempotent —
    -- if the component already had a tooltip attached, the old hover
    -- handlers are disconnected first so a later :Tooltip(newText) cleanly
    -- replaces an earlier cfg.Tooltip. Returns obj so it's chainable.
    local function attachTooltip(obj, row, text)
        if not text or text == "" or not row then return obj end
        local TT = Tab.Window and Tab.Window.Tooltip
        if not TT then return obj end
        if obj._tooltipConns then
            for _, c in ipairs(obj._tooltipConns) do pcall(function() c:Disconnect() end) end
        end
        obj._tooltipConns = {
            row.MouseEnter:Connect(function() TT:Show(text) end),
            row.MouseLeave:Connect(function() TT:Hide() end),
        }
        obj.TooltipText = text
        return obj
    end

    -- If a custom Holder was supplied (settings popup case), skip section
    -- frame creation entirely and use the caller's holder. Otherwise build
    -- the standard section frame (header, icon badge, title, content holder).
    if config.Holder then
        Section.Holder = config.Holder
    else
        -- alternate columns
        local parentCol = Tab._columnFlip and Tab.RightHolder or Tab.LeftHolder
        Tab._columnFlip = not Tab._columnFlip

        -- CanvasGroup (drop-in for Frame) so we can fade the entire section
        -- subtree at once with GroupTransparency for the entrance animation.
        -- Matches the supplied dump: Size (0, 1, 0, 70) + AutomaticSize.XY
        -- both axes, ClipsDescendants true. Roblox computes AutomaticSize
        -- against descendant bounds BEFORE clipping is applied, so the
        -- Holder (grandchild via Header) is picked up and the section
        -- grows downward to cover it.
        local sectionFrame = new("CanvasGroup", {
            Name = "Section_Left", Parent = parentCol,
            BackgroundColor3 = Theme.BgDark,
            BorderSizePixel = 0,
            Size = UDim2.new(0, 1, 0, 70),
            AutomaticSize = Enum.AutomaticSize.XY,
            ClipsDescendants = true,
        })
        new("UICorner", {Parent = sectionFrame, CornerRadius = UDim.new(0, 6)})
        themed(sectionFrame, "BackgroundColor3", "BgDark")
        Section.Frame = sectionFrame
        -- Per-section UIScale for the entrance pop. Lives inside the section
        -- so it doesn't push surrounding layout (UIScale affects render
        -- bounds, not the slot UIListLayout reserves for the section).
        Section._entranceScale = new("UIScale", {
            Name = "EntranceScale",
            Parent = sectionFrame,
            Scale = 1,
        })

        -- Header
        local header = new("Frame", {
            Name = "Header", Parent = sectionFrame,
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            Size = UDim2.new(1, 0, 0, 70),
        })
        new("UICorner", {Parent = header, CornerRadius = UDim.new(0, 6)})
        themed(header, "BackgroundColor3", "BgHeader")

        -- Icon badge
        local iconBadge = new("Frame", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 13, 0.5, 0),
            Size = UDim2.new(0, 35, 0, 35),
            BackgroundColor3 = Theme.Accent,
            BackgroundTransparency = 0.9,
            BorderSizePixel = 0,
        })
        new("UICorner", {Parent = iconBadge, CornerRadius = UDim.new(0, 6)})
        themed(iconBadge, "BackgroundColor3", "Accent")
        local iconBadgeIcon = new("ImageLabel", {
            Parent = iconBadge,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 18, 0, 18),
            BackgroundTransparency = 1,
            Image = Section.IconAsset,
            ImageColor3 = Theme.Accent,
        })
        themed(iconBadgeIcon, "ImageColor3", "Accent")

        -- Title + subtitle
        local titleLbl = new("TextLabel", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0.02787456475198269, 53, 0.44285714626312256, -5),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = Section.Name, TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(titleLbl, "TextColor3", "Text")
        local subLbl = new("TextLabel", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0.02787456475198269, 52, 0.44285714626312256, 12),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = Section.SubText, TextColor3 = Theme.TextDim,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(subLbl, "TextColor3", "TextDim")

        -- Left gradient liner
        local liner = new("Frame", {
            Parent = header,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, -2, 0.5, 0),
            Size = UDim2.new(0, 5, 0.5, 1),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
        })
        local linerGrad = new("UIGradient", {
            Parent = liner, Rotation = 90,
            Color = ColorSequence.new(Theme.Accent),
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.92),
                NumberSequenceKeypoint.new(0.5, 0.35),
                NumberSequenceKeypoint.new(1, 1),
            }),
        })
        themedGradient(linerGrad, "Accent")

        -- Bottom divider
        local bottomDivider = new("Frame", {
            Parent = header,
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, 0),
            Size = UDim2.new(1, 0, 0, 3),
            BackgroundColor3 = Theme.BgDark,
            BorderSizePixel = 0,
        })
        themed(bottomDivider, "BackgroundColor3", "BgDark")

        -- Content holder — parented to HEADER per dump, anchored top-center
        -- at Header's bottom edge. AutomaticSize.XY grows with content. The
        -- AutomaticSize chain goes Holder → Header (no, Header is fixed) →
        -- Section_Left (XY auto-size includes ALL descendants, grandchildren
        -- included). So Section_Left grows downward to cover the Holder's
        -- bottom edge, LeftHolder grows, ScrollingFrame's canvas grows, and
        -- scrolling works. Section_Left has ClipsDescendants=false so the
        -- Holder isn't clipped during initial layout before the auto-size
        -- propagates.
        local holder = new("Frame", {
            Name = "Holder", Parent = header,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0.5, 0, 1, 0),
            Size = UDim2.new(1, 1, 0.529411792755127, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
        })
        new("UIPadding", {Parent = holder, PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 80)})
        new("UIListLayout", {Parent = holder, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})
        Section.Holder = holder
    end

    --// ────────────────────────────────────────────────────────────
    --// Component helpers
    --// ────────────────────────────────────────────────────────────
    local function nextFlag(prefix)
        local n = 0
        for _ in pairs(Library.Flags) do n = n + 1 end
        return "_auto_" .. (prefix or "f") .. "_" .. n
    end

    -- Component width comes from Section.ComponentWidth (287 for the main
    -- panel, 259 for settings popups). Inner element widths use relative
    -- offsets so they adapt automatically.
    local function component(name, height)
        return new("Frame", {
            Name = name, Parent = Section.Holder,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, Section.ComponentWidth or 287, 0, height),
            BorderSizePixel = 0,
        })
    end

    --// ── Colorpicker helper (chip + ColorWindow popup) ─────────
    -- Chip: 20x20 with checker-pattern bg and a two-half color visual
    --   (left half solid color, right half color@alpha over pattern)
    -- Popup: 218x175 floating window with sat/val area, hue slider, alpha
    --   slider, decorative eyedropper button. Lives in Window.PopupGui.
    local function createColorpicker(chipParent, anchorOpts, cfg)
        cfg = cfg or {}
        local CP = {
            Hue = 0, Sat = 0, Val = 1, Alpha = 1,
            Value = cfg.Default or Color3.fromRGB(255, 100, 0),
            Open = false,
        }
        CP.Hue, CP.Sat, CP.Val = CP.Value:ToHSV()

        -- Chip
        local chip = new("ImageButton", {
            Parent = chipParent,
            Image = "rbxassetid://70964617193772",
            ImageColor3 = Color3.fromRGB(200, 200, 200),
            BackgroundTransparency = 1,
            ClipsDescendants = true,
            AutoButtonColor = false,
            Size = UDim2.new(0, 20, 0, 20),
        })
        new("UICorner", {Parent = chip, CornerRadius = UDim.new(0, 2)})
        if anchorOpts then
            if anchorOpts.AnchorPoint then chip.AnchorPoint = anchorOpts.AnchorPoint end
            if anchorOpts.Position    then chip.Position    = anchorOpts.Position    end
            if anchorOpts.LayoutOrder then chip.LayoutOrder = anchorOpts.LayoutOrder end
        end

        local rightHalf = new("Frame", {
            Parent = chip,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, 0, 0.5, 0),
            Size = UDim2.new(0, 10, 0, 20),
            BackgroundColor3 = CP.Value,
            BackgroundTransparency = 1 - CP.Alpha,
            BorderSizePixel = 0,
        })
        local leftHalf = new("Frame", {
            Parent = chip,
            Position = UDim2.new(0, 0, 0, 0),
            Size = UDim2.new(0, 10, 0, 20),
            BackgroundColor3 = CP.Value,
            BorderSizePixel = 0,
        })

        -- Popup ColorWindow
        local popupParent = (Tab.Window and Tab.Window.PopupGui) or chipParent
        local popup = new("Frame", {
            Name = "ColorWidget",
            Parent = popupParent,
            Size = UDim2.new(0, 218, 0, 175),
            BackgroundColor3 = Color3.fromRGB(2, 3, 3),
            BorderSizePixel = 0,
            Visible = false,
            ClipsDescendants = true,
            ZIndex = 9999,
        })
        new("UICorner", {Parent = popup, CornerRadius = UDim.new(0, 3)})
        themed(popup, "BackgroundColor3", "Background")
        local cpPopupStroke = new("UIStroke", {Parent = popup, Color = Color3.fromRGB(21, 25, 30), Thickness = 1})
        themed(cpPopupStroke, "Color", "BgHeader")

        -- ─── Layout matches the supplied dump 1:1 ─────────────────────
        -- ColorWidget (218x175):
        --   Colorframe (sat/val) at (11, 13) size 196x106
        --   Hue HORIZONTAL bar at (48, 134) size 157x10  (UICorner radius 30)
        --   Alpha HORIZONTAL bar at (48, 151) size 157x10 (UICorner radius 30)
        --   PickerButton (eyedropper) at (10, popup_bottom-12) size 28x28
        -- The dump uses Rotation=90 on the hue with a vertical hue image.
        -- We use a horizontal bar + UIGradient instead — visually identical,
        -- no rotation math needed for drag handling.

        -- Sat/Val area (colorframe)
        local colorframe = new("ImageButton", {
            Parent = popup,
            Position = UDim2.new(0, 11, 0, 13),
            Size = UDim2.new(0, 196, 0, 106),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Image = "",
            ZIndex = 9999,
        })
        new("UICorner", {Parent = colorframe, CornerRadius = UDim.new(0, 4)})
        local satGrad = new("UIGradient", {
            Parent = colorframe,
            Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(CP.Hue, 1, 1)),
        })

        -- Value overlay (transparent top → black bottom)
        local valOverlay = new("Frame", {
            Parent = colorframe,
            Size = UDim2.new(1, 0, 1, 0),
            BackgroundColor3 = Color3.new(0, 0, 0),
            BorderSizePixel = 0,
            ZIndex = 10000,
        })
        new("UIGradient", {
            Parent = valOverlay,
            Rotation = 90,
            Transparency = NumberSequence.new(1, 0),
        })
        new("UICorner", {Parent = valOverlay, CornerRadius = UDim.new(0, 4)})

        -- Sat/Val picker dot
        local cfPicker = new("Frame", {
            Parent = colorframe,
            Size = UDim2.new(0, 8, 0, 8),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(CP.Sat, 0, 1 - CP.Val, 0),
            BackgroundTransparency = 1,
            ZIndex = 10001,
        })
        local cfStroke = new("UIStroke", {Parent = cfPicker, Color = Color3.new(1, 1, 1), Thickness = 2})
        new("UICorner", {Parent = cfPicker, CornerRadius = UDim.new(0, 50)})

        -- Hover effect on the colorframe: grow the picker dot + thicken its
        -- ring on enter (Back easing → springy "pop"), settle back on leave
        -- (Quart easing → quick smooth). Makes the dot read as interactive
        -- without disturbing the gradient underneath.
        colorframe.MouseEnter:Connect(function()
            tween(cfPicker, {Size = UDim2.new(0, 14, 0, 14)}, TI_POP)
            tween(cfStroke, {Thickness = 3}, TI_QUICK)
        end)
        colorframe.MouseLeave:Connect(function()
            tween(cfPicker, {Size = UDim2.new(0, 8, 0, 8)}, TI_QUICK)
            tween(cfStroke, {Thickness = 2}, TI_QUICK)
        end)

        -- Hue bar — HORIZONTAL, below the colorframe (matches dump's
        -- rotated-90 vertical bar, but rendered natively horizontal).
        local hueBar = new("ImageButton", {
            Parent = popup,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0, 127, 0, 134),
            Size = UDim2.new(0, 157, 0, 10),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Image = "",
            ZIndex = 9999,
        })
        new("UICorner", {Parent = hueBar, CornerRadius = UDim.new(0, 30)})
        local hueKeypoints = {}
        for i = 0, 6 do
            table.insert(hueKeypoints, ColorSequenceKeypoint.new(i / 6, Color3.fromHSV((i % 6) / 6, 1, 1)))
        end
        new("UIGradient", {
            Parent = hueBar,
            Color = ColorSequence.new(hueKeypoints),
        })
        -- Hue picker dot — horizontal position driven by CP.Hue.
        local huePicker = new("Frame", {
            Parent = hueBar,
            Size = UDim2.new(0, 12, 0, 12),
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(CP.Hue, 0, 0.5, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 10001,
        })
        new("UIStroke", {Parent = huePicker, Color = Color3.new(1, 1, 1)})
        new("UICorner", {Parent = huePicker, CornerRadius = UDim.new(1, 100)})

        -- Alpha bar — HORIZONTAL, below the hue bar.
        local alphaBar = new("ImageButton", {
            Parent = popup,
            AnchorPoint = Vector2.new(0.5, 0),
            Position = UDim2.new(0, 127, 0, 151),
            Size = UDim2.new(0, 157, 0, 10),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            AutoButtonColor = false,
            Image = "",
            ZIndex = 9999,
        })
        new("UICorner", {Parent = alphaBar, CornerRadius = UDim.new(0, 30)})
        local alphaGrad = new("UIGradient", {
            Parent = alphaBar,
            Color = ColorSequence.new(Color3.new(0, 0, 0), CP.Value),
        })
        local alphaPicker = new("Frame", {
            Parent = alphaBar,
            Size = UDim2.new(0, 12, 0, 12),
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(CP.Alpha, 0, 0.5, 0),
            BackgroundColor3 = Color3.new(1, 1, 1),
            BorderSizePixel = 0,
            ZIndex = 10001,
        })
        new("UIStroke", {Parent = alphaPicker, Color = Color3.new(1, 1, 1)})
        new("UICorner", {Parent = alphaPicker, CornerRadius = UDim.new(1, 100)})

        -- Eyedropper button — bottom-left.
        local eyeBtn = new("Frame", {
            Parent = popup,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 10, 1, -12),
            Size = UDim2.new(0, 28, 0, 28),
            BackgroundColor3 = Color3.fromRGB(21, 25, 30),
            BorderSizePixel = 0,
            ZIndex = 9999,
        })
        new("UICorner", {Parent = eyeBtn, CornerRadius = UDim.new(0, 3)})
        themed(eyeBtn, "BackgroundColor3", "BgHeader")
        local eyeIcon = new("ImageLabel", {
            Parent = eyeBtn,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 18, 0, 18),
            BackgroundTransparency = 1,
            Image = "rbxassetid://140690366906069",
            ImageColor3 = Color3.fromRGB(126, 125, 130),
            ZIndex = 10000,
        })
        themed(eyeIcon, "ImageColor3", "TextInactive")

        -- Logic
        local function updateColor(fire)
            CP.Value = Color3.fromHSV(CP.Hue, CP.Sat, CP.Val)
            leftHalf.BackgroundColor3 = CP.Value
            rightHalf.BackgroundColor3 = CP.Value
            rightHalf.BackgroundTransparency = 1 - CP.Alpha
            satGrad.Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromHSV(CP.Hue, 1, 1))
            alphaGrad.Color = ColorSequence.new(Color3.new(0, 0, 0), CP.Value)
            cfPicker.Position = UDim2.new(CP.Sat, 0, 1 - CP.Val, 0)
            huePicker.Position = UDim2.new(CP.Hue, 0, 0.5, 0)
            alphaPicker.Position = UDim2.new(CP.Alpha, 0, 0.5, 0)
            if cfg.Flag then Library.Flags[cfg.Flag] = CP.Value end
            if fire and cfg.Callback then pcall(cfg.Callback, CP.Value, CP.Alpha) end
        end

        local function bindDrag(area, onDrag)
            local dragging = false
            area.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    dragging = true; onDrag()
                end
            end)
            connect(UserInputService.InputEnded, function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
            end)
            connect(UserInputService.InputChanged, function(input)
                if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then onDrag() end
            end)
        end

        -- GetMouseLocation() and AbsolutePosition share a coord space here
        -- (PopupGui has IgnoreGuiInset = true), so the cursor's Y and the
        -- colorframe's Y are already in the same system — no inset
        -- adjustment needed.
        bindDrag(colorframe, function()
            local m = UserInputService:GetMouseLocation()
            local abs, sz = colorframe.AbsolutePosition, colorframe.AbsoluteSize
            CP.Sat = math.clamp((m.X - abs.X) / sz.X, 0, 1)
            CP.Val = 1 - math.clamp((m.Y - abs.Y) / sz.Y, 0, 1)
            updateColor(true)
        end)
        bindDrag(hueBar, function()
            local m = UserInputService:GetMouseLocation()
            local abs, sz = hueBar.AbsolutePosition, hueBar.AbsoluteSize
            CP.Hue = math.clamp((m.X - abs.X) / sz.X, 0, 1)
            updateColor(true)
        end)
        bindDrag(alphaBar, function()
            local m = UserInputService:GetMouseLocation()
            local abs, sz = alphaBar.AbsolutePosition, alphaBar.AbsoluteSize
            CP.Alpha = math.clamp((m.X - abs.X) / sz.X, 0, 1)
            updateColor(true)
        end)

        local function updatePopupPos()
            local abs, sz = chip.AbsolutePosition, chip.AbsoluteSize
            popup.Position = UDim2.fromOffset(
                math.max(8, abs.X + sz.X - 218),
                abs.Y + sz.Y + 6
            )
        end

        local followConn
        local function setOpen(open)
            CP.Open = open
            if open then
                updatePopupPos()
                popup.Visible = true
                popup.Size = UDim2.new(0, 218, 0, 0)
                tween(popup, {Size = UDim2.new(0, 218, 0, 175)}, TI_SMOOTH)
                followConn = RunService.RenderStepped:Connect(updatePopupPos)
                if Tab.Window and Tab.Window.OpenPopup then
                    Tab.Window:OpenPopup(popup, function() setOpen(false) end)
                end
            else
                if followConn then followConn:Disconnect(); followConn = nil end
                tween(popup, {Size = UDim2.new(0, 218, 0, 0)}, TI_QUICK)
                if Tab.Window and Tab.Window.ClosePopup then
                    Tab.Window:ClosePopup(popup)
                end
                task.delay(0.16, function() if not CP.Open then popup.Visible = false end end)
            end
        end

        -- Chip interactions. Outside-click closure is handled by the window's
        -- modal blocker; no UIS listener needed here.
        chip.MouseEnter:Connect(function() tween(chip, {Size = UDim2.new(0, 22, 0, 22)}, TI_POP) end)
        chip.MouseLeave:Connect(function() tween(chip, {Size = UDim2.new(0, 20, 0, 20)}, TI_QUICK) end)
        chip.MouseButton1Click:Connect(function() setOpen(not CP.Open) end)

        function CP:Set(color, alpha, silent)
            -- silent=true: snap chip + popup visuals to new color WITHOUT
            -- firing cfg.Callback. Used by the Theming section's preset
            -- loader so applying a preset doesn't bounce SetTheme→Callback
            -- →SetTheme in a loop.
            if type(color) == "table" then color = Color3.fromRGB(color[1], color[2], color[3]) end
            self.Value = color
            if alpha then self.Alpha = math.clamp(alpha, 0, 1) end
            self.Hue, self.Sat, self.Val = color:ToHSV()
            updateColor(not silent)
        end

        if cfg.Flag then
            Library.Flags[cfg.Flag] = CP.Value
            Library.SetFlags[cfg.Flag] = function(v) CP:Set(v) end
        end
        updateColor(false)
        return CP
    end

    --// ── AddLabel (with optional :Colorpicker chained) ──────────
    function Section:AddLabel(text)
        local row = component("Label_Component", 26)
        local lbl = new("TextLabel", {
            Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.new(1, -24, 1, 0),
            BackgroundTransparency = 1,
            Text = text or "",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(lbl, "TextColor3", "Text")
        local Label = {Frame = row, Instance = lbl}
        Label._searchKey = (text or ""):lower()
        function Label:Set(t)
            lbl.Text = t
            self._searchKey = (t or ""):lower()
        end

        -- Chained colorpickers — lazy right-side chip holder created on the
        -- first :Colorpicker call. Subsequent chained calls append to it;
        -- each gets a higher LayoutOrder so newer chips go to the right and
        -- older ones shift left within the right-aligned stack.
        local cpHolder
        local cpCount = 0
        function Label:Colorpicker(cp)
            if not cpHolder then
                cpHolder = new("Frame", {
                    Parent = row,
                    AnchorPoint = Vector2.new(1, 0.5),
                    Position = UDim2.new(1, -12, 0.5, 0),
                    Size = UDim2.new(0, 1, 0, 20),
                    AutomaticSize = Enum.AutomaticSize.X,
                    BackgroundTransparency = 1,
                    BorderSizePixel = 0,
                })
                new("UIListLayout", {
                    Parent = cpHolder,
                    FillDirection = Enum.FillDirection.Horizontal,
                    HorizontalAlignment = Enum.HorizontalAlignment.Right,
                    VerticalAlignment = Enum.VerticalAlignment.Center,
                    Padding = UDim.new(0, 6),
                    SortOrder = Enum.SortOrder.LayoutOrder,
                })
            end
            cpCount = cpCount + 1
            return createColorpicker(cpHolder, { LayoutOrder = cpCount }, cp)
        end

        function Label:Tooltip(text) return attachTooltip(self, lbl, text) end

        table.insert(Section.Components, Label)
        return Label
    end

    --// ── AddToggle (with optional Keybind / Settings cog / Colorpicker chip) ──
    function Section:AddToggle(cfg)
        cfg = cfg or {}
        local flag = cfg.Flag or nextFlag("toggle")
        local Toggle = {Value = cfg.Default and true or false, Flag = flag}

        local row = component("Toggle_Component", 35)

        local box = new("TextButton", {
            Name = "Toggle", Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.new(0, 20, 0, 20),
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            AutoButtonColor = false, Text = "",
        })
        new("UICorner", {Parent = box, CornerRadius = UDim.new(0, 2)})

        local check = new("ImageLabel", {
            Name = "Check", Parent = box,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, 12, 0, 10),
            BackgroundTransparency = 1,
            Image = ICONS.check,
            ImageColor3 = Theme.CheckIcon,
            ImageTransparency = 1,
            ScaleType = Enum.ScaleType.Fit,
        })
        themed(check, "ImageColor3", "CheckIcon")

        local lbl = new("TextLabel", {
            Name = "Toggle_Name", Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 43, 0.5, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = cfg.Name or "Toggle",
            TextColor3 = Theme.TextDisabled,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        -- State-dependent label color (Text when ON, TextDisabled when OFF).
        local function applyLblColor()
            lbl.TextColor3 = Toggle.Value and Theme.Text or Theme.TextDisabled
        end
        subscribeTheme("Text", applyLblColor)
        subscribeTheme("TextDisabled", applyLblColor)

        function Toggle:Set(v, fire)
            self.Value = v and true or false
            Library.Flags[flag] = self.Value
            tween(box, {BackgroundColor3 = self.Value and Theme.Accent or Theme.BgHeader}, TI_QUICK)
            tween(check, {
                ImageTransparency = self.Value and 0 or 1,
                Size = self.Value and UDim2.new(0, 12, 0, 10) or UDim2.new(0, 6, 0, 5),
            }, TI_POP)
            tween(lbl, {TextColor3 = self.Value and Theme.Text or Theme.TextDisabled}, TI_QUICK)
            if fire ~= false and cfg.Callback then pcall(cfg.Callback, self.Value) end
        end

        -- Live theme update for the toggle box. State-dependent (Accent when
        -- ON, BgHeader when OFF) so we subscribe to both keys and recompute
        -- against the current Toggle.Value on each fire.
        local function applyBoxBg()
            box.BackgroundColor3 = Toggle.Value and Theme.Accent or Theme.BgHeader
        end
        subscribeTheme("Accent", applyBoxBg)
        subscribeTheme("BgHeader", applyBoxBg)

        box.MouseEnter:Connect(function()
            if not Toggle.Value then tween(box, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end
        end)
        box.MouseLeave:Connect(function()
            if not Toggle.Value then tween(box, {BackgroundColor3 = Theme.BgHeader}, TI_QUICK) end
        end)
        -- Only the box itself triggers the toggle. Clicking elsewhere on the
        -- row (cog, keybind pill, etc.) must not fire it.
        box.MouseButton1Click:Connect(function() Toggle:Set(not Toggle.Value, true) end)

        -- Right-side holder (for keybind / settings / colorpicker)
        local rightHolder = new("Frame", {
            Parent = row,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
        })
        new("UIListLayout", {
            Parent = rightHolder,
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })
        Toggle.RightHolder = rightHolder

        -- Optional Keybind sub-component (Toggle:Keybind({...}) chain).
        -- Layout matches the supplied design: [SettingsHolder/cog] [Keybind/pill]
        -- in a row, right-aligned. Cog goes LEFT (LayoutOrder 1), pill goes
        -- RIGHT (LayoutOrder 2). Cog is decorative (hover-only ImageLabel),
        -- pill is the listener TextLabel.
        function Toggle:Keybind(kcfg)
            kcfg = kcfg or {}
            local KB = {Key = kcfg.Default}
            if kcfg.Flag and kcfg.Default then
                Library.Flags[kcfg.Flag] = kcfg.Default
            end

            -- Optional integration with the window's keybind list widget.
            -- ShowInList=true tells the list to show this binding while
            -- Toggle.Value is true. Mode = "Hold"/"Toggle" controls BOTH
            -- the H/T badge AND the runtime: Hold = toggle is ON only
            -- while the key is held; Toggle = key-press flips the value.
            -- currentMode is the live state — right-click on the pill
            -- opens a context menu that mutates it via setMode().
            local showInList = kcfg.ShowInList and true or false
            local listName = kcfg.Name or cfg.Name or "Toggle"
            local currentMode = kcfg.Mode or "Toggle"
            local function syncList()
                if not showInList then return end
                local KL = Tab.Window and Tab.Window.KeybindList
                if not KL then return end
                if Toggle.Value and KB.Key then
                    KL:Add(listName, currentMode, KB.Key.Name)
                else
                    KL:Remove(listName)
                end
            end

            -- Wrap Toggle:Set so any state flip (UI click, hotkey, config
            -- load) re-syncs the list. Wrapped per-Keybind so toggles
            -- without ShowInList aren't paying for the extra call.
            if showInList then
                local origSet = Toggle.Set
                Toggle.Set = function(self, v, fire)
                    origSet(self, v, fire)
                    syncList()
                end
            end

            -- Cog + settings popup only exist when the caller passed a
            -- Settings function. Without one, the row is just [Toggle][Pill]
            -- (matches the design for popup-less keybind rows like Triggerbot).
            local settingsPopup
            if type(kcfg.Settings) == "function" then
                local cogHolder = new("Frame", {
                    Name = "SettingsHolder",
                    Parent = rightHolder, LayoutOrder = 1,
                    BackgroundTransparency = 1,
                    Size = UDim2.new(0, 26, 0, 26),
                    BorderSizePixel = 0,
                })
                local cogImg = new("ImageLabel", {
                    Parent = cogHolder,
                    AnchorPoint = Vector2.new(0.5, 0.5),
                    Position = UDim2.new(0.5, 0, 0.5, 0),
                    Size = UDim2.new(0, 18, 0, 18),
                    BackgroundTransparency = 1,
                    Image = ICONS.cog,
                    ImageColor3 = Theme.TextInactive,
                    BorderSizePixel = 0,
                })
                themed(cogImg, "ImageColor3", "TextInactive")
                cogHolder.MouseEnter:Connect(function()
                    tween(cogImg, {ImageColor3 = Theme.Text, Rotation = 30}, TI_QUICK)
                end)
                cogHolder.MouseLeave:Connect(function()
                    tween(cogImg, {ImageColor3 = Theme.TextInactive, Rotation = 0}, TI_QUICK)
                end)

                settingsPopup = createSettingsPopup(cogHolder, {
                    Name = kcfg.SettingsName or (kcfg.Name and (kcfg.Name .. " Options")) or "Options",
                    Icon = kcfg.SettingsIcon,
                }, Tab)
                pcall(kcfg.Settings, settingsPopup)

                cogHolder.InputBegan:Connect(function(input)
                    if input.UserInputType == Enum.UserInputType.MouseButton1 then
                        settingsPopup:Toggle()
                    end
                end)
            end
            KB.Settings = settingsPopup

            -- Pill (right)
            local pill = new("TextLabel", {
                Name = "Keybind",
                Parent = rightHolder, LayoutOrder = 2,
                BackgroundColor3 = Theme.BgHeader,
                BorderSizePixel = 0,
                Text = KB.Key and KB.Key.Name or "NONE",
                TextColor3 = Theme.Text,
                FontFace = FONT_MED, TextSize = 14,
                AutomaticSize = Enum.AutomaticSize.XY,
                Size = UDim2.new(0, 1, 0, 1),
                ZIndex = 50,
            })
            new("UICorner", {Parent = pill, CornerRadius = UDim.new(0, 4)})
            new("UIPadding", {
                Parent = pill,
                PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
                PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
            })
            themed(pill, "BackgroundColor3", "BgHeader")
            themed(pill, "TextColor3", "Text")

            -- State menu is lazy-created on the first right-click. Its
            -- setMode callback mutates currentMode AND re-syncs the list
            -- (so the H/T badge swaps live). KL:Add handles the same-name
            -- path with a mode swap, no need to remove + re-add.
            local stateMenu
            local function openStateMenu()
                if not stateMenu then
                    stateMenu = createKeybindStateMenu(
                        Tab.Window, pill,
                        function() return currentMode end,
                        function(newMode)
                            currentMode = newMode
                            syncList()
                        end
                    )
                end
                stateMenu:Toggle()
            end

            local listening = false
            pill.InputBegan:Connect(function(input)
                if input.UserInputType == Enum.UserInputType.MouseButton1 then
                    listening = true
                    pill.Text = "..."
                elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
                    openStateMenu()
                end
            end)
            connect(UserInputService.InputBegan, function(input, gpe)
                if gpe then return end
                if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                    KB.Key = input.KeyCode
                    pill.Text = input.KeyCode.Name
                    listening = false
                    if kcfg.Flag then Library.Flags[kcfg.Flag] = input.KeyCode end
                    if kcfg.Callback then pcall(kcfg.Callback, input.KeyCode) end
                    syncList()
                elseif not listening and KB.Key and input.KeyCode == KB.Key then
                    -- Hold mode → key down forces ON; KeyUp listener below
                    -- forces OFF on release. Toggle mode → flip the value.
                    if currentMode == "Hold" then
                        Toggle:Set(true, true)
                    else
                        Toggle:Set(not Toggle.Value, true)
                    end
                end
            end)
            -- Hold-mode key release → force OFF. No-op for Toggle mode or
            -- when the released key isn't the bind.
            connect(UserInputService.InputEnded, function(input)
                if currentMode == "Hold" and KB.Key and input.KeyCode == KB.Key then
                    Toggle:Set(false, true)
                end
            end)

            function KB:Set(k)
                self.Key = k
                pill.Text = k and k.Name or "NONE"
                syncList()
            end

            if kcfg.Flag then
                -- KB:Set updates the pill visuals + list, but doesn't touch
                -- Library.Flags or the user callback (that's done in the
                -- input handler on a real keypress). Mirror those here so
                -- a config load fully restores the bind.
                Library.SetFlags[kcfg.Flag] = function(v)
                    KB:Set(v)
                    Library.Flags[kcfg.Flag] = v
                    if kcfg.Callback then pcall(kcfg.Callback, v) end
                end
            end

            -- Catch the case where the toggle starts ON with a default key —
            -- the syncList from the Set wrap fired before Keybind was wired.
            if showInList and Toggle.Value and KB.Key then
                task.defer(syncList)
            end
            return KB
        end

        -- Optional Colorpicker chip(s) — chain Toggle:Colorpicker({...})
        -- multiple times to stack chips. Each call gets an incrementing
        -- LayoutOrder so the newest chip goes to the rightmost slot and
        -- older chips shift left within the right-aligned rightHolder.
        local cpCount = 0
        function Toggle:Colorpicker(cp)
            cpCount = cpCount + 1
            return createColorpicker(rightHolder, { LayoutOrder = 50 + cpCount }, cp)
        end

        Toggle:Set(Toggle.Value, false)
        -- Config-load setter — fires the callback so user-side state
        -- (speed, ESP, etc) actually re-applies, not just the UI.
        Library.SetFlags[flag] = function(v) Toggle:Set(v, true) end
        Toggle.Frame = row
        Toggle.Box = box
        Toggle._searchKey = (cfg.Name or "toggle"):lower()
        function Toggle:Tooltip(text) return attachTooltip(self, lbl, text) end
        if cfg.Tooltip then attachTooltip(Toggle, lbl, cfg.Tooltip) end
        table.insert(Section.Components, Toggle)
        return Toggle
    end

    --// ── AddButton ──────────────────────────────────────────────
    function Section:AddButton(cfg)
        cfg = cfg or {}
        local row = component("Button_Component", 46)
        local btn = new("TextButton", {
            Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.new(1, -24, 0, 35),
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            Text = cfg.Name or "Button",
            TextColor3 = Theme.Text,
            FontFace = FONT_REG, TextSize = 14,
            AutoButtonColor = false,
        })
        new("UICorner", {Parent = btn, CornerRadius = UDim.new(0, 2)})
        themed(btn, "BackgroundColor3", "BgHeader")
        themed(btn, "TextColor3", "Text")

        btn.MouseEnter:Connect(function() tween(btn, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end)
        btn.MouseLeave:Connect(function() tween(btn, {BackgroundColor3 = Theme.BgHeader}, TI_QUICK) end)
        btn.MouseButton1Down:Connect(function() tween(btn, {BackgroundColor3 = Theme.Accent}, TI_QUICK) end)
        btn.MouseButton1Up:Connect(function() tween(btn, {BackgroundColor3 = Theme.BgHeader}, TI_SMOOTH) end)
        btn.MouseButton1Click:Connect(function()
            if cfg.Callback then pcall(cfg.Callback) end
        end)

        local Btn = {Frame = row, Instance = btn}
        Btn._searchKey = (cfg.Name or "button"):lower()
        function Btn:Set(text) btn.Text = text end
        function Btn:Tooltip(text) return attachTooltip(self, btn, text) end
        if cfg.Tooltip then attachTooltip(Btn, btn, cfg.Tooltip) end
        table.insert(Section.Components, Btn)
        return Btn
    end

    --// ── AddSlider ──────────────────────────────────────────────
    function Section:AddSlider(cfg)
        cfg = cfg or {}
        local flag = cfg.Flag or nextFlag("slider")
        local minV, maxV = cfg.Min or 0, cfg.Max or 100
        local Slider = {Value = cfg.Default or minV, Flag = flag}

        local row = component("Slider_Component", 38)
        local sliderName = new("TextLabel", {
            Name = "Slider_Name", Parent = row,
            Position = UDim2.new(0, 13, 0, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = cfg.Name or "Slider",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(sliderName, "TextColor3", "Text")
        local valLbl = new("TextLabel", {
            Name = "Slider_Value", Parent = row,
            AnchorPoint = Vector2.new(1, 0),
            Position = UDim2.new(1, -15, 0, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = tostring(Slider.Value),
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
        })
        themed(valLbl, "TextColor3", "Text")

        local progBg = new("Frame", {
            Name = "Progress_BG", Parent = row,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 12, 1, 0),
            Size = UDim2.new(1, -24, 0, 15),
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
        })
        new("UICorner", {Parent = progBg, CornerRadius = UDim.new(0, 2)})
        themed(progBg, "BackgroundColor3", "BgHeader")

        local progBar = new("Frame", {
            Name = "Progress_Bar", Parent = progBg,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 0, 0.5, 0),
            Size = UDim2.new(0, 0, 1, 0),
            BackgroundColor3 = Theme.Accent,
            BorderSizePixel = 0,
        })
        new("UICorner", {Parent = progBar, CornerRadius = UDim.new(0, 2)})
        themed(progBar, "BackgroundColor3", "Accent")

        local function setValue(v, fire)
            v = math.clamp(v, minV, maxV)
            local step = cfg.Step or 1
            v = math.floor(v / step + 0.5) * step
            Slider.Value = v
            Library.Flags[flag] = v
            local pct = (v - minV) / math.max(maxV - minV, 1e-6)
            tween(progBar, {Size = UDim2.new(pct, 0, 1, 0)}, TI_SLIDE)
            valLbl.Text = (cfg.Suffix and tostring(v) .. cfg.Suffix) or tostring(v)
            if fire and cfg.Callback then pcall(cfg.Callback, v) end
        end

        local dragging = false
        progBg.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then
                dragging = true
                local mx = UserInputService:GetMouseLocation().X
                local pct = math.clamp((mx - progBg.AbsolutePosition.X) / progBg.AbsoluteSize.X, 0, 1)
                setValue(minV + (maxV - minV) * pct, true)
            end
        end)
        connect(UserInputService.InputEnded, function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
        end)
        connect(UserInputService.InputChanged, function(input)
            if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
                local mx = UserInputService:GetMouseLocation().X
                local pct = math.clamp((mx - progBg.AbsolutePosition.X) / progBg.AbsoluteSize.X, 0, 1)
                setValue(minV + (maxV - minV) * pct, true)
            end
        end)

        progBg.MouseEnter:Connect(function() tween(progBg, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end)
        progBg.MouseLeave:Connect(function() tween(progBg, {BackgroundColor3 = Theme.BgHeader}, TI_QUICK) end)

        function Slider:Set(v) setValue(v, true) end
        setValue(Slider.Value, false)
        Library.SetFlags[flag] = function(v) Slider:Set(tonumber(v) or v) end
        Slider.Frame = row
        Slider._searchKey = (cfg.Name or "slider"):lower()
        function Slider:Tooltip(text) return attachTooltip(self, sliderName, text) end
        if cfg.Tooltip then attachTooltip(Slider, sliderName, cfg.Tooltip) end
        table.insert(Section.Components, Slider)
        return Slider
    end

    --// ── AddTextbox ─────────────────────────────────────────────
    function Section:AddTextbox(cfg)
        cfg = cfg or {}
        local flag = cfg.Flag or nextFlag("textbox")
        local TB = {Value = cfg.Default or "", Flag = flag}

        local row = component("TextInput_Component", 53)
        local tbName = new("TextLabel", {
            Name = "TextInput_Name", Parent = row,
            Position = UDim2.new(0, 12, 0, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = cfg.Name or "Textbox",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(tbName, "TextColor3", "Text")

        local box = new("Frame", {
            Name = "Textbox", Parent = row,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 12, 1, 0),
            Size = UDim2.new(1, -24, 0, 30),
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
        })
        new("UICorner", {Parent = box, CornerRadius = UDim.new(0, 2)})
        themed(box, "BackgroundColor3", "BgHeader")

        local tbIcon = new("ImageLabel", {
            Name = "Icon", Parent = box,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.new(0, 14, 0, 14),
            BackgroundTransparency = 1,
            Image = ICONS.edit,
            ImageColor3 = Theme.TextInactive,
        })
        themed(tbIcon, "ImageColor3", "TextInactive")

        local input = new("TextBox", {
            Name = "Textinput", Parent = box,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 11, 0.5, 0),
            Size = UDim2.new(1, -32, 0, 20),
            BackgroundTransparency = 1,
            Text = TB.Value,
            PlaceholderText = cfg.Placeholder or "",
            PlaceholderColor3 = Theme.TextPH,
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            ClearTextOnFocus = false,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(input, "TextColor3", "Text")
        themed(input, "PlaceholderColor3", "TextPH")

        local function commit()
            local v = input.Text
            if cfg.Numeric then v = tonumber(v) or 0 end
            TB.Value = v
            Library.Flags[flag] = v
            if cfg.Callback then pcall(cfg.Callback, v) end
        end

        if cfg.Finished then
            input.FocusLost:Connect(commit)
        else
            input:GetPropertyChangedSignal("Text"):Connect(commit)
        end

        input.Focused:Connect(function() tween(box, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end)
        input.FocusLost:Connect(function() tween(box, {BackgroundColor3 = Theme.BgHeader}, TI_QUICK) end)

        function TB:Set(v) input.Text = tostring(v); commit() end
        commit()
        Library.SetFlags[flag] = function(v) TB:Set(v) end
        TB.Frame = row
        TB.Instance = input
        TB._searchKey = (cfg.Name or "textbox"):lower()
        function TB:Tooltip(text) return attachTooltip(self, tbName, text) end
        if cfg.Tooltip then attachTooltip(TB, tbName, cfg.Tooltip) end
        table.insert(Section.Components, TB)
        return TB
    end

    --// ── AddDropdown (single + multi) ───────────────────────────
    -- Popup lives in Window.PopupGui (separate ScreenGui, DisplayOrder 10000)
    -- so it floats above every other UI. Option rows match the supplied design:
    -- selected → bg (31,37,44) + checkmark icon + blue gradient liner + indented label
    -- unselected → bg (21,25,30) + dim text at left padding
    function Section:AddDropdown(cfg)
        cfg = cfg or {}
        local flag = cfg.Flag or nextFlag("dropdown")
        local items = cfg.Items or {}
        local multi = cfg.Multi and true or false
        local DD = {Value = cfg.Default, Flag = flag, Open = false, Items = items, Multi = multi}

        local row = component(multi and "MultiDropdown_Component" or "Dropdown_Component", 52)
        local ddName = new("TextLabel", {
            Name = "Dropdown_Name", Parent = row,
            Position = UDim2.new(0, 12, 0, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 1,
            Text = cfg.Name or "Dropdown",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(ddName, "TextColor3", "Text")

        local box = new("TextButton", {
            Name = "Dropdown", Parent = row,
            AnchorPoint = Vector2.new(0, 1),
            Position = UDim2.new(0, 12, 1, 0),
            Size = UDim2.new(1, -24, 0, 30),
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            AutoButtonColor = false, Text = "",
        })
        new("UICorner", {Parent = box, CornerRadius = UDim.new(0, 2)})
        themed(box, "BackgroundColor3", "BgHeader")

        local optLbl = new("TextLabel", {
            Name = "Option", Parent = box,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 11, 0.5, 0),
            Size = UDim2.new(1, -32, 0, 20),
            BackgroundTransparency = 1,
            Text = "...",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
        })
        themed(optLbl, "TextColor3", "Text")

        -- Single dropdowns use a different icon (chevronDown) than multis
        -- (chevron / hamburger) — matches the supplied dump.
        local chevron = new("ImageLabel", {
            Name = "Icon", Parent = box,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -10, 0.5, 0),
            Size = UDim2.new(0, 14, 0, 16),
            BackgroundTransparency = 1,
            Image = multi and ICONS.chevron or ICONS.chevronDown,
            ImageColor3 = Theme.Text,
        })
        themed(chevron, "ImageColor3", "Text")

        -- POPUP — lives in the top-level Window.PopupGui (above everything)
        local popupParent = (Tab.Window and Tab.Window.PopupGui) or row
        local popup = new("Frame", {
            Name = "DropdownOptions", Parent = popupParent,
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.new(0, 260, 0, 0),
            Visible = false,
            ClipsDescendants = true,
            ZIndex = 200,  -- above the settings popup (ZIndex 20)
        })
        new("UICorner", {Parent = popup, CornerRadius = UDim.new(0, 2)})
        new("UIListLayout", {Parent = popup, SortOrder = Enum.SortOrder.LayoutOrder})
        themed(popup, "BackgroundColor3", "BgHeader")

        -- Total target height grows/shrinks with the items array.
        local function getTargetHeight()
            return #items * 30
        end

        -- Position-follow: keep popup glued under the dropdown box. Size is
        -- driven by the open/close tween, NOT here — so we only touch X
        -- offset/width here and leave Y.Offset alone.
        local function updatePopupPos()
            local abs = box.AbsolutePosition
            local sz  = box.AbsoluteSize
            popup.Position = UDim2.fromOffset(abs.X, abs.Y + sz.Y + 4)
        end

        local followConn

        local function refresh()
            if multi then
                local picked = {}
                if type(DD.Value) == "table" then
                    for k, v in pairs(DD.Value) do if v then table.insert(picked, k) end end
                end
                table.sort(picked)
                optLbl.Text = (#picked == 0) and "None" or table.concat(picked, ", ")
            else
                optLbl.Text = tostring(DD.Value or "None")
            end
        end

        local function isItemSelected(item)
            if multi then
                return type(DD.Value) == "table" and DD.Value[item] == true
            else
                return DD.Value == item
            end
        end

        -- Smooth popup show/hide. On open: snap to 0 height, tween to target,
        -- register with the window's popup manager. On close: tween back to
        -- 0 height, then hide; manager teardown happens via ClosePopup.
        local function setOpen(v)
            DD.Open = v
            if v then
                updatePopupPos()
                local targetW = box.AbsoluteSize.X
                local targetH = getTargetHeight()
                popup.Size = UDim2.new(0, targetW, 0, 0)
                popup.Visible = true
                tween(popup, {Size = UDim2.new(0, targetW, 0, targetH)}, TI_SMOOTH)
                tween(chevron, {Rotation = 180}, TI_SMOOTH)
                followConn = RunService.RenderStepped:Connect(updatePopupPos)
                if Tab.Window and Tab.Window.OpenPopup then
                    Tab.Window:OpenPopup(popup, function() setOpen(false) end)
                end
            else
                tween(chevron, {Rotation = 0}, TI_SMOOTH)
                if followConn then followConn:Disconnect(); followConn = nil end
                local curW = popup.Size.X.Offset
                tween(popup, {Size = UDim2.new(0, curW, 0, 0)}, TI_QUICK)
                if Tab.Window and Tab.Window.ClosePopup then
                    Tab.Window:ClosePopup(popup)
                end
                task.delay(0.16, function()
                    if not DD.Open then popup.Visible = false end
                end)
            end
        end

        -- Store option syncers so we can refresh all when selection changes
        -- OR when a theme key the options depend on changes (they read live
        -- Theme.X at sync time so this re-applies the current values).
        local optionSyncers = {}
        local function reapplyOptionThemes()
            for _, sync in ipairs(optionSyncers) do
                pcall(sync, false)
            end
        end
        subscribeTheme("Accent", reapplyOptionThemes)
        subscribeTheme("Text", reapplyOptionThemes)
        subscribeTheme("TextDim", reapplyOptionThemes)
        subscribeTheme("BgHeader", reapplyOptionThemes)
        subscribeTheme("Hover", reapplyOptionThemes)
        subscribeTheme("Selected", reapplyOptionThemes)

        local function buildItems()
            for _, c in ipairs(popup:GetChildren()) do
                if c:IsA("TextButton") then c:Destroy() end
            end
            table.clear(optionSyncers)

            for i, item in ipairs(items) do
                -- Each row: 260x30, ClipsDescendants, has rounded corners
                local opt = new("TextButton", {
                    Name = "OptionHolder", Parent = popup,
                    Size = UDim2.new(1, 0, 0, 30),
                    BackgroundColor3 = Theme.BgHeader,
                    BorderSizePixel = 0,
                    Text = "",
                    AutoButtonColor = false,
                    LayoutOrder = i,
                    ClipsDescendants = true,
                    ZIndex = 9999,
                })
                new("UICorner", {Parent = opt, CornerRadius = UDim.new(0, 2)})

                -- Left gradient liner (only visible when selected — fades in)
                local liner = new("Frame", {
                    Name = "Liner", Parent = opt,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, -2, 0.5, 0),
                    Size = UDim2.new(0, 5, 0.8, 1),
                    BackgroundColor3 = Color3.new(1, 1, 1),
                    BackgroundTransparency = 1,  -- hidden by default
                    BorderSizePixel = 0,
                    ZIndex = 10000,
                })
                local linerGrad = new("UIGradient", {
                    Parent = liner, Rotation = 90,
                    Color = ColorSequence.new(Theme.Accent),
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0.92),
                        NumberSequenceKeypoint.new(0.544, 0.35),
                        NumberSequenceKeypoint.new(1, 1),
                    }),
                })
                themedGradient(linerGrad, "Accent")

                -- Checkmark icon (only visible when selected)
                local icon = new("ImageLabel", {
                    Name = "Icon", Parent = opt,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 12, 0.5, 0),
                    Size = UDim2.new(0, 14, 0, 14),
                    BackgroundTransparency = 1,
                    Image = "rbxassetid://95956300578145",
                    ImageColor3 = Theme.Accent,
                    ImageTransparency = 1,
                    ZIndex = 10000,
                })
                themed(icon, "ImageColor3", "Accent")

                local lbl = new("TextLabel", {
                    Name = "Option", Parent = opt,
                    AnchorPoint = Vector2.new(0, 0.5),
                    Position = UDim2.new(0, 11, 0.5, 0),  -- shifts to 30 when selected
                    Size = UDim2.new(0, 1, 0, 1),
                    AutomaticSize = Enum.AutomaticSize.XY,
                    BackgroundTransparency = 1,
                    Text = tostring(item),
                    TextColor3 = Theme.TextDim,
                    FontFace = FONT_MED, TextSize = 14,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    ZIndex = 10000,
                })

                local hovering = false
                local function syncState(animated)
                    local sel = isItemSelected(item)
                    local bg = sel and Theme.Selected
                        or (hovering and Theme.Hover or Theme.BgHeader)
                    local lblPos = UDim2.new(0, sel and 30 or 11, 0.5, 0)
                    local lblColor = sel and Theme.Text or (hovering and Theme.Text or Theme.TextDim)

                    if animated then
                        tween(opt, {BackgroundColor3 = bg}, TI_QUICK)
                        tween(lbl, {Position = lblPos, TextColor3 = lblColor}, TI_SLIDE)
                        tween(icon, {ImageTransparency = sel and 0 or 1}, TI_QUICK)
                        tween(liner, {BackgroundTransparency = sel and 0 or 1}, TI_QUICK)
                    else
                        opt.BackgroundColor3 = bg
                        lbl.Position = lblPos
                        lbl.TextColor3 = lblColor
                        icon.ImageTransparency = sel and 0 or 1
                        liner.BackgroundTransparency = sel and 0 or 1
                    end
                end

                optionSyncers[i] = syncState
                syncState(false)

                opt.MouseEnter:Connect(function()
                    hovering = true
                    syncState(true)
                end)
                opt.MouseLeave:Connect(function()
                    hovering = false
                    syncState(true)
                end)
                opt.MouseButton1Click:Connect(function()
                    if multi then
                        if type(DD.Value) ~= "table" then DD.Value = {} end
                        if DD.Value[item] then DD.Value[item] = nil else DD.Value[item] = true end
                    else
                        DD.Value = item
                        setOpen(false)
                    end
                    Library.Flags[flag] = DD.Value
                    refresh()
                    if cfg.Callback then pcall(cfg.Callback, DD.Value) end
                    for _, sync in ipairs(optionSyncers) do sync(true) end
                end)
            end
        end

        -- Box hover + click. Outside-click closure is handled by the window's
        -- modal blocker; no UIS listener needed here.
        box.MouseEnter:Connect(function() tween(box, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end)
        box.MouseLeave:Connect(function() tween(box, {BackgroundColor3 = Theme.BgHeader}, TI_QUICK) end)
        box.MouseButton1Click:Connect(function() setOpen(not DD.Open) end)

        function DD:Set(v)
            self.Value = v
            Library.Flags[flag] = v
            refresh()
            for _, sync in ipairs(optionSyncers) do sync(true) end
            if cfg.Callback then pcall(cfg.Callback, v) end
        end
        function DD:Refresh(newItems)
            items = newItems or items
            self.Items = items
            buildItems()
        end

        buildItems()
        if multi and type(cfg.Default) == "table" then
            DD.Value = {}
            for _, v in ipairs(cfg.Default) do DD.Value[v] = true end
            for _, sync in ipairs(optionSyncers) do sync(false) end
        end
        refresh()
        Library.Flags[flag] = DD.Value
        Library.SetFlags[flag] = function(v) DD:Set(v) end
        DD.Frame = row
        DD._searchKey = (cfg.Name or "dropdown"):lower()
        function DD:Tooltip(text) return attachTooltip(self, ddName, text) end
        if cfg.Tooltip then attachTooltip(DD, ddName, cfg.Tooltip) end
        table.insert(Section.Components, DD)
        return DD
    end

    --// ── AddKeybind (standalone) ────────────────────────────────
    function Section:AddKeybind(cfg)
        cfg = cfg or {}
        local flag = cfg.Flag or nextFlag("keybind")
        local KB = {Key = cfg.Default, Flag = flag}
        if cfg.Default then Library.Flags[flag] = cfg.Default end

        -- Keybind list integration — standalone keybinds show in the list
        -- whenever a key is bound (no toggle state to gate on).
        local showInList = cfg.ShowInList and true or false
        local listName = cfg.Name or "Keybind"
        local listMode = cfg.Mode or "Toggle"
        local function syncList()
            if not showInList then return end
            local KL = Tab.Window and Tab.Window.KeybindList
            if not KL then return end
            if KB.Key then
                KL:Add(listName, listMode, KB.Key.Name)
            else
                KL:Remove(listName)
            end
        end

        local row = component("Keybind_Component", 35)

        local kbName = new("TextLabel", {
            Name = "Keybind_Name", Parent = row,
            AnchorPoint = Vector2.new(0, 0.5),
            Position = UDim2.new(0, 12, 0.5, 0),
            Size = UDim2.new(1, -100, 1, 0),
            BackgroundTransparency = 1,
            Text = cfg.Name or "Keybind",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(kbName, "TextColor3", "Text")

        local pill = new("TextButton", {
            Name = "Keybind", Parent = row,
            AnchorPoint = Vector2.new(1, 0.5),
            Position = UDim2.new(1, -12, 0.5, 0),
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundColor3 = Theme.BgHeader,
            BorderSizePixel = 0,
            Text = KB.Key and KB.Key.Name or "NONE",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            AutoButtonColor = false,
        })
        new("UICorner", {Parent = pill, CornerRadius = UDim.new(0, 4)})
        new("UIPadding", {
            Parent = pill,
            PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4),
            PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6),
        })
        themed(pill, "BackgroundColor3", "BgHeader")
        themed(pill, "TextColor3", "Text")

        pill.MouseEnter:Connect(function() tween(pill, {BackgroundColor3 = Theme.Hover}, TI_QUICK) end)
        pill.MouseLeave:Connect(function() tween(pill, {BackgroundColor3 = Theme.BgHeader}, TI_QUICK) end)

        local listening = false
        pill.MouseButton1Click:Connect(function()
            listening = true
            pill.Text = "..."
        end)
        connect(UserInputService.InputBegan, function(input, gpe)
            if gpe then return end
            if listening and input.UserInputType == Enum.UserInputType.Keyboard then
                KB.Key = input.KeyCode
                pill.Text = input.KeyCode.Name
                listening = false
                Library.Flags[flag] = input.KeyCode
                if cfg.Callback then pcall(cfg.Callback, input.KeyCode) end
                syncList()
            elseif not listening and KB.Key and input.KeyCode == KB.Key then
                if cfg.Pressed then pcall(cfg.Pressed) end
            end
        end)

        function KB:Set(k)
            self.Key = k
            pill.Text = k and k.Name or "NONE"
            syncList()
        end
        -- KB:Set is intentionally minimal (visual + list only). The setter
        -- below mirrors what the live input handler does — write to Flags
        -- and fire Callback — so a config load fully restores the bind.
        Library.SetFlags[flag] = function(v)
            KB:Set(v)
            Library.Flags[flag] = v
            if cfg.Callback then pcall(cfg.Callback, v) end
        end
        KB.Frame = row
        KB._searchKey = (cfg.Name or "keybind"):lower()
        function KB:Tooltip(text) return attachTooltip(self, kbName, text) end
        if cfg.Tooltip then attachTooltip(KB, kbName, cfg.Tooltip) end
        -- Catch the case where a default key was supplied — defer so the
        -- KeybindList exists by the time we touch it.
        if showInList and KB.Key then task.defer(syncList) end
        table.insert(Section.Components, KB)
        return KB
    end

    --// ── AddColorpicker (standalone) ────────────────────────────
    -- Row layout: [Chip(s)][Label]. The first chip is built from cfg
    -- (Default/Flag/Callback). Chain :Colorpicker({...}) to add more
    -- chips next to the first — each gets a higher LayoutOrder so
    -- newer chips go to the right and the label slides further right.
    -- Useful for gradient start/end, primary/secondary, etc.
    function Section:AddColorpicker(cfg)
        cfg = cfg or {}
        local row = component("Colorpicker_Component", 35)

        new("UIPadding", {Parent = row, PaddingLeft = UDim.new(0, 12)})
        new("UIListLayout", {
            Parent = row,
            FillDirection = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Left,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 10),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        -- Chip stack (left)
        local chipHolder = new("Frame", {
            Parent = row, LayoutOrder = 0,
            BackgroundTransparency = 1,
            Size = UDim2.new(0, 1, 0, 20),
            AutomaticSize = Enum.AutomaticSize.X,
            BorderSizePixel = 0,
        })
        new("UIListLayout", {
            Parent = chipHolder,
            FillDirection = Enum.FillDirection.Horizontal,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Padding = UDim.new(0, 6),
            SortOrder = Enum.SortOrder.LayoutOrder,
        })

        -- Label (right of chip stack)
        local lbl = new("TextLabel", {
            Parent = row, LayoutOrder = 1,
            BackgroundTransparency = 1,
            Text = cfg.Name or "Colorpicker",
            TextColor3 = Theme.Text,
            FontFace = FONT_MED, TextSize = 14,
            Size = UDim2.new(0, 1, 0, 1),
            AutomaticSize = Enum.AutomaticSize.XY,
            TextXAlignment = Enum.TextXAlignment.Left,
        })
        themed(lbl, "TextColor3", "Text")

        local CP = {Frame = row, Instance = lbl, ChipHolder = chipHolder}
        CP._searchKey = (cfg.Name or "colorpicker"):lower()

        local cpCount = 0
        function CP:Colorpicker(cp)
            cpCount = cpCount + 1
            return createColorpicker(chipHolder, { LayoutOrder = cpCount }, cp)
        end

        -- Build the first chip from cfg.
        CP.Primary = CP:Colorpicker(cfg)

        function CP:Tooltip(text) return attachTooltip(self, lbl, text) end
        if cfg.Tooltip then attachTooltip(CP, lbl, cfg.Tooltip) end
        table.insert(Section.Components, CP)
        return CP
    end

    if not config.Holder then
        table.insert(Tab.Sections, Section)
        -- First-load case: SwitchTab fires before any sections exist, so its
        -- cascade has nothing to animate. Catch newly-added sections to the
        -- currently-visible tab here so they pop in as they're created.
        if Tab.Window and Tab.Window.CurrentTab == Tab and Tab.Window._animateSectionEntrance then
            Tab.Window:_animateSectionEntrance(Section, 0)
        end
    end
    return Section
end

--// ============================================================
--// Settings popup (right-of-cog widget)
--// ============================================================
-- Floats to the right of an anchor element (typically the keybind cog). Body
-- is built by passing a `Settings = function(s) ... end` to Toggle:Keybind —
-- the function receives a Section-like object with the standard API
-- (AddToggle/AddSlider/AddDropdown/etc) and adds whatever rows it wants.
createSettingsPopup = function(anchor, opts, Tab)
    opts = opts or {}
    local W = (Tab and Tab.Window) or nil
    local popupParent = (W and W.PopupGui) or anchor

    -- TextButton (not Frame) so it RELIABLY absorbs clicks. In Roblox, a
    -- Frame's `Active = true` is supposed to sink input but in practice
    -- still leaks clicks through to siblings behind it in some setups.
    -- TextButton always intercepts the click — children with their own
    -- handlers still get clicks first since they render on top.
    local popup = new("TextButton", {
        Name = "MiscOptions",
        Parent = popupParent,
        AnchorPoint = Vector2.new(0, 0),  -- top-left anchor → drops down from cog
        Position = UDim2.fromOffset(0, 0),
        Size = UDim2.new(0, 259, 0, 0),
        BackgroundColor3 = Theme.BgDark,
        BorderSizePixel = 0,
        AutomaticSize = Enum.AutomaticSize.Y,
        Visible = false,
        ZIndex = 20,
        Text = "",
        AutoButtonColor = false,
        Selectable = false,
        Active = true,
    })
    new("UICorner", {Parent = popup, CornerRadius = UDim.new(0, 4)})
    themed(popup, "BackgroundColor3", "BgDark")
    -- 1.5px stroke with ApplyStrokeMode.Border so it renders strictly on the
    -- popup's outline. Color stays at Theme.BgHeader per the dump; thickness
    -- bumped from 1 → 1.5 so it's actually visible against the dark bg.
    local popupStroke = new("UIStroke", {
        Parent = popup,
        Color = Theme.BgHeader,
        Thickness = 1.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        LineJoinMode = Enum.LineJoinMode.Round,
    })
    themed(popupStroke, "Color", "BgHeader")
    new("UIListLayout", {Parent = popup, SortOrder = Enum.SortOrder.LayoutOrder})
    new("UIPadding", {Parent = popup, PaddingBottom = UDim.new(0, 6)})

    -- UIScale animates the popout (Scale tween 0 → 1 / 1 → 0).
    local scale = new("UIScale", {Parent = popup, Scale = 0})

    -- Header (35h): icon (15x15 at x=15) + title at x=40
    local header = new("Frame", {
        Name = "Header",
        Parent = popup,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 259, 0, 35),
        BorderSizePixel = 0,
        LayoutOrder = 0,
    })
    local popupHeaderIcon = new("ImageLabel", {
        Name = "Icon",
        Parent = header,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 15, 0.5, 0),
        Size = UDim2.new(0, 15, 0, 15),
        BackgroundTransparency = 1,
        Image = resolveIcon(opts.Icon or "rbxassetid://128977408453752"),
        ImageColor3 = Theme.Accent,
    })
    themed(popupHeaderIcon, "ImageColor3", "Accent")
    local popupHeaderText = new("TextLabel", {
        Name = "MiscName",
        Parent = header,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 40, 0.5, 0),
        Size = UDim2.new(0, 1, 0, 1),
        AutomaticSize = Enum.AutomaticSize.XY,
        BackgroundTransparency = 1,
        Text = opts.Name or "Settings",
        TextColor3 = Theme.Text,
        FontFace = FONT_MED,
        TextSize = 14,
    })
    themed(popupHeaderText, "TextColor3", "Text")

    -- Content holder (where AddToggle/AddSlider/etc place their components).
    -- Also a TextButton with transparent background so it absorbs clicks in
    -- the 4px gaps between rows without becoming visible.
    local contentHolder = new("TextButton", {
        Name = "Content",
        Parent = popup,
        LayoutOrder = 1,
        BackgroundTransparency = 1,
        Size = UDim2.new(0, 259, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Selectable = false,
        Active = true,
    })
    new("UIListLayout", {Parent = contentHolder, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder})

    -- Reuse buildSection — it skips frame creation and just attaches the
    -- component API to the supplied Holder.
    local Section = buildSection(Tab, {
        Name = opts.Name or "Settings",
        Icon = opts.Icon,
        Holder = contentHolder,
        ComponentWidth = 259,
    })
    Section.Popup    = popup
    Section.IsOpen   = false
    Section.Header   = header
    Section.Anchor   = anchor

    -- Popup top-left sits 8px right of the cog and 12px below its bottom.
    -- With AnchorPoint (0, 0) the popup grows right and down from there.
    local function updatePopupPos()
        local abs = anchor.AbsolutePosition
        local sz  = anchor.AbsoluteSize
        popup.Position = UDim2.fromOffset(abs.X + sz.X + 8, abs.Y + sz.Y + 28)
    end

    local followConn
    function Section:Open()
        if self.IsOpen then return end
        self.IsOpen = true
        updatePopupPos()
        popup.Visible = true
        scale.Scale = 0
        tween(scale, {Scale = 1}, TI_SMOOTH)
        followConn = RunService.RenderStepped:Connect(updatePopupPos)
        if W and W.OpenPopup then
            W:OpenPopup(popup, function() self:Close() end)
        end
    end
    function Section:Close()
        if not self.IsOpen then return end
        self.IsOpen = false
        if followConn then followConn:Disconnect(); followConn = nil end
        tween(scale, {Scale = 0}, TI_QUICK)
        if W and W.ClosePopup then W:ClosePopup(popup) end
        task.delay(0.16, function()
            if not Section.IsOpen then popup.Visible = false end
        end)
    end
    function Section:Toggle()
        if self.IsOpen then self:Close() else self:Open() end
    end

    return Section
end

return Library
