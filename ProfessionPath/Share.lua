-- Partage de ce que le joueur a relevé : /ppath partager (ou /ppath share).
-- Ouvre une fenêtre avec un texte à copier, que le joueur colle dans une issue GitHub. Ce texte
-- contient les PNJ rencontrés (maîtres, marchands de fournitures) et les recettes lues chez les
-- maîtres, rangées par numéro. Il ne contient ni nom de personnage ni royaume.
-- tools/import_shares.js vérifie ces partages et les ajoute aux listes livrées avec l'add-on.

local _, ns = ...
local L, T = ns.L, ns.Theme
local C, S = T.colors, T.sizes

local SHARE_VERSION = 1
local ISSUE_URL = "https://github.com/Ryugan29/ProfessionPath/issues/new?template=share.yml"
local WIDTH, HEIGHT, PAD = 540, 380, 16
local BOX_HEIGHT = 200

-- Un champ du texte ne doit contenir ni séparateur ni retour à la ligne.
local function Field(value)
    if value == nil then return "" end
    if type(value) == "number" then
        if value == math.floor(value) then return string.format("%d", value) end
        local text = string.format("%.4f", value):gsub("0+$", "")
        return text
    end
    return (tostring(value):gsub("[;\r\n|]", " "))
end

local function Line(parts)
    local fields = {}
    for index = 1, parts.n or #parts do fields[index] = Field(parts[index]) end
    return table.concat(fields, ";")
end

-- PNJ vus en jeu par ce joueur (y compris ceux déjà livrés : ils comptent comme confirmations).
local function NpcLines()
    local lines = {}
    for key, npc in pairs(ns.db.npcs or {}) do
        local kind, id = tostring(key):match("^(%a+):(%d+)$")
        if kind and type(npc) == "table" and type(npc.map) == "number" then
            local items = {}
            for itemID in pairs(npc.items or {}) do items[#items + 1] = itemID end
            table.sort(items)
            lines[#lines + 1] = Line({ n = 11, "N", kind, tonumber(id), npc.name, npc.map, npc.x, npc.y,
                -- Le numéro de métier peut manquer (métier inconnu du personnage) : seul un nombre est partagé.
                npc.faction, type(npc.professionID) == "number" and npc.professionID or nil, npc.profession,
                table.concat(items, ",") })
        end
    end
    table.sort(lines)
    return lines
end

-- Recettes lues chez les maîtres, retrouvées par leur numéro grâce aux métiers des personnages
-- du compte (le maître les désigne par leur nom, qui change selon la langue du jeu).
local function RecipeLines()
    local lines, seen = {}, {}
    for _, char in pairs(ns.db.chars or {}) do
        for _, prof in pairs(char.profs or {}) do
            local taught = type(prof.id) == "number" and ns.TrainerRecipes(prof) or {}
            for _, recipe in ipairs(prof.recipes or {}) do
                local entry = taught[recipe.name]
                if entry and type(recipe.id) == "number" and not seen[recipe.id] then
                    seen[recipe.id] = true
                    -- D'anciennes sauvegardes notent 0 pour « aucun niveau requis » : c'est le niveau 1.
                    local level = (type(entry.level) == "number" and entry.level >= 1) and entry.level or 1
                    lines[#lines + 1] = { id = recipe.id, text = Line({ n = 5, "R", prof.id, recipe.id, level, entry.cost }) }
                end
            end
        end
    end
    table.sort(lines, function(a, b) return a.id < b.id end)
    local texts = {}
    for index, line in ipairs(lines) do texts[index] = line.text end
    return texts
end

-- Texte complet du partage, et nombre de PNJ et de recettes qu'il contient.
function ns.BuildShareText()
    local version, build = GetBuildInfo()
    local npcs, recipes = NpcLines(), RecipeLines()
    local all = { Line({ n = 3, "ProfessionPath-share " .. SHARE_VERSION, tostring(version) .. "." .. tostring(build), GetLocale() }) }
    for _, line in ipairs(npcs) do all[#all + 1] = line end
    for _, line in ipairs(recipes) do all[#all + 1] = line end
    return table.concat(all, "\n"), #npcs, #recipes
end

local frame

local function Build()
    frame = CreateFrame("Frame", "ProfessionPathShareFrame", UIParent)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
    frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    T.Fill(frame, "BACKGROUND", C.background):SetAllPoints(frame)
    T.Border(frame, C.border)
    tinsert(UISpecialFrames, "ProfessionPathShareFrame") -- Échap ferme la fenêtre

    frame.title = T.Text(frame, S.title, C.accent)
    frame.title:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -PAD)

    frame.help = T.Text(frame, S.small, C.text)
    frame.help:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
    frame.help:SetWidth(WIDTH - 2 * PAD)
    frame.help:SetWordWrap(true)
    frame.help:SetSpacing(2)

    frame.stats = T.Text(frame, S.small, C.muted)
    frame.stats:SetPoint("TOPLEFT", frame.help, "BOTTOMLEFT", 0, -8)

    local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", frame.stats, "BOTTOMLEFT", 0, -10)
    scroll:SetSize(WIDTH - 2 * PAD - 24, BOX_HEIGHT)
    T.Fill(scroll, "BACKGROUND", C.card):SetAllPoints(scroll)

    local box = CreateFrame("EditBox", nil, scroll)
    box:SetMultiLine(true)
    box:SetAutoFocus(false)
    box:SetFontObject(ChatFontNormal)
    box:SetWidth(WIDTH - 2 * PAD - 30)
    box:SetScript("OnEscapePressed", function() frame:Hide() end)
    -- Lecture seule : si le joueur tape dedans, le texte du partage revient tel quel.
    box:SetScript("OnTextChanged", function(self, byUser)
        if byUser and frame.text then
            self:SetText(frame.text)
            self:HighlightText()
        end
    end)
    scroll:SetScrollChild(box)
    frame.box = box

    local close = T.Button(frame, 100, 24, function() frame:Hide() end)
    close:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -PAD, PAD)
    close:SetLabel(L.SHARE_CLOSE)
end

-- Ouvre la fenêtre « texte à copier », texte déjà sélectionné. Sert au partage et au diagnostic :
-- { title, help, stats, text }.
function ns.ShowCopyWindow(content)
    if not frame then Build() end
    frame.text = content.text
    frame.title:SetText(content.title)
    frame.help:SetText(content.help)
    frame.stats:SetText(content.stats)
    frame.box:SetText(content.text)
    frame:Show()
    frame.box:SetFocus()
    frame.box:HighlightText()
end

-- /ppath partager
function ns.ShowShare()
    local text, npcs, recipes = ns.BuildShareText()
    if npcs + recipes == 0 then
        ns.Print(L.SHARE_EMPTY)
        return
    end
    ns.ShowCopyWindow({ title = L.SHARE_TITLE, help = L.SHARE_HELP:format(ISSUE_URL),
        stats = L.SHARE_STATS:format(npcs, recipes), text = text })
end
