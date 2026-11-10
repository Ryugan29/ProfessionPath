-- Favoris : les composants que le joueur a marqués d'une étoile.
-- Logique pure, sans appel au jeu : testable hors de WoW (tests/favorites_test.lua).
-- Les favoris sont communs à tous les personnages du compte.

local _, ns = ...

local Favorites = {}
ns.Favorites = Favorites

-- Image de l'étoile : celle de la marque de raid, présente dans tous les clients du jeu.
Favorites.ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_1"

local store = {}      -- { [identifiant d'objet] = true }, remplacé par la sauvegarde au démarrage
local listeners = {}
local lastError

local function IsItemID(value)
    return type(value) == "number" and value > 0 and value == math.floor(value)
end

-- Branche les favoris sur la table sauvegardée par le jeu (ou sur une table vide à défaut).
function Favorites.Attach(saved)
    store = type(saved) == "table" and saved or {}
end

function Favorites.Is(itemID)
    return IsItemID(itemID) and store[itemID] == true
end

function Favorites.Count()
    local count = 0
    for itemID, value in pairs(store) do
        if IsItemID(itemID) and value == true then count = count + 1 end
    end
    return count
end

-- Fonction appelée à chaque changement, avec (identifiant d'objet, est favori).
function Favorites.OnChange(listener)
    if type(listener) == "function" then listeners[#listeners + 1] = listener end
end

-- Dernière panne d'un écouteur, pour /mpp debug.
function Favorites.LastError()
    return lastError
end

-- Met en favori, ou retire si c'en était déjà un. Renvoie le nouvel état.
function Favorites.Toggle(itemID)
    if not IsItemID(itemID) then return false end
    local isFavorite = not Favorites.Is(itemID)
    store[itemID] = isFavorite or nil
    for _, listener in ipairs(listeners) do
        local ok, err = pcall(listener, itemID, isFavorite)
        if not ok then lastError = tostring(err) end
    end
    return isFavorite
end
