-- Rang suivant d'un métier (Compagnon, Expert, Artisan) : quand l'apprendre, et chez qui.
-- Les conditions (métier et niveau requis) et les maîtres viennent de Data/Trainers.lua, tiré des
-- pages de wow-professions.com/forever. Le rang Expert de la Cuisine, du Secourisme et de la Pêche
-- s'apprend avec un livre (guides du même site) : le PNJ indiqué est alors celui qui le vend.

local _, ns = ...
local L = ns.L

local RANK_STEP = 75 -- chaque rang monte le maximum de 75 points
local RANK_KEYS = { [150] = "RANK_JOURNEYMAN", [225] = "RANK_EXPERT", [300] = "RANK_ARTISAN" }

-- Métiers dont le rang Expert s'apprend avec un livre.
local EXPERT_FROM_BOOK = {
    [185] = true, -- Cuisine
    [129] = true, -- Secourisme
    [356] = true, -- Pêche
}

--- Rang que le personnage peut apprendre maintenant pour ce métier, ou nil.
-- Renvoie le titre et le texte du bandeau, et le PNJ à aller voir (ou nil s'il n'est pas connu).
function ns.NextRankText(prof)
    if not prof or type(prof.skill) ~= "number" or type(prof.max) ~= "number" then return nil end
    local nextMax = prof.max + RANK_STEP
    local key = RANK_KEYS[nextMax]
    local rule = key and ns.RankRules and ns.RankRules[prof.id] and ns.RankRules[prof.id][nextMax]
    if not (rule and type(rule.skill) == "number") or prof.skill < rule.skill then return nil end

    local rankName = L[key]
    local body
    if key == "RANK_EXPERT" and EXPERT_FROM_BOOK[prof.id] then
        body = L.RANK_BOOK:format(rankName, prof.max)
    else
        body = L.RANK_TRAINER:format(prof.name or "?", rankName, prof.max)
    end
    local npc = ns.RankTrainer and ns.RankTrainer(prof.id, nextMax)
    if npc then body = body .. L.RANK_WHERE:format(npc.name, ns.NpcZoneName(npc.map)) end
    -- Le niveau du personnage peut être une valeur protégée du jeu : tonumber la rend comparable.
    local level = tonumber(UnitLevel and UnitLevel("player"))
    if type(rule.level) == "number" and level and level < rule.level then
        body = body .. L.RANK_LEVEL:format(rule.level, level)
    end
    return L.RANK_TITLE:format(rankName), body, npc
end
