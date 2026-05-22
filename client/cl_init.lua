local Settings = lib.load('shared.settings')

if not Settings then return end

local function GetVehicleFuelConsumptionRate(veh)
    if not DoesEntityExist(veh) then return Settings.globalFuelConsumptionRate or 10.0 end

    local modelHash = GetEntityModel(veh)
    if Settings.vehicleModelFuelRates then
        if Settings.vehicleModelFuelRates[modelHash] then
            return Settings.vehicleModelFuelRates[modelHash]
        end
        for modelKey, rate in pairs(Settings.vehicleModelFuelRates) do
            if type(modelKey) == "string" and GetHashKey(modelKey) == modelHash then
                return rate
            end
        end
    end

    local vehClass = GetVehicleClass(veh)
    if Settings.vehicleClassFuelRates and Settings.vehicleClassFuelRates[vehClass] then
        return Settings.vehicleClassFuelRates[vehClass]
    end

    return Settings.globalFuelConsumptionRate or 10.0
end

SetFuelConsumptionState(true)
local startVeh = GetVehiclePedIsIn(PlayerPedId(), false)
SetFuelConsumptionRateMultiplier(startVeh ~= 0 and GetVehicleFuelConsumptionRate(startVeh) or Settings.globalFuelConsumptionRate)

AddTextEntry('lns_fuel_station', locale('fuel_station_blip'))

local hlpr = require('client.cl_utils')
local st = require('client.cl_state')
local fuelMod  = require('client.cl_fuel')

require('client.cl_stations')
require('client.cl_delivery')

local function handleVehicleDriving()
    local veh = cache.vehicle

    if not DoesVehicleUseFuel(veh) then return end

    local vehStateBag = Entity(veh).state

    if vehStateBag.fuel == nil then
        vehStateBag:set('fuel', GetVehicleFuelLevel(veh), true)
        while vehStateBag.fuel == nil do Wait(0) end
    end

    SetVehicleFuelLevel(veh, vehStateBag.fuel)

    local tickCounter = 0

    while cache.seat == -1 do
        if GetIsVehicleEngineRunning(veh) then
            if not DoesEntityExist(veh) then return end
            SetFuelConsumptionRateMultiplier(GetVehicleFuelConsumptionRate(veh))

            local currentSavedFuel = tonumber(vehStateBag.fuel)
            local actualFuel = GetVehicleFuelLevel(veh)
            
            if currentSavedFuel > 0 then
                if GetVehiclePetrolTankHealth(veh) < 700 then
                    actualFuel = actualFuel - (math.random(10, 20) * 0.01)
                end

                if currentSavedFuel ~= actualFuel then
                    if tickCounter == 15 then
                        tickCounter = 0
                    end

                    local shouldReplicate = (tickCounter == 0)
                    fuelMod.setFuel(vehStateBag, veh, actualFuel, shouldReplicate)
                    tickCounter = tickCounter + 1
                end
            end
        else
            if not DoesEntityExist(veh) then return end
            SetFuelConsumptionRateMultiplier(0.0)
        end
        Wait(1000)
    end

    fuelMod.setFuel(vehStateBag, veh, vehStateBag.fuel, true)
end

if cache.seat == -1 then CreateThread(handleVehicleDriving) end

lib.onCache('seat', function(newSeat)
    if cache.vehicle then
        st.lastVehicle = cache.vehicle
    end

    if newSeat == -1 then
        SetTimeout(0, handleVehicleDriving)
    end
end)

RegisterNetEvent('LNS_Fuel:setFuel', function(amt)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    
    if veh and veh ~= 0 then
        local vehStateBag = Entity(veh).state
        fuelMod.setFuel(vehStateBag, veh, amt, true)
    end
end)

local function registerCompatibilityExport(resourceName, exportName, func)
    AddEventHandler(('__cfx_export_%s_%s'):format(resourceName, exportName), function(setCB)
        setCB(func)
    end)
end

local function GetFuel(vehicle)
    if not DoesEntityExist(vehicle) then return 0.0 end
    local state = Entity(vehicle).state
    return state.fuel or GetVehicleFuelLevel(vehicle)
end

local function SetFuel(vehicle, amount)
    if not DoesEntityExist(vehicle) then return end
    amount = tonumber(amount)
    if not amount then return end
    
    local state = Entity(vehicle).state
    fuelMod.setFuel(state, vehicle, amount, true)
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

RegisterCommand('testoxfuel', function(source, args)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        lib.notify({ type = 'error', description = 'Must be in a vehicle!' })
        return
    end

    local setAmount = tonumber(args[1])
    if setAmount then
        Entity(veh).state.fuel = setAmount
        lib.notify({ type = 'info', description = ('ox_fuel: Set fuel to %.1f%%'):format(setAmount) })
    end

    Wait(100)
    local fuel = Entity(veh).state.fuel
    lib.notify({ type = 'success', description = ('ox_fuel: Current fuel is %.1f%%'):format(fuel) })
end, false)

RegisterCommand('testcdnfuel', function(source, args)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        lib.notify({ type = 'error', description = 'Must be in a vehicle!' })
        return
    end

    local setAmount = tonumber(args[1])
    if setAmount then
        exports['cdn-fuel']:SetFuel(veh, setAmount)
        lib.notify({ type = 'info', description = ('cdn-fuel: Set fuel to %.1f%%'):format(setAmount) })
    end

    Wait(100)
    local fuel = exports['cdn-fuel']:GetFuel(veh)
    lib.notify({ type = 'success', description = ('cdn-fuel: Current fuel is %.1f%%'):format(fuel) })
end, false)

RegisterCommand('testlegacyfuel', function(source, args)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if not veh or veh == 0 then
        lib.notify({ type = 'error', description = 'Must be in a vehicle!' })
        return
    end

    local setAmount = tonumber(args[1])
    if setAmount then
        exports['LegacyFuel']:SetFuel(veh, setAmount)
        lib.notify({ type = 'info', description = ('LegacyFuel: Set fuel to %.1f%%'):format(setAmount) })
    end

    Wait(100)
    local fuel = exports['LegacyFuel']:GetFuel(veh)
    lib.notify({ type = 'success', description = ('LegacyFuel: Current fuel is %.1f%%'):format(fuel) })
end, false)

if Settings.ox_target then 
    require('client.cl_target')
    return 
end

RegisterCommand('startfueling', function()
    if st.isFueling or cache.vehicle or lib.progressActive() then return end

    local hasCan = Settings.petrolCan.enabled and GetSelectedPedWeapon(cache.ped) == `WEAPON_PETROLCAN`
    local plyCoords = GetEntityCoords(cache.ped)
    local nearPump = st.nearestPump

    if nearPump then
        local bal = hlpr.getMoney()

        if hasCan and bal >= Settings.petrolCan.refillPrice then
            return fuelMod.getPetrolCan(nearPump, true)
        end

        local isVehNear = st.lastVehicle and #(GetEntityCoords(st.lastVehicle) - plyCoords) <= 3

        if not isVehNear then
            if not Settings.petrolCan.enabled then return end

            if bal >= Settings.petrolCan.price then
                return fuelMod.getPetrolCan(nearPump)
            end

            return lib.notify({ type = 'error', description = locale('petrolcan_cannot_afford') })
        elseif bal >= Settings.priceTick then
            return fuelMod.startFueling(st.lastVehicle, true)
        else
            return lib.notify({ type = 'error', description = locale('refuel_cannot_afford') })
        end

        return lib.notify({ type = 'error', description = locale('vehicle_far') })
    elseif hasCan then
        local targetVeh = hlpr.getVehicleInFront()

        if targetVeh and DoesVehicleUseFuel(targetVeh) then
            local capBoneIdx = hlpr.getVehiclePetrolCapBoneIndex(targetVeh)
            local capPos = capBoneIdx and GetWorldPositionOfEntityBone(targetVeh, capBoneIdx)

            if capPos and #(plyCoords - capPos) < 1.8 then
                return fuelMod.startFueling(targetVeh, false)
            end

            return lib.notify({ type = 'error', description = locale('vehicle_far') })
        end
    end
end)

RegisterKeyMapping('startfueling', 'Fuel vehicle', 'keyboard', 'e')
TriggerEvent('chat:removeSuggestion', '/startfueling')