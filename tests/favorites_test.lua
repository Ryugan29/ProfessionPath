-- Tests des favoris (composants marqués d'une étoile), hors du jeu.
-- Lancés par tests/run.js, qui charge d'abord ProfessionPath/Favorites.lua dans « ns ».

local ns = ...
local F = ns.Favorites

local passed, failed = 0, 0

local function test(name, fn)
    F.Attach({})
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

test("rien n'est favori au depart", function()
    eq(F.Is(501), false)
    eq(F.Count(), 0)
end)

test("un clic met en favori, un second l'enleve", function()
    eq(F.Toggle(501), true, "premier clic")
    eq(F.Is(501), true)
    eq(F.Count(), 1)
    eq(F.Toggle(501), false, "second clic")
    eq(F.Is(501), false)
    eq(F.Count(), 0)
end)

test("les favoris sont ecrits dans la table de sauvegarde fournie", function()
    local saved = { [777] = true }
    F.Attach(saved)
    eq(F.Is(777), true, "favori deja sauvegarde")
    F.Toggle(501)
    eq(saved[501], true, "nouveau favori sauvegarde")
    F.Toggle(777)
    eq(saved[777], nil, "un favori retire ne laisse aucune trace")
end)

test("un identifiant invalide est refuse sans rien modifier", function()
    local saved = {}
    F.Attach(saved)
    for _, bad in ipairs({ "501", 0, -3, 1.5, true, {} }) do
        eq(F.Toggle(bad), false, "bascule de " .. tostring(bad))
        eq(F.Is(bad), false, "favori " .. tostring(bad))
    end
    eq(F.Toggle(nil), false, "bascule de nil")
    eq(F.Is(nil), false, "favori nil")
    eq(next(saved), nil, "la sauvegarde doit rester vide")
end)

test("une sauvegarde abimee ne cree pas de faux favoris", function()
    F.Attach({ [501] = "oui", [502] = 1, [503] = true })
    eq(F.Is(501), false)
    eq(F.Is(502), false)
    eq(F.Is(503), true)
    eq(F.Count(), 1)
    F.Attach(nil)
    eq(F.Is(503), false, "sans sauvegarde, aucun favori")
    eq(F.Toggle(503), true, "les favoris marchent meme sans sauvegarde")
end)

test("chaque changement previent ceux qui ecoutent", function()
    local seen = {}
    F.OnChange(function(itemID, isFavorite) seen[#seen + 1] = itemID .. (isFavorite and "+" or "-") end)
    F.Toggle(501)
    F.Toggle(501)
    F.Toggle("invalide")
    eq(table.concat(seen, " "), "501+ 501-")
end)

test("un ecouteur en panne n'empeche pas les autres d'etre prevenus", function()
    local reached = false
    F.OnChange(function() error("panne volontaire") end)
    F.OnChange(function() reached = true end)
    eq(F.Toggle(600), true)
    eq(reached, true)
    eq(type(F.LastError()), "string", "la panne doit rester consultable")
end)

print(string.format("favoris : %d tests reussis, %d en echec", passed, failed))
return failed
