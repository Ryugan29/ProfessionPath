-- Profession Path — prix des objets vendus par les marchands, livrés avec l'add-on.
--
-- À QUOI ÇA SERT
--   La priorité « Le moins coûteux » a besoin d'un prix pour chaque matériau. Les objets de
--   marchand (sel, teintures, fil...) ne sont presque jamais à l'hôtel des ventes : sans prix,
--   leurs recettes étaient écartées. Cette liste donne leur prix dès l'installation.
--
-- D'OÙ VIENNENT CES PRIX
--   Uniquement de marchands réellement ouverts en jeu sur WoW Forever (lus par Vendor.lua).
--   Les fichiers du jeu donnent un prix théorique à chaque objet, mais ne disent pas lesquels
--   un marchand vend vraiment : on ne s'en sert donc pas pour remplir cette liste.
--
-- FORME
--       [numéro de l'objet] = prix à l'unité, en pièces de cuivre,
--   (1 pièce d'argent = 100 cuivre ; 1 pièce d'or = 10 000 cuivre)
--
-- PRIORITÉ
--   Un prix que le joueur a lu lui-même chez un marchand remplace celui de cette liste : son
--   prix peut différer (remise de réputation, par exemple).

local _, ns = ...

-- RELEVÉ
--   47 matériaux de recettes, relevés en jeu le 2026-11-10 chez les marchands de
--   fournitures de métier. Chaque prix a été comparé au prix marchand des fichiers du jeu : tous identiques
--   (aucune remise de réputation dans le relevé). Les noms en commentaire sont ceux des fichiers
--   du jeu, en anglais.
--   Les objets relevés qui ne servent à aucune recette de métier ne sont pas repris ici.

ns.VendorPricesBuild = "1.60.1.70862" -- version du jeu sur laquelle la liste a été relevée

ns.VendorPrices = {
    [159] = 5, -- Refreshing Spring Water
    [1179] = 25, -- Ice Cold Milk
    [1205] = 100, -- Melon Juice
    [1645] = 400, -- Moonberry Juice
    [1708] = 200, -- Sweet Nectar
    [2320] = 10, -- Coarse Thread
    [2321] = 100, -- Fine Thread
    [2324] = 25, -- Bleach
    [2325] = 1000, -- Black Dye
    [2604] = 50, -- Red Dye
    [2605] = 100, -- Green Dye
    [2678] = 2, -- Mild Spices
    [2692] = 40, -- Hot Spices
    [2880] = 100, -- Weak Flux
    [2928] = 20, -- Dust of Decay
    [3030] = 1.5, -- Razor Arrow
    [3371] = 4, -- Empty Vial
    [3372] = 40, -- Leaded Vial
    [3466] = 2000, -- Strong Flux
    [3713] = 160, -- Soothing Spices
    [4289] = 50, -- Salt
    [4291] = 500, -- Silken Thread
    [4340] = 350, -- Gray Dye
    [4341] = 500, -- Yellow Dye
    [4342] = 2500, -- Purple Dye
    [4399] = 200, -- Wooden Stock
    [4400] = 2000, -- Heavy Stock
    [4470] = 38, -- Simple Wood
    [4536] = 5, -- Shiny Red Apple
    [6217] = 124, -- Copper Rod
    [6260] = 50, -- Blue Dye
    [6261] = 1000, -- Orange Dye
    [6530] = 100, -- Nightcrawlers
    [8343] = 2000, -- Heavy Silken Thread
    [8766] = 800, -- Morning Glory Dew
    [8925] = 500, -- Crystal Vial
    [10284] = 200, -- Simple Flour
    [10290] = 2500, -- Pink Dye
    [11291] = 4500, -- Star Wood
    [14341] = 5000, -- Rune Thread
    [16583] = 10000, -- Demonic Figurine
    [17034] = 200, -- Maple Seed
    [17035] = 400, -- Stranglethorn Seed
    [18256] = 6000, -- Imbued Vial
    [18567] = 150000, -- Elemental Flux
    [247786] = 10, -- Mote of Magic
    [272941] = 200000, -- Thick Logs
}
