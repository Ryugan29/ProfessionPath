-- Diagnostic à copier : /ppath diag.
-- Ouvre la fenêtre « texte à copier » avec l'état technique de l'add-on, à coller dans un
-- signalement de bug sur GitHub (formulaire bug.yml). Aucun nom de personnage ni de royaume.

local ADDON, ns = ...
local L = ns.L

local DIAG_VERSION = 1
local ISSUE_URL = "https://github.com/Ryugan29/ProfessionPath/issues/new?template=bug.yml"

local function Count(map)
    local count = 0
    for _ in pairs(map or {}) do count = count + 1 end
    return count
end

-- Version écrite dans le .toc. Le nom de la fonction du jeu a changé selon les versions du client.
local function AddonVersion()
    local read = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if type(read) ~= "function" then return "?" end
    local ok, version = pcall(read, ADDON, "Version")
    return ok and version or "?"
end

local function ProfessionLines()
    local lines = {}
    for _, prof in ipairs(ns.SortedProfessions()) do
        lines[#lines + 1] = ("  %s %s/%s (id %s) : %d recettes lues, maitre : %s"):format(
            tostring(prof.name), tostring(prof.skill), tostring(prof.max), tostring(prof.id),
            #(prof.recipes or {}), ns.TrainerDataSource(prof) or "aucun")
    end
    if #lines == 0 then lines[1] = "  aucun metier lu" end
    return lines
end

local function EventsLine()
    local events = {}
    for event, count in pairs(ns.eventCounts or {}) do events[#events + 1] = event .. "=" .. count end
    table.sort(events)
    return #events > 0 and table.concat(events, ", ") or "aucun"
end

-- Texte complet du diagnostic, et nombre de métiers lus.
function ns.BuildDiagText()
    local db = ns.db
    local version, build, _, interface = GetBuildInfo()
    local seenNpcs, shippedNpcs = ns.CountNpcs()
    local bags = ns.Bags and ns.Bags.Hooked() or {}
    local lines = {
        "ProfessionPath-diag " .. DIAG_VERSION,
        "add-on : " .. tostring(AddonVersion()),
        ("jeu : %s (build %s, interface %s), langue %s"):format(tostring(version), tostring(build),
            tostring(interface), tostring(GetLocale())),
        ("sauvegarde : version %s%s"):format(tostring(db.version),
            ns.migrationError and (", conversion ratee " .. ns.migrationError) or ""),
        ("reglages : priorite %s, affichage %s, taille %d %%, bouton mini-carte %s"):format(tostring(db.mode),
            tostring(db.layout or "column"), math.floor((tonumber(db.scale) or 1) * 100 + 0.5),
            (type(db.minimap) == "table" and db.minimap.hide) and "cache" or "visible"),
        "Auctionator : " .. (ns.HasPrices() and "oui" or "non"),
        "metiers :",
    }
    local professions = ProfessionLines()
    for _, line in ipairs(professions) do lines[#lines + 1] = line end
    local status = ns.scanStatus or {}
    lines[#lines + 1] = ("derniere lecture : %s recettes, %s erreurs du jeu"):format(tostring(status.recipes), tostring(status.errors))
    lines[#lines + 1] = ("donnees : %d seuils, %d maitres lus, prix marchands %d lus / %d livres, PNJ %d vus / %d livres"):format(
        Count(ns.Thresholds), Count(db.trainer), Count(db.vendor), Count(ns.VendorPrices), seenNpcs, shippedNpcs)
    lines[#lines + 1] = ("favoris : %d, sacs relies : %s"):format(ns.Favorites.Count(), #bags > 0 and table.concat(bags, ", ") or "aucun")
    lines[#lines + 1] = "derniere erreur : " .. tostring(ns.Bags and ns.Bags.LastError() or ns.Favorites.LastError() or "aucune")
    lines[#lines + 1] = "evenements : " .. EventsLine()
    return table.concat(lines, "\n"), #ns.SortedProfessions()
end

-- /ppath diag
function ns.ShowDiag()
    local text, professions = ns.BuildDiagText()
    ns.ShowCopyWindow({ title = L.DIAG_TITLE, help = L.DIAG_HELP:format(ISSUE_URL),
        stats = L.DIAG_STATS:format(tostring(AddonVersion()), professions), text = text })
end
