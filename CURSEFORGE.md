# Page CurseForge — Profession Path

> Textes prêts à coller dans la page du projet. La partie anglaise va en premier (CurseForge est surtout anglophone), la partie française en dessous.

## Réglages du projet

- **Nom** : Profession Path
- **Auteur** : Ryugan
- **Jeu** : World of Warcraft — version « Forever » (interface 16001, client 1.60.1)
- **Catégorie** : Professions
- **Licence** : MIT
- **Type de fichier** : Beta
- **Dépendance facultative** : Auctionator
- **Fichier à envoyer** : le zip le plus récent, `ProfessionPath-<version>.zip` (un seul gardé dans le dossier du projet)

## Résumé (une ligne, en anglais)

Step-by-step profession leveling for WoW Forever: what to craft next, how many, with which materials, at what cost — and why.

## Description (anglais)

**Profession Path** tells you which recipe to craft next to level your profession, and explains its choice. It reads your real recipes from the game, so the path is built for your character.

**What it shows**

- **Next recipe**: what to craft now, how many, the chance of a skill point, and the materials for that step.
- **Full path**: the following steps up to the skill level you are aiming for.
- **Trainer visits**: when to go back to your trainer and what to learn, grouped to save trips.
- **Shopping list**: every material for the whole path, with what you already own (bags and bank shown separately).
- **To craft yourself first**: materials that are cheaper to craft than to buy (cured hides, bars...), with their own materials added to the shopping list.
- **Estimated cost** of the whole path.
- **Favourites**: star a material and it gets a star in your bags and at vendors.
- **Profession tabs**: one click to switch profession.

**Three priorities**

- **Simplest**: fewest crafts, guaranteed skill points first.
- **Fewest materials**: reuses the same materials as much as possible.
- **Cheapest** (needs Auctionator): lowest cost per skill point, using auction house prices, vendor prices, and the cost of crafting a material yourself.

**How to use it**

1. Open your profession window once so the add-on can read your recipes.
2. Talk to your profession trainer once, with the "Unavailable" filter ticked, so the add-on learns what they teach. Until then the window shows a "Provisional path" warning.
3. Type `/ppath`.

**Information only.** The add-on never crafts, buys, sells or moves anything for you.

**Honest about its data.** Recipe thresholds come from the WoW Forever game files. When something is unknown (a price, a trainer not read yet), the add-on says so instead of guessing. Quantities marked `~` are averages.

**Works with** the default bags, Bagnon, AdiBags, Baganator, LiteBag, Baggins, Inventorian, ElvUI and ArkInventory for the favourite star. Only the default bags and Bagnon have been tested in game so far.

**Languages**: English, French.

**Beta**: tested in game on Leatherworking and Blacksmithing. Feedback on other professions is very welcome.

## Description (français)

**Profession Path** te dit quelle recette fabriquer pour faire progresser ton métier, et t'explique son choix. Il lit tes vraies recettes dans le jeu : le parcours est fait pour ton personnage.

**Ce qu'il affiche**

- **Prochaine recette** : quoi fabriquer maintenant, combien, la chance de gagner un point, et les matériaux de l'étape.
- **Parcours complet** : les étapes suivantes jusqu'au niveau que tu vises.
- **Visites au maître** : quand retourner voir ton maître et quoi apprendre, regroupé pour éviter les allers-retours.
- **Liste de courses** : tous les matériaux du parcours, avec ce que tu possèdes déjà (sacs et banque séparés).
- **À préparer toi-même** : les matériaux moins chers à fabriquer qu'à acheter (peaux traitées, barres…), avec leurs propres matériaux ajoutés à la liste.
- **Coût estimé** de tout le parcours.
- **Favoris** : mets une étoile sur un matériau, elle apparaît dans tes sacs et chez les marchands.
- **Onglets de métier** : un clic pour changer de métier.

**Trois priorités**

- **Le plus simple** : le moins de fabrications, les points garantis d'abord.
- **Le moins de matériaux** : réutilise les mêmes matériaux autant que possible.
- **Le moins coûteux** (demande Auctionator) : le coût le plus bas par point, d'après les prix de l'hôtel des ventes, des marchands, et le coût de fabrication d'un matériau par toi-même.

**Utilisation**

1. Ouvre une fois ta fenêtre de métier, pour que l'add-on lise tes recettes.
2. Parle une fois à ton maître de métier, filtre « Indisponible » coché, pour qu'il sache ce qu'il enseigne. D'ici là, la fenêtre affiche « Parcours provisoire ».
3. Tape `/mpp` (ou `/ppath`).

**Il informe seulement.** L'add-on ne fabrique, n'achète, ne vend et ne déplace rien à ta place.

**Honnête sur ses données.** Les seuils des recettes viennent des fichiers du jeu WoW Forever. Quand une information manque (un prix, un maître pas encore lu), l'add-on le dit au lieu de deviner. Les quantités marquées `~` sont des moyennes.

**Bêta** : testé en jeu sur le Travail du cuir et la Forge. Les retours sur les autres métiers sont les bienvenus.

## Captures d'écran à prendre (dans le jeu)

1. La fenêtre entière sur un métier, priorité « Le moins coûteux », avec les onglets visibles à droite.
2. La souris sur une ligne de « À préparer toi-même », infobulle ouverte.
3. Les sacs ouverts avec quelques étoiles de favoris.
4. La fenêtre avec le bandeau « Parcours provisoire » (un métier dont le maître n'est pas lu).

## Notes de version (changelog) — 1.0.0-beta9

- New "Next rank" banner: as soon as you can learn Journeyman, Expert or Artisan, the window tells you which trainer to visit (closest one of your faction, with a "Map" button for the arrow) and the character level you need. For Cooking, First Aid and Fishing, it reminds you that Expert is learned from a book.
- Every profession trainer of WoW Forever is now built in, with its position: the "Profession NPCs" section shows the trainers for your rank and the next one, even if you have never met them.
- More built-in data: 23 trainers and supply vendors and 82 trainer recipe levels recorded in game (for example, Patterned Bronze Bracers can be learned at 95).
- Nothing to share anymore: the add-on ships all its data, players have nothing to copy or post.

## Notes de version (changelog) — 1.0.0-beta8

Includes 1.0.0-beta7 (diag command, never released on its own).

- Fixed: beginner recipes taught by your trainer (no skill level required) no longer drop out of the path after you talk to the trainer.
- Fixed: a vendor that sells an item only in limited stock or for tokens no longer erases the price learned at another vendor, and the lowest vendor price is kept.
- Fixed: talking again to a trainer or vendor (for example with another character) now completes what the add-on knows about them instead of replacing it.
- Smoother: the window no longer recalculates every time the game loads item information for other add-ons (auction house, Auctionator scans).
- Profession tabs now show only the professions your character has: a profession you dropped no longer appears (its data is kept and comes back if you learn it again).
- Material names that the game had not loaded yet ("Item #2841") now appear once the game knows them.
- Recipe data updated for game build 1.60.1.70938 (for example, Coarse Grinding Stone now gives skill points up to 90).

## Notes de version (changelog) — 1.0.0-beta7

- New /ppath diag command: opens a text to copy and paste in a bug report (add-on and game versions, what the add-on has read). No character or realm name is included. A "Report a bug" form is now available on GitHub.
- Sturdier start-up and saved data: the add-on now prepares its answers before listening to the game, and its saved data carries a version number so future updates can convert it without losing your favourites or the NPCs you met.

## Notes de version (changelog) — 1.0.0-beta6

- New wide layout: click "Layout" at the bottom of the window (or type /ppath layout) to switch between the tall column and a wide two-column rectangle that takes less height on screen. Your choice is remembered. In the wide layout, the materials list grows to use the free space of the right column.
- Resize the window: drag the grip in the bottom-right corner to make the whole window bigger or smaller (60% to 130%). Double-click the grip to go back to the original size. The size is remembered.

## Notes de version (changelog) — 1.0.0-beta5

Includes 1.0.0-beta4 (share command).

- First community data: 2 Stormwind trainers (Leatherworking, Skinning) and 42 trainer recipe levels (Leatherworking, First Aid, Cooking), shared with /ppath share and checked before inclusion.

## Notes de version (changelog) — 1.0.0-beta4

- New /ppath share command: copy the trainers and vendors you met and the trainer recipes you read, and paste them in a GitHub issue (template provided). Shared data is checked and added to the add-on for everyone. No character or realm name is shared.
- Trainer recipes shared by players are used when you have not read your trainer yet; the window then says the path relies on shared data that may be incomplete.

## Notes de version (changelog) — 1.0.0-beta3

Includes 1.0.0-beta2 (never released on its own).

- New "Profession NPCs" section: your profession trainer and supplies vendors, those in your zone first. The add-on remembers where they are once you have talked to them.
- "Map" button on each NPC, and "Show my trainer" next to trainer visits: places the game map marker with its guiding arrow (one marker at a time).
- New minimap button with the Profession Path icon: click to open or close the window, drag to move it (square minimaps supported). Type /ppath minimap to hide or show it.
- The add-on list now shows the Profession Path icon.

## Notes de version (changelog) — 1.0.0-beta2

- New minimap button with the Profession Path icon: click to open or close the window, drag to move it around the minimap (square minimaps supported). Type /ppath minimap to hide or show it.
- The add-on list now shows the Profession Path icon.

## Notes de version (changelog) — 1.0.0-beta1

First public beta.

- Step-by-step path with three priorities (simplest, fewest materials, cheapest).
- Trainer recipes read in game and grouped into trainer visits.
- Vendor prices (47 crafting materials shipped, more read when you open a vendor).
- Materials you can craft yourself priced at the cost of their own materials, and listed under "To craft yourself first".
- Estimated cost of the path.
- Favourite star in bags and at vendors; profession tabs.
