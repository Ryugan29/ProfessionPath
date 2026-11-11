-- Profession Path — niveau et prix des recettes enseignées par les maîtres, livrés avec l'add-on.
-- FICHIER FABRIQUÉ par tools/import_shares.js à partir des partages des joueurs (/ppath partager) :
-- ne pas le modifier à la main.
--
-- D'OÙ VIENNENT CES DONNÉES
--   Les fichiers du jeu ne disent pas à quel niveau un maître enseigne une recette : seule la
--   fenêtre du maître le montre. Chaque ligne vient d'un maître réellement lu en jeu sur
--   WoW Forever par un joueur, puis vérifiée avant d'être ajoutée.
--
-- FORME
--   [numéro de la recette] = { niveau de métier requis, prix en cuivre (ou nil) },
--   Rangé par numéro et non par nom : la liste sert dans toutes les langues du jeu.
--
-- PRIORITÉ
--   Un maître que le joueur a lu lui-même remplace cette liste.

local _, ns = ...

ns.TrainerLevels = {
}
