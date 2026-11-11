-- Essai « à blanc » de l'add-on complet dans un faux jeu.
-- But : charger tous les fichiers dans l'ordre du .toc, simuler l'ouverture d'un métier, ouvrir
-- la fenêtre, cliquer sur les boutons et faire tourner les animations, pour attraper les erreurs
-- de programmation (fonction absente, valeur vide...) sans lancer WoW.
-- Limite : le faux jeu ne dessine rien. Il ne dit pas si c'est joli, seulement si ça plante.
-- Les recettes ci-dessous sont FICTIVES.

local loadAddonFile, tocFiles = ...

-- Faux éléments d'interface ---------------------------------------------------

local allFrames = {}

local defaults = {
    GetStringHeight = 12, GetStringWidth = 60, GetVerticalScroll = 0,
    GetLeft = 100, GetTop = 500, HasFocus = false, GetFont = "Fonts\\FAUX.TTF",
}

local function IsNumber(...)
    for index = 1, select("#", ...) do
        if type((select(index, ...))) ~= "number" then return false end
    end
    return true
end

local widgetMethods = {}
function widgetMethods:SetScript(name, fn) self.scripts[name] = fn end
function widgetMethods:GetScript(name) return self.scripts[name] end
function widgetMethods:Show()
    local wasShown = self.shown
    self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function widgetMethods:Hide()
    local wasShown = self.shown
    self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function widgetMethods:SetShown(shown) if shown then self:Show() else self:Hide() end end
function widgetMethods:IsShown() return self.shown end
function widgetMethods:SetText(text) self.shownText = text end
function widgetMethods:GetText() return self.shownText end
function widgetMethods:SetHeight(height) assert(IsNumber(height), "hauteur invalide") self.shownHeight = height end
function widgetMethods:GetHeight() return self.shownHeight or 0 end
function widgetMethods:SetWidth(width) assert(IsNumber(width), "largeur invalide") end
function widgetMethods:SetSize(width, height) self:SetWidth(width) self:SetHeight(height) end
function widgetMethods:SetAlpha(alpha) assert(IsNumber(alpha), "opacite invalide") self.shownAlpha = alpha end
function widgetMethods:GetAlpha() return self.shownAlpha or 1 end
function widgetMethods:GetParent() return self.parentWidget end
function widgetMethods:SetPoint(point) assert(type(point) == "string", "point d'ancrage invalide") end
function widgetMethods:SetColorTexture(r, g, b) assert(IsNumber(r, g, b), "couleur invalide") end
function widgetMethods:SetTextColor(r, g, b) assert(IsNumber(r, g, b), "couleur de texte invalide") end
function widgetMethods:SetVerticalScroll(value) assert(IsNumber(value), "defilement invalide") end
function widgetMethods:CreateTexture() return NewWidget(self) end
function widgetMethods:CreateMaskTexture() return NewWidget(self) end
function widgetMethods:CreateFontString() return NewWidget(self) end

function NewWidget(parent)
    local widget = { scripts = {}, shown = true, parentWidget = parent }
    return setmetatable(widget, {
        __index = function(_, key)
            if widgetMethods[key] then return widgetMethods[key] end
            -- Les méthodes du jeu commencent par une majuscule : on les accepte toutes, sans effet.
            -- Les champs ajoutés par l'add-on (minuscule) restent vides tant qu'il ne les remplit pas.
            if type(key) == "string" and key:match("^%u") then
                local value = defaults[key]
                return function() return value end
            end
            return nil
        end,
    })
end

function CreateFrame(_, name, parent)
    local frame = NewWidget(parent)
    allFrames[#allFrames + 1] = frame
    if name then _G[name] = frame end
    return frame
end

-- Faux jeu ----------------------------------------------------------------------

UIParent = NewWidget()
GameTooltip = NewWidget()
-- Fausse mini-carte : 140 pixels de large, centrée en (500, 400). Le curseur se règle dans les scénarios.
Minimap = NewWidget(UIParent)
Minimap.GetWidth = function() return 140 end
Minimap.GetHeight = function() return 140 end
Minimap.GetCenter = function() return 500, 400 end
Minimap.GetEffectiveScale = function() return 1 end
local cursorX, cursorY = 0, 0
function GetCursorPosition() return cursorX, cursorY end
GameFontNormal = NewWidget()
GameFontHighlight = NewWidget()
UISpecialFrames = {}
SlashCmdList = {}
tinsert = table.insert

local printed = {}
local realPrint = print
function print(...) printed[#printed + 1] = table.concat({ ... }, " ") end

function GetLocale() return "frFR" end
-- Le PNJ en face du joueur (maître ou marchand) change selon le scénario.
local npcTarget = { name = "Maitre Test", guid = "Creature-0-1-2-3-3355-0000AAAA", faction = "Alliance" }
function UnitName(unit)
    if unit == "npc" then return npcTarget.name end
    return "Testeur"
end
function UnitGUID(unit) return unit == "npc" and npcTarget.guid or "Player-1-0000BBBB" end
function UnitFactionGroup(unit) return unit == "npc" and npcTarget.faction or "Alliance" end
-- Fausse carte du monde : le joueur est sur la carte 1453 (« Hurlevent »), en (0.5, 0.6).
local playerMap, playerX, playerY = 1453, 0.5, 0.6
local pinned = {}
C_Map = {
    GetBestMapForUnit = function() return playerMap end,
    GetPlayerMapPosition = function() return { GetXY = function() return playerX, playerY end } end,
    -- La carte 7777 est la petite carte d un batiment : pas de repere possible, sa carte parente est 1453.
    GetMapInfo = function(map) return { name = map == 1453 and "Hurlevent" or ("Carte " .. map), parentMapID = map == 7777 and 1453 or 0 } end,
    CanSetUserWaypointOnMap = function(map) return map ~= 7777 end,
    SetUserWaypoint = function(point) pinned.point = point end,
}
UiMapPoint = { CreateFromCoordinates = function(map, x, y) return { uiMapID = map, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) pinned.tracked = on end }
function GetRealmName() return "Royaume" end
function GetBuildInfo() return "1.60.1", "70862", "", 16001 end
function GetProfessions() return 5, nil, nil, nil, 7 end
function GetProfessionInfo(index)
    if index == 5 then return "Forge", 1001, 76, 150, 0, 0, 164 end
    return "Cuisine", 1002, 90, 150, 0, 0, 185
end

local pendingTimers = {}
C_Timer = { After = function(_, fn) pendingTimers[#pendingTimers + 1] = fn end }
local function RunTimers()
    local timers = pendingTimers
    pendingTimers = {}
    for _, fn in ipairs(timers) do fn() end
end

Enum = {
    TradeskillRelativeDifficulty = { Optimal = 0, Medium = 1, Easy = 2, Trivial = 3 },
    CraftingReagentType = { Basic = 1 },
}

local fakeRecipes = {
    [9001] = { name = "Recette orange", learned = true, relativeDifficulty = 0, icon = 1, reagents = { { 501, 2 } } },
    [9002] = { name = "Recette jaune", learned = true, relativeDifficulty = 1, icon = 2, reagents = { { 501, 1 }, { 502, 3 } } },
    [9003] = { name = "Recette grise", learned = true, relativeDifficulty = 3, icon = 3, reagents = { { 503, 1 } } },
    [9004] = { name = "Recette inconnue", learned = false, icon = 4, reagents = { { 504, 1 } } },
    [9005] = { name = "Recette sans seuils", learned = true, relativeDifficulty = 0, icon = 5, reagents = {} },
}

local openProfession = {}

C_TradeSkillUI = {
    GetAllRecipeIDs = function() return { 9001, 9002, 9003, 9004, 9005 } end,
    GetRecipeInfo = function(id)
        local recipe = fakeRecipes[id]
        return { recipeID = id, name = recipe.name, learned = recipe.learned, icon = recipe.icon,
            relativeDifficulty = recipe.relativeDifficulty, numSkillUps = 1 }
    end,
    GetRecipeSchematic = function(id)
        local slots = {}
        for _, reagent in ipairs(fakeRecipes[id].reagents) do
            slots[#slots + 1] = { reagents = { { itemID = reagent[1] } }, quantityRequired = reagent[2], reagentType = 1 }
        end
        return { reagentSlotSchematics = slots }
    end,
    GetBaseProfessionInfo = function() return openProfession end,
    IsTradeSkillLinked = function() return false end,
    IsTradeSkillGuild = function() return false end,
}

C_Item = {
    -- 501 : 25 dans les sacs et 15 en banque. Les autres objets : aucun.
    GetItemCount = function(itemID, includeBank)
        if itemID ~= 501 then return 0 end
        return includeBank and 40 or 25
    end,
    GetItemNameByID = function(itemID) return itemID ~= 504 and ("Objet " .. itemID) or nil end,
    GetItemIconByID = function(itemID) return itemID end,
    RequestLoadItemDataByID = function() end,
}

-- Faux sacs : ceux du jeu, et trois add-ons de sacs (Bagnon, AdiBags, Baganator) -------

-- Comme dans le jeu : la fonction d'origine s'exécute, puis celle qu'on a greffée dessus.
function hooksecurefunc(a, b, c)
    local owner, name, hook = a, b, c
    if type(a) == "string" then owner, name, hook = _G, a, b end
    local original = owner[name]
    assert(type(original) == "function", "greffe sur une fonction absente : " .. tostring(name))
    owner[name] = function(...)
        original(...)
        hook(...)
    end
end

local bagContents = { [0] = { [1] = 501, [2] = 502 } }
C_Container = { GetContainerItemID = function(bag, slot) return bagContents[bag] and bagContents[bag][slot] end }

local function BagButton(bag, slot)
    local button = CreateFrame("Button")
    button.GetBagID = function() return bag end
    button.GetID = function() return slot end
    return button
end

local defaultButtons = { BagButton(0, 1), BagButton(0, 2) }
ContainerFrameCombinedBags = {
    UpdateItems = function() end,
    EnumerateValidItems = function() return ipairs(defaultButtons) end,
}
ContainerFrameContainer = { ContainerFrames = {} }

-- Comme Bagnon 12.1.8 : l'add-on se déclare sous le nom de son socle, « BagBrother ».
BagBrother = { Item = { Update = function() end } }

local adiCallbacks = {}
local fakeAdiBags = { RegisterMessage = function(_, message, fn) adiCallbacks[message] = fn end }
function LibStub(name)
    if name ~= "AceAddon-3.0" then return nil end
    return { GetAddon = function(_, addon) return addon == "AdiBags" and fakeAdiBags or nil end }
end

local baganatorWidget, baganatorRefreshes = nil, 0
Baganator = { API = {
    RegisterCornerWidget = function(_, _, onUpdate, onInit) baganatorWidget = { onUpdate = onUpdate, onInit = onInit } end,
    RequestItemButtonsRefresh = function() baganatorRefreshes = baganatorRefreshes + 1 end,
} }

-- Faux marchand : deux objets par page ; il vend 502, 501, puis 501 en page 2.
local merchantGoods = { 502, 501, 501 }
MERCHANT_ITEMS_PER_PAGE = 2
MerchantFrame = { page = 1 }
MerchantItem1ItemButton = CreateFrame("Button")
MerchantItem2ItemButton = CreateFrame("Button")
function GetMerchantItemID(index) return merchantGoods[index] end
-- Ce que le marchand annonce : 502 a 100 l'unite ; 501 par lot de 5 pour 500 (stock illimite),
-- puis 501 en stock limite a prix casse, qui ne doit pas servir de reference.
local merchantOffers = {
    { price = 100, stackCount = 1, numAvailable = -1 },
    { price = 500, stackCount = 5, numAvailable = -1 },
    { price = 50, stackCount = 1, numAvailable = 2 },
}
function GetMerchantNumItems() return #merchantGoods end
C_MerchantFrame = { GetItemInfo = function(index) return merchantOffers[index] end }
function MerchantFrame_UpdateMerchantInfo() end
function MerchantFrame_UpdateBuybackInfo() end

-- Chargement de l'add-on, dans l'ordre du .toc -------------------------------------

local ns = {}
-- Faux maître de forge : un titre, une recette à venir, un rang de métier.
local trainerServices = {
    { name = "Fabrication", serviceType = "header" },
    { name = "Recette inconnue", serviceType = "unavailable", skill = "Forge", level = 120, cost = 500 },
    { name = "Compagnon forgeron", serviceType = "available", skill = "Forge", level = 50, cost = 100 },
}
function GetNumTrainerServices() return #trainerServices end
function GetTrainerServiceInfo(index) return trainerServices[index].name, nil, trainerServices[index].serviceType end
function GetTrainerServiceSkillReq(index) return trainerServices[index].skill, trainerServices[index].level end
function GetTrainerServiceCost(index) return trainerServices[index].cost end
function GetTrainerServiceTypeFilter() return false end
function GetCoinTextureString(copper) return copper .. " cuivre" end

assert(#tocFiles >= 10, "liste des fichiers du .toc illisible")
for _, file in ipairs(tocFiles) do
    loadAddonFile(file, "ProfessionPath", ns)
end

-- Seuils fictifs pour les recettes fictives (9005 n'en a volontairement pas).
ns.Thresholds[9001] = { 0, 100, 115, 130 }
ns.Thresholds[9002] = { 0, 70, 105, 140 }
ns.Thresholds[9003] = { 0, 20, 30, 40 }
-- 9004 est une recette de maître : son niveau d'apprentissage (0) est inconnu des données.
ns.Thresholds[9004] = { 0, 140, 150, 160 }

-- Outils du scénario ----------------------------------------------------------------

local function Fire(event, ...)
    for _, frame in ipairs(allFrames) do
        if frame.scripts.OnEvent then frame.scripts.OnEvent(frame, event, ...) end
    end
    RunTimers()
end

-- Fait avancer le temps : exécute les animations jusqu'à leur fin.
local function Advance(seconds)
    local step = 0.05
    for _ = 1, math.ceil(seconds / step) do
        for _, frame in ipairs(allFrames) do
            if frame.shown and frame.scripts.OnUpdate then frame.scripts.OnUpdate(frame, step) end
        end
    end
    RunTimers()
end

local function IsVisible(frame)
    while frame do
        if not frame.shown then return false end
        frame = frame.parentWidget
    end
    return true
end

local function OpenWindow()
    if not (ProfessionPathFrame and ProfessionPathFrame:IsShown()) then
        SlashCmdList.PROFESSIONPATH("")
        Advance(1)
    end
    assert(ProfessionPathFrame:IsShown(), "fenetre non ouverte")
end

-- Clique sur chaque bouton visible, en rouvrant la fenêtre si un clic l'a fermée.
local function ClickAll(label)
    local count = 0
    for index = 1, #allFrames do
        OpenWindow()
        local frame = allFrames[index]
        if IsVisible(frame) and frame.scripts.OnClick then
            frame.scripts.OnClick(frame)
            count = count + 1
            Advance(1)
        end
    end
    assert(count >= 5, "trop peu de boutons cliques (" .. count .. ") : " .. label)
end

local function HoverAll()
    for index = 1, #allFrames do
        local frame = allFrames[index]
        if IsVisible(frame) and frame.scripts.OnEnter then frame.scripts.OnEnter(frame) end
        if IsVisible(frame) and frame.scripts.OnLeave then frame.scripts.OnLeave(frame) end
    end
    Advance(0.5)
end

-- Le bandeau « parcours provisoire » de la fenêtre, s'il a été construit.
local function TrainerWarning()
    for _, frame in ipairs(allFrames) do
        if frame.trainerWarning then return frame end
    end
    return nil
end

local passed, failed = 0, 0
local function scenario(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        realPrint("ECHEC  " .. name .. "\n       " .. tostring(err))
    end
end

-- Scénarios -------------------------------------------------------------------------

scenario("tous les textes utilises par la fenetre existent", function()
    for _, key in ipairs({ "LEVEL_RANGE", "LEVEL_MAX", "OWNED", "ANIM_ON", "ANIM_OFF", "ANIM_TIP",
        "TITLE", "DONE", "RESET", "TARGET", "NEXT_HEADER", "STEPS_HEADER", "MATERIALS_HEADER", "NO_PROFESSION",
        "FAV_ADD", "FAV_REMOVE", "FAV_TIP", "FAV_WIDGET", "FAV_NONE_IN_BAGS", "OWNED_BANK", "DEBUG_FAVORITES",
        "HERO_MATERIALS", "PER_CRAFT", "STEP_MATERIALS",
        "TAB_LEVEL", "TAB_UNREAD", "MINIMAP_TIP_CLICK", "MINIMAP_TIP_DRAG", "MINIMAP_TIP_HIDE", "MINIMAP_HIDDEN", "MINIMAP_SHOWN", "NPC_HEADER", "NPC_TRAINER", "NPC_VENDOR", "NPC_MAP_BUTTON", "NPC_MAP_TIP", "NPC_PIN_DONE", "NPC_PIN_FAILED", "NPC_NONE", "VISIT_PIN", "DEBUG_NPCS", "SHARE_TITLE", "SHARE_HELP", "SHARE_STATS", "SHARE_EMPTY", "SHARE_CLOSE", "WARN_TRAINER_SHIPPED", "VENDOR_READ", "DEBUG_VENDOR", "COST_TOTAL", "COST_PARTIAL", "COST_TIP", "PREPARE_HEADER", "PREPARE_LINE", "PREPARE_LINE_CRAFTS", "PREPARE_TIP", "PREPARE_MADE_WITH", "PREPARE_YIELD", "WARN_TRAINER_TITLE", "WARN_TRAINER_BODY" }) do
        assert(type(ns.L[key]) == "string", "texte manquant : " .. key)
    end
end)

scenario("demarrage de l'add-on", function()
    Fire("ADDON_LOADED", "ProfessionPath")
    Fire("PLAYER_LOGIN")
    assert(ProfessionPathDB and ns.db, "sauvegarde non creee")
end)

scenario("ouverture puis fermeture de la fenetre sans aucun metier lu", function()
    OpenWindow()
    assert(ns.SelectedProfession() == nil, "aucun metier ne devrait etre lu")
    HoverAll()
    SlashCmdList.PROFESSIONPATH("")
    Advance(1)
    assert(not ProfessionPathFrame:IsShown(), "fenetre non fermee")
end)

scenario("lecture du metier a l'ouverture de la fenetre de metier", function()
    openProfession = { professionID = 164, professionName = "Forge", skillLevel = 76, maxSkillLevel = 150 }
    Fire("TRADE_SKILL_SHOW")
    local prof = ns.SelectedProfession()
    assert(prof and prof.name == "Forge" and prof.skill == 76, "metier mal lu")
    assert(#prof.recipes == 5, "5 recettes attendues, lu " .. #prof.recipes)
end)

scenario("affichage du parcours, survols et animations", function()
    OpenWindow()
    assert(ProfessionPathFrame:GetHeight() > 200, "hauteur de fenetre non calculee")
    HoverAll()
    Fire("BAG_UPDATE_DELAYED")
    Fire("SKILL_LINES_CHANGED")
    Advance(1)
end)

scenario("sans maitre lu, la recette a apprendre reste hors parcours et la fenetre le dit", function()
    local prof = ns.SelectedProfession()
    assert(not ns.HasTrainerData(prof), "aucun maitre ne devrait etre lu")
    local plan = ns.Planner.Plan({ skill = prof.skill, target = 150, mode = "simple", recipes = ns.RecipesForPlanner(prof) })
    assert(#plan.visits == 0, "aucune visite attendue")
    for _, step in ipairs(plan.steps) do
        assert(step.recipe.id ~= 9004, "la recette du maitre ne devrait pas etre proposee")
    end
    -- L'avertissement « parcours provisoire » est affiché en haut, avec le nom du métier.
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local warning = TrainerWarning()
    assert(warning and IsVisible(warning), "avertissement absent alors que le maitre n'est pas lu")
    assert((warning.body:GetText() or ""):find("Forge", 1, true), "l'avertissement ne nomme pas le metier")
end)

scenario("lecture du maitre : sa recette entre dans le parcours avec une visite", function()
    Fire("TRAINER_SHOW")
    local taught = ns.db.trainer.Forge and ns.db.trainer.Forge["Recette inconnue"]
    assert(taught and taught.level == 120 and taught.cost == 500, "recette du maitre mal lue")
    assert(ns.db.trainer.Forge["Fabrication"] == nil, "un titre ne doit pas etre lu comme une recette")
    local prof = ns.SelectedProfession()
    local plan = ns.Planner.Plan({ skill = prof.skill, target = 150, mode = "simple", recipes = ns.RecipesForPlanner(prof) })
    assert(#plan.visits == 1, "une visite attendue, obtenu " .. #plan.visits)
    assert(plan.visits[1].level == 120, "visite attendue au niveau 120, obtenu " .. plan.visits[1].level)
    assert(plan.visits[1].recipes[1].id == 9004, "mauvaise recette dans la visite")
    assert(plan.complete, "le parcours devrait aller au bout")
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    HoverAll()
    local warning = TrainerWarning()
    assert(warning and not IsVisible(warning), "avertissement reste affiche apres la lecture du maitre")
end)

scenario("etoile de la liste des materiaux : un clic met en favori, un second l'enleve", function()
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local star
    for _, frame in ipairs(allFrames) do
        if frame.favoriteStar and IsVisible(frame) and frame.itemID == 501 then star = frame end
    end
    assert(star, "aucune etoile visible pour le composant 501")
    assert(not ns.Favorites.Is(501), "501 ne devrait pas etre favori au depart")
    star.scripts.OnClick(star)
    assert(ns.Favorites.Is(501), "le clic n'a pas mis 501 en favori")
    assert(ProfessionPathDB.favorites[501] == true, "favori non sauvegarde")
    star.scripts.OnEnter(star)
    star.scripts.OnLeave(star)
    star.scripts.OnClick(star)
    assert(not ns.Favorites.Is(501), "le second clic n'a pas retire le favori")
end)

scenario("materiaux : ce qui est en banque est affiche a part de ce qui est dans les sacs", function()
    assert(ns.BagCount(501) == 25 and ns.OwnedCount(501) == 40, "comptes sacs / total faux")
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local banked, plain = 0, 0
    for _, frame in ipairs(allFrames) do
        -- Seulement la liste du bas : la carte « Prochaine recette » a son propre scénario.
        if frame.count and not frame.heroMaterial and IsVisible(frame) and frame.itemID then
            local text = frame.count:GetText()
            if frame.itemID == 501 then
                assert(text:find("25", 1, true) and text:find("15", 1, true), "sacs et banque attendus, lu : " .. text)
                banked = banked + 1
            else
                assert(text:find("^0 / "), "aucune banque attendue, lu : " .. text)
                plain = plain + 1
            end
        end
    end
    assert(banked == 1 and plain >= 1, "lignes de materiaux non trouvees")
end)

scenario("prochaine recette : ses materiaux sont affiches dans la carte, avec une etoile", function()
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local rows = {}
    for _, frame in ipairs(allFrames) do
        if frame.heroMaterial and IsVisible(frame) then rows[#rows + 1] = frame end
    end
    assert(#rows >= 1, "aucun materiau affiche dans la carte de la prochaine recette")
    assert(ProfessionPathFrame:GetHeight() > 200, "hauteur de fenetre non recalculee")
    for _, row in ipairs(rows) do
        assert(type(row.itemID) == "number", "ligne sans objet")
        assert((row.name:GetText() or "") ~= "" and (row.count:GetText() or "") ~= "", "ligne sans texte")
        assert(row.star and row.star.itemID == row.itemID, "etoile absente ou mal reliee")
        row.star.scripts.OnClick(row.star)
        assert(ns.Favorites.Is(row.itemID), "l'etoile de la carte ne met pas en favori")
        row.star.scripts.OnClick(row.star)
    end
    HoverAll()
end)

scenario("etoile dans les sacs : sacs du jeu, Bagnon, AdiBags et Baganator", function()
    local hooked = table.concat(ns.Bags.Hooked(), " ")
    for _, name in ipairs({ "Blizzard", "BagBrother", "AdiBags", "Baganator" }) do
        assert(hooked:find(name, 1, true), "sacs non branches : " .. name .. " (branches : " .. hooked .. ")")
    end
    assert(ns.Favorites.Toggle(501), "501 devrait devenir favori")

    ContainerFrameCombinedBags:UpdateItems()
    assert(ns.Bags.IsStarred(defaultButtons[1]), "sacs du jeu : etoile absente sur le favori")
    assert(not ns.Bags.IsStarred(defaultButtons[2]), "sacs du jeu : etoile sur un objet non favori")

    local bagnonButton, emptyButton = CreateFrame("Button"), CreateFrame("Button")
    bagnonButton.info = { itemID = 501 }
    emptyButton.info = {}
    BagBrother.Item.Update(bagnonButton)
    BagBrother.Item.Update(emptyButton)
    assert(ns.Bags.IsStarred(bagnonButton), "Bagnon : etoile absente")
    assert(not ns.Bags.IsStarred(emptyButton), "Bagnon : etoile sur une case vide")

    local adiButton = CreateFrame("Button")
    adiButton.itemId = 501
    adiCallbacks.AdiBags_UpdateButton("AdiBags_UpdateButton", adiButton)
    assert(ns.Bags.IsStarred(adiButton), "AdiBags : etoile absente")

    assert(baganatorWidget, "Baganator : coin non declare")
    assert(baganatorWidget.onInit(CreateFrame("Button")), "Baganator : etoile non creee")
    assert(baganatorWidget.onUpdate(nil, { itemID = 501 }) == true, "Baganator : favori non signale")
    assert(baganatorWidget.onUpdate(nil, { itemID = 502 }) == false, "Baganator : faux favori")
    assert(baganatorWidget.onUpdate(nil, { itemLink = "|Hitem:501::::|h[Objet]|h" }) == true, "Baganator : lien d'objet non reconnu")
    assert(baganatorWidget.onUpdate(nil, nil) == false, "Baganator : case sans description")

    -- L'objet change de case : l'étoile suit le contenu, pas la case.
    bagContents[0][1], bagContents[0][2] = 502, 501
    ContainerFrameCombinedBags:UpdateItems()
    assert(not ns.Bags.IsStarred(defaultButtons[1]) and ns.Bags.IsStarred(defaultButtons[2]), "l'etoile n'a pas suivi l'objet")

    -- Retirer le favori enlève l'étoile partout, sans attendre que les sacs se redessinent.
    local refreshesBefore = baganatorRefreshes
    ns.Favorites.Toggle(501)
    for label, button in pairs({ jeu = defaultButtons[2], Bagnon = bagnonButton, AdiBags = adiButton }) do
        assert(not ns.Bags.IsStarred(button), "etoile restee apres retrait du favori : " .. label)
    end
    assert(baganatorRefreshes > refreshesBefore, "Baganator n'a pas ete prevenu du changement")

    -- Une case inattendue ne doit jamais faire planter les sacs du joueur.
    ns.Bags.Mark(nil, 501)
    ns.Bags.Mark({}, 501)
    BagBrother.Item.Update({})
    BagBrother.Item.Update(nil)
    assert(type(ns.Bags.LastError()) == "string", "la panne d'une case doit rester consultable")
end)

scenario("prix des marchands : lus a l'ouverture, a l'unite, sans les stocks limites ni les monnaies", function()
    assert(ns.VendorPrice(501) == nil and ns.VendorPrice(502) == nil, "aucun prix de marchand attendu au depart")
    merchantGoods[4], merchantOffers[4] = 503, { price = 10, stackCount = 1, numAvailable = -1, hasExtendedCost = true }
    printed = {}
    Fire("MERCHANT_SHOW")
    assert(ns.VendorPrice(502) == 100, "prix de 502 mal lu")
    assert(ns.VendorPrice(501) == 100, "prix a l'unite attendu pour 501 (500 les 5), lu " .. tostring(ns.VendorPrice(501)))
    assert(ns.VendorPrice(503) == nil, "un objet paye en monnaie speciale ne doit pas etre note")
    assert(ProfessionPathDB.vendor[502] == 100, "prix non sauvegarde")
    assert(#printed == 1, "une annonce attendue dans le chat, vu " .. #printed)
    Fire("MERCHANT_SHOW")
    assert(#printed == 1, "pas de nouvelle annonce quand rien ne change")
    merchantGoods[4], merchantOffers[4] = nil, nil

    -- Le marchand ne vend plus 502 qu en stock limite : son ancien prix est oublie.
    merchantOffers[1].numAvailable = 3
    Fire("MERCHANT_UPDATE")
    assert(ns.VendorPrice(502) == nil, "un prix devenu peu fiable doit etre oublie")
    assert(ns.VendorPrice(501) == 100, "501 garde son prix : une de ses lignes reste en stock illimite")
    merchantOffers[1].numAvailable = -1
    Fire("MERCHANT_UPDATE")
    assert(ns.VendorPrice(502) == 100, "prix de 502 non relu")
    -- Une sauvegarde abimee ne masque pas le prix livre avec l add-on.
    ns.db.vendor[507], ns.VendorPrices[507] = "abime", 3
    assert(ns.VendorPrice(507) == 3, "prix livre masque par une sauvegarde abimee")
    ns.db.vendor[507], ns.VendorPrices[507] = nil, nil

    -- Un prix livre avec l'add-on sert tant que le joueur n'a pas vu le marchand lui-meme.
    ns.VendorPrices[504] = 7
    assert(ns.VendorPrice(504) == 7, "prix livre ignore")
    ns.db.vendor[504] = 9
    assert(ns.VendorPrice(504) == 9, "le prix lu en jeu doit primer sur le prix livre")
    ns.VendorPrices[504], ns.db.vendor[504] = nil, nil

    -- « Le moins couteux » prend le prix le plus bas entre le marchand et l'hotel des ventes.
    assert(ns.PriceOf(502) == 100, "prix de marchand ignore sans Auctionator")
    Auctionator = { API = { v1 = {
        GetAuctionPriceByItemID = function(_, itemID) return ({ [501] = 300, [502] = 60, [503] = 40 })[itemID] end,
        GetVendorPriceByItemID = function(_, itemID) return itemID == 505 and 12 or nil end,
    } } }
    assert(ns.PriceOf(501) == 100, "le marchand, moins cher que l'hotel des ventes, doit primer")
    assert(ns.PriceOf(502) == 60, "l'hotel des ventes, moins cher que le marchand, doit primer")
    assert(ns.PriceOf(503) == 40, "prix de l'hotel des ventes seul")
    assert(ns.PriceOf(505) == 12, "prix de marchand connu d'Auctionator ignore")
    assert(ns.PriceOf(506) == nil, "aucun prix ne doit etre invente")
    Auctionator = nil
end)

scenario("prix de fabrication et cout estime du parcours", function()
    -- 9001 (connue) fabrique l'objet 510 avec 2 x 501 ; 9004 (inconnue) fabriquerait 511 avec 1 x 504.
    ns.Crafts[9001], ns.Crafts[9004] = { 510, 1 }, { 511, 1 }
    ns.db.vendor[504] = 5
    assert(ns.VendorPrice(501) == 100, "le prix de 501 lu chez le marchand est attendu")
    local priceOf = ns.NewPricer()
    assert(priceOf(510) == 200, "prix de fabrication attendu : 2 x 100, obtenu " .. tostring(priceOf(510)))
    assert(priceOf(511) == nil, "une recette inconnue du joueur ne doit pas donner de prix")
    assert(priceOf(501) == 100 and priceOf(599) == nil, "prix de base alteres")
    ns.Crafts[9001], ns.Crafts[9004], ns.db.vendor[504] = nil, nil, nil

    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local text = ProfessionPathFrame.costLabel:GetText() or ""
    assert(text:find("cuivre", 1, true), "cout estime absent : " .. text)
    assert(text:find("sans prix", 1, true), "les materiaux sans prix doivent etre signales : " .. text)
    HoverAll()
end)

scenario("objets a preparer soi-meme : detailles dans la liste, annonces dans leur section", function()
    OpenWindow()
    ns.Character().skipped = {}
    ns.RefreshUI()
    Advance(1)
    local function MaterialRows()
        local rows = {}
        for _, frame in ipairs(allFrames) do
            if frame.count and not frame.heroMaterial and IsVisible(frame) and frame.itemID then rows[frame.itemID] = frame end
        end
        return rows
    end
    -- Lignes de la section « À préparer toi-même » : { [objet] = ligne }.
    local function PrepareRows()
        local rows, count = {}, 0
        for _, frame in ipairs(allFrames) do
            if frame.prepareRow and IsVisible(frame) then rows[frame.itemID], count = frame, count + 1 end
        end
        return rows, count
    end
    local before = MaterialRows()
    assert(before[501], "le parcours d'essai devrait demander l'objet 501")
    assert(select(2, PrepareRows()) == 0, "rien a preparer au depart")

    -- 9003 (connue) fabrique 501 avec 1 x 503 ; 503 coute 1, 501 coute 100 chez le marchand.
    ns.Crafts[9003] = { 501, 1 }
    ns.db.vendor[503] = 1
    ns.RefreshUI()
    Advance(1)
    local after = MaterialRows()
    assert(not after[501], "501 est a fabriquer : il ne doit plus etre dans la liste a reunir")
    assert(after[503], "le materiau de 501 doit apparaitre dans la liste")
    local prepareRows, prepareCount = PrepareRows()
    assert(prepareCount == 1 and prepareRows[501], "501 devrait etre la seule ligne a preparer")
    assert((prepareRows[501].name:GetText() or ""):find("Objet 501", 1, true), "501 non annonce a preparer")
    assert(type(prepareRows[501].entry.reagents) == "table", "la ligne doit connaitre les materiaux de l'objet")
    -- Survol : infobulle de l'objet, completee par ce qu'il faut pour le fabriquer.
    prepareRows[501].scripts.OnEnter(prepareRows[501])
    prepareRows[501].scripts.OnLeave(prepareRows[501])
    HoverAll()

    -- Si l'acheter devient moins cher que le fabriquer, tout revient comme avant.
    ns.db.vendor[503] = 500
    ns.RefreshUI()
    Advance(1)
    assert(MaterialRows()[501], "501 moins cher a l'achat : il doit revenir dans la liste")
    assert(select(2, PrepareRows()) == 0, "plus rien a preparer")
    ns.Crafts[9003], ns.db.vendor[503] = nil, nil
end)

scenario("PNJ du metier : maitre et marchand notes, liste triee, repere sur la carte", function()
    -- Le maître de forge a été lu plus haut : il est noté avec sa position.
    local trainer = ns.db.npcs["trainer:3355"]
    assert(trainer, "le maitre lu n'a pas ete note")
    assert(trainer.kind == "trainer" and trainer.name == "Maitre Test", "maitre mal note")
    assert(trainer.profession == "Forge" and trainer.professionID == 164, "metier du maitre mal note")
    assert(trainer.map == 1453 and trainer.x == 0.5 and trainer.y == 0.6, "position du maitre mal notee")
    assert(trainer.faction == "Alliance", "faction du maitre mal notee")

    -- Un marchand qui vend des materiaux de recettes est note avec ce qu'il vend.
    npcTarget.name, npcTarget.guid = "Marchand Test", "Creature-0-1-2-3-4444-0000CCCC"
    playerX, playerY = 0.52, 0.61
    Fire("MERCHANT_SHOW")
    local vendor = ns.db.npcs["vendor:4444"]
    assert(vendor and vendor.kind == "vendor", "le marchand n'a pas ete note")
    assert(vendor.items and vendor.items[501], "le marchand doit retenir les materiaux qu'il vend")

    -- Un PNJ de la Horde ne doit pas etre propose a un joueur de l'Alliance.
    ns.db.npcs[9999] = { kind = "trainer", name = "Maitre Horde", profession = "Forge", professionID = 164,
        map = 1453, x = 0.5, y = 0.6, faction = "Horde" }
    -- Un maitre plus loin, sur une autre carte.
    ns.db.npcs[8888] = { kind = "trainer", name = "Maitre Lointain", profession = "Forge", professionID = 164,
        map = 1455, x = 0.1, y = 0.1, faction = "Alliance" }
    -- Le joueur revient pres du maitre : le plus proche doit passer en tete.
    playerX, playerY = 0.5, 0.6
    local list = ns.NpcsFor(ns.SelectedProfession())
    local names = {}
    for _, entry in ipairs(list) do names[#names + 1] = entry.npc.name end
    local joined = table.concat(names, ", ")
    assert(not joined:find("Horde", 1, true), "un PNJ de l'autre faction est propose : " .. joined)
    assert(names[1] == "Maitre Test", "le maitre de la zone doit passer en premier : " .. joined)
    assert(joined:find("Maitre Lointain", 1, true) and joined:find("Marchand Test", 1, true), "liste incomplete : " .. joined)

    -- La fenetre affiche la section, et le bouton « Carte » pose le repere officiel du jeu.
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local mapButton
    for _, frame in ipairs(allFrames) do
        if frame.npcPin and IsVisible(frame) and frame.npc and frame.npc.name == "Maitre Lointain" then mapButton = frame end
    end
    assert(mapButton, "bouton « Carte » absent pour le maitre lointain")
    printed = {}
    mapButton.scripts.OnClick(mapButton)
    assert(pinned.point and pinned.point.uiMapID == 1455 and pinned.point.x == 0.1, "repere mal pose")
    assert(pinned.tracked == true, "le repere doit etre suivi (fleche a l'ecran)")
    assert(#printed == 1, "la pose du repere doit etre annoncee")
    HoverAll()

    -- Rien de connu pour un metier : la section le dit au lieu de rester vide.
    local saved = ns.db.npcs
    ns.db.npcs = {}
    assert(#ns.NpcsFor(ns.SelectedProfession()) == 0, "aucun PNJ attendu")
    ns.RefreshUI()
    Advance(1)
    ns.db.npcs = saved
    npcTarget.name, npcTarget.guid = "Maitre Test", "Creature-0-1-2-3-3355-0000AAAA"

    -- Dans un batiment qui a sa propre petite carte, le PNJ est note sur la carte de la ville.
    playerMap = 7777
    Fire("TRAINER_SHOW")
    assert(ns.db.npcs["trainer:3355"].map == 1453, "le PNJ doit etre note sur une carte qui accepte les reperes")
    playerMap = 1453
    playerX, playerY = 0.5, 0.6
end)

scenario("partage : texte sans donnees personnelles, fenetre, recettes de maitre livrees", function()
    local text = ns.BuildShareText()
    assert(text:find("ProfessionPath-share 1", 1, true), "en-tete du partage absent")
    assert(text:find("\nN;trainer;3355;Maitre Test;1453;", 1, true), "maitre absent du partage :\n" .. text)
    assert(text:find("\nN;vendor;4444;Marchand Test;1453;", 1, true), "marchand absent du partage")
    -- La recette « Recette inconnue » (numero 9004) est enseignee au niveau 120 pour 500.
    assert(text:find("\nR;164;9004;120;500", 1, true), "recette de maitre absente du partage :\n" .. text)
    assert(not text:find("Testeur", 1, true) and not text:find("Royaume", 1, true), "le partage ne doit contenir ni personnage ni royaume")

    -- La commande ouvre la fenetre avec ce texte, pret a copier.
    SlashCmdList.PROFESSIONPATH("partager")
    assert(ProfessionPathShareFrame and ProfessionPathShareFrame:IsShown(), "fenetre de partage absente")
    assert(ProfessionPathShareFrame.box:GetText() == text, "le texte de la fenetre doit etre celui du partage")
    HoverAll()
    ProfessionPathShareFrame:Hide()

    -- Recettes de maitre livrees avec l'add-on : elles servent quand le joueur n'a pas lu le maitre.
    local savedTrainer = ns.db.trainer
    ns.db.trainer = {}
    local prof = ns.SelectedProfession()
    assert(ns.TrainerDataSource(prof) == nil, "sans maitre lu ni liste livree, pas de donnees attendues")
    ns.TrainerLevels[9004] = { 120, 500 }
    -- La liste livree peut etre incomplete : elle ne vaut pas un maitre lu, le bandeau reste mais change.
    assert(ns.TrainerDataSource(prof) == "shipped", "la liste livree doit etre reconnue")
    assert(not ns.HasTrainerData(prof), "la liste livree ne doit pas compter comme un maitre lu")
    OpenWindow()
    ns.RefreshUI()
    Advance(1)
    local warning = TrainerWarning()
    assert(warning and IsVisible(warning), "le bandeau doit rester avec une liste livree seulement")
    assert(warning.body:GetText() == ns.L.WARN_TRAINER_SHIPPED:format(prof.name), "le bandeau doit dire que la liste vient des autres joueurs")
    local found
    for _, recipe in ipairs(ns.RecipesForPlanner(prof)) do
        if recipe.id == 9004 then found = recipe end
    end
    assert(found and found.learnLevel == 120 and found.learnCost == 500 and found.learnSource == "trainer", "recette livree non utilisee")
    ns.TrainerLevels[9004] = nil
    ns.db.trainer = savedTrainer
end)

scenario("etoile chez le marchand : sur les favoris vendus, page par page, pas sur le rachat", function()
    assert(table.concat(ns.Bags.Hooked(), " "):find("Marchand", 1, true), "marchand non branche")
    local first, second = MerchantItem1ItemButton, MerchantItem2ItemButton
    ns.Favorites.Toggle(501)

    MerchantFrame.page = 1
    MerchantFrame_UpdateMerchantInfo()
    assert(not ns.Bags.IsStarred(first), "page 1 : etoile sur un objet non favori")
    assert(ns.Bags.IsStarred(second), "page 1 : etoile absente sur le favori")

    MerchantFrame.page = 2
    MerchantFrame_UpdateMerchantInfo()
    assert(ns.Bags.IsStarred(first), "page 2 : etoile absente sur le favori")
    assert(not ns.Bags.IsStarred(second), "page 2 : etoile sur une case vide")

    MerchantFrame_UpdateBuybackInfo()
    assert(not ns.Bags.IsStarred(first) and not ns.Bags.IsStarred(second), "rachat : aucune etoile attendue")

    MerchantFrame.page = 1
    MerchantFrame_UpdateMerchantInfo()
    ns.Favorites.Toggle(501)
    assert(not ns.Bags.IsStarred(second), "etoile restee chez le marchand apres retrait du favori")
end)

scenario("etoile dans les sacs : fenetre de sac et add-on de sacs arrives apres la connexion", function()
    -- Le jeu crée une fenêtre de sac après coup.
    local lateButton = BagButton(0, 2)
    local lateFrame = { UpdateItems = function() end, EnumerateValidItems = function() return ipairs({ lateButton }) end }
    ContainerFrameContainer.ContainerFrames[1] = lateFrame
    -- Un add-on de sacs (Baggins) se charge après coup.
    local bagginsButton = CreateFrame("Button")
    Baggins = { UpdateItemButton = function() end }
    Fire("ADDON_LOADED", "Baggins")
    Fire("ADDON_LOADED", "AutreChose")
    assert(table.concat(ns.Bags.Hooked(), " "):find("Baggins", 1, true), "Baggins non branche apres coup")

    ns.Favorites.Toggle(501)
    local updates = 0
    hooksecurefunc(lateFrame, "UpdateItems", function() updates = updates + 1 end)
    lateFrame:UpdateItems()
    Baggins:UpdateItemButton(nil, bagginsButton, 0, 2)
    assert(updates == 1, "fenetre de sac mise a jour " .. updates .. " fois")
    assert(ns.Bags.IsStarred(lateButton), "fenetre de sac tardive : etoile absente")
    assert(ns.Bags.IsStarred(bagginsButton), "Baggins : etoile absente")
    ns.Favorites.Toggle(501)
    assert(not ns.Bags.IsStarred(lateButton) and not ns.Bags.IsStarred(bagginsButton), "etoile restee")
end)

scenario("clic sur chaque bouton, avec animations", function()
    ClickAll("avec animations")
end)

scenario("clic sur chaque bouton, animations reduites", function()
    OpenWindow()
    ns.Character().skipped = {}
    ns.db.reduceMotion = true
    ns.RefreshUI()
    ClickAll("animations reduites")
    ns.db.reduceMotion = false
end)

scenario("chaque priorite et un objectif saisi a la main", function()
    OpenWindow()
    for _, mode in ipairs(ns.Planner.MODES) do
        ns.db.mode = mode
        ns.RefreshUI()
        Advance(1)
    end
    ns.SetTarget(ns.SelectedProfession(), 100)
    ns.RefreshUI()
    ns.SetTarget(ns.SelectedProfession(), 76)
    ns.RefreshUI()
    Advance(1)
end)

scenario("onglets de metier : un par metier du personnage, clic direct, non lu en grise", function()
    local function Tabs()
        local tabs = {}
        for _, frame in ipairs(allFrames) do
            if frame.professionTab and IsVisible(frame) then tabs[frame.info.name] = frame end
        end
        return tabs
    end
    OpenWindow()
    ns.RefreshUI()
    Advance(1)

    local list = ns.ProfessionTabs()
    assert(#list == 2, "2 metiers attendus, obtenu " .. #list)
    assert(list[1].name == "Forge" and list[1].read and list[1].id == 164, "Forge devrait etre lue")
    assert(list[1].skill == 76 and list[1].max == 150 and list[1].icon == 1001, "niveau ou icone de Forge faux")
    assert(list[2].name == "Cuisine" and not list[2].read and list[2].id == nil, "Cuisine ne devrait pas etre lue")

    local tabs = Tabs()
    assert(tabs.Forge and tabs.Cuisine, "onglets absents")
    assert(tabs.Forge.active and not tabs.Cuisine.active, "l'onglet du metier affiche doit etre mis en avant")
    for _, tab in pairs(tabs) do
        tab.scripts.OnEnter(tab)
        tab.scripts.OnLeave(tab)
    end

    -- Un métier jamais ouvert ne peut pas être affiché : le clic ne change rien.
    tabs.Cuisine.scripts.OnClick(tabs.Cuisine)
    assert(ns.SelectedProfession().id == 164, "un metier non lu ne doit pas devenir le metier affiche")

    -- Une fois la Cuisine lue, chaque onglet mène directement à son métier.
    openProfession = { professionID = 185, professionName = "Cuisine", skillLevel = 90, maxSkillLevel = 150 }
    Fire("TRADE_SKILL_SHOW")
    Advance(1)
    tabs = Tabs()
    assert(ns.ProfessionTabs()[2].read, "Cuisine devrait maintenant etre lue")
    tabs.Forge.scripts.OnClick(tabs.Forge)
    assert(ns.SelectedProfession().id == 164, "clic sur Forge sans effet")
    assert(Tabs().Forge.active and not Tabs().Cuisine.active, "mise en avant non mise a jour")
    tabs.Cuisine.scripts.OnClick(tabs.Cuisine)
    assert(ns.SelectedProfession().id == 185, "clic sur Cuisine sans effet")
    assert(Tabs().Cuisine.active and not Tabs().Forge.active, "mise en avant non mise a jour")

    tabs.Forge.scripts.OnClick(tabs.Forge)
    openProfession = { professionID = 164, professionName = "Forge", skillLevel = 76, maxSkillLevel = 150 }
end)

scenario("bouton de mini-carte : position, clic, deplacement, masquage", function()
    local offset = ns.MinimapButtonOffset
    local function near(a, b) return math.abs(a - b) < 0.01 end
    -- Mini-carte ronde : sur le cercle, juste au-dela du bord (70 + 5).
    local x, y = offset(0, 140, 140, "ROUND")
    assert(near(x, 75) and near(y, 0), "position a droite fausse")
    x, y = offset(math.pi / 2, 140, 140, nil)
    assert(near(x, 0) and near(y, 75), "position en haut fausse")
    x, y = offset(math.pi / 4, 140, 140, "ROUND")
    assert(near(math.sqrt(x * x + y * y), 75), "en diagonale, le bouton doit rester sur le cercle")
    -- Mini-carte carree : le bouton suit le bord du carre, coin compris.
    x, y = offset(math.pi / 4, 140, 140, "SQUARE")
    assert(near(x, 75) and near(y, 75), "sur une mini-carte carree, la diagonale va au coin")
    x, y = offset(math.pi, 140, 140, "SQUARE")
    assert(near(x, -75) and near(y, 0), "position a gauche fausse sur une mini-carte carree")

    local button = ProfessionPathMinimapButton
    assert(button, "bouton de mini-carte absent")
    assert(button:IsShown(), "le bouton doit etre visible par defaut")
    assert(type(ns.db.minimap) == "table" and type(ns.db.minimap.angle) == "number", "position non sauvegardee")

    -- Clic gauche : ouvre puis ferme la fenetre.
    local wasShown = ProfessionPathFrame and ProfessionPathFrame:IsShown()
    button.scripts.OnClick(button, "LeftButton")
    Advance(1)
    assert(ProfessionPathFrame:IsShown() ~= (wasShown and true or false), "le clic n'a pas bascule la fenetre")
    button.scripts.OnClick(button, "LeftButton")
    Advance(1)

    -- Glisser : la position suit le curseur (curseur pose au-dessus du centre).
    cursorX, cursorY = 500, 600
    button.scripts.OnDragStart(button)
    button.scripts.OnUpdate(button, 0.05)
    button.scripts.OnDragStop(button)
    assert(near(ns.db.minimap.angle, math.pi / 2), "angle apres deplacement faux : " .. ns.db.minimap.angle)
    assert(not button.scripts.OnUpdate, "le suivi du curseur doit s'arreter au lacher")

    -- Infobulle.
    button.scripts.OnEnter(button)
    button.scripts.OnLeave(button)

    -- /ppath minimap cache puis reaffiche le bouton, et s'en souvient.
    printed = {}
    SlashCmdList.PROFESSIONPATH("minimap")
    assert(not button:IsShown() and ns.db.minimap.hide == true, "le bouton aurait du etre cache")
    SlashCmdList.PROFESSIONPATH("minimap")
    assert(button:IsShown() and not ns.db.minimap.hide, "le bouton aurait du reapparaitre")
    assert(#printed == 2, "chaque bascule doit etre annoncee dans le chat")
end)

scenario("commandes du chat", function()
    for _, command in ipairs({ "debug", "recettes", "lire", "aide" }) do
        SlashCmdList.PROFESSIONPATH(command)
    end
    assert(#printed > 0, "les commandes n'ont rien affiche")
end)

realPrint(string.format("essai a blanc : %d scenarios reussis, %d en echec", passed, failed))
return failed
