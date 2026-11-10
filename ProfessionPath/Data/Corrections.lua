-- Profession Path — corrections manuelles des seuils.
--
-- Ce fichier est chargé APRÈS Thresholds.lua : ce que tu écris ici remplace ou complète
-- les valeurs fabriquées automatiquement. Il n'est jamais écrasé par l'outil.
--
-- COMMENT AJOUTER OU CORRIGER UNE RECETTE
--   Une ligne par recette, entre les accolades ci-dessous :
--
--       [numéro de la recette] = { orange, jaune, vert, gris },
--
--   * numéro de la recette : visible en jeu avec la commande  /mpp recettes
--   * orange : niveau de métier requis pour apprendre la recette (0 si tu ne le connais pas)
--   * jaune  : niveau où elle passe au jaune (le point n'est plus garanti)
--   * vert   : niveau où elle passe au vert
--   * gris   : niveau où elle ne donne plus aucun point
--
--   Exemple de FORME uniquement (recette imaginaire, à ne pas recopier) :
--       [999999] = { 1, 30, 45, 60 },
--
-- RÈGLE DU PROJET
--   N'écrire ici que des valeurs vérifiées pour WoW Forever (relevées en jeu).
--   Jamais de valeurs d'une autre version de WoW, jamais d'estimations.

local _, ns = ...

local corrections = {
}

for recipeID, thresholds in pairs(corrections) do
    ns.Thresholds[recipeID] = thresholds
end
