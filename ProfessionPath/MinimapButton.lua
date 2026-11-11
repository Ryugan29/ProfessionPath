-- Bouton de l'add-on sur le bord de la mini-carte.
-- Clic gauche : ouvre ou ferme la fenêtre. Glisser : le déplace autour de la mini-carte.
-- /ppath minimap : le cache ou le réaffiche. Position et choix sont gardés pour tout le compte :
--   ProfessionPathDB.minimap = { angle = angle en radians, hide = true si caché }
-- Fait maison, sans bibliothèque d'un autre auteur.

local _, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\ProfessionPath\\Media\\icon.png" -- extension obligatoire pour une image PNG
local DEFAULT_ANGLE = math.rad(225) -- en bas à gauche de la mini-carte
local EDGE_GAP = 5                  -- le centre du bouton se place juste au-delà du bord
local atan2 = math.atan2 or math.atan -- math.atan2 n'existe plus dans les Lua récents (tests hors jeu)

-- Décalage du bouton par rapport au centre de la mini-carte, pour un angle donné.
-- shape : réponse de GetMinimapShape() quand un add-on (Leatrix Plus, ElvUI...) change la forme
-- de la mini-carte. « SQUARE » : le bouton suit le bord du carré. Toute autre forme : un cercle.
function ns.MinimapButtonOffset(angle, width, height, shape)
    local halfWidth = (width or 140) / 2 + EDGE_GAP
    local halfHeight = (height or width or 140) / 2 + EDGE_GAP
    local x, y = math.cos(angle), math.sin(angle)
    if shape == "SQUARE" then
        -- Agrandit le vecteur jusqu'au bord du carré : le plus grand des deux côtés touche le bord.
        local stretch = 1 / math.max(math.abs(x), math.abs(y))
        x, y = x * stretch, y * stretch
    end
    return x * halfWidth, y * halfHeight
end

local function Settings()
    local db = ns.db
    if type(db.minimap) ~= "table" then db.minimap = {} end
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = DEFAULT_ANGLE end
    return db.minimap
end

local button = CreateFrame("Button", "ProfessionPathMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("LeftButtonUp")
button:RegisterForDrag("LeftButton")
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:Hide() -- affiché à la connexion, une fois la sauvegarde lue

local background = button:CreateTexture(nil, "BACKGROUND")
background:SetSize(20, 20)
background:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
background:SetPoint("TOPLEFT", button, "TOPLEFT", 7, -5)

local icon = button:CreateTexture(nil, "ARTWORK")
icon:SetSize(22, 22)
icon:SetTexture(ICON)
icon:SetPoint("TOPLEFT", button, "TOPLEFT", 5, -4)
-- Découpe ronde de l'icône, quand le client le permet.
if button.CreateMaskTexture and icon.AddMaskTexture then
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
end

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT", button, "TOPLEFT", 0, 0)

local function Place()
    local shape = type(GetMinimapShape) == "function" and GetMinimapShape() or "ROUND"
    local x, y = ns.MinimapButtonOffset(Settings().angle, Minimap:GetWidth(), Minimap:GetHeight(), shape)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- Pendant le glisser : l'angle suit le curseur autour du centre de la mini-carte.
local function FollowCursor()
    local centerX, centerY = Minimap:GetCenter()
    local cursorX, cursorY = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    if not (centerX and centerY and cursorX and cursorY) or scale == 0 then return end
    Settings().angle = atan2(cursorY / scale - centerY, cursorX / scale - centerX)
    Place()
end

button:SetScript("OnDragStart", function(self)
    GameTooltip:Hide()
    self:SetScript("OnUpdate", FollowCursor)
end)
button:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
end)
button:SetScript("OnClick", function()
    ns.ToggleUI()
end)
button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L.TITLE)
    GameTooltip:AddLine(L.MINIMAP_TIP_CLICK, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_TIP_DRAG, 1, 1, 1)
    GameTooltip:AddLine(L.MINIMAP_TIP_HIDE, 0.62, 0.64, 0.68, true)
    GameTooltip:Show()
end)
button:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- /ppath minimap : cache ou réaffiche le bouton, et annonce le résultat.
function ns.ToggleMinimapButton()
    local settings = Settings()
    settings.hide = not settings.hide or nil
    button:SetShown(not settings.hide)
    ns.Print(settings.hide and L.MINIMAP_HIDDEN or L.MINIMAP_SHOWN)
end

-- À la connexion, tous les add-ons sont chargés : une mini-carte carrée est déjà en place.
local eventFrame = CreateFrame("Frame")
pcall(eventFrame.RegisterEvent, eventFrame, "PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    if not ns.db then return end
    Place()
    button:SetShown(not Settings().hide)
end)
