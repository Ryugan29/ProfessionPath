-- PNJ du métier : où trouver son maître et un marchand de fournitures, et repère sur la carte.
--
-- Les fichiers du jeu ne contiennent pas la position des PNJ. On la note quand le joueur parle
-- à un maître de métier ou à un marchand qui vend des matériaux de recettes : c'est la position
-- du joueur à ce moment-là, donc à quelques pas du PNJ. Rien n'est inventé.
--
-- Le repère est celui du jeu (celui qu'on pose soi-même sur la carte) : un seul à la fois.
-- L'add-on ne déplace jamais le personnage.

local _, ns = ...
local L = ns.L

local COORD_PRECISION = 10000 -- quatre décimales suffisent pour un repère sur une carte
local MAX_TRAINERS, MAX_VENDORS = 2, 2

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

-- Numéro du PNJ, tiré de son identifiant : « Creature-0-serveur-instance-zone-NUMÉRO-apparition ».
local function NpcID(guid)
    if type(guid) ~= "string" then return nil end
    return tonumber(guid:match("^%a+%-%d+%-%d+%-%d+%-%d+%-(%d+)"))
end

local function Round(value)
    return math.floor(value * COORD_PRECISION + 0.5) / COORD_PRECISION
end

-- Carte sur laquelle on peut poser un repère : celle du joueur, ou la première carte parente qui
-- l'accepte (dans un bâtiment ou un quartier qui a sa propre petite carte, par exemple).
local MAX_PARENT_STEPS = 5
local function MarkableMap(map)
    if not C_Map.CanSetUserWaypointOnMap then return map end
    for _ = 1, MAX_PARENT_STEPS do
        if Call(C_Map.CanSetUserWaypointOnMap, map) then return map end
        local info = Call(C_Map.GetMapInfo, map)
        local parent = type(info) == "table" and info.parentMapID or nil
        if type(parent) ~= "number" or parent == 0 then return map end
        map = parent
    end
    return map
end

-- Carte et position du joueur, ou nil (dans un donjon, par exemple, il n'y en a pas).
-- Tout est protégé : une valeur inattendue du jeu ne doit jamais empêcher la fenêtre de s'afficher.
local ReadPlayerPosition
local function PlayerPosition()
    local ok, map, x, y = pcall(ReadPlayerPosition)
    if ok then return map, x, y end
    return nil
end

ReadPlayerPosition = function()
    if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition) then return nil end
    local best = Call(C_Map.GetBestMapForUnit, "player")
    if type(best) ~= "number" then return nil end
    local map = MarkableMap(best)
    -- Le jeu donne la position du joueur sur n'importe quelle carte qui le contient.
    local position = Call(C_Map.GetPlayerMapPosition, map, "player")
    if type(position) ~= "table" then return nil end
    local x, y
    if type(position.GetXY) == "function" then
        x, y = Call(position.GetXY, position)
    else
        x, y = position.x, position.y
    end
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then return nil end
    return map, Round(x), Round(y)
end

function ns.NpcZoneName(map)
    local info = C_Map and Call(C_Map.GetMapInfo, map)
    return type(info) == "table" and info.name or "?"
end

-- Note le PNJ en face du joueur. Renvoie l'entrée notée, ou nil s'il manque une information.
local function Record(kind, fields)
    if not ns.db then return nil end
    local id = NpcID(Call(UnitGUID, "npc"))
    local name = Call(UnitName, "npc")
    local map, x, y = PlayerPosition()
    if not (id and type(name) == "string" and map) then return nil end
    local npc = { kind = kind, name = name, map = map, x = x, y = y, faction = Call(UnitFactionGroup, "npc") }
    for key, value in pairs(fields) do npc[key] = value end
    -- Clé « genre:numéro » : un même PNJ peut être à la fois maître et marchand.
    local key = kind .. ":" .. id
    local previous = ns.db.npcs[key]
    -- Revu (par exemple par un autre personnage) : on complète la fiche au lieu de la remplacer.
    if type(previous) == "table" then
        if type(previous.items) == "table" and type(npc.items) == "table" then
            for itemID in pairs(previous.items) do npc.items[itemID] = true end
        end
        if npc.professionID == nil then npc.professionID = previous.professionID end
    end
    ns.db.npcs[key] = npc
    return npc
end

local function ProfessionIDByName(name)
    for _, prof in pairs(ns.Character().profs) do
        if prof.name == name then return prof.id end
    end
    return nil
end

-- Appelé par Trainer.lua quand un maître de métier a été lu.
function ns.RecordTrainerNpc(profession)
    return Record("trainer", { profession = profession, professionID = ProfessionIDByName(profession) })
end

-- Matériaux de métier : ceux des prix livrés, et ceux des recettes des métiers du personnage.
local function CraftingItems()
    local items = {}
    for itemID in pairs(ns.VendorPrices or {}) do items[itemID] = true end
    for _, prof in pairs(ns.Character().profs) do
        for _, recipe in ipairs(prof.recipes or {}) do
            for _, reagent in ipairs(recipe.reagents or {}) do items[reagent[1]] = true end
        end
    end
    return items
end

-- Appelé par Vendor.lua à l'ouverture d'un marchand. Un marchand qui ne vend aucun matériau
-- de métier (armes, nourriture...) n'est pas noté.
function ns.RecordVendorNpc()
    local crafting, sold, count = CraftingItems(), {}, 0
    for index = 1, Call(GetMerchantNumItems) or 0 do
        local itemID = Call(GetMerchantItemID, index)
        if type(itemID) == "number" and crafting[itemID] then
            sold[itemID] = true
            count = count + 1
        end
    end
    if count == 0 then return nil end
    return Record("vendor", { items = sold })
end

-- Annuaire des maîtres (Data/Trainers.lua), mis en forme comme les PNJ notés en jeu.
-- unlocks : maximums de métier que ce maître permet d'atteindre (75 = Apprenti, 150 = Compagnon...).
local directory
local function Directory()
    if directory then return directory end
    directory = {}
    for skillLine, trainers in pairs(ns.Trainers or {}) do
        for index, t in ipairs(trainers) do
            directory["dir:" .. skillLine .. ":" .. index] = {
                kind = "trainer", directory = true, name = t.name, map = t.map, x = t.x, y = t.y,
                faction = t.faction, professionID = skillLine, unlocks = t.unlocks or {},
            }
        end
    end
    return directory
end

-- Deux fiches du même maître : l'annuaire est en anglais, une fiche notée en jeu est dans la
-- langue du joueur. On les reconnaît au même métier et au même endroit (ou au même nom).
local TWIN_DISTANCE = 0.02
local function SameTrainer(known, entry)
    if type(known) ~= "table" or known.kind ~= "trainer" then return false end
    if known.professionID ~= nil and known.professionID ~= entry.professionID then return false end
    if known.name == entry.name then return true end
    return known.map == entry.map and type(known.x) == "number" and type(known.y) == "number"
        and math.abs(known.x - entry.x) <= TWIN_DISTANCE and math.abs(known.y - entry.y) <= TWIN_DISTANCE
end

-- PNJ livrés avec l'add-on, puis ceux vus par le joueur (qui les remplacent).
local function KnownNpcs()
    local known = {}
    for id, npc in pairs(ns.NPCs or {}) do known[id] = npc end
    for id, npc in pairs(ns.db and ns.db.npcs or {}) do known[id] = npc end
    return known
end

-- Fiche notée en jeu du maître de l'annuaire « entry », s'il a déjà été rencontré.
local function KnownTwin(entry, known)
    for _, npc in pairs(known) do
        if SameTrainer(npc, entry) then return npc end
    end
    return nil
end

-- Tous les PNJ connus : ceux notés (livrés ou vus par le joueur), puis les maîtres de l'annuaire
-- qui n'ont pas encore de fiche notée.
local function AllNpcs()
    local all = KnownNpcs()
    local known = {}
    for id, npc in pairs(all) do known[id] = npc end
    for id, npc in pairs(Directory()) do
        if not KnownTwin(npc, known) then all[id] = npc end
    end
    return all
end

local function Reagents(prof)
    local reagents = {}
    for _, recipe in ipairs(prof.recipes or {}) do
        for _, reagent in ipairs(recipe.reagents or {}) do reagents[reagent[1]] = true end
    end
    return reagents
end

-- Un maître sert le métier qu'il enseigne ; un marchand, s'il vend des matériaux de ses recettes.
-- Renvoie le nombre de matériaux du métier que le PNJ fournit (0 : il ne sert pas ce métier).
-- Un maître compte comme un fournisseur complet, pour passer avant les marchands.
local TRAINER_WEIGHT = 1000
local function Serves(npc, prof, reagents)
    if npc.kind == "trainer" then
        local teaches = (npc.professionID ~= nil and npc.professionID == prof.id) or npc.profession == prof.name
        -- Maître de l'annuaire : seulement s'il enseigne le rang actuel ou le suivant.
        if teaches and npc.directory then
            teaches = npc.unlocks[prof.max] or npc.unlocks[(prof.max or 0) + 75] or false
        end
        return teaches and TRAINER_WEIGHT or 0
    end
    local matches = 0
    if npc.kind == "vendor" and type(npc.items) == "table" then
        for itemID in pairs(npc.items) do
            if reagents[itemID] then matches = matches + 1 end
        end
    end
    return matches
end

-- Les PNJ neutres servent tout le monde ; les autres, seulement leur faction.
local function SameFaction(npcFaction, playerFaction)
    return npcFaction == nil or npcFaction == "Neutral" or playerFaction == nil or npcFaction == playerFaction
end

-- PNJ utiles pour ce métier : ceux de la zone du joueur d'abord (les plus proches en tête),
-- puis les autres, rangés par zone. Chaque entrée : { id, npc, zone, sameMap, distance }.
function ns.NpcsFor(prof)
    if type(prof) ~= "table" then return {} end
    local reagents = Reagents(prof)
    local here, hereX, hereY = PlayerPosition()
    local playerFaction = Call(UnitFactionGroup, "player")
    local list = {}
    for id, npc in pairs(AllNpcs()) do
        local usable = type(npc) == "table" and type(npc.map) == "number"
            and type(npc.x) == "number" and type(npc.y) == "number" and type(npc.name) == "string"
        local matches = usable and SameFaction(npc.faction, playerFaction) and Serves(npc, prof, reagents) or 0
        if matches > 0 then
            local sameMap = here ~= nil and npc.map == here
            list[#list + 1] = {
                id = id, npc = npc, zone = ns.NpcZoneName(npc.map), sameMap = sameMap, matches = matches,
                distance = sameMap and ((npc.x - hereX) ^ 2 + (npc.y - hereY) ^ 2) or math.huge,
            }
        end
    end
    -- Dans la zone du joueur d'abord. Ensuite, le vrai marchand de fournitures (qui vend beaucoup
    -- de matériaux du métier) passe avant une échoppe qui n'en vend qu'un, même plus proche.
    table.sort(list, function(a, b)
        if a.sameMap ~= b.sameMap then return a.sameMap end
        if a.matches ~= b.matches then return a.matches > b.matches end
        if a.distance ~= b.distance then return a.distance < b.distance end
        if a.zone ~= b.zone then return a.zone < b.zone end
        return a.npc.name < b.npc.name
    end)
    return list
end

-- Les plus utiles à afficher : jusqu'à deux maîtres et deux marchands, dans l'ordre de NpcsFor.
function ns.NpcsToShow(prof)
    local shown, trainers, vendors = {}, 0, 0
    for _, entry in ipairs(ns.NpcsFor(prof)) do
        if entry.npc.kind == "trainer" and trainers < MAX_TRAINERS then
            trainers = trainers + 1
            shown[#shown + 1] = entry
        elseif entry.npc.kind == "vendor" and vendors < MAX_VENDORS then
            vendors = vendors + 1
            shown[#shown + 1] = entry
        end
    end
    return shown
end

-- Maître de l'annuaire qui enseigne le rang de maximum « nextMax », accessible au joueur : celui de
-- la zone du joueur (le plus proche) d'abord, puis ceux de sa faction (les villes de sa faction)
-- avant les lieux neutres, puis par zone et par nom. S'il a déjà été rencontré, on renvoie sa fiche
-- notée en jeu (nom dans la langue du joueur, position exacte).
function ns.RankTrainer(skillLine, nextMax)
    local here, hereX, hereY = PlayerPosition()
    local playerFaction = Call(UnitFactionGroup, "player")
    local zones = {}
    local function Zone(map)
        zones[map] = zones[map] or ns.NpcZoneName(map)
        return zones[map]
    end
    local best, bestKey
    for _, npc in pairs(Directory()) do
        if npc.professionID == skillLine and npc.unlocks[nextMax] and SameFaction(npc.faction, playerFaction) then
            local sameMap = here ~= nil and npc.map == here
            local distance = sameMap and ((npc.x - hereX) ^ 2 + (npc.y - hereY) ^ 2) or math.huge
            local ownFaction = playerFaction ~= nil and npc.faction == playerFaction
            local key = { sameMap and 0 or 1, distance, ownFaction and 0 or 1, Zone(npc.map), npc.name }
            local better = not bestKey
            for i = 1, #key do
                if better or key[i] ~= bestKey[i] then
                    better = better or key[i] < bestKey[i]
                    break
                end
            end
            if better then best, bestKey = npc, key end
        end
    end
    return best and (KnownTwin(best, KnownNpcs()) or best)
end

-- Pose le repère du jeu sur ce PNJ, avec la flèche qui guide jusqu'à lui.
function ns.PinNpc(npc, zone)
    local point
    local canPin = C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates
    if canPin and C_Map.CanSetUserWaypointOnMap then
        canPin = Call(C_Map.CanSetUserWaypointOnMap, npc.map)
    end
    if canPin then point = Call(UiMapPoint.CreateFromCoordinates, npc.map, npc.x, npc.y) end
    if not (point and pcall(C_Map.SetUserWaypoint, point)) then
        ns.Print(L.NPC_PIN_FAILED)
        return false
    end
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
    end
    ns.Print(L.NPC_PIN_DONE:format(npc.name, zone or ns.NpcZoneName(npc.map)))
    return true
end

-- Pour /ppath debug : PNJ vus en jeu, et PNJ livrés avec l'add-on.
function ns.CountNpcs()
    local seen, shipped = 0, 0
    for _ in pairs(ns.db and ns.db.npcs or {}) do seen = seen + 1 end
    for _ in pairs(ns.NPCs or {}) do shipped = shipped + 1 end
    return seen, shipped
end
