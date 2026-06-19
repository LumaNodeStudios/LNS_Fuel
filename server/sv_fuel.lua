local Settings = lib.load('shared.settings')

if not Settings then return end

local function reportSecurityCheck(src, message)
    print(message)
    lib.logger(src, 'Security Check', message)
    if Settings.exploitdrop then
        DropPlayer(src, "Security violation detected (LNS_Fuel)")
    end
end

local function validateNumber(val)
    local num = tonumber(val)
    if not num or num ~= num or num == math.huge or num == -math.huge then
        return nil
    end
    return num
end

local function validateInteger(val)
    local num = validateNumber(val)
    if not num then return nil end
    return math.floor(num)
end

local function GetStationId(coords)
    return string.format("station_%.2f_%.2f", coords.x, coords.y)
end

local function GetStationIndex(stationId)
    if type(stationId) ~= "string" then return nil end
    for i = 1, #Settings.Stations do
        if GetStationId(Settings.Stations[i].blip) == stationId then
            return i
        end
    end
    return nil
end

local function applyFuelLevel(networkId, fuelLevel)
    local veh = NetworkGetEntityFromNetworkId(networkId)

    if veh == 0 or GetEntityType(veh) ~= 2 then return end

    local vehState = Entity(veh)?.state
    local clampedFuel = math.clamp(fuelLevel, 0, 100)

    vehState:set('fuel', clampedFuel, true)
end

local function isNearAnyPump(playerCoords, maxDistance)
    maxDistance = maxDistance or 15.0
    if not Settings or not Settings.Stations then return false end
    for i = 1, #Settings.Stations do
        local station = Settings.Stations[i]
        if station.pumps then
            for _, pump in ipairs(station.pumps) do
                if #(playerCoords - pump) < maxDistance then
                    return true
                end
            end
        end
        local electricPumps = station.electricpumps or station.electricPumps
        if electricPumps then
            for _, pump in ipairs(electricPumps) do
                local coords = type(pump) == "table" and pump.coords or pump
                local vec3Coords = type(coords) == "vector4" and vec3(coords.x, coords.y, coords.z) or coords
                if #(playerCoords - vec3Coords) < maxDistance then
                    return true
                end
            end
        end
    end

    if ownedStations then
        for _, station in pairs(ownedStations) do
            if station.electric_chargers then
                for _, pump in ipairs(station.electric_chargers) do
                    local coords = type(pump) == "table" and pump.coords or pump
                    local vec3Coords = type(coords) == "vector4" and vec3(coords.x, coords.y, coords.z) or coords
                    if #(playerCoords - vec3Coords) < maxDistance then
                        return true
                    end
                end
            end
        end
    end

    return false
end

local function handleDefaultPayment(plyId, cost)
    local isSuccess = exports.ox_inventory:RemoveItem(plyId, 'money', cost)

    if isSuccess then 
        return true 
    end

    local currentBal = exports.ox_inventory:GetItemCount(plyId, 'money')

    TriggerClientEvent('ox_lib:notify', plyId, {
        type = 'error',
        description = locale('not_enough_money', cost - currentBal)
    })
end

local processPayment = handleDefaultPayment

exports('setPaymentMethod', function(customFunc)
    processPayment = customFunc or handleDefaultPayment
end)

local function isVehicleElectric(veh)
    if not DoesEntityExist(veh) then return false end
    local modelHash = GetEntityModel(veh)
    if Settings.electricVehicles then
        if Settings.electricVehicles[modelHash] then
            return true
        end
        for modelKey, _ in pairs(Settings.electricVehicles) do
            if type(modelKey) == "string" and GetHashKey(modelKey) == modelHash then
                return true
            end
        end
    end
    return false
end

RegisterNetEvent('LNS_Fuel:pay', function(cost, currentFuel, nId, stationId, litersFueled)
    local src = source

    local validatedCost = validateNumber(cost)
    local validatedCurrentFuel = validateNumber(currentFuel)
    local validatedNId = validateInteger(nId)
    local validatedLiters = validateNumber(litersFueled)

    if not validatedCost or not validatedCurrentFuel or not validatedNId or not validatedLiters then
        reportSecurityCheck(src, ("[Security Check] Player %s sent invalid/NaN/inf pay parameters! Cost: %s, Fuel: %s, NetId: %s, Liters: %s"):format(
            src, tostring(cost), tostring(currentFuel), tostring(nId), tostring(litersFueled)
        ))
        return
    end

    if stationId ~= nil then
        if type(stationId) ~= "string" then
            reportSecurityCheck(src, ("[Security Check] Player %s sent invalid type for stationId: %s"):format(src, type(stationId)))
            return
        end
        if not GetStationIndex(stationId) then
            reportSecurityCheck(src, ("[Security Check] Player %s sent unregistered stationId: %s"):format(src, stationId))
            return
        end
    end

    cost = validatedCost
    litersFueled = validatedLiters
    currentFuel = validatedCurrentFuel

    if cost < 0 or litersFueled < 0 or currentFuel < 0 or currentFuel > 100 then
        reportSecurityCheck(src, ("[Security Check] Player %s sent invalid/out-of-bounds pay parameters! Cost: %s, Liters: %s, Fuel: %s"):format(src, cost, litersFueled, currentFuel))
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(validatedNId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:pay with invalid vehicle NetId!"):format(src))
        return
    end

    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local vehCoords = GetEntityCoords(vehicle)
    local distanceToVeh = #(playerCoords - vehCoords)

    if distanceToVeh > 15.0 then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:pay too far from vehicle! Distance: %0.2f meters"):format(src, distanceToVeh))
        return
    end

    if not isNearAnyPump(playerCoords, 15.0) then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:pay too far from any gas pump!"):format(src))
        return
    end

    local vehState = Entity(vehicle)?.state
    local currentServerFuel = (vehState and vehState.fuel) or 0
    local fuelDelta = currentFuel - currentServerFuel
    if fuelDelta > 0 then
        if litersFueled < fuelDelta - 2.0 then
            reportSecurityCheck(src, ("[Security Check] Player %s attempted free refuel! Liters Fueled: %s, Actual Fuel Delta: %0.2f (Server: %0.2f, Client Target: %s)"):format(
                src, litersFueled, fuelDelta, currentServerFuel, currentFuel
            ))

            return
        end
    end

    local isElectric = isVehicleElectric(vehicle)

    local expectedPrice = isElectric and ((Settings.electricPriceTick or 2) / Settings.refillValue) or (Settings.priceTick / Settings.refillValue)
    if stationId and ownedStations and ownedStations[stationId] then
        if isElectric then
            expectedPrice = ownedStations[stationId].electricPrice or 2
        else
            expectedPrice = ownedStations[stationId].price
        end
    end

    local expectedCost = math.ceil(litersFueled * expectedPrice)
    if cost < expectedCost - 2 then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:pay with manipulated cost! Cost: %s, Expected: %s, Liters: %s"):format(src, cost, expectedCost, litersFueled))
        return
    end
    
    if stationId and ownedStations and ownedStations[stationId] then
        local station = ownedStations[stationId]
        local fuelToDeduct = isElectric and 0 or math.ceil(litersFueled or 0)
        
        if not isElectric then
            if station.stock < fuelToDeduct then
                fuelToDeduct = station.stock
            end

            if fuelToDeduct <= 0 and litersFueled and litersFueled > 0 then
                return TriggerClientEvent('ox_lib:notify', src, { type = 'error', description = locale('notify_station_out_of_fuel') })
            end
        end

        if not processPayment(src, cost) then return end

        if not isElectric then
            station.stock = math.max(0, station.stock - fuelToDeduct)
            station.statistics.totalSales = (station.statistics.totalSales or 0) + fuelToDeduct
        end
        station.balance = station.balance + cost
        station.statistics.totalRevenue = (station.statistics.totalRevenue or 0) + cost
        station.statistics.lifetimeClients = (station.statistics.lifetimeClients or 0) + 1

        MySQL.query.await([[
            UPDATE lns_fuel_stations 
            SET stock = ?, balance = ?, statistics = ?
            WHERE station_id = ?
        ]], { station.stock, station.balance, json.encode(station.statistics), stationId })

        TriggerClientEvent('LNS_Fuel:syncStation', -1, stationId, station)

        currentFuel = math.floor(currentFuel)
        applyFuelLevel(validatedNId, currentFuel)

        local actionWord = isElectric and 'Charged' or 'Fueled'
        local unitWord = isElectric and 'kWh' or 'liters'
        lib.logger(src, 'Fuel Purchase', ('%s vehicle (netId: %d) with %0.2f %s for $%d at owned station %s. New charge level: %d%%'):format(actionWord, validatedNId, litersFueled, unitWord, cost, stationId, currentFuel), ('stationId:%s'):format(stationId), ('netId:%d'):format(validatedNId), ('liters:%0.2f'):format(litersFueled), ('cost:$%d'):format(cost))

        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            description = isElectric and ("Charged to %s%% - $%s"):format(currentFuel, cost) or locale('fuel_success', currentFuel, cost)
        })
        return
    end

    if not processPayment(src, cost) then return end

    currentFuel = math.floor(currentFuel)
    applyFuelLevel(validatedNId, currentFuel)

    local actionWord = isElectric and 'Charged' or 'Fueled'
    local unitWord = isElectric and 'kWh' or 'liters'
    lib.logger(src, 'Fuel Purchase', ('%s vehicle (netId: %d) with %0.2f %s for $%d at standard station. New charge level: %d%%'):format(actionWord, validatedNId, litersFueled, unitWord, cost, currentFuel), ('netId:%d'):format(validatedNId), ('liters:%0.2f'):format(litersFueled), ('cost:$%d'):format(cost))

    TriggerClientEvent('ox_lib:notify', src, {
        type = 'success',
        description = isElectric and ("Charged to %s%% - $%s"):format(currentFuel, cost) or locale('fuel_success', currentFuel, cost)
    })
end)

RegisterNetEvent('LNS_Fuel:fuelCan', function(ownsCan, cost, stationId)
    local src = source

    if type(ownsCan) ~= "boolean" then
        reportSecurityCheck(src, ("[Security Check] Player %s sent invalid type for ownsCan: %s"):format(src, type(ownsCan)))
        return
    end

    local validatedCost = validateNumber(cost)
    if not validatedCost then
        reportSecurityCheck(src, ("[Security Check] Player %s sent invalid/NaN/inf Jerry Can price: %s"):format(src, tostring(cost)))
        return
    end
    cost = validatedCost

    if cost < 0 then
        reportSecurityCheck(src, ("[Security Check] Player %s sent negative Jerry Can price: %s"):format(src, cost))
        return
    end

    if stationId ~= nil then
        if type(stationId) ~= "string" then
            reportSecurityCheck(src, ("[Security Check] Player %s sent invalid type for stationId: %s"):format(src, type(stationId)))
            return
        end
        if not GetStationIndex(stationId) then
            reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:fuelCan with unregistered stationId: %s"):format(src, stationId))
            return
        end
    end

    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    if not isNearAnyPump(playerCoords, 15.0) then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:fuelCan too far from any gas pump!"):format(src))
        return
    end

    local expectedCost = Settings.petrolCan.price
    if ownsCan then
        expectedCost = Settings.petrolCan.refillPrice
    end

    if cost < expectedCost then
        reportSecurityCheck(src, ("[Security Check] Player %s attempted Jerry Can refill/purchase with manipulated cost! Cost: %s, Expected: %s"):format(src, cost, expectedCost))
        return
    end
    
    if ownsCan then
        local wpnItem = exports.ox_inventory:GetCurrentWeapon(src)

        if not wpnItem or wpnItem.name ~= 'WEAPON_PETROLCAN' or not processPayment(src, cost) then 
            return 
        end

        if stationId and ownedStations and ownedStations[stationId] then
            local station = ownedStations[stationId]
            station.balance = station.balance + cost
            MySQL.query.await("UPDATE lns_fuel_stations SET balance = ? WHERE station_id = ?", { station.balance, stationId })
            TriggerClientEvent('LNS_Fuel:syncStation', -1, stationId, station)
        end

        wpnItem.metadata.durability = 100
        wpnItem.metadata.ammo = 100

        exports.ox_inventory:SetMetadata(src, wpnItem.slot, wpnItem.metadata)

        lib.logger(src, 'Jerry Can Transaction', ('Refilled Petrol Can for $%d at station %s'):format(cost, stationId or 'standard'), stationId and ('stationId:%s'):format(stationId) or nil, ('cost:$%d'):format(cost))

        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            description = locale('petrolcan_refill', cost)
        })
    else
        local canCarry = exports.ox_inventory:CanCarryItem(src, 'WEAPON_PETROLCAN', 1)
        if not canCarry then
            TriggerClientEvent('ox_lib:notify', src, {
                type = 'error',
                description = locale('petrolcan_cannot_carry')
            })
            return
        end

        if not processPayment(src, cost) then return end

        if stationId and ownedStations and ownedStations[stationId] then
            local station = ownedStations[stationId]
            station.balance = station.balance + cost
            MySQL.query.await("UPDATE lns_fuel_stations SET balance = ? WHERE station_id = ?", { station.balance, stationId })
            TriggerClientEvent('LNS_Fuel:syncStation', -1, stationId, station)
        end

        exports.ox_inventory:AddItem(src, 'WEAPON_PETROLCAN', 1)

        lib.logger(src, 'Jerry Can Transaction', ('Purchased new Petrol Can for $%d at station %s'):format(cost, stationId or 'standard'), stationId and ('stationId:%s'):format(stationId) or nil, ('cost:$%d'):format(cost))

        TriggerClientEvent('ox_lib:notify', src, {
            type = 'success',
            description = locale('petrolcan_buy', cost)
        })
    end
end)

RegisterNetEvent('LNS_Fuel:updateFuelCan', function(dura, nId, currentFuel)
    local src = source

    local validatedDura = validateNumber(dura)
    local validatedNId = validateInteger(nId)
    local validatedCurrentFuel = validateNumber(currentFuel)

    if not validatedDura or not validatedNId or not validatedCurrentFuel then
        reportSecurityCheck(src, ("[Security Check] Player %s sent invalid/NaN/inf updateFuelCan parameters! Dura: %s, NetId: %s, Fuel: %s"):format(
            src, tostring(dura), tostring(nId), tostring(currentFuel)
        ))
        return
    end

    dura = validatedDura
    currentFuel = validatedCurrentFuel

    if dura <= 0 or currentFuel < 0 or currentFuel > 100 then
        return
    end

    local vehicle = NetworkGetEntityFromNetworkId(validatedNId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then 
        return 
    end

    local playerPed = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(playerPed)
    local vehCoords = GetEntityCoords(vehicle)
    local distanceToVeh = #(playerCoords - vehCoords)

    if distanceToVeh > 15.0 then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:updateFuelCan too far from vehicle! Distance: %0.2f meters"):format(src, distanceToVeh))
        return
    end

    local wpnItem = exports.ox_inventory:GetCurrentWeapon(src)
    if not wpnItem or wpnItem.name ~= 'WEAPON_PETROLCAN' then
        reportSecurityCheck(src, ("[Security Check] Player %s triggered LNS_Fuel:updateFuelCan without a Petrol Can equipped!"):format(src))
        return
    end

    local vehState = Entity(vehicle)?.state
    local currentServerFuel = (vehState and vehState.fuel) or 0
    local fuelAdded = currentFuel - currentServerFuel

    if fuelAdded > 0 then
        local expectedDura = (fuelAdded / Settings.refillValue) * Settings.durabilityTick
        local minAllowedDura = (expectedDura * 0.9) - 1.0
        if dura < minAllowedDura then
            reportSecurityCheck(src, ("[Security Check] Player %s attempted LNS_Fuel:updateFuelCan with manipulated durability! Dura: %s, Expected Min: %0.2f, Fuel Added: %0.2f"):format(src, dura, minAllowedDura, fuelAdded))
            return
        end
    end

    local newDura = math.floor(wpnItem.metadata.durability - dura)
    if newDura < 0 then newDura = 0 end
    wpnItem.metadata.durability = newDura
    wpnItem.metadata.ammo = newDura

    exports.ox_inventory:SetMetadata(src, wpnItem.slot, wpnItem.metadata)
    applyFuelLevel(validatedNId, currentFuel)

    lib.logger(src, 'Jerry Can Refuel', ('Refueled vehicle (netId: %d) using Jerry Can. New fuel level: %d%%'):format(validatedNId, currentFuel), ('netId:%d'):format(validatedNId), ('newFuel:%d'):format(currentFuel))
end)

RegisterNetEvent('LNS_Fuel:initVehicleFuel', function(vehNetId, fuelLevel)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    
    local ped = GetPlayerPed(src)
    local playerCoords = GetEntityCoords(ped)
    local vehCoords = GetEntityCoords(vehicle)
    if #(playerCoords - vehCoords) > 15.0 then
        reportSecurityCheck(src, ("[Security Check] Player %s attempted LNS_Fuel:initVehicleFuel too far from vehicle! Distance: %0.2f meters"):format(src, #(playerCoords - vehCoords)))
        return
    end

    local state = Entity(vehicle).state
    if state.fuel == nil then
        local clamped = math.clamp(fuelLevel or 100.0, 0.0, 100.0)
        state:set('fuel', clamped, true)
    end
end)

RegisterNetEvent('LNS_Fuel:setVehicleFuel', function(vehNetId, fuelLevel)
    local src = source
    local vehicle = NetworkGetEntityFromNetworkId(vehNetId)
    if vehicle == 0 or not DoesEntityExist(vehicle) then return end
    
    local ped = GetPlayerPed(src)
    local vehSeat = GetVehiclePedIsIn(ped, false)
    if vehSeat ~= vehicle then
        local playerCoords = GetEntityCoords(ped)
        local vehCoords = GetEntityCoords(vehicle)
        if #(playerCoords - vehCoords) > 15.0 then
            reportSecurityCheck(src, ("[Security Check] Player %s attempted LNS_Fuel:setVehicleFuel too far from vehicle! Distance: %0.2f meters"):format(src, #(playerCoords - vehCoords)))
            return
        end
    end

    local state = Entity(vehicle).state
    local clamped = math.clamp(fuelLevel or 0.0, 0.0, 100.0)
    state:set('fuel', clamped, true)
end)

lib.addCommand('setfuel', {
    help = 'Set/lower the fuel level of the vehicle you are currently in',
    params = {
        { name = 'amount', type = 'number', help = 'Fuel level percentage (0-100)' }
    },
    restricted = 'group.admin'
}, function(source, args, raw)
    local ped = GetPlayerPed(source)
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 then
        return TriggerClientEvent('ox_lib:notify', source, {
            type = 'error',
            description = locale('must_be_inside_vehicle')
        })
    end

    local amount = math.clamp(args.amount or 0, 0, 100)
    
    local state = Entity(veh).state
    state:set('fuel', amount, true)
    TriggerClientEvent('LNS_Fuel:setFuel', source, amount)

    lib.logger(source, 'Set Fuel Admin Command', ('Admin set vehicle fuel level to %d%%'):format(amount), ('newFuel:%d'):format(amount))

    TriggerClientEvent('ox_lib:notify', source, {
        type = 'success',
        description = ('Vehicle fuel level set to %s%%'):format(amount)
    })
end)

CreateThread(function()
    local resource = GetCurrentResourceName()
    local currentVersion = GetResourceMetadata(resource, 'version', 0) or '1.0.0'
    
    PerformHttpRequest('https://raw.githubusercontent.com/LumaNodeStudios/LNS_Fuel/main/fxmanifest.lua', function(status, response, headers)
        if status ~= 200 then
            print('^3[' .. resource .. '] ^7Unable to check for updates (Status: ' .. status .. ')^0')
            return
        end
        
        local latestVersion = response:match("version%s+'([%d%.]+)'") or response:match('version%s+"([%d%.]+)"')
        
        if not latestVersion then
            print('^3[' .. resource .. '] ^7Unable to parse version from GitHub^0')
            return
        end
        
        if currentVersion ~= latestVersion then
            print('^0====================================^0')
            print('^3[' .. resource .. '] ^1Update Available!^0')
            print('^7Current Version: ^3' .. currentVersion .. '^0')
            print('^7Latest Version: ^2' .. latestVersion .. '^0')
            print('^7Download: ^5https://github.com/LumaNodeStudios/LNS_Fuel^0')
            print('^0====================================^0')
        else
            lib.print.info('^7You are running the latest version (^2' .. currentVersion .. '^7)^0')
        end
    end, 'GET')
end)

local function registerCompatibilityExport(resourceName, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(resourceName, exportName), function(setCB)
        setCB(func)
    end)
end

local function GetFuel(vehicle)
    if not DoesEntityExist(vehicle) then return 0.0 end
    local state = Entity(vehicle).state
    return state.fuel or (GetVehicleFuelLevel and GetVehicleFuelLevel(vehicle)) or 0.0
end

local function SetFuel(vehicle, amount)
    if not DoesEntityExist(vehicle) then return end
    amount = tonumber(amount)
    if not amount then return end
    amount = math.clamp(amount, 0.0, 100.0)

    local state = Entity(vehicle).state
    state:set('fuel', amount, true)

    if SetVehicleFuelLevel then
        SetVehicleFuelLevel(vehicle, amount)
    end
end

exports('GetFuel', GetFuel)
exports('SetFuel', SetFuel)
exports('getFuel', GetFuel)
exports('setFuel', SetFuel)

local legacyResources = { 'ox_fuel', 'cdn-fuel', 'LegacyFuel' }
for _, res in ipairs(legacyResources) do
    registerCompatibilityExport(res, 'GetFuel', GetFuel)
    registerCompatibilityExport(res, 'SetFuel', SetFuel)
    registerCompatibilityExport(res, 'getFuel', GetFuel)
    registerCompatibilityExport(res, 'setFuel', SetFuel)
end