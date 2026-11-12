-- Profession Path — maîtres de métier et marchands de fournitures, livrés avec l'add-on.
-- FICHIER FABRIQUÉ par tools/import_shares.js à partir des partages des joueurs (/ppath partager) :
-- ne pas le modifier à la main. Source : tools/community.json.
--
-- Les fichiers du jeu ne disent pas où se trouvent les PNJ. Chaque entrée vient d'un PNJ réellement
-- rencontré en jeu sur WoW Forever par un joueur, puis vérifiée. Rien n'est repris d'une autre
-- version du jeu ni d'un autre add-on. Un PNJ que le joueur a rencontré lui-même remplace celui-ci.
--
-- Forme : ["trainer:numéro"] ou ["vendor:numéro"] = { kind, name, map, x, y, faction,
--         professionID et profession (maître), items (marchand : matériaux de métier vendus) }

local _, ns = ...

ns.NPCsBuild = "1.60.1.70888" -- version du jeu des relevés

ns.NPCs = {
    ["trainer:1292"] = { kind = "trainer", name = "Maris Granger", map = 1453, x = 0.7202, y = 0.6233, faction = "Alliance", professionID = 393, profession = "Dépeçage" },
    ["trainer:5564"] = { kind = "trainer", name = "Simon Tanner", map = 1453, x = 0.718, y = 0.6291, faction = "Alliance", professionID = 165, profession = "Travail du cuir" },
}
