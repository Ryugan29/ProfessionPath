-- Lecture des prix chez les marchands.
-- Quand le joueur ouvre un marchand, on note ce qu'il vend et à quel prix. L'add-on se contente
-- de LIRE la fenêtre : il n'achète rien et ne clique sur rien.
--
-- Pourquoi : la priorité « Le moins coûteux » a besoin d'un prix par matériau, et les objets de
-- marchand ne sont presque jamais à l'hôtel des ventes.
--
-- Ce qui est noté : seulement les objets vendus contre de l'argent, en stock illimité. Un objet
-- en quantité limitée ou payé en monnaie spéciale n'est pas une source d'approvisionnement
-- fiable : on ne le note pas (même règle que l'add-on Auctionator).

local _, ns = ...
local L = ns.L

local READ_DELAY = 0.2 -- secondes : laisse la fenêtre du marchand se remplir, regroupe les mises à jour
local UNLIMITED_STOCK = -1
local PRICE_TOLERANCE = 0.001 -- en cuivre

local readPending = false

local function Call(fn, ...)
    if type(fn) ~= "function" then return nil end
    local ok, a, b, c, d, e, f, g, h = pcall(fn, ...)
    if ok then return a, b, c, d, e, f, g, h end
    return nil
end

-- Ce que le marchand annonce pour une ligne : prix du lot, taille du lot, stock, monnaie spéciale.
-- Deux générations d'interface possibles selon le client : on prend celle qui existe.
local function Offer(index)
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = Call(C_MerchantFrame.GetItemInfo, index)
        if type(info) ~= "table" then return nil end
        return info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
    end
    local _, _, price, stackCount, numAvailable, _, _, extendedCost = Call(GetMerchantItemInfo, index)
    return price, stackCount, numAvailable, extendedCost
end

-- Prix à l'unité d'une ligne du marchand, ou nil si elle ne doit pas servir de référence.
local function UnitPrice(index)
    local price, stackCount, numAvailable, extendedCost = Offer(index)
    if type(price) ~= "number" or price <= 0 then return nil end
    if extendedCost or numAvailable ~= UNLIMITED_STOCK then return nil end
    if type(stackCount) ~= "number" or stackCount < 1 then stackCount = 1 end
    return price / stackCount
end

-- Ce que ce marchand propose : { [objet] = prix à l'unité le plus bas, ou false si aucune de ses
-- lignes pour cet objet ne peut servir de référence }.
local function MerchantPrices()
    local prices = {}
    for index = 1, Call(GetMerchantNumItems) or 0 do
        local itemID = Call(GetMerchantItemID, index)
        if type(itemID) == "number" then
            local price = UnitPrice(index)
            local known = prices[itemID]
            if price and (not known or price < known) then
                prices[itemID] = price
            elseif known == nil then
                prices[itemID] = false
            end
        end
    end
    return prices
end

-- Deux prix sont « les mêmes » à moins d'un millième de cuivre près : un prix à l'unité peut
-- être une fraction (5 cuivre les 3) et sa relecture depuis la sauvegarde n'est pas exacte.
local function SamePrice(a, b)
    return type(a) == "number" and type(b) == "number" and math.abs(a - b) < PRICE_TOLERANCE
end

-- Met la sauvegarde à jour. Renvoie le nombre d'objets à prix et le nombre de changements.
local function ReadMerchant()
    local seen, changed = 0, 0
    for itemID, price in pairs(MerchantPrices()) do
        local saved = ns.db.vendor[itemID]
        if price then
            seen = seen + 1
            if not SamePrice(saved, price) then
                ns.db.vendor[itemID] = price
                changed = changed + 1
            end
        elseif saved ~= nil then
            -- Ce marchand ne vend plus l'objet en stock illimité contre de l'argent : l'ancien
            -- prix n'est plus fiable, on l'oublie plutôt que de le garder indéfiniment.
            ns.db.vendor[itemID] = nil
            changed = changed + 1
        end
    end
    return seen, changed
end

local function ReadAndReport()
    readPending = false
    if not ns.db then return end
    -- On retient aussi où se trouve ce marchand, s'il vend des matériaux de métier.
    if ns.RecordVendorNpc then ns.RecordVendorNpc() end
    local seen, changed = ReadMerchant()
    if changed == 0 then return end
    ns.Print(L.VENDOR_READ:format(seen, changed))
    ns.RefreshUI()
end

local function Schedule()
    if readPending then return end
    readPending = true
    C_Timer.After(READ_DELAY, ReadAndReport)
end

local eventFrame = CreateFrame("Frame")
-- Un évènement absent de ce client ne doit pas empêcher l'add-on de se charger.
pcall(eventFrame.RegisterEvent, eventFrame, "MERCHANT_SHOW")
pcall(eventFrame.RegisterEvent, eventFrame, "MERCHANT_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then Schedule() end
end)
