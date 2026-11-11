-- Profession Path — maîtres de métier et marchands de fournitures, livrés avec l'add-on.
--
-- D'OÙ VIENNENT CES POSITIONS
--   Les fichiers du jeu ne disent pas où se trouvent les PNJ : c'est gardé sur le serveur.
--   Chaque entrée vient d'un PNJ réellement rencontré en jeu sur WoW Forever (lu par Npcs.lua).
--   Aucune position n'est reprise d'une autre version du jeu ni d'un autre add-on.
--
-- FORME
--   ["trainer:numéro du PNJ"] ou ["vendor:numéro du PNJ"] = {
--       kind = "trainer" (maître) ou "vendor" (marchand de fournitures),
--       name = nom du PNJ, map = numéro de la carte, x et y = position sur cette carte (0 à 1),
--       faction = "Alliance", "Horde" ou nil (neutre),
--       profession = nom du métier (maître seulement), professionID = numéro du métier,
--       items = { [numéro d'objet] = true } (marchand seulement : matériaux de métier vendus),
--   },
--
-- PRIORITÉ
--   Un PNJ que le joueur a rencontré lui-même remplace celui de cette liste.

local _, ns = ...

ns.NPCsBuild = nil -- version du jeu sur laquelle la liste a été relevée

ns.NPCs = {
}
