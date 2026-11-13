-- Tests du moteur de recommandations (Planner.lua).
-- Lancement : node tests/run.js   (voir README, section « Tests »)
-- Les recettes ci-dessous sont FICTIVES : elles ne servent qu'à vérifier les calculs.

local ns = ...
local P = ns.Planner

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        print("ECHEC  " .. name .. "\n       " .. tostring(err))
    end
end
local function eq(actual, expected, label)
    if actual ~= expected then
        error((label or "valeur") .. " : attendu " .. tostring(expected) .. ", obtenu " .. tostring(actual), 2)
    end
end
local function near(actual, expected, label)
    if math.abs(actual - expected) > 1e-6 then
        error((label or "valeur") .. " : attendu " .. tostring(expected) .. ", obtenu " .. tostring(actual), 2)
    end
end

local function recipe(id, thresholds, reagents, extra)
    local r = { id = id, name = "R" .. id, learned = true, thresholds = thresholds, reagents = reagents or {} }
    for k, v in pairs(extra or {}) do r[k] = v end
    return r
end

-- Chance ---------------------------------------------------------------

test("chance vaut 1 tant que la recette est orange", function()
    near(P.Chance(10, { 1, 30, 45, 60 }), 1)
    near(P.Chance(29, { 1, 30, 45, 60 }), 1)
end)

test("chance baisse de facon reguliere entre jaune et gris", function()
    near(P.Chance(30, { 1, 30, 45, 60 }), 1)
    near(P.Chance(45, { 1, 30, 45, 60 }), 0.5)
    near(P.Chance(60, { 1, 30, 45, 60 }), 0)
    near(P.Chance(80, { 1, 30, 45, 60 }), 0)
end)

test("chance inconnue sans seuils", function()
    eq(P.Chance(10, nil), nil)
end)

test("chance nulle quand jaune et gris sont identiques et atteints", function()
    near(P.Chance(50, { 1, 50, 50, 50 }), 0)
end)

test("des seuils mal ecrits sont refuses", function()
    eq(P.IsValidThresholds({ 1, 30, 45, 60 }), true)
    eq(P.IsValidThresholds({ 1, 30, 45 }), false, "trois nombres")
    eq(P.IsValidThresholds({ 1, "30", 45, 60 }), false, "du texte")
    eq(P.IsValidThresholds({ 1, 60, 45, 30 }), false, "ordre inverse")
    eq(P.IsValidThresholds(nil), false, "rien")
    eq(P.IsValidThresholds("x"), false, "pas une liste")
end)

test("des seuils mal ecrits sont ignores par le parcours au lieu de le faire planter", function()
    local plan = P.Plan({
        skill = 1, target = 5, mode = "simple",
        recipes = { recipe(1, { 1, 30 }, { { 100, 1 } }), recipe(2, { 1, 50, 60, 70 }, { { 101, 1 } }) },
    })
    eq(#plan.steps, 1)
    eq(plan.steps[1].recipe.id, 2)
end)

-- Parcours -------------------------------------------------------------

test("une seule recette orange : un craft par point", function()
    local plan = P.Plan({
        skill = 1, target = 11, mode = "simple",
        recipes = { recipe(1, { 1, 50, 60, 70 }, { { 100, 2 } }) },
    })
    eq(#plan.steps, 1, "nombre d'etapes")
    eq(plan.steps[1].recipe.id, 1)
    eq(plan.steps[1].from, 1)
    eq(plan.steps[1].to, 11)
    eq(plan.steps[1].crafts, 10)
    eq(plan.steps[1].exact, true)
    eq(plan.complete, true)
    eq(plan.materials[1].itemID, 100)
    eq(plan.materials[1].qty, 20)
end)

test("passe a la recette suivante quand elle devient disponible et plus sure", function()
    local plan = P.Plan({
        skill = 1, target = 40, mode = "simple",
        recipes = {
            recipe(1, { 1, 20, 30, 40 }, { { 100, 1 } }),
            recipe(2, { 20, 45, 55, 65 }, { { 101, 1 } }),
        },
    })
    eq(#plan.steps, 2, "nombre d'etapes")
    eq(plan.steps[1].recipe.id, 1)
    eq(plan.steps[1].to, 21)
    eq(plan.steps[2].recipe.id, 2)
    eq(plan.steps[2].from, 21)
    eq(plan.steps[2].to, 40)
    eq(plan.complete, true)
end)

test("quantite arrondie au-dessus et marquee estimee quand la chance baisse", function()
    local plan = P.Plan({
        skill = 30, target = 32, mode = "simple",
        recipes = { recipe(1, { 1, 30, 45, 60 }, { { 100, 1 } }) },
    })
    -- point 30 : chance 1 -> 1 craft ; point 31 : chance 29/30 -> 1,034 craft
    eq(plan.steps[1].crafts, 3)
    eq(plan.steps[1].exact, false)
end)

test("s'arrete et signale un trou quand plus rien ne fait progresser", function()
    local plan = P.Plan({
        skill = 1, target = 100, mode = "simple",
        recipes = { recipe(1, { 1, 20, 30, 40 }, { { 100, 1 } }) },
    })
    eq(plan.complete, false)
    eq(plan.stopReason, "gap")
    eq(plan.reached, 40)
end)

test("une recette non connue n'est proposee que s'il n'y a rien d'autre, et elle est signalee", function()
    local plan = P.Plan({
        skill = 1, target = 30, mode = "simple",
        recipes = {
            recipe(1, { 1, 10, 15, 20 }, { { 100, 1 } }),
            recipe(2, { 1, 40, 50, 60 }, { { 101, 1 } }, { learned = false }),
        },
    })
    eq(plan.steps[1].recipe.id, 1, "la recette connue d'abord")
    local last = plan.steps[#plan.steps]
    eq(last.recipe.id, 2)
    eq(last.needsLearning, true)
    eq(plan.complete, true)
end)

test("une recette non connue trop haute pour etre apprise est ignoree", function()
    local plan = P.Plan({
        skill = 1, target = 30, mode = "simple",
        recipes = { recipe(2, { 25, 40, 50, 60 }, {}, { learned = false }) },
    })
    eq(#plan.steps, 0)
    eq(plan.stopReason, "gap")
end)

test("une recette non connue au niveau d'apprentissage inconnu (0) n'est pas mise dans le parcours", function()
    local plan = P.Plan({
        skill = 10, target = 30, mode = "simple",
        recipes = { recipe(2, { 0, 250, 270, 290 }, {}, { learned = false }) },
    })
    eq(#plan.steps, 0)
    eq(plan.stopReason, "gap")
    eq(plan.unlearnedHelpful, 1, "mais elle est comptee comme piste")
end)

test("une recette connue fonctionne meme si son niveau d'apprentissage est inconnu (0)", function()
    local plan = P.Plan({
        skill = 10, target = 15, mode = "simple",
        recipes = { recipe(1, { 0, 40, 55, 70 }, { { 100, 1 } }) },
    })
    eq(plan.steps[1].crafts, 5)
    eq(plan.complete, true)
    eq(plan.unlearnedHelpful, 0)
end)

-- Visites au maitre ----------------------------------------------------

local function trainerRecipe(id, learnLevel, thresholds, reagents)
    return recipe(id, thresholds, reagents, { learned = false, learnLevel = learnLevel, learnSource = "trainer" })
end

test("une recette du maitre entre dans le parcours quand ce qu'on connait ne garantit plus assez le point", function()
    local plan = P.Plan({
        skill = 96, target = 150, mode = "simple",
        recipes = {
            recipe(1, { 0, 80, 115, 150 }, { { 100, 1 } }),
            trainerRecipe(2, 90, { 0, 90, 125, 160 }, { { 101, 1 } }),
            trainerRecipe(3, 115, { 0, 115, 150, 185 }, { { 102, 1 } }),
        },
    })
    eq(plan.complete, true)
    eq(plan.steps[1].recipe.id, 1, "d'abord la recette connue, encore efficace")
    eq(plan.steps[2].recipe.id, 2)
    eq(plan.steps[2].needsLearning, true)
    eq(plan.steps[3].recipe.id, 3)
    eq(#plan.visits, 2, "deux visites au maitre")
    eq(plan.visits[1].level, plan.steps[2].from)
    eq(plan.visits[1].recipes[1].id, 2)
    eq(plan.visits[2].recipes[1].id, 3)
    local crafts = 0
    for _, step in ipairs(plan.steps) do crafts = crafts + step.crafts end
    local alone = P.Plan({
        skill = 96, target = 150, mode = "simple",
        recipes = { recipe(1, { 0, 80, 115, 150 }, { { 100, 1 } }) },
    })
    eq(crafts * 3 < alone.steps[1].crafts, true,
        "au moins trois fois moins de fabrications qu'avec la seule recette connue (" .. crafts .. " contre " .. alone.steps[1].crafts .. ")")
end)

test("une visite regroupe toutes les recettes apprenables a ce niveau", function()
    local plan = P.Plan({
        skill = 50, target = 90, mode = "simple",
        recipes = {
            recipe(1, { 0, 20, 40, 60 }, { { 100, 1 } }),
            trainerRecipe(2, 30, { 0, 60, 70, 80 }, { { 101, 1 } }),
            trainerRecipe(3, 45, { 0, 80, 100, 120 }, { { 102, 1 } }),
        },
    })
    eq(#plan.visits, 1, "une seule visite, tout de suite")
    eq(plan.visits[1].level, 50)
    eq(#plan.visits[1].recipes, 2)
    eq(plan.complete, true)
end)

test("une recette du maitre n'est pas proposee avant le niveau requis", function()
    local plan = P.Plan({
        skill = 10, target = 60, mode = "simple",
        recipes = { trainerRecipe(2, 40, { 0, 60, 70, 80 }, {}) },
    })
    eq(#plan.steps, 0)
    eq(plan.stopReason, "gap")
end)

test("s'arrete au lieu de faire fabriquer en masse quand une recette inconnue ferait mieux", function()
    local plan = P.Plan({
        skill = 96, target = 150, mode = "simple",
        recipes = {
            recipe(1, { 0, 80, 115, 150 }, { { 100, 1 } }),
            recipe(2, { 0, 115, 150, 185 }, { { 101, 1 } }, { learned = false }),
        },
    })
    eq(plan.stopReason, "trainer")
    eq(plan.reached, 116, "s'arrete quand la recette connue passe sous 50 %")
    eq(plan.complete, false)
    eq(plan.unlearnedHelpful, 1)
    eq(plan.steps[1].crafts < 40, true, "quantite raisonnable (" .. plan.steps[1].crafts .. ")")
end)

test("continue avec une recette faible quand il n'existe vraiment rien d'autre", function()
    local plan = P.Plan({
        skill = 96, target = 150, mode = "simple",
        recipes = { recipe(1, { 0, 80, 115, 150 }, { { 100, 1 } }) },
    })
    eq(plan.complete, true)
    eq(plan.stopReason, nil)
end)

test("pas de visite fantome quand la priorite prefere quand meme la recette connue", function()
    -- La recette connue donne 2 points par fabrication : meme a 60 %, elle reste la meilleure.
    local plan = P.Plan({
        skill = 62, target = 64, mode = "simple",
        recipes = {
            recipe(1, { 0, 50, 65, 80 }, { { 100, 1 } }, { skillUps = 2 }),
            trainerRecipe(2, 1, { 0, 60, 70, 80 }, { { 101, 1 } }),
        },
    })
    eq(plan.steps[1].recipe.id, 1)
    eq(#plan.visits, 0, "aucune visite ne doit etre prevue")
end)

test("les visites sont listees dans l'ordre des niveaux", function()
    local plan = P.Plan({
        skill = 96, target = 150, mode = "simple",
        recipes = {
            recipe(1, { 0, 80, 115, 150 }, { { 100, 1 } }),
            trainerRecipe(2, 90, { 0, 90, 125, 160 }, { { 101, 1 } }),
            trainerRecipe(3, 115, { 0, 115, 150, 185 }, { { 102, 1 } }),
        },
    })
    for index = 2, #plan.visits do
        eq(plan.visits[index - 1].level < plan.visits[index].level, true, "ordre des visites")
    end
end)

test("pas de visite tant que les recettes connues garantissent le point", function()
    local plan = P.Plan({
        skill = 1, target = 20, mode = "simple",
        recipes = {
            recipe(1, { 0, 50, 60, 70 }, { { 100, 1 } }),
            trainerRecipe(2, 1, { 0, 60, 70, 80 }, { { 101, 1 } }),
        },
    })
    eq(#plan.visits, 0)
    eq(plan.steps[1].recipe.id, 1)
end)

test("une recette marquee terminee est ecartee du parcours", function()
    local plan = P.Plan({
        skill = 1, target = 10, mode = "simple",
        skipped = { [1] = true },
        recipes = {
            recipe(1, { 1, 50, 60, 70 }, { { 100, 1 } }),
            recipe(2, { 1, 50, 60, 70 }, { { 101, 5 } }),
        },
    })
    eq(#plan.steps, 1)
    eq(plan.steps[1].recipe.id, 2)
end)

test("deja au niveau vise : rien a faire", function()
    local plan = P.Plan({ skill = 50, target = 50, mode = "simple", recipes = {} })
    eq(#plan.steps, 0)
    eq(plan.complete, true)
end)

test("les materiaux de plusieurs etapes sont additionnes", function()
    local plan = P.Plan({
        skill = 1, target = 30, mode = "simple",
        recipes = {
            recipe(1, { 1, 20, 30, 40 }, { { 100, 2 } }),
            recipe(2, { 20, 45, 55, 65 }, { { 100, 1 }, { 101, 3 } }),
        },
    })
    local byItem = {}
    for _, m in ipairs(plan.materials) do byItem[m.itemID] = m.qty end
    eq(byItem[100], 20 * 2 + 9 * 1)
    eq(byItem[101], 27)
end)

test("une recette qui donne plusieurs points demande moins de crafts", function()
    local plan = P.Plan({
        skill = 1, target = 11, mode = "simple",
        recipes = { recipe(1, { 1, 50, 60, 70 }, { { 100, 1 } }, { skillUps = 5 }) },
    })
    eq(plan.steps[1].crafts, 2)
    eq(plan.steps[1].to, 11)
end)

-- Couleur lue en jeu ---------------------------------------------------

test("sans seuils : conseille d'apres la couleur vue en jeu, sans quantite", function()
    local plan = P.Plan({
        skill = 12, target = 50, mode = "simple",
        recipes = {
            recipe(1, nil, { { 100, 1 } }, { difficulty = "green" }),
            recipe(2, nil, { { 101, 1 } }, { difficulty = "orange" }),
            recipe(3, nil, { { 102, 1 } }, { difficulty = "grey" }),
        },
    })
    eq(#plan.steps, 1)
    eq(plan.steps[1].recipe.id, 2)
    eq(plan.steps[1].crafts, nil)
    eq(plan.steps[1].byColor, true)
    eq(plan.stopReason, "nodata")
    eq(plan.complete, false)
end)

test("la couleur vue en jeu l'emporte : une recette grise en jeu n'est pas proposee", function()
    local plan = P.Plan({
        skill = 10, target = 12, mode = "simple",
        recipes = {
            recipe(1, { 1, 50, 60, 70 }, { { 100, 1 } }, { difficulty = "grey" }),
            recipe(2, { 1, 12, 20, 30 }, { { 101, 9 } }, { difficulty = "orange" }),
        },
    })
    eq(plan.steps[1].recipe.id, 2)
end)

-- Priorites ------------------------------------------------------------

test("moins de materiaux differents : reste sur les composants deja utilises", function()
    local recipes = {
        recipe(1, { 1, 20, 30, 40 }, { { 100, 1 } }),
        recipe(2, { 20, 45, 55, 65 }, { { 101, 1 }, { 102, 1 } }),
    }
    local simple = P.Plan({ skill = 1, target = 30, mode = "simple", recipes = recipes })
    local few = P.Plan({ skill = 1, target = 30, mode = "fewmats", recipes = recipes })
    eq(#simple.materials, 3, "simple utilise les trois composants")
    eq(#few.materials, 1, "fewmats n'en utilise qu'un")
    eq(few.complete, true)
end)

test("moins couteux : choisit la recette la moins chere par point", function()
    local prices = { [100] = 500, [101] = 10 }
    local plan = P.Plan({
        skill = 1, target = 10, mode = "cheap",
        priceOf = function(itemID) return prices[itemID] end,
        recipes = {
            recipe(1, { 1, 50, 60, 70 }, { { 100, 1 } }),
            recipe(2, { 1, 50, 60, 70 }, { { 101, 3 } }),
        },
    })
    eq(plan.steps[1].recipe.id, 2)
    eq(plan.pricesMissing, false)
end)

test("moins couteux : ne s'accroche pas a une recette presque grise quand une autre est efficace", function()
    local prices = { [100] = 10 }
    local plan = P.Plan({
        skill = 1, target = 40, mode = "cheap",
        priceOf = function(itemID) return prices[itemID] end,
        recipes = {
            recipe(1, { 1, 20, 30, 40 }, { { 100, 1 } }),
            recipe(2, { 1, 60, 70, 80 }, { { 101, 1 } }),
        },
    })
    eq(plan.steps[1].recipe.id, 1, "la moins chere tant qu'elle reste efficace")
    eq(plan.steps[1].to, 31, "abandonnee quand sa chance passe sous 50 %")
    eq(plan.steps[1].priced, true)
    eq(plan.steps[2].recipe.id, 2, "puis la recette efficace, meme sans prix connu")
    eq(plan.steps[2].priced, false)
    eq(plan.complete, true)
end)

test("moins de materiaux differents : meme garde-fou contre une recette presque grise", function()
    local plan = P.Plan({
        skill = 1, target = 40, mode = "fewmats",
        recipes = {
            recipe(1, { 1, 20, 30, 40 }, { { 100, 1 } }),
            recipe(2, { 1, 60, 70, 80 }, { { 101, 1 }, { 102, 1 } }),
        },
    })
    eq(plan.steps[1].to, 31)
    eq(plan.steps[2].recipe.id, 2)
end)

test("moins couteux : signale les prix manquants au lieu de les inventer", function()
    local plan = P.Plan({
        skill = 1, target = 10, mode = "cheap",
        priceOf = function() return nil end,
        recipes = { recipe(1, { 1, 50, 60, 70 }, { { 100, 1 } }) },
    })
    eq(plan.steps[1].recipe.id, 1)
    eq(plan.pricesMissing, true)
end)

test("une recette aux materiaux inconnus ne passe pas pour gratuite", function()
    for _, mode in ipairs({ "simple", "fewmats", "cheap" }) do
        local unknown = recipe(1, { 1, 50, 60, 70 })
        unknown.reagents = nil
        local plan = P.Plan({
            skill = 1, target = 5, mode = mode,
            priceOf = function() return 10 end,
            recipes = { unknown, recipe(2, { 1, 50, 60, 70 }, { { 101, 4 } }) },
        })
        eq(plan.steps[1].recipe.id, 2, mode)
    end
end)

test("chaque prix n'est demande qu'une fois par calcul", function()
    local calls = 0
    P.Plan({
        skill = 1, target = 50, mode = "cheap",
        priceOf = function() calls = calls + 1 return 10 end,
        recipes = { recipe(1, { 1, 60, 70, 80 }, { { 100, 1 } }), recipe(2, { 1, 60, 70, 80 }, { { 101, 2 } }) },
    })
    eq(calls, 2)
end)

test("ne modifie pas les donnees recues", function()
    local r = recipe(1, { 1, 50, 60, 70 }, { { 100, 1 } })
    local skipped = {}
    P.Plan({ skill = 1, target = 10, mode = "simple", recipes = { r }, skipped = skipped })
    eq(next(skipped), nil)
    eq(r.reagents[1][2], 1)
    eq(#r.thresholds, 4)
end)

test("materiaux d'une etape : quantite par fabrication et total pour l'etape", function()
    local step = { crafts = 7, exact = true, recipe = { reagents = { { 100, 2 }, { 101, 1 } } } }
    local list = P.StepMaterials(step)
    eq(#list, 2)
    eq(list[1].itemID, 100)
    eq(list[1].perCraft, 2)
    eq(list[1].total, 14)
    eq(list[2].itemID, 101)
    eq(list[2].total, 7)
    eq(step.recipe.reagents[1][2], 2, "les donnees recues ne doivent pas changer")
end)

test("materiaux d'une etape : sans nombre de fabrications, pas de total invente", function()
    local list = P.StepMaterials({ recipe = { reagents = { { 100, 3 } } } })
    eq(#list, 1)
    eq(list[1].perCraft, 3)
    eq(list[1].total, nil)
end)

test("materiaux d'une etape : composants non lus ou etape absente, liste vide", function()
    eq(#P.StepMaterials({ crafts = 5, recipe = {} }), 0)
    eq(#P.StepMaterials({ crafts = 5 }), 0)
    eq(#P.StepMaterials(nil), 0)
    eq(#P.StepMaterials({ crafts = 5, recipe = { reagents = { { "abc", 1 }, { 100 }, { 101, 0 } } } }), 0, "lignes abimees ignorees")
end)

-- Prix des objets que le joueur sait fabriquer ---------------------------------------

local function prices(list)
    local asked = {}
    return function(itemID)
        asked[itemID] = (asked[itemID] or 0) + 1
        return list[itemID]
    end, asked
end

test("prix : sans recette de fabrication, le prix connu est rendu tel quel", function()
    local priceOf = P.NewPricer(prices({ [100] = 40 }), {})
    eq(priceOf(100), 40)
    eq(priceOf(101), nil, "aucun prix ne doit etre invente")
end)

test("prix : un objet fabricable vaut le cout de ses materiaux s'il est moins cher", function()
    local sources = { [200] = { { reagents = { { 100, 1 }, { 101, 2 } }, yield = 1 } } }
    eq(P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)(200), 50, "sans prix de vente")
    eq(P.NewPricer(prices({ [100] = 40, [101] = 5, [200] = 300 }), sources)(200), 50, "fabriquer est moins cher")
    eq(P.NewPricer(prices({ [100] = 40, [101] = 5, [200] = 30 }), sources)(200), 30, "acheter est moins cher")
end)

test("prix : un materiau sans prix interdit le prix de fabrication", function()
    local sources = { [200] = { { reagents = { { 100, 1 }, { 999, 1 } }, yield = 1 } } }
    eq(P.NewPricer(prices({ [100] = 40 }), sources)(200), nil, "rien d'invente")
    eq(P.NewPricer(prices({ [100] = 40, [200] = 70 }), sources)(200), 70, "le prix de vente reste utilisable")
end)

test("prix : une fabrication qui donne plusieurs objets est divisee d'autant", function()
    local sources = { [200] = { { reagents = { { 100, 1 } }, yield = 5 } } }
    eq(P.NewPricer(prices({ [100] = 40 }), sources)(200), 8)
end)

test("prix : la recette la moins chere est retenue, et les recettes abimees sont ignorees", function()
    local sources = { [200] = {
        { reagents = { { 100, 3 } }, yield = 1 },
        { reagents = { { 101, 2 } }, yield = 1 },
        { reagents = {}, yield = 1 },
        { reagents = { { 101, 1 } }, yield = 0 },
        { yield = 1 },
    } }
    eq(P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)(200), 10)
end)

test("prix : un objet fabrique a partir d'un autre objet fabrique", function()
    local sources = {
        [200] = { { reagents = { { 100, 2 } }, yield = 1 } },
        [300] = { { reagents = { { 200, 1 }, { 101, 1 } }, yield = 1 } },
    }
    eq(P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)(300), 85)
end)

test("prix : deux recettes qui se renvoient l'une a l'autre ne bouclent pas", function()
    local sources = {
        [200] = { { reagents = { { 300, 1 } }, yield = 1 } },
        [300] = { { reagents = { { 200, 1 } }, yield = 1 } },
    }
    eq(P.NewPricer(prices({}), sources)(200), nil, "aucun prix de depart")
    eq(P.NewPricer(prices({ [300] = 12 }), sources)(200), 12, "200 se fabrique avec 300, qui a un prix")
    eq(P.NewPricer(prices({ [300] = 12 }), sources)(300), 12, "300 garde son prix")
end)

test("prix : chaque prix de base n'est demande qu'une fois", function()
    local base, asked = prices({ [100] = 40, [101] = 5 })
    local sources = { [200] = { { reagents = { { 100, 1 }, { 101, 1 } }, yield = 1 } } }
    local priceOf = P.NewPricer(base, sources)
    priceOf(200) priceOf(200) priceOf(100) priceOf(101)
    eq(asked[100], 1) eq(asked[101], 1) eq(asked[200], 1)
end)

test("cout du parcours : somme des materiaux a prix, et decompte de ceux sans prix", function()
    local materials = { { itemID = 100, qty = 10 }, { itemID = 101, qty = 4 }, { itemID = 999, qty = 7 } }
    local cost = P.PlanCost(materials, prices({ [100] = 40, [101] = 5 }))
    eq(cost.total, 420)
    eq(cost.unpricedItems, 1)
    eq(cost.unpricedQty, 7)
    local empty = P.PlanCost({}, prices({}))
    eq(empty.total, 0) eq(empty.unpricedItems, 0)
    eq(P.PlanCost(materials, nil), nil, "sans source de prix, pas de cout")
end)

-- Détail des objets à fabriquer soi-même ----------------------------------------------

local function byItem(list)
    local map = {}
    for _, entry in ipairs(list) do map[entry.itemID] = entry end
    return map
end

test("le tarificateur dit quand fabriquer est le choix retenu", function()
    local sources = { [200] = { { reagents = { { 100, 1 }, { 101, 1 } }, yield = 1 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)
    eq(sourceOf(200), sources[200][1], "fabriquer : seul moyen connu")
    eq(sourceOf(100), nil, "un objet sans recette s'achete")
    local _, buy = P.NewPricer(prices({ [100] = 40, [101] = 5, [200] = 30 }), sources)
    eq(buy(200), nil, "acheter est moins cher : pas de fabrication")
    local _, unknown = P.NewPricer(prices({ [100] = 40 }), sources)
    eq(unknown(200), nil, "cout de fabrication inconnu : on ne decompose pas")
end)

test("detail : un objet a fabriquer est remplace par ses materiaux", function()
    local sources = { [200] = { { reagents = { { 100, 1 }, { 101, 1 } }, yield = 1 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40, [101] = 5, [102] = 9 }), sources)
    local materials = { { itemID = 200, qty = 29 }, { itemID = 102, qty = 10 }, { itemID = 100, qty = 5 } }
    local detail = P.ExpandMaterials(materials, sourceOf)
    local raw, prepare = byItem(detail.materials), byItem(detail.prepare)
    eq(raw[200], nil, "l'objet fabrique ne doit plus etre a reunir")
    eq(raw[100].qty, 34, "100 : 5 directs + 29 pour la fabrication")
    eq(raw[101].qty, 29)
    eq(raw[102].qty, 10)
    eq(prepare[200].qty, 29)
    eq(prepare[200].crafts, 29)
    eq(prepare[200].reagents, sources[200][1].reagents, "la recette retenue accompagne l'objet a preparer")
    eq(prepare[200].yield, 1)
    eq(#detail.prepare, 1)
    eq(detail.materials[1].itemID, 100, "tri par quantite decroissante")
    eq(materials[1].itemID, 200, "la liste recue ne doit pas changer")
    eq(#materials, 3)
end)

test("detail : une fabrication qui donne plusieurs objets est arrondie au-dessus", function()
    local sources = { [200] = { { reagents = { { 100, 2 } }, yield = 5 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40 }), sources)
    local detail = P.ExpandMaterials({ { itemID = 200, qty = 12 } }, sourceOf)
    eq(byItem(detail.prepare)[200].crafts, 3, "12 objets a 5 par fabrication")
    eq(byItem(detail.materials)[100].qty, 6)
end)

test("detail : un objet fabrique a partir d'un autre objet fabrique", function()
    local sources = {
        [200] = { { reagents = { { 100, 2 } }, yield = 1 } },
        [300] = { { reagents = { { 200, 1 }, { 101, 1 } }, yield = 1 } },
    }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)
    local detail = P.ExpandMaterials({ { itemID = 300, qty = 4 } }, sourceOf)
    local raw, prepare = byItem(detail.materials), byItem(detail.prepare)
    eq(raw[100].qty, 8) eq(raw[101].qty, 4)
    eq(raw[200], nil) eq(raw[300], nil)
    eq(prepare[300].qty, 4) eq(prepare[200].qty, 4)
end)

test("detail : sans tarificateur ou sans recette, la liste reste telle quelle", function()
    local materials = { { itemID = 200, qty = 3 }, { itemID = 100, qty = 9 } }
    local same = P.ExpandMaterials(materials, nil)
    eq(#same.materials, 2) eq(#same.prepare, 0)
    eq(byItem(same.materials)[200].qty, 3)
    local none = P.ExpandMaterials(materials, function() return nil end)
    eq(#none.materials, 2) eq(#none.prepare, 0)
    local empty = P.ExpandMaterials(nil, nil)
    eq(#empty.materials, 0) eq(#empty.prepare, 0)
end)

test("detail : des recettes qui se renvoient l'une a l'autre ne bouclent pas", function()
    local loop = { reagents = { { 200, 1 } }, yield = 1 }
    local detail = P.ExpandMaterials({ { itemID = 200, qty = 2 } }, function() return loop end)
    eq(byItem(detail.materials)[200].qty, 2, "il reste l'objet a reunir, sans boucle infinie")
end)

-- Objets déjà possédés (sacs + banque) : ownedOf(itemID) -> nombre.
local function owned(map) return function(itemID) return map[itemID] end end

test("detail : un objet a fabriquer deja possede en entier n'est pas decompose", function()
    local sources = { [200] = { { reagents = { { 100, 1 }, { 101, 1 } }, yield = 1 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)
    local materials = { { itemID = 200, qty = 29 }, { itemID = 100, qty = 5 } }
    local detail = P.ExpandMaterials(materials, sourceOf, owned({ [200] = 40 }))
    local raw = byItem(detail.materials)
    eq(raw[200].qty, 29, "l'objet possede reste dans la liste, a sa quantite necessaire")
    eq(raw[100].qty, 5, "pas de materiaux pour le fabriquer")
    eq(raw[101], nil)
    eq(#detail.prepare, 0, "rien a preparer")
end)

test("detail : seule la partie manquante d'un objet possede est fabriquee", function()
    local sources = { [200] = { { reagents = { { 100, 1 }, { 101, 1 } }, yield = 1 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)
    local materials = { { itemID = 200, qty = 29 }, { itemID = 100, qty = 5 } }
    local detail = P.ExpandMaterials(materials, sourceOf, owned({ [200] = 12 }))
    local raw, prepare = byItem(detail.materials), byItem(detail.prepare)
    eq(raw[200].qty, 12, "les 12 possedes restent a reunir (deja dans les sacs)")
    eq(prepare[200].qty, 17, "17 a fabriquer")
    eq(prepare[200].crafts, 17)
    eq(raw[100].qty, 22, "5 directs + 17 pour la fabrication")
    eq(raw[101].qty, 17)
end)

test("detail : un objet possede est aussi deduit plus bas dans la chaine", function()
    local sources = {
        [200] = { { reagents = { { 100, 2 } }, yield = 1 } },
        [300] = { { reagents = { { 200, 1 }, { 101, 1 } }, yield = 1 } },
    }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40, [101] = 5 }), sources)
    local detail = P.ExpandMaterials({ { itemID = 300, qty = 4 } }, sourceOf, owned({ [200] = 3 }))
    local raw, prepare = byItem(detail.materials), byItem(detail.prepare)
    eq(prepare[300].qty, 4)
    eq(raw[200].qty, 3, "les 3 intermediaires possedes servent")
    eq(prepare[200].qty, 1, "un seul intermediaire a fabriquer")
    eq(raw[100].qty, 2)
    eq(raw[101].qty, 4)
end)

test("detail : le stock possede n'est compte qu'une fois", function()
    local sources = {
        [200] = { { reagents = { { 100, 2 } }, yield = 1 } },
        [300] = { { reagents = { { 200, 1 } }, yield = 1 } },
    }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40 }), sources)
    -- 5 objets 200 demandes directement + 4 via 300 ; on en possede 6.
    local detail = P.ExpandMaterials({ { itemID = 200, qty = 5 }, { itemID = 300, qty = 4 } }, sourceOf,
        owned({ [200] = 6 }))
    local raw, prepare = byItem(detail.materials), byItem(detail.prepare)
    eq(raw[200].qty, 6, "les 6 possedes, pas plus")
    eq(prepare[200].qty, 3, "5 + 4 - 6 = 3 a fabriquer")
    eq(raw[100].qty, 6)
end)

test("detail : fabrication par lots, seule la partie manquante compte", function()
    local sources = { [200] = { { reagents = { { 100, 2 } }, yield = 5 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40 }), sources)
    local detail = P.ExpandMaterials({ { itemID = 200, qty = 12 } }, sourceOf, owned({ [200] = 4 }))
    eq(byItem(detail.prepare)[200].crafts, 2, "8 manquants a 5 par fabrication")
    eq(byItem(detail.materials)[100].qty, 4)
    eq(byItem(detail.materials)[200].qty, 4)
end)

test("detail : une quantite nulle ne donne ni ligne ni fabrication", function()
    local sources = { [200] = { { reagents = { { 100, 1 } }, yield = 1 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40 }), sources)
    local detail = P.ExpandMaterials({ { itemID = 200, qty = 0 }, { itemID = 100, qty = 0 } }, sourceOf)
    eq(#detail.materials, 0)
    eq(#detail.prepare, 0)
end)

test("detail : un stock illisible compte pour zero", function()
    local sources = { [200] = { { reagents = { { 100, 1 } }, yield = 1 } } }
    local _, sourceOf = P.NewPricer(prices({ [100] = 40 }), sources)
    for _, value in ipairs({ -3, 0, "x", 1.5 }) do
        local detail = P.ExpandMaterials({ { itemID = 200, qty = 4 } }, sourceOf, function() return value end)
        local expected = value == 1.5 and 3 or 4
        eq(byItem(detail.prepare)[200].qty, expected, "stock " .. tostring(value))
    end
    local broken = P.ExpandMaterials({ { itemID = 200, qty = 4 } }, sourceOf, function() error("boom") end)
    eq(byItem(broken.prepare)[200].qty, 4, "une erreur de lecture du stock ne casse pas le calcul")
end)

print(string.format("%d tests reussis, %d en echec", passed, failed))
return failed
