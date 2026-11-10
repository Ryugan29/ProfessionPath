-- Profession Path — moteur de recommandations.
-- Ce fichier ne touche à aucune fonction du jeu : il reçoit des recettes et renvoie un parcours.
-- C'est ce qui permet de le tester en dehors de WoW (voir tests/planner_test.lua).
--
-- Format d'une recette :
--   { id, name, learned, difficulty, thresholds, reagents, skillUps }
--   difficulty : couleur lue en jeu au niveau actuel ("orange", "yellow", "green", "grey") ou nil
--   thresholds : { orange, jaune, vert, gris } (niveaux de compétence) ou nil si inconnus
--   reagents   : liste de { itemID, quantité }
--   skillUps   : points gagnés par fabrication réussie (1 par défaut)

local _, ns = ...

local Planner = {}
ns.Planner = Planner

-- En dessous de cette chance, une recette connue est jugée inefficace : on regarde
-- alors aussi les recettes à apprendre.
local LOW_CHANCE = 0.5
-- Poids qui fait passer « nouveau type de matériau » avant tout le reste en mode "fewmats".
local NEW_MATERIAL_PENALTY = 1000
-- Coût attribué à une recette dont on ne connaît pas le prix, pour la classer après les autres.
local UNKNOWN_PRICE_COST = 1e12
local TIE_EPSILON = 1e-9
-- Valeur du seuil orange quand le jeu ne donne pas le niveau requis pour apprendre la recette.
local UNKNOWN_LEARN_LEVEL = 0
-- En dessous de cette chance avec ce qu'on sait déjà fabriquer, une visite au maître vaut le
-- déplacement. Plus bas = moins de trajets mais plus de fabrications.
local VISIT_CHANCE = 0.75
local COLOR_RANK = { orange = 1, yellow = 2, green = 3 }

Planner.MODES = { "simple", "fewmats", "cheap" }

--- Vrai si les seuils sont bien quatre nombres croissants : { orange, jaune, vert, gris }.
-- Protège le calcul contre une ligne mal écrite dans Data/Thresholds.lua.
function Planner.IsValidThresholds(thresholds)
    if type(thresholds) ~= "table" then return false end
    for index = 1, 4 do
        if type(thresholds[index]) ~= "number" then return false end
        if index > 1 and thresholds[index] < thresholds[index - 1] then return false end
    end
    return true
end

--- Chance de gagner un point en fabriquant une recette à un niveau donné.
-- Règle des seuils de couleur : 100 % tant que la recette est orange, puis baisse
-- régulière du seuil jaune jusqu'au seuil gris (0 %). Renvoie nil si les seuils sont inconnus.
function Planner.Chance(skill, thresholds)
    if not Planner.IsValidThresholds(thresholds) then return nil end
    local yellow, grey = thresholds[2], thresholds[4]
    if skill >= grey then return 0 end
    if skill < yellow then return 1 end
    return (grey - skill) / (grey - yellow)
end

local function MaterialQuantity(recipe)
    local total = 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        total = total + reagent[2]
    end
    return total
end

local function GoldCost(recipe, priceOf)
    local total = 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        local price = priceOf and priceOf(reagent[1])
        if not price then return nil end
        total = total + price * reagent[2]
    end
    return total
end

local function NewMaterialKinds(recipe, usedMaterials)
    local count = 0
    for _, reagent in ipairs(recipe.reagents or {}) do
        if not usedMaterials[reagent[1]] then count = count + 1 end
    end
    return count
end

-- Plus le coût est bas, meilleure est la recette pour la priorité choisie.
local function CostPerPoint(recipe, chance, opts, usedMaterials)
    local perCraft = chance * math.max(1, recipe.skillUps or 1)
    -- Matériaux inconnus (lecture ratée en jeu) : la recette passe après toutes les autres.
    if recipe.reagents == nil then return 2 * UNKNOWN_PRICE_COST + 1 / perCraft end
    local quantity = MaterialQuantity(recipe)
    if opts.mode == "cheap" then
        local gold = GoldCost(recipe, opts.priceOf)
        if not gold then return UNKNOWN_PRICE_COST + quantity / perCraft end
        return gold / perCraft
    end
    if opts.mode == "fewmats" then
        return NewMaterialKinds(recipe, usedMaterials) * NEW_MATERIAL_PENALTY + quantity / perCraft
    end
    return 1 / perCraft + quantity * 0.0001
end

local function IsExcluded(recipe, opts)
    if opts.skipped and opts.skipped[recipe.id] then return true end
    -- Une recette grise en jeu le restera : la couleur vue en jeu l'emporte sur les données.
    return recipe.difficulty == "grey"
end

--- Niveau de métier requis pour apprendre une recette (0 = inconnu).
-- recipe.learnLevel vient d'un maître lu en jeu ; sinon on prend la valeur des données.
local function LearnLevel(recipe)
    if recipe.learnLevel then return recipe.learnLevel end
    return Planner.IsValidThresholds(recipe.thresholds) and recipe.thresholds[1] or UNKNOWN_LEARN_LEVEL
end

local function ChanceAt(recipe, skill, isCurrentSkill)
    local chance = Planner.Chance(skill, recipe.thresholds)
    if not chance then return nil end
    if isCurrentSkill and recipe.difficulty == "orange" then return 1 end
    return chance
end

local function BestChance(candidates)
    local best = 0
    for _, candidate in ipairs(candidates) do
        best = math.max(best, candidate.chance)
    end
    return best
end

-- Range les recettes utiles à ce niveau en trois groupes :
--   usable    : connues, ou apprises lors d'une visite au maître déjà prévue dans le parcours ;
--   reachable : chez le maître, apprenables à ce niveau, mais qui demandent une nouvelle visite ;
--   fallback  : apprises par un objet (plan, patron) : pas garanties d'être à portée du joueur.
-- Une recette dont on ignore le niveau d'apprentissage n'entre dans aucun groupe.
local function Classify(skill, opts, visits)
    local lastVisit = visits[#visits]
    local groups = { usable = {}, reachable = {}, fallback = {} }
    for _, recipe in ipairs(opts.recipes) do
        if not IsExcluded(recipe, opts) then
            local chance = ChanceAt(recipe, skill, skill == opts.skill)
            if chance and chance > 0 then
                local level = LearnLevel(recipe)
                local group
                if recipe.learned then
                    group = groups.usable
                elseif level ~= UNKNOWN_LEARN_LEVEL and level <= skill then
                    if recipe.learnSource ~= "trainer" then
                        -- Apprise par un objet, ou niveau donné par la table du jeu sans que
                        -- l'on sache comment l'apprendre : dernier recours seulement.
                        group = groups.fallback
                    elseif lastVisit and level <= lastVisit then
                        group = groups.usable
                    else
                        group = groups.reachable
                    end
                end
                if group then group[#group + 1] = { recipe = recipe, chance = chance } end
            end
        end
    end
    return groups
end

local function BestOf(candidates, opts, usedMaterials, currentRecipe)
    local best, bestCost, currentCost
    for _, candidate in ipairs(candidates) do
        local cost = CostPerPoint(candidate.recipe, candidate.chance, opts, usedMaterials)
        if candidate.recipe == currentRecipe then currentCost = cost end
        if not bestCost or cost < bestCost - TIE_EPSILON then
            best, bestCost = candidate, cost
        end
    end
    -- À égalité, on garde la recette en cours : inutile de changer pour rien.
    if currentCost and currentCost <= bestCost + TIE_EPSILON then
        for _, candidate in ipairs(candidates) do
            if candidate.recipe == currentRecipe then return candidate end
        end
    end
    return best
end

-- Choisit la meilleure recette parmi celles qui sont utilisables, avec les recettes apprises
-- par un objet en dernier recours.
local function Select(usable, fallback, opts, usedMaterials, currentRecipe)
    if BestChance(usable) >= LOW_CHANCE then
        -- Garde-fou commun à toutes les priorités : tant qu'une recette utilisable est efficace,
        -- on écarte celles qui sont presque grises, même si elles coûtent moins par fabrication.
        local efficient = {}
        for _, candidate in ipairs(usable) do
            if candidate.chance >= LOW_CHANCE then efficient[#efficient + 1] = candidate end
        end
        return BestOf(efficient, opts, usedMaterials, currentRecipe)
    end
    local all = {}
    for _, candidate in ipairs(usable) do all[#all + 1] = candidate end
    for _, candidate in ipairs(fallback) do all[#all + 1] = candidate end
    if #all == 0 then return nil end
    -- Plus rien d'efficace : on compare sur la chance, quelle que soit la priorité,
    -- pour ne pas rester bloqué sur une recette presque grise.
    return BestOf(all, { mode = "simple" }, usedMaterials, currentRecipe)
end

local function Pick(skill, opts, usedMaterials, currentRecipe, visits)
    local groups = Classify(skill, opts, visits)
    local visitHelps = BestChance(groups.usable) < VISIT_CHANCE
        and BestChance(groups.reachable) > BestChance(groups.usable)
    if not visitHelps then
        return Select(groups.usable, groups.fallback, opts, usedMaterials, currentRecipe)
    end
    -- Ce qu'on sait fabriquer ne garantit plus assez le point et le maître a mieux : on regarde
    -- ce que donnerait une visite, où tout ce qui est apprenable à ce niveau devient utilisable.
    local afterVisit, fromTrainer = {}, {}
    for _, candidate in ipairs(groups.usable) do afterVisit[#afterVisit + 1] = candidate end
    for _, candidate in ipairs(groups.reachable) do
        afterVisit[#afterVisit + 1] = candidate
        fromTrainer[candidate.recipe] = true
    end
    local pick = Select(afterVisit, groups.fallback, opts, usedMaterials, currentRecipe)
    if pick and fromTrainer[pick.recipe] then
        visits[#visits + 1] = skill
        return pick
    end
    -- La priorité choisie préfère quand même une recette déjà utilisable : la visite ne servirait
    -- à rien, on ne la prévoit pas.
    return Select(groups.usable, groups.fallback, opts, usedMaterials, currentRecipe)
end

-- Regroupe les recettes à apprendre chez le maître par visite : chaque recette est rattachée
-- à la première visite prévue où le joueur a le niveau pour l'apprendre.
local function BuildVisits(steps, visitLevels)
    local byLevel, list = {}, {}
    for _, step in ipairs(steps) do
        if step.needsLearning and step.recipe.learnSource == "trainer" then
            for _, level in ipairs(visitLevels) do
                if LearnLevel(step.recipe) <= level then
                    if not byLevel[level] then
                        byLevel[level] = { level = level, recipes = {} }
                        list[#list + 1] = byLevel[level]
                    end
                    local recipes = byLevel[level].recipes
                    recipes[#recipes + 1] = step.recipe
                    step.visitLevel = level
                    break
                end
            end
        end
    end
    table.sort(list, function(a, b) return a.level < b.level end)
    return list
end

-- Sans seuils chiffrés, on ne peut conseiller que d'après la couleur affichée par le jeu.
local function PickByColor(opts)
    local best, bestRank, bestQuantity
    for _, recipe in ipairs(opts.recipes) do
        local rank = COLOR_RANK[recipe.difficulty]
        if rank and recipe.learned and not IsExcluded(recipe, opts) then
            local quantity = MaterialQuantity(recipe)
            if not best or rank < bestRank or (rank == bestRank and quantity < bestQuantity) then
                best, bestRank, bestQuantity = recipe, rank, quantity
            end
        end
    end
    return best
end

local function HasAnyThresholds(recipes)
    for _, recipe in ipairs(recipes) do
        if Planner.IsValidThresholds(recipe.thresholds) then return true end
    end
    return false
end

-- Nombre de recettes non connues qui donneraient encore des points à ce niveau, mais dont on
-- ignore à partir de quel niveau elles s'apprennent.
local function CountUnlearnedHelpful(opts, skill)
    local count = 0
    for _, recipe in ipairs(opts.recipes) do
        if not recipe.learned and not IsExcluded(recipe, opts) then
            local chance = Planner.Chance(skill, recipe.thresholds)
            if chance and chance > 0 and LearnLevel(recipe) == UNKNOWN_LEARN_LEVEL then
                count = count + 1
            end
        end
    end
    return count
end

local function SumMaterials(steps)
    local totals = {}
    for _, step in ipairs(steps) do
        if step.crafts then
            for _, reagent in ipairs(step.recipe.reagents or {}) do
                totals[reagent[1]] = (totals[reagent[1]] or 0) + reagent[2] * step.crafts
            end
        end
    end
    local list = {}
    for itemID, qty in pairs(totals) do
        list[#list + 1] = { itemID = itemID, qty = qty }
    end
    table.sort(list, function(a, b)
        if a.qty ~= b.qty then return a.qty > b.qty end
        return a.itemID < b.itemID
    end)
    return list
end

local function HasMissingPrices(steps, priceOf)
    for _, step in ipairs(steps) do
        if GoldCost(step.recipe, priceOf) == nil then return true end
    end
    return false
end

local function FinishSteps(steps)
    for _, step in ipairs(steps) do
        if step.expected then
            -- Petite marge retirée avant d'arrondir : évite qu'une erreur de virgule ajoute un craft.
            step.crafts = math.ceil(step.expected - 1e-6)
            step.expected = nil
        end
    end
end

--- Calcule le parcours du niveau actuel jusqu'au niveau visé.
-- opts : { skill, target, mode, recipes, skipped = { [recipeID] = true }, priceOf = function(itemID) }
-- Une recette peut préciser learnLevel (niveau requis pour l'apprendre) et learnSource
-- ("trainer" = chez un maître, sinon apprise par un objet).
-- Renvoie { steps, visits, materials, reached, complete, stopReason, pricesMissing }.
--   visits : visites au maître à prévoir, { { level, recipes = { ... } } }, dans l'ordre.
--   stopReason : nil (objectif atteint), "gap" (plus aucune recette ne fait progresser),
--                "trainer" (il ne reste que des recettes peu efficaces : voir le maître),
--                "nodata" (seuils inconnus : impossible de calculer la suite).
function Planner.Plan(request)
    -- Chaque prix n'est demandé qu'une fois par calcul (false = « pas de prix »).
    local priceCache = {}
    local function CachedPrice(itemID)
        if priceCache[itemID] == nil then
            priceCache[itemID] = request.priceOf and request.priceOf(itemID) or false
        end
        return priceCache[itemID] or nil
    end
    -- Copie de la demande avec les prix mémorisés : la demande reçue n'est pas modifiée.
    local opts = {
        skill = request.skill, target = request.target, mode = request.mode,
        recipes = request.recipes, skipped = request.skipped, priceOf = CachedPrice,
    }
    local steps, usedMaterials, visitLevels = {}, {}, {}
    local skill, stopReason = opts.skill, nil
    local currentStep

    while skill < opts.target do
        local pick = Pick(skill, opts, usedMaterials, currentStep and currentStep.recipe, visitLevels)
        if not pick then
            stopReason = HasAnyThresholds(opts.recipes) and "gap" or "nodata"
            break
        end
        -- Il ne reste que des recettes peu efficaces, alors que des recettes non connues (dont on
        -- ignore le niveau d'apprentissage) feraient mieux : on s'arrête et on envoie le joueur
        -- chez son maître, plutôt que de lui faire fabriquer des centaines d'objets.
        if pick.chance < LOW_CHANCE and CountUnlearnedHelpful(opts, skill) > 0 then
            stopReason = "trainer"
            break
        end
        local recipe = pick.recipe
        if not currentStep or currentStep.recipe ~= recipe then
            currentStep = {
                recipe = recipe, from = skill, expected = 0, exact = true,
                chanceStart = pick.chance, needsLearning = not recipe.learned,
                -- Vrai si le prix de tous ses matériaux est connu (utile en priorité « cheap »).
                priced = GoldCost(recipe, opts.priceOf) ~= nil,
            }
            steps[#steps + 1] = currentStep
            for _, reagent in ipairs(recipe.reagents or {}) do
                usedMaterials[reagent[1]] = true
            end
        end
        currentStep.expected = currentStep.expected + 1 / pick.chance
        currentStep.exact = currentStep.exact and pick.chance >= 1
        currentStep.chanceEnd = pick.chance
        skill = math.min(opts.target, skill + math.max(1, recipe.skillUps or 1))
        currentStep.to = skill
    end

    if #steps == 0 and stopReason and stopReason ~= "trainer" then
        local recipe = PickByColor(opts)
        if recipe then
            steps[1] = { recipe = recipe, from = skill, byColor = true, exact = false, needsLearning = false }
            stopReason = "nodata"
        end
    end

    FinishSteps(steps)
    return {
        steps = steps,
        visits = BuildVisits(steps, visitLevels),
        materials = SumMaterials(steps),
        reached = skill,
        complete = skill >= opts.target,
        stopReason = stopReason,
        unlearnedHelpful = stopReason and CountUnlearnedHelpful(opts, skill) or 0,
        pricesMissing = opts.mode == "cheap" and HasMissingPrices(steps, opts.priceOf) or false,
    }
end

-- Matériaux d'une seule étape : { { itemID, perCraft, total } }.
-- « total » couvre toutes les fabrications de l'étape ; il vaut nil quand leur nombre est inconnu
-- (on n'invente pas de total). Liste vide si les composants de la recette n'ont pas pu être lus.
function Planner.StepMaterials(step)
    local list = {}
    local recipe = type(step) == "table" and step.recipe or nil
    local crafts = type(step) == "table" and type(step.crafts) == "number" and step.crafts or nil
    for _, reagent in ipairs(type(recipe) == "table" and recipe.reagents or {}) do
        local itemID, perCraft = reagent[1], reagent[2]
        if type(itemID) == "number" and type(perCraft) == "number" and perCraft > 0 then
            list[#list + 1] = {
                itemID = itemID,
                perCraft = perCraft,
                total = crafts and math.ceil(perCraft * crafts) or nil,
            }
        end
    end
    return list
end

-- Prix des objets que le joueur sait fabriquer -----------------------------------------

-- Nombre maximal de fabrications emboîtées (un objet fait d'un objet fait d'un objet...).
local MAX_CRAFT_DEPTH = 4

-- Fabrique une fonction « prix d'un objet » qui retient le plus bas entre :
--   * le prix de base (marchand, hôtel des ventes), donné par basePriceOf(itemID) ;
--   * le coût de fabrication par le joueur : somme des prix de ses matériaux, divisée par le
--     nombre d'objets obtenus.
-- sources : { [objet] = { { reagents = { { itemID, quantité }, ... }, yield = objets obtenus }, ... } }
--   (uniquement les recettes que le joueur connaît).
-- Rien n'est inventé : si un seul matériau n'a pas de prix, la recette ne donne pas de prix.
-- Les résultats sont retenus le temps de vie de la fonction : en créer une par calcul.
function Planner.NewPricer(basePriceOf, sources)
    local memo, visiting = {}, {}
    local chosen = {} -- [objet] = recette retenue, quand le fabriquer est le moyen le moins cher
    -- Compte les fois où l'on a dû renoncer à explorer (recettes qui se renvoient l'une à l'autre,
    -- ou trop de niveaux) : un résultat obtenu dans ces conditions n'est pas retenu, car il peut
    -- être moins bon que celui qu'on obtiendrait en partant d'ailleurs.
    local shortcuts = 0
    local priceOf

    local function CraftCost(source, depth)
        if type(source) ~= "table" or type(source.reagents) ~= "table" or #source.reagents == 0 then return nil end
        if type(source.yield) ~= "number" or source.yield < 1 then return nil end
        local total = 0
        for _, reagent in ipairs(source.reagents) do
            local quantity = reagent[2]
            local price = type(quantity) == "number" and quantity > 0 and priceOf(reagent[1], depth + 1) or nil
            if not price then return nil end
            total = total + price * quantity
        end
        return total / source.yield
    end

    priceOf = function(itemID, depth)
        local known = memo[itemID]
        if known ~= nil then return known or nil end
        if visiting[itemID] or depth > MAX_CRAFT_DEPTH then
            shortcuts = shortcuts + 1
            return nil
        end
        visiting[itemID] = true
        local shortcutsBefore = shortcuts
        local best = basePriceOf(itemID)
        if type(best) ~= "number" or best <= 0 then best = nil end
        local bestSource
        for _, source in ipairs(sources[itemID] or {}) do
            local cost = CraftCost(source, depth)
            if cost and (not best or cost < best) then best, bestSource = cost, source end
        end
        visiting[itemID] = nil
        if depth == 0 or shortcuts == shortcutsBefore then
            memo[itemID] = best or false
            chosen[itemID] = bestSource
        end
        return best
    end

    -- Seconde fonction rendue : la recette à utiliser pour cet objet, ou nil s'il vaut mieux
    -- l'acheter (ou si son coût de fabrication est inconnu).
    local function sourceOf(itemID)
        priceOf(itemID, 0)
        return chosen[itemID]
    end

    return function(itemID) return priceOf(itemID, 0) end, sourceOf
end

local function SortedMaterials(totals)
    local list = {}
    for itemID, qty in pairs(totals) do
        list[#list + 1] = { itemID = itemID, qty = qty }
    end
    table.sort(list, function(a, b)
        if a.qty ~= b.qty then return a.qty > b.qty end
        return a.itemID < b.itemID
    end)
    return list
end

local function IsUsableSource(source)
    return type(source) == "table" and type(source.reagents) == "table" and #source.reagents > 0
        and type(source.yield) == "number" and source.yield >= 1
end

-- Détaille une liste de matériaux : les objets que le joueur a intérêt à fabriquer lui-même
-- (d'après sourceOf, voir NewPricer) sont remplacés par leurs propres matériaux.
-- Renvoie { materials = ce qu'il faut réellement réunir, prepare = objets à fabriquer d'abord,
-- chacun { itemID, qty = objets nécessaires, crafts = nombre de fabrications, reagents et yield =
-- matériaux et objets obtenus pour UNE fabrication } }.
-- Ne modifie pas la liste reçue. Sans sourceOf, la liste est rendue telle quelle.
function Planner.ExpandMaterials(materials, sourceOf)
    local pending, raw, prepare = {}, {}, {}
    for _, material in ipairs(materials or {}) do
        pending[material.itemID] = (pending[material.itemID] or 0) + material.qty
    end
    for _ = 1, MAX_CRAFT_DEPTH + 1 do
        local nextPending, expanded = {}, false
        for itemID, qty in pairs(pending) do
            local source = type(sourceOf) == "function" and sourceOf(itemID) or nil
            if IsUsableSource(source) then
                local crafts = math.ceil(qty / source.yield)
                -- La recette retenue accompagne l'objet, pour pouvoir dire avec quoi il se fabrique.
                local entry = prepare[itemID]
                    or { itemID = itemID, qty = 0, crafts = 0, reagents = source.reagents, yield = source.yield }
                entry.qty, entry.crafts = entry.qty + qty, entry.crafts + crafts
                prepare[itemID] = entry
                for _, reagent in ipairs(source.reagents) do
                    nextPending[reagent[1]] = (nextPending[reagent[1]] or 0) + reagent[2] * crafts
                end
                expanded = true
            else
                raw[itemID] = (raw[itemID] or 0) + qty
            end
        end
        pending = nextPending
        if not expanded then break end
    end
    -- Trop de niveaux emboîtés : ce qui reste est à réunir tel quel.
    for itemID, qty in pairs(pending) do
        raw[itemID] = (raw[itemID] or 0) + qty
    end
    local toPrepare = {}
    for _, entry in pairs(prepare) do toPrepare[#toPrepare + 1] = entry end
    table.sort(toPrepare, function(a, b)
        if a.qty ~= b.qty then return a.qty > b.qty end
        return a.itemID < b.itemID
    end)
    return { materials = SortedMaterials(raw), prepare = toPrepare }
end

-- Coût estimé d'une liste de matériaux : { total (en cuivre), unpricedItems (nombre de matériaux
-- différents sans prix), unpricedQty (nombre d'objets sans prix) }. nil sans source de prix.
function Planner.PlanCost(materials, priceOf)
    if type(priceOf) ~= "function" then return nil end
    local cost = { total = 0, unpricedItems = 0, unpricedQty = 0 }
    for _, material in ipairs(materials or {}) do
        local price = priceOf(material.itemID)
        if price then
            cost.total = cost.total + price * material.qty
        else
            cost.unpricedItems = cost.unpricedItems + 1
            cost.unpricedQty = cost.unpricedQty + material.qty
        end
    end
    return cost
end
