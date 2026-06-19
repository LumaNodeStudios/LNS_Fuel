local Settings = lib.load('shared.settings')
local st = require('client.cl_state')
local hlpr = require('client.cl_utils')
local isStrictMode = GetConvar('sv_stateBagStrictMode', 'false') == 'true'

local spawnedNozzleProp = nil
local spawnedRope = nil
local grabbedCoords = nil

local function getPumpTypeNearPlayer()
    local plyCoords = GetEntityCoords(cache.ped)
    local closestPumpDist = 99999.0
    local isElectric = false

    if Settings.pumpModels then
        for i = 1, #Settings.pumpModels do
            local model = Settings.pumpModels[i]
            local entity = GetClosestObjectOfType(plyCoords.x, plyCoords.y, plyCoords.z, 3.0, model, false, false, false)
            if entity and entity ~= 0 then
                local dist = #(plyCoords - GetEntityCoords(entity))
                if dist < closestPumpDist then
                    closestPumpDist = dist
                    isElectric = false
                end
            end
        end
    end

    local chargerModels = Settings.electricPumpModels or { `electric_charger` }
    for i = 1, #chargerModels do
        local model = chargerModels[i]
        local entity = GetClosestObjectOfType(plyCoords.x, plyCoords.y, plyCoords.z, 3.0, model, false, false, false)
        if entity and entity ~= 0 then
            local dist = #(plyCoords - GetEntityCoords(entity))
            if dist < closestPumpDist then
                closestPumpDist = dist
                isElectric = true
            end
        end
    end

    return isElectric, closestPumpDist
end

local fuelModule = {}

function fuelModule.setFuel(stateBag, veh, amt, sync)
    if not DoesEntityExist(veh) then return end
    
    local safeAmt = math.clamp(amt, 0, 100)
    SetVehicleFuelLevel(veh, safeAmt)
    
    if sync and isStrictMode then
        stateBag:set('fuel', safeAmt, false)
        TriggerServerEvent('LNS_Fuel:setVehicleFuel', NetworkGetNetworkIdFromEntity(veh), safeAmt)
    else
        stateBag:set('fuel', safeAmt, sync)
    end
end

local cl_ownership = Settings.ownership and Settings.ownership.enabled and require('client.cl_ownership') or nil

local function GetStationId(coords)
    return string.format("station_%.2f_%.2f", coords.x, coords.y)
end

function fuelModule.getPetrolCan(pos, isRefilling)
    local playerPed = cache.ped
    TaskTurnPedToFaceCoord(playerPed, pos.x, pos.y, pos.z, Settings.petrolCan.duration)
    Wait(500)

    local success = hlpr.progress({
        duration = Settings.petrolCan.duration,
        label = locale('petrolcan_buy_or_refill'),
        useWhileDead = false,
        canCancel = true,
        disable = {
            move = true,
            car = true,
            combat = true,
        },
        anim = {
            dict = 'timetable@gardener@filling_can',
            clip = 'gar_ig_5_filling_can',
            flags = 49,
        }
    })

    local stationId = nil
    if cl_ownership then
        local plyCoords = GetEntityCoords(playerPed)
        for sId, data in pairs(cl_ownership.ownedStations) do
            local sConf = nil
            for i = 1, #Settings.Stations do
                if GetStationId(Settings.Stations[i].blip) == sId then
                    sConf = Settings.Stations[i]
                    break
                end
            end

            if sConf then
                for _, pump in ipairs(sConf.pumps) do
                    if #(plyCoords - pump) < 5.0 then
                        stationId = sId
                        break
                    end
                end
            end
            if stationId then break end
        end
    end

    if success then
        if isRefilling and exports.ox_inventory:GetItemCount('WEAPON_PETROLCAN') > 0 then
            TriggerServerEvent('LNS_Fuel:fuelCan', true, Settings.petrolCan.refillPrice, stationId)
        else
            TriggerServerEvent('LNS_Fuel:fuelCan', false, Settings.petrolCan.price, stationId)
        end
    end

    ClearPedTasks(playerPed)
end

function fuelModule.startFueling(veh, usingPump)
    local vState = Entity(veh).state
    local currentLevel = vState.fuel or GetVehicleFuelLevel(veh)
    local isElectricVeh = isVehicleElectric(veh)
    
    local missing = 100.0 - currentLevel
    if missing < Settings.refillValue then
        local errorMsg = isElectricVeh and (locale('battery_full') or "The battery of this vehicle is already fully charged!") or locale('tank_full')
        lib.notify({ type = 'error', description = errorMsg })
        return
    end

    local isElectricPump = false
    if usingPump then
        local isPumpElec, dist = getPumpTypeNearPlayer()
        if dist < 4.0 then
            isElectricPump = isPumpElec
        end

        if isElectricVeh and not isElectricPump then
            lib.notify({ type = 'error', description = locale('electric_vehicle_gas_pump') or "This vehicle is electric! You must use a charging station." })
            return
        end
        if not isElectricVeh and isElectricPump then
            lib.notify({ type = 'error', description = locale('not_electric_vehicle') or "This vehicle is not electric! You must use a gas station." })
            return
        end
    else
        if isElectricVeh then
            lib.notify({ type = 'error', description = locale('electric_vehicle_no_jerrycan') or "You cannot charge an electric vehicle with a petrol can!" })
            return
        end
    end

    local stationId = nil
    local isStationOwned = false
    local stationData = nil
    local pricePerTick = isElectricVeh and (Settings.electricPriceTick or 2) or Settings.priceTick
    local stationName = isElectricVeh and "Public Charging Station" or "Public Gas Station"

    if usingPump and cl_ownership then
        local plyCoords = GetEntityCoords(cache.ped)
        for sId, data in pairs(cl_ownership.ownedStations) do
            local sConf = nil
            for i = 1, #Settings.Stations do
                if GetStationId(Settings.Stations[i].blip) == sId then
                    sConf = Settings.Stations[i]
                    break
                end
            end

            if sConf then
                if sConf.pumps then
                    for _, pump in ipairs(sConf.pumps) do
                        if #(plyCoords - pump) < 5.0 then
                            stationId = sId
                            stationData = data
                            break
                        end
                    end
                end
                if not stationId and sConf.electricpumps then
                    for _, pump in ipairs(sConf.electricpumps) do
                        local rawCoords = type(pump) == "table" and pump.coords or pump
                        local coords = type(rawCoords) == "table" and vec3(rawCoords.x or rawCoords[1], rawCoords.y or rawCoords[2], rawCoords.z or rawCoords[3]) or rawCoords
                        if type(coords) == "vector4" then
                            coords = vec3(coords.x, coords.y, coords.z)
                        end
                        if #(plyCoords - coords) < 5.0 then
                            stationId = sId
                            stationData = data
                            break
                        end
                    end
                end
                if not stationId and data.electric_chargers then
                    for _, pump in ipairs(data.electric_chargers) do
                        local rawCoords = type(pump) == "table" and pump.coords or pump
                        local coords = type(rawCoords) == "table" and vec3(rawCoords.x or rawCoords[1], rawCoords.y or rawCoords[2], rawCoords.z or rawCoords[3]) or rawCoords
                        if type(coords) == "vector4" then
                            coords = vec3(coords.x, coords.y, coords.z)
                        end
                        if #(plyCoords - coords) < 5.0 then
                            stationId = sId
                            stationData = data
                            break
                        end
                    end
                end
            end
            if stationId then break end
        end

        if stationId and stationData and stationData.owner then
            isStationOwned = true
            if isElectricVeh then
                pricePerTick = stationData.electricPrice or Settings.ownership.defaultElectricPrice or 2
            else
                pricePerTick = stationData.price or Settings.priceTick
            end
            stationName = stationData.name or (isElectricVeh and "Charging Station" or "Gas Station")

            if not isElectricVeh and stationData.stock <= 0 then
                lib.notify({ type = 'error', description = locale('notify_station_out_of_fuel') })
                return
            end
        end
    end

    if usingPump then
        local playerMoney = hlpr.getMoney()
        local costPerLiter = 0
        if isStationOwned then
            costPerLiter = pricePerTick
        else
            costPerLiter = pricePerTick / Settings.refillValue
        end
        
        local model = GetEntityModel(veh)
        local displayModel = GetDisplayNameFromVehicleModel(model)
        local vehicleLabel = GetLabelText(displayModel)
        if vehicleLabel == "CARNOTFOUND" then
            vehicleLabel = displayModel
        end

        local p = promise.new()
        st.activePumpPromise = p

        local currentLocales = hlpr.getLocaleData()
        if isElectricVeh then
            currentLocales["pump_btn_begin_refueling"] = "Begin Charging"
            currentLocales["progress_refueling"] = "Charging vehicle..."
            currentLocales["pump_tank_already_full"] = "Vehicle battery is already fully charged!"
            currentLocales["tank_full"] = "The battery of this vehicle is fully charged"
            currentLocales["pump_current_level"] = "Current Charge: %s%"
            currentLocales["pump_liters_presets"] = "kWh Presets"
            currentLocales["pump_custom_liters"] = "Custom kWh"
            currentLocales["pump_volume_to_pump"] = "Energy to Charge"
            currentLocales["pump_total_cost"] = "Total Cost"
            currentLocales["pump_unit_price"] = "Price per kWh"
            currentLocales["fuel_success"] = "Charged to %s%% - $%s"
        end

        SetNuiFocus(true, true)
        SendNUIMessage({
            action = "openPumpUI",
            data = {
                stationName = stationName,
                pricePerLiter = costPerLiter,
                currentFuel = math.floor(currentLevel),
                playerMoney = playerMoney,
                stockLeft = isElectricVeh and 99999 or (isStationOwned and stationData.stock or 99999),
                vehicleName = vehicleLabel,
                isOwned = isStationOwned,
                theme = Settings.theme,
                isElectric = isElectricVeh
            },
            locales = currentLocales
        })

        local selectedLiters = Citizen.Await(p)
        st.activePumpPromise = nil

        if not selectedLiters or selectedLiters <= 0 then
            return
        end

        local maxAffordable = playerMoney / costPerLiter
        local maxNeeded = 100.0 - currentLevel
        local maxAvailable = isElectricVeh and 99999 or (isStationOwned and stationData.stock or 99999)

        local litersToPump = math.min(selectedLiters, maxAffordable, maxNeeded, maxAvailable)
        if litersToPump <= 0 then return end

        local fillDuration = math.ceil(litersToPump / Settings.refillValue) * Settings.refillTick
        local costTotal = litersToPump * costPerLiter

        st.isFueling = true
        local playerPed = cache.ped

        TaskTurnPedToFaceEntity(playerPed, veh, fillDuration)
        Wait(500)

        CreateThread(function()
            local animDict = 'timetable@gardener@filling_can'
            local animClip = 'gar_ig_5_filling_can'
            local propModel = isElectricVeh and 'electric_nozzle' or 'prop_cs_fuel_nozle'
            local propData = {
                model = propModel,
                bone = 18905,
                pos = vec3(0.1, 0.02, 0.02),
                rot = vec3(90.0, 40.0, 170.0),
                rotOrder = 1,
            }
            if st.holdingNozzle or st.holdingElectricNozzle then
                propData = nil
            end

            local progressLabel = isElectricVeh and (locale('progress_charging') or "Charging vehicle...") or locale('progress_refueling')
            hlpr.progress({
                duration = fillDuration,
                label = progressLabel,
                useWhileDead = false,
                canCancel = true,
                disable = {
                    move = true,
                    car = true,
                    combat = true,
                },
                anim = {
                    dict = animDict,
                    clip = animClip,
                },
                prop = propData,
            })

            st.isFueling = false
        end)

        local currentPumped = 0
        while st.isFueling do
            currentPumped = currentPumped + Settings.refillValue
            if currentPumped >= litersToPump and lib.progressActive() then
                lib.cancelProgress()
                break
            end
            Wait(Settings.refillTick)
        end

        ClearPedTasks(playerPed)

        local actualLiters = math.min(currentPumped, litersToPump)
        local finalLevel = math.min(100.0, currentLevel + actualLiters)
        local finalCost = math.ceil(actualLiters * costPerLiter)

        if actualLiters > 0 then
            local vehNetId = NetworkGetNetworkIdFromEntity(veh)
            TriggerServerEvent('LNS_Fuel:pay', finalCost, finalLevel, vehNetId, stationId, actualLiters)
        end
    else
        if not st.petrolCan then
            lib.notify({ type = 'error', description = locale('petrolcan_not_equipped') })
            return
        end
        if st.petrolCan.metadata.ammo <= Settings.durabilityTick then
            lib.notify({
                type = 'error',
                description = locale('petrolcan_not_enough_fuel')
            })
            return
        end

        st.isFueling = true
        local playerPed = cache.ped

        local fillDuration = math.ceil(missing / Settings.refillValue) * Settings.refillTick
        TaskTurnPedToFaceEntity(playerPed, veh, fillDuration)
        Wait(500)

        CreateThread(function()
            hlpr.progress({
                duration = fillDuration,
                label = locale('progress_refueling'),
                useWhileDead = false,
                canCancel = true,
                disable = {
                    move = true,
                    car = true,
                    combat = true,
                },
                anim = {
                    dict = 'weapon@w_sp_jerrycan',
                    clip = 'fire',
                },
            })

            st.isFueling = false
        end)

        local canDegradation = 0
        while st.isFueling do
            canDegradation = canDegradation + Settings.durabilityTick

            if canDegradation >= st.petrolCan.metadata.ammo then
                lib.cancelProgress()
                canDegradation = st.petrolCan.metadata.ammo
                break
            end

            currentLevel = currentLevel + Settings.refillValue

            if currentLevel >= 100.0 then
                st.isFueling = false
                currentLevel = 100.0
            end

            Wait(Settings.refillTick)
        end

        ClearPedTasks(playerPed)

        local vehNetId = NetworkGetNetworkIdFromEntity(veh)
        TriggerServerEvent('LNS_Fuel:updateFuelCan', canDegradation, vehNetId, currentLevel)
    end
end

RegisterNUICallback('startRefueling', function(data, cb)
    SetNuiFocus(false, false)
    if st.activePumpPromise then
        st.activePumpPromise:resolve(data.liters)
    end
    cb('ok')
end)

RegisterNUICallback('closePumpUI', function(data, cb)
    SetNuiFocus(false, false)
    if st.activePumpPromise then
        st.activePumpPromise:resolve(nil)
    end
    cb('ok')
end)

local function GetClosestPump(coords, isElectric)
    local models = isElectric and (Settings.electricPumpModels or { `electric_charger` }) or Settings.pumpModels
    local closestPump, closestDist = nil, 99999.0
    for i = 1, #models do
        local model = models[i]
        local entity = GetClosestObjectOfType(coords.x, coords.y, coords.z, 3.0, model, false, false, false)
        if entity and entity ~= 0 then
            local dist = #(coords - GetEntityCoords(entity))
            if dist < closestDist then
                closestDist = dist
                closestPump = entity
            end
        end
    end
    return closestPump and GetEntityCoords(closestPump) or nil, closestPump
end

local function playNozzleEquipAnimation(playerPed)
    lib.playAnim(playerPed, "anim@am_hold_up@male", "shoplift_high", 1.0, 7.0, 300, 50)
    Wait(300)
    RemoveAnimDict("anim@am_hold_up@male")
end

local function spawnAndAttachNozzleProp(playerPed, isElectricType)
    local modelHash = isElectricType and `electric_nozzle` or `prop_cs_fuel_nozle`
    lib.requestModel(modelHash)
    local nozzleProp = CreateObject(modelHash, 1.0, 1.0, 1.0, true, true, false)
    SetModelAsNoLongerNeeded(modelHash)
    
    local leftHandBone = GetPedBoneIndex(playerPed, 18905)
    if isElectricType then
        AttachEntityToEntity(nozzleProp, playerPed, leftHandBone, 0.24, 0.10, -0.052, -45.0, 120.0, 75.0, 0, 1, 0, 1, 0, 1)
    else
        AttachEntityToEntity(nozzleProp, playerPed, leftHandBone, 0.13, 0.04, 0.01, -42.0, -115.0, -63.42, 0, 1, 0, 1, 0, 1)
    end
    return nozzleProp
end

local function setupHosePhysicalRope(pumpObj, pumpCoords, nozzleProp, isElectricType)
    RopeLoadTextures()
    while not RopeAreTexturesLoaded() do
        Wait(0)
        RopeLoadTextures()
    end
    
    local ropeStyle = isElectricType and (Settings.ropeType.electric or 4) or (Settings.ropeType.fuel or 3)
    local anchorHeight = isElectricType and 1.76 or 2.1
    
    local createdRope = AddRope(pumpCoords.x, pumpCoords.y, pumpCoords.z, 0.0, 0.0, 0.0, 3.0, ropeStyle, 8.0, 0.0, 1.0, false, false, false, 1.0, true)
    while not createdRope do
        Wait(0)
    end
    
    ActivatePhysics(createdRope)
    Wait(100)
    
    local offsetNozzle = GetOffsetFromEntityInWorldCoords(nozzleProp, isElectricType and -0.005 or 0.0, isElectricType and 0.185 or -0.033, isElectricType and -0.05 or -0.195)
    AttachEntitiesToRope(createdRope, pumpObj, nozzleProp, pumpCoords.x, pumpCoords.y, pumpCoords.z + anchorHeight, offsetNozzle.x, offsetNozzle.y, offsetNozzle.z, 8.0, false, false, nil, nil)
    
    return createdRope
end

function fuelModule.grabNozzle(pumpEntity, isElectric)
    local ped = cache.ped
    if st.holdingNozzle or st.holdingElectricNozzle then return end

    playNozzleEquipAnimation(ped)
    spawnedNozzleProp = spawnAndAttachNozzleProp(ped, isElectric)
    grabbedCoords = GetEntityCoords(ped)

    if Settings.pumpHose then
        local pumpCoords, pump = GetClosestPump(grabbedCoords, isElectric)
        if not pump or pump == 0 then
            pump = pumpEntity
            pumpCoords = pump and GetEntityCoords(pump) or grabbedCoords
        end

        if pump and pump ~= 0 then
            spawnedRope = setupHosePhysicalRope(pump, pumpCoords, spawnedNozzleProp, isElectric)
        end
    end

    if isElectric then
        st.holdingElectricNozzle = true
    else
        st.holdingNozzle = true
    end

    CreateThread(function()
        local maxRange = Settings.nozzleLength or 7.5
        while st.holdingNozzle or st.holdingElectricNozzle do
            local currentCoords = GetEntityCoords(cache.ped)
            local currentDist = #(grabbedCoords - currentCoords)
            if currentDist > maxRange or cache.vehicle then
                fuelModule.returnNozzle()
                lib.notify({ type = 'error', description = locale('nozzle_cannot_reach') or "The hose cannot reach this far!" })
                break
            end
            Wait(1000)
        end
    end)
end

function fuelModule.returnNozzle()
    if not (st.holdingNozzle or st.holdingElectricNozzle) then return end
    st.holdingNozzle = false
    st.holdingElectricNozzle = false
    grabbedCoords = nil

    local ped = cache.ped
    playNozzleEquipAnimation(ped)

    if DoesEntityExist(spawnedNozzleProp) then
        DeleteEntity(spawnedNozzleProp)
        spawnedNozzleProp = nil
    end

    if spawnedRope then
        RopeUnloadTextures()
        DeleteRope(spawnedRope)
        spawnedRope = nil
    end
end

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then
        if DoesEntityExist(spawnedNozzleProp) then
            DeleteEntity(spawnedNozzleProp)
        end
        if spawnedRope then
            RopeUnloadTextures()
            DeleteRope(spawnedRope)
        end
    end
end)

return fuelModule