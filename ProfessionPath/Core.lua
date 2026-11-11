-- Profession Path — lecture des métiers et recettes dans le jeu, sauvegarde, commandes.
-- L'add-on ne fait que LIRE et AFFICHER : il ne fabrique, n'achète et ne déplace rien.

local ADDON, ns = ...
local L = ns.L

local DB_VERSION = 1
local SCAN_DELAY = 0.3
local REFRESH_DELAY = 0.2
local PRINT_PREFIX = "|cff33ccffProfession Path|r : "

ns.scanStatus = { recipes = "-", errors = "-" }

local function Print(text)
    print(PRINT_PREFIX .. text)
end
ns.Print = Print

-- Appelle une fonction du jeu sans faire planter l'add-on si elle n'existe pas ou échoue
-- sur ce client. Les échecs sont comptés et visibles avec /mpp debug.
local apiErrors = 0
local function Try(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g = pcall(fn, ...)
    if not ok then
        apiErrors = apiErrors + 1
        return nil
    end
    return a, b, c, d, e, f, g
end

local pendingTimers = {}
local function Debounce(key, delay, fn)
    if pendingTimers[key] then return end
    pendingTimers[key] = true
    C_Timer.After(delay, function()
        pendingTimers[key] = nil
        fn()
    end)
end

-- Sauvegarde ------------------------------------------------------------

local function CharacterKey()
    return (UnitName("player") or "?") .. " - " .. (GetRealmName() or "?")
end

local function InitDB()
    ProfessionPathDB = ProfessionPathDB or {}
    local db = ProfessionPathDB
    db.version = db.version or DB_VERSION
    db.mode = db.mode or "simple"
    db.chars = db.chars or {}
    -- Recettes des maîtres lues en jeu, communes à tous les personnages :
    -- { [nom du métier] = { [nom de la recette] = { level = niveau requis, cost = prix en cuivre } } }
    db.trainer = db.trainer or {}
    -- Composants marqués d'une étoile, communs à tous les personnages : { [identifiant d'objet] = true }
    if type(db.favorites) ~= "table" then db.favorites = {} end
    ns.Favorites.Attach(db.favorites)
    -- Prix lus chez les marchands, communs à tous les personnages :
    -- { [identifiant d'objet] = prix à l'unité en cuivre }
    if type(db.vendor) ~= "table" then db.vendor = {} end
    -- PNJ rencontrés (maîtres, marchands de fournitures) et leur position, communs à tous les
    -- personnages : { ["trainer:numéro" ou "vendor:numéro"] = { kind, name, map, x, y, faction, ... } } (voir Npcs.lua)
    if type(db.npcs) ~= "table" then db.npcs = {} end
    ns.db = db
end

function ns.Character()
    local key = CharacterKey()
    local char = ns.db.chars[key]
    if not char then
        char = { profs = {}, targets = {}, skipped = {} }
        ns.db.chars[key] = char
    end
    return char
end

function ns.SortedProfessions()
    local list = {}
    for _, prof in pairs(ns.Character().profs) do
        list[#list + 1] = prof
    end
    table.sort(list, function(a, b) return (a.name or "") < (b.name or "") end)
    return list
end

function ns.SelectedProfession()
    local char = ns.Character()
    local prof = char.selected and char.profs[char.selected]
    if prof then return prof end
    prof = ns.SortedProfessions()[1]
    char.selected = prof and prof.id or nil
    return prof
end

function ns.SelectNextProfession()
    local char = ns.Character()
    local list = ns.SortedProfessions()
    if #list == 0 then return end
    local nextIndex = 1
    for index, prof in ipairs(list) do
        if prof.id == char.selected then nextIndex = index % #list + 1 end
    end
    char.selected = list[nextIndex].id
end

function ns.SkippedFor(prof)
    local char = ns.Character()
    char.skipped[prof.id] = char.skipped[prof.id] or {}
    return char.skipped[prof.id]
end

function ns.TargetFor(prof)
    local target = ns.Character().targets[prof.id]
    if not target then return prof.max end
    -- Un objectif choisi puis atteint reste affiché (« Objectif atteint ») : il ne saute pas au maximum.
    return math.min(target, prof.max)
end

function ns.SetTarget(prof, value)
    ns.Character().targets[prof.id] = value
end

-- Lecture du jeu --------------------------------------------------------

local function DifficultyNames()
    local enum = Enum and Enum.TradeskillRelativeDifficulty
    if not enum then return {} end
    return {
        [enum.Optimal] = "orange",
        [enum.Medium] = "yellow",
        [enum.Easy] = "green",
        [enum.Trivial] = "grey",
    }
end

local function IsBasicReagentSlot(slot)
    if slot.required == false then return false end
    local basic = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
    return basic == nil or slot.reagentType == nil or slot.reagentType == basic
end

local function ReadReagents(recipeID)
    local schematic = Try(C_TradeSkillUI.GetRecipeSchematic, recipeID, false)
    -- Lecture ratée : on renvoie nil (« matériaux inconnus ») plutôt qu'une liste vide,
    -- qui ferait passer la recette pour gratuite.
    if not schematic then return nil end
    local reagents = {}
    for _, slot in ipairs(schematic.reagentSlotSchematics or {}) do
        local reagent = slot.reagents and slot.reagents[1]
        if reagent and reagent.itemID and IsBasicReagentSlot(slot) then
            reagents[#reagents + 1] = { reagent.itemID, slot.quantityRequired or 1 }
        end
    end
    return reagents
end

local function ReadRecipes()
    local difficultyNames = DifficultyNames()
    local recipes, known = {}, 0
    for _, recipeID in ipairs(Try(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
        local info = Try(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if info and info.name and not info.isDummyRecipe then
            local learned = info.learned and true or false
            if learned then known = known + 1 end
            recipes[#recipes + 1] = {
                id = recipeID,
                name = info.name,
                icon = info.icon,
                learned = learned,
                difficulty = learned and difficultyNames[info.relativeDifficulty] or nil,
                skillUps = info.numSkillUps,
                reagents = ReadReagents(recipeID),
            }
        end
    end
    return recipes, known
end

-- Niveau du métier ouvert. « Professions » est l'outil du jeu qui sait lire le bon niveau ;
-- à défaut on prend les informations de base de la fenêtre.
local function NonEmpty(text)
    if type(text) == "string" and text ~= "" then return text end
    return nil
end

-- Les métiers du personnage tels que le jeu les liste : { name, icon, rank, max, skillLine }.
-- La liste du jeu peut avoir des trous (pas de second métier, par exemple).
local function PlayerProfessions()
    local list = {}
    local function Add(...)
        for position = 1, select("#", ...) do
            local index = select(position, ...)
            if index then
                local name, icon, rank, maxRank, _, _, skillLine = Try(GetProfessionInfo, index)
                if name then
                    list[#list + 1] = { name = name, icon = icon, rank = rank, max = maxRank, skillLine = skillLine }
                end
            end
        end
    end
    Add(Try(GetProfessions))
    return list
end

-- Ce que chaque fonction du jeu répond sur le métier ouvert. Sert à la lecture et à /mpp debug.
local function ProbeOpenProfession()
    local base = Try(C_TradeSkillUI.GetBaseProfessionInfo) or {}
    local live = Professions and Try(Professions.GetProfessionInfo) or {}
    local _, modernLineName = Try(C_TradeSkillUI.GetTradeSkillLine)
    local legacyLineName = Try(GetTradeSkillLine)
    return {
        base = base,
        live = live,
        name = NonEmpty(base.professionName) or NonEmpty(live.professionName)
            or NonEmpty(modernLineName) or NonEmpty(legacyLineName) or NonEmpty(live.displayName),
        professions = PlayerProfessions(),
    }
end

local function ValidLevels(skill, max)
    return type(skill) == "number" and type(max) == "number" and max > 0
end

-- Niveau du métier ouvert. On essaie d'abord la fenêtre de métier ; si elle ne donne pas de
-- niveau utilisable, on le prend dans la liste des métiers du personnage (même nom).
local function ReadOpenProfession()
    local probe = ProbeOpenProfession()
    local skill = probe.live.skillLevel or probe.base.skillLevel
    local max = probe.live.maxSkillLevel or probe.base.maxSkillLevel
    local id = probe.base.professionID or probe.live.professionID
    if not ValidLevels(skill, max) then
        for _, known in ipairs(probe.professions) do
            if known.name == probe.name or (id and known.skillLine == id) then
                skill, max = known.rank, known.max
                id = id or known.skillLine
            end
        end
    end
    id = id or probe.name
    if not id or not ValidLevels(skill, max) then return nil end
    return { id = id, name = probe.name or tostring(id), skill = skill, max = max }
end

local function IsOwnProfessionWindow()
    if Try(C_TradeSkillUI.IsTradeSkillLinked) or Try(C_TradeSkillUI.IsTradeSkillGuild) then return false end
    if Try(C_TradeSkillUI.IsNPCCrafting) then return false end
    return true
end

-- Renvoie true si le métier a été lu, false s'il faudra réessayer.
local function ScanOpenProfession(announce)
    -- Fenêtre d'un autre joueur ou d'un PNJ : rien à lire, et inutile de réessayer.
    if not IsOwnProfessionWindow() then return true end
    apiErrors = 0
    local prof = ReadOpenProfession()
    if not prof then return false end
    local recipes, known = ReadRecipes()
    ns.scanStatus = { recipes = #recipes, errors = apiErrors }
    if #recipes == 0 then
        if announce then Print(L.SCAN_EMPTY) end
        return false
    end
    prof.recipes = recipes
    prof.scanSkill = prof.skill
    local char = ns.Character()
    local isNew = char.profs[prof.id] == nil
    char.profs[prof.id] = prof
    -- On ne change pas le métier affiché dans le dos du joueur lors d'une simple relecture.
    if isNew or not char.selected then char.selected = prof.id end
    if announce or isNew then
        Print(L.SCAN_OK:format(prof.name or "?", #recipes, known))
    end
    ns.RefreshUI()
    return true
end

-- Met à jour le niveau des métiers déjà lus, même fenêtre de métier fermée.
local function RefreshSkillLevels()
    local char = ns.Character()
    for _, known in ipairs(PlayerProfessions()) do
        for _, prof in pairs(char.profs) do
            if (prof.id == known.skillLine or prof.name == known.name) and ValidLevels(known.rank, known.max) then
                prof.skill = known.rank
                prof.max = known.max
            end
        end
    end
    ns.RefreshUI()
end

-- Onglets de métier : un par métier du personnage, dans l'ordre où le jeu les liste.
-- { id (nil si jamais lu), name, icon, skill, max, read }. Un métier « non lu » est connu du
-- personnage mais sa fenêtre n'a jamais été ouverte : l'add-on n'a pas ses recettes.
-- Les métiers déjà lus que le jeu ne liste plus sont ajoutés à la fin, pour rester accessibles.
function ns.ProfessionTabs()
    local char = ns.Character()
    local tabs, matched = {}, {}
    for _, known in ipairs(PlayerProfessions()) do
        -- Le numéro du métier fait foi ; le nom ne sert que si aucun numéro ne correspond.
        local saved = known.skillLine ~= nil and char.profs[known.skillLine] or nil
        if matched[saved] then saved = nil end
        if not saved then
            for _, prof in ipairs(ns.SortedProfessions()) do
                if not saved and not matched[prof] and prof.name == known.name then saved = prof end
            end
        end
        if saved then matched[saved] = true end
        tabs[#tabs + 1] = {
            id = saved and saved.id or nil,
            name = known.name,
            icon = known.icon,
            skill = known.rank,
            max = known.max,
            read = saved ~= nil,
        }
    end
    for _, prof in ipairs(ns.SortedProfessions()) do
        if not matched[prof] then
            tabs[#tabs + 1] = { id = prof.id, name = prof.name, skill = prof.skill, max = prof.max, read = true }
        end
    end
    return tabs
end

-- Affiche directement ce métier. Renvoie false s'il n'a jamais été lu.
function ns.SelectProfession(id)
    local char = ns.Character()
    if id == nil or not char.profs[id] then return false end
    char.selected = id
    return true
end

-- Données pour le moteur ------------------------------------------------

--- Recettes enseignées par le maître de ce métier, ou une liste vide s'il n'a pas encore été lu.
-- Le maître range ses recettes sous le nom de métier qu'il annonce. Ce nom peut différer de
-- celui de la fenêtre de métier : on essaie alors le nom donné par la liste des métiers du
-- personnage pour le même métier.
local function FindTrainerRecipes(prof)
    local found = prof.name and ns.db.trainer[prof.name]
    if found then return found end
    for _, known in ipairs(PlayerProfessions()) do
        if known.skillLine == prof.id and ns.db.trainer[known.name] then
            return ns.db.trainer[known.name]
        end
    end
    return nil
end

function ns.TrainerRecipes(prof)
    return FindTrainerRecipes(prof) or {}
end

function ns.HasTrainerData(prof)
    return FindTrainerRecipes(prof) ~= nil
end

-- Prépare les recettes pour le moteur, sans modifier celles qui sont sauvegardées.
function ns.RecipesForPlanner(prof)
    local coloursAreFresh = prof.scanSkill == prof.skill
    -- Ce que le maître de ce métier enseigne, tel que lu en jeu : { [nom] = { level, cost } }.
    local taughtByTrainer = ns.TrainerRecipes(prof)
    local list = {}
    for _, saved in ipairs(prof.recipes or {}) do
        local difficulty = saved.difficulty
        -- Une couleur lue à un autre niveau n'est plus fiable, sauf le gris qui est définitif.
        if not coloursAreFresh and difficulty ~= "grey" then difficulty = nil end
        -- Une recette déjà connue n'a plus rien à apprendre chez le maître.
        local taught = not saved.learned and taughtByTrainer[saved.name] or nil
        local teachingItem = ns.TeachingItems[saved.id]
        list[#list + 1] = {
            -- Le maître lu en jeu fait foi ; sinon, l'objet qui apprend la recette (données du jeu).
            learnLevel = taught and taught.level or nil,
            learnCost = taught and taught.cost or nil,
            learnSource = taught and "trainer" or (teachingItem and "item" or nil),
            teachingItem = teachingItem,
            id = saved.id,
            name = saved.name,
            icon = saved.icon,
            learned = saved.learned,
            difficulty = difficulty,
            skillUps = saved.skillUps,
            reagents = saved.reagents,
            thresholds = ns.Thresholds[saved.id],
        }
    end
    return list
end

function ns.HasPrices()
    return Auctionator ~= nil and Auctionator.API ~= nil and Auctionator.API.v1 ~= nil
        and type(Auctionator.API.v1.GetAuctionPriceByItemID) == "function"
end

-- Prix d'un objet chez un marchand : celui que le joueur a lu lui-même en jeu, sinon celui
-- livré avec l'add-on. nil si aucun marchand connu ne le vend.
function ns.VendorPrice(itemID)
    local read = ns.db and ns.db.vendor and ns.db.vendor[itemID]
    if type(read) == "number" and read > 0 then return read end
    local shipped = ns.VendorPrices[itemID]
    if type(shipped) == "number" and shipped > 0 then return shipped end
    return nil
end

-- Interroge Auctionator, s'il est installé et connaît cette question. nil sinon.
local function AuctionatorPrice(method, itemID)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if type(api) ~= "table" or type(api[method]) ~= "function" then return nil end
    local ok, price = pcall(api[method], ADDON, itemID)
    if ok and type(price) == "number" and price > 0 then return price end
    return nil
end

-- Prix le plus bas connu pour un objet : marchand (lu par cet add-on ou par Auctionator) ou
-- hôtel des ventes. nil si aucune source ne le connaît : on n'invente jamais de prix.
function ns.PriceOf(itemID)
    local best
    local function Keep(price)
        if price and (not best or price < best) then best = price end
    end
    Keep(ns.VendorPrice(itemID))
    Keep(AuctionatorPrice("GetVendorPriceByItemID", itemID))
    Keep(AuctionatorPrice("GetAuctionPriceByItemID", itemID))
    return best
end

-- Recettes que ce personnage connaît, rangées par objet fabriqué :
-- { [objet] = { { reagents = matériaux, yield = objets obtenus par fabrication }, ... } }.
-- Sert à donner un prix aux objets qu'il sait fabriquer lui-même (voir Planner.NewPricer).
function ns.CraftSources()
    local sources = {}
    for _, prof in pairs(ns.Character().profs) do
        for _, recipe in ipairs(prof.recipes or {}) do
            local craft = recipe.learned and ns.Crafts[recipe.id]
            if craft and type(recipe.reagents) == "table" and #recipe.reagents > 0 then
                local itemID = craft[1]
                sources[itemID] = sources[itemID] or {}
                table.insert(sources[itemID], { reagents = recipe.reagents, yield = craft[2] })
            end
        end
    end
    return sources
end

-- Fonction « prix d'un objet » pour un calcul : le plus bas entre marchand, hôtel des ventes et
-- fabrication par le joueur. À recréer à chaque calcul, car elle retient ses résultats.
function ns.NewPricer()
    return ns.Planner.NewPricer(ns.PriceOf, ns.CraftSources())
end

-- Total possédé : sacs et banque du personnage.
function ns.OwnedCount(itemID)
    return Try(C_Item.GetItemCount, itemID, true) or 0
end

-- Seulement ce qui est dans les sacs (sans la banque).
function ns.BagCount(itemID)
    return Try(C_Item.GetItemCount, itemID, false) or 0
end

--- Somme d'argent écrite avec les icônes or / argent / cuivre du jeu, ou nil si indisponible.
function ns.MoneyText(copper)
    return Try(GetCoinTextureString, copper)
        or (C_CurrencyInfo and Try(C_CurrencyInfo.GetCoinTextureString, copper))
        or nil
end

function ns.ItemIcon(itemID)
    return Try(C_Item.GetItemIconByID, itemID)
end

-- Chaque nom n'est demandé au jeu qu'une fois, pour ne pas redessiner la fenêtre en boucle.
local requestedItemNames = {}

function ns.ItemName(itemID)
    local name = Try(C_Item.GetItemNameByID, itemID)
    if name then return name end
    if not requestedItemNames[itemID] then
        requestedItemNames[itemID] = true
        Try(C_Item.RequestLoadItemDataByID, itemID)
    end
    return L.ITEM_UNKNOWN:format(itemID)
end

-- Commandes -------------------------------------------------------------

local function CountThresholds()
    local count = 0
    for _ in pairs(ns.Thresholds) do count = count + 1 end
    return count
end

-- Compteurs des signaux reçus du jeu, pour comprendre une lecture qui ne se fait pas.
local eventCounts = {}

-- Affiche ce que le jeu répond réellement, à envoyer tel quel en cas de souci.
local function PrintDebug()
    local version, build, _, interface = GetBuildInfo()
    Print(L.DEBUG:format(tostring(version), tostring(build), tostring(interface),
        tostring(ns.scanStatus.recipes), tostring(ns.scanStatus.errors), CountThresholds()))
    local bags = ns.Bags and ns.Bags.Hooked() or {}
    print(L.DEBUG_FAVORITES:format(ns.Favorites.Count(), #bags > 0 and table.concat(bags, ", ") or "-",
        tostring(ns.Bags and ns.Bags.LastError() or ns.Favorites.LastError() or "-")))

    local probe = ProbeOpenProfession()
    local recipeIDs = Try(C_TradeSkillUI.GetAllRecipeIDs)
    print(("  open: name=%s | base id=%s lvl=%s/%s | live id=%s lvl=%s/%s | recipeIDs=%s | Professions=%s"):format(
        tostring(probe.name),
        tostring(probe.base.professionID), tostring(probe.base.skillLevel), tostring(probe.base.maxSkillLevel),
        tostring(probe.live.professionID), tostring(probe.live.skillLevel), tostring(probe.live.maxSkillLevel),
        recipeIDs and tostring(#recipeIDs) or "nil", tostring(Professions ~= nil)))

    local known = {}
    for _, prof in ipairs(probe.professions) do
        known[#known + 1] = ("%s %s/%s (%s)"):format(prof.name, tostring(prof.rank), tostring(prof.max), tostring(prof.skillLine))
    end
    print("  character: " .. (#known > 0 and table.concat(known, ", ") or "none"))

    local trainers = {}
    for professionName, recipes in pairs(ns.db.trainer) do
        local count = 0
        for _ in pairs(recipes) do count = count + 1 end
        trainers[#trainers + 1] = ("%s (%d)"):format(professionName, count)
    end
    table.sort(trainers)
    print("  trainers read: " .. (#trainers > 0 and table.concat(trainers, ", ") or "none"))

    local readPrices, shippedPrices = 0, 0
    for _ in pairs(ns.db.vendor) do readPrices = readPrices + 1 end
    for _ in pairs(ns.VendorPrices) do shippedPrices = shippedPrices + 1 end
    print(L.DEBUG_VENDOR:format(readPrices, shippedPrices))
    if ns.CountNpcs then print(L.DEBUG_NPCS:format(ns.CountNpcs())) end

    local events = {}
    for event, count in pairs(eventCounts) do
        events[#events + 1] = event .. "=" .. count
    end
    table.sort(events)
    print("  events: " .. (#events > 0 and table.concat(events, ", ") or "none"))
end

-- Lecture demandée par le joueur (/mpp lire) : on dit clairement si elle a réussi.
local function ScanOnDemand()
    if not ScanOpenProfession(true) then Print(L.SCAN_FAILED) end
end

-- Appelée à l'ouverture de la fenêtre de l'add-on : rattrape un métier déjà ouvert en jeu.
function ns.TryScan()
    return ScanOpenProfession(false)
end

-- Sonde : affiche tout ce que le jeu dit d'une recette NON connue du métier ouvert, pour voir
-- s'il fournit une information qu'on n'exploite pas encore. search : début du nom (facultatif).
local function PrintProbe(search)
    local wanted = (search or ""):lower()
    for _, recipeID in ipairs(Try(C_TradeSkillUI.GetAllRecipeIDs) or {}) do
        local info = Try(C_TradeSkillUI.GetRecipeInfo, recipeID)
        if info and info.name and not info.learned and info.name:lower():find(wanted, 1, true) then
            Print(("%d - %s"):format(recipeID, info.name))
            local fields = {}
            for key, value in pairs(info) do
                if type(value) ~= "table" and type(value) ~= "function" then
                    fields[#fields + 1] = tostring(key) .. "=" .. tostring(value)
                end
            end
            table.sort(fields)
            print("  info: " .. table.concat(fields, ", "))
            print("  source: " .. tostring(Try(C_TradeSkillUI.GetRecipeSourceText, recipeID)))
            return
        end
    end
    Print(L.PROBE_NONE)
end

local function PrintRecipes()
    local prof = ns.SelectedProfession()
    if not prof then
        Print(L.NO_PROFESSION)
        return
    end
    Print(L.RECIPES_HEADER:format(prof.name or "?"))
    for _, recipe in ipairs(prof.recipes or {}) do
        print(("  %d - %s"):format(recipe.id, recipe.name))
    end
end

-- /ppath et /profpath pour tout le monde ; /mpp et /metiers gardés pour les habitués français.
SLASH_PROFESSIONPATH1 = "/ppath"
SLASH_PROFESSIONPATH2 = "/profpath"
SLASH_PROFESSIONPATH3 = "/mpp"
SLASH_PROFESSIONPATH4 = "/metiers"
SlashCmdList.PROFESSIONPATH = function(message)
    local command, rest = (message or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    if command == "sonde" or command == "probe" then
        PrintProbe(rest)
    elseif command == "debug" then
        PrintDebug()
    elseif command == "lire" or command == "scan" then
        ScanOnDemand()
    elseif command == "recettes" or command == "recipes" then
        PrintRecipes()
    elseif command == "minimap" then
        if ns.ToggleMinimapButton then ns.ToggleMinimapButton() end
    elseif command == "aide" or command == "help" then
        Print(L.HELP)
    else
        ns.ToggleUI()
    end
end

-- Bouton du menu des add-ons (près de la mini-carte).
function ProfessionPath_OnAddonCompartmentClick()
    ns.ToggleUI()
end

-- Évènements ------------------------------------------------------------

local handlers = {}

function handlers.ADDON_LOADED(name)
    if name == ADDON then InitDB() end
end

function handlers.PLAYER_LOGIN()
    RefreshSkillLevels()
end

-- Relire toutes les recettes coûte un peu : on ne le fait que lorsque quelque chose a changé.
local windowOpen, needScan = false, false

local function RequestScan()
    needScan = true
    Debounce("scan", SCAN_DELAY, function()
        if not (windowOpen and needScan) then return end
        -- Si la lecture échoue (données pas encore prêtes), on réessaiera au prochain signal du jeu.
        needScan = not ScanOpenProfession(false)
    end)
end

function handlers.TRADE_SKILL_SHOW()
    windowOpen = true
    RequestScan()
end
handlers.TRADE_SKILL_DATA_SOURCE_CHANGED = handlers.TRADE_SKILL_SHOW

function handlers.TRADE_SKILL_CLOSE()
    windowOpen = false
end

function handlers.NEW_RECIPE_LEARNED()
    if windowOpen then RequestScan() end
end

-- Le jeu envoie souvent cet évènement : on ne relit que si la lecture précédente était vide.
function handlers.TRADE_SKILL_LIST_UPDATE()
    if windowOpen and needScan then RequestScan() end
end

function handlers.SKILL_LINES_CHANGED()
    Debounce("skills", REFRESH_DELAY, RefreshSkillLevels)
    -- Un point gagné change les couleurs des recettes : on les relit si la fenêtre est ouverte.
    if windowOpen then RequestScan() end
end

function handlers.BAG_UPDATE_DELAYED()
    Debounce("refresh", REFRESH_DELAY, function() ns.RefreshUI() end)
end
handlers.GET_ITEM_INFO_RECEIVED = handlers.BAG_UPDATE_DELAYED

local eventFrame = CreateFrame("Frame")
for event in pairs(handlers) do
    -- Un évènement absent de ce client ne doit pas empêcher l'add-on de se charger.
    pcall(eventFrame.RegisterEvent, eventFrame, event)
end
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if not ns.db and event ~= "ADDON_LOADED" then return end
    if event:find("SKILL", 1, true) or event == "NEW_RECIPE_LEARNED" then
        eventCounts[event] = (eventCounts[event] or 0) + 1
    end
    local handler = handlers[event]
    if handler then handler(...) end
end)

-- Remplacées par UI.lua ; définies ici pour que Core fonctionne même si la fenêtre n'existe pas.
ns.RefreshUI = ns.RefreshUI or function() end
ns.ToggleUI = ns.ToggleUI or function() end
