-- Profession Path — lecture des maîtres de métier.
-- Les fichiers du jeu ne disent pas à quel niveau un maître enseigne une recette. Cette
-- information n'existe que dans la fenêtre du maître : on la lit quand le joueur lui parle,
-- et on la garde. Une seule visite par maître suffit. L'add-on n'achète rien : il lit.

local _, ns = ...
local L = ns.L

local READ_DELAY = 0.3
local NO_REQUIREMENT_LEVEL = 1

local hintShown = false
local readPending = false
local announcePending = false

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
    return nil
end

local function CountEntries(list)
    local count = 0
    for _ in pairs(list) do count = count + 1 end
    return count
end

-- Lit les recettes affichées par le maître. Renvoie le nom du métier et le nombre de
-- recettes nouvelles ou modifiées, ou nil si ce n'est pas un maître de métier.
local function ReadTrainer()
    -- Premier passage : ce que le maître affiche, et de quel métier il s'agit.
    local services, profession = {}, nil
    for index = 1, Call(GetNumTrainerServices) or 0 do
        local name, _, serviceType = Call(GetTrainerServiceInfo, index)
        if type(name) == "string" and serviceType ~= "header" then
            local skillName, skillLevel = Call(GetTrainerServiceSkillReq, index)
            if type(skillName) == "string" and skillName ~= "" then profession = skillName end
            services[#services + 1] = {
                name = name,
                -- Aucun niveau demandé par le maître : la recette s'apprend dès le niveau 1.
                level = type(skillLevel) == "number" and skillLevel or NO_REQUIREMENT_LEVEL,
                cost = Call(GetTrainerServiceCost, index),
            }
        end
    end
    -- Aucune ligne ne cite un métier : ce n'est pas un maître de métier (maître de classe...).
    if not profession then return nil, 0 end

    ns.db.trainer[profession] = ns.db.trainer[profession] or {}
    local known, changed = ns.db.trainer[profession], 0
    for _, service in ipairs(services) do
        local previous = known[service.name]
        local cost = service.cost
        if type(cost) ~= "number" then cost = previous and previous.cost or nil end
        if not previous or previous.level ~= service.level or previous.cost ~= cost then
            known[service.name] = { level = service.level, cost = cost }
            changed = changed + 1
        end
    end
    return profession, changed
end

-- Le maître ne liste que ce que ses filtres affichent : sans « Indisponible », on ne verrait
-- pas les recettes des niveaux à venir. On le signale, sans toucher au réglage du joueur.
local function WarnAboutFilter()
    if hintShown then return end
    if Call(GetTrainerServiceTypeFilter, "unavailable") == false then
        hintShown = true
        ns.Print(L.TRAINER_FILTER)
    end
end

local function ReadAndReport()
    local announce = announcePending
    readPending, announcePending = false, false
    if not ns.db then return end
    local profession, changed = ReadTrainer()
    if not profession then return end
    WarnAboutFilter()
    if announce or changed > 0 then
        ns.Print(L.TRAINER_READ:format(profession, CountEntries(ns.db.trainer[profession]), changed))
    end
    if changed > 0 then ns.RefreshUI() end
end

local function Schedule(announce)
    -- L'ouverture du maître demande une annonce, même si une mise à jour est arrivée avant elle.
    announcePending = announcePending or announce
    if readPending then return end
    readPending = true
    C_Timer.After(READ_DELAY, ReadAndReport)
end

local eventFrame = CreateFrame("Frame")
-- Un évènement absent de ce client ne doit pas empêcher l'add-on de se charger.
pcall(eventFrame.RegisterEvent, eventFrame, "TRAINER_SHOW")
pcall(eventFrame.RegisterEvent, eventFrame, "TRAINER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "TRAINER_SHOW" or event == "TRAINER_UPDATE" then
        Schedule(event == "TRAINER_SHOW")
    end
end)
