local Settings = lib.load('shared.settings')
if not Settings or not Settings.ownership or not Settings.ownership.enabled then return end

local hlpr = require('client.cl_utils')
local activeJob = nil

local isDeliveryUIShown = false

local function showDeliveryUI(text, options)
    lib.showTextUI(text, options)
    isDeliveryUIShown = true
end

local function hideDeliveryUI()
    if isDeliveryUIShown then
        lib.hideTextUI()
        isDeliveryUIShown = false
    end
end

local function LoadModel(modelHash)
    if not IsModelInCdimage(modelHash) then return false end
    lib.requestModel(modelHash)
    while not HasModelLoaded(modelHash) do
        Wait(0)
    end
    return true
end

local function CleanUpJob()
    if activeJob then
        TriggerServerEvent('LNS_Fuel:abortDelivery')
        if activeJob.truckBlip and DoesBlipExist(activeJob.truckBlip) then RemoveBlip(activeJob.truckBlip) end
        if activeJob.trailerBlip and DoesBlipExist(activeJob.trailerBlip) then RemoveBlip(activeJob.trailerBlip) end
        if activeJob.destBlip and DoesBlipExist(activeJob.destBlip) then RemoveBlip(activeJob.destBlip) end
        if activeJob.returnBlip and DoesBlipExist(activeJob.returnBlip) then RemoveBlip(activeJob.returnBlip) end
        activeJob = nil
    end
    hideDeliveryUI()
end

local function SpawnJobVehicles()
    local deliveryConf = Settings.ownership.delivery
    local truckModel = deliveryConf.truckModel
    local trailerModel = deliveryConf.trailerModel

    if not LoadModel(truckModel) then
        CleanUpJob()
        return lib.notify({ type = 'error', description = locale('notify_failed_truck_model') })
    end
    if not LoadModel(trailerModel) then
        CleanUpJob()
        return lib.notify({ type = 'error', description = locale('notify_failed_trailer_model') })
    end

    local truckPos = deliveryConf.truckSpawn
    local trailerPos = deliveryConf.trailerSpawn

    local truck, trailer
    if Settings.spawnType == 'server' then
        local spawned = lib.callback.await('LNS_Fuel:spawnDeliveryVehicles', false)
        if not activeJob then
            return
        end
        if not spawned then
            CleanUpJob()
            return lib.notify({ type = 'error', description = locale('notify_failed_spawn_server') })
        end

        activeJob.truckNetId = spawned.truckNetId
        activeJob.trailerNetId = spawned.trailerNetId
        
        truck = nil
        trailer = nil
    else
        truck = CreateVehicle(truckModel, truckPos.x, truckPos.y, truckPos.z, truckPos.w, true, false)
        SetVehicleHasBeenOwnedByPlayer(truck, true)
        SetEntityAsMissionEntity(truck, true, true)
        
        trailer = CreateVehicle(trailerModel, trailerPos.x, trailerPos.y, trailerPos.z, trailerPos.w, true, false)
        SetEntityAsMissionEntity(trailer, true, true)
    end

    SetModelAsNoLongerNeeded(truckModel)
    SetModelAsNoLongerNeeded(trailerModel)

    if not activeJob then
        return
    end

    activeJob.truck = truck
    activeJob.trailer = trailer
    activeJob.state = 'tow'

    if Settings.spawnType == 'client' then
        local timeout = 100
        local isNetworked = NetworkGetEntityIsNetworked(truck)
        while not isNetworked and timeout > 0 do
            Wait(10)
            isNetworked = NetworkGetEntityIsNetworked(truck)
            timeout = timeout - 1
        end

        if not activeJob then
            return
        end

        local truckNetId = NetworkGetNetworkIdFromEntity(truck)
        local plate = GetVehicleNumberPlateText(truck)
        TriggerServerEvent('LNS_Fuel:giveDeliveryKeys', plate, truckNetId)
    end

    if activeJob.truckBlip and DoesBlipExist(activeJob.truckBlip) then
        RemoveBlip(activeJob.truckBlip)
    end
    activeJob.truckBlip = AddBlipForCoord(truckPos.x, truckPos.y, truckPos.z)
    SetBlipSprite(activeJob.truckBlip, 477)
    SetBlipColour(activeJob.truckBlip, 5)
    SetBlipScale(activeJob.truckBlip, 0.9)
    SetBlipRoute(activeJob.truckBlip, true)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Retrieval Truck")
    EndTextCommandSetBlipName(activeJob.truckBlip)

    if activeJob.trailerBlip and DoesBlipExist(activeJob.trailerBlip) then
        RemoveBlip(activeJob.trailerBlip)
    end
    activeJob.trailerBlip = AddBlipForCoord(trailerPos.x, trailerPos.y, trailerPos.z)
    SetBlipSprite(activeJob.trailerBlip, 479)
    SetBlipColour(activeJob.trailerBlip, 18)
    SetBlipScale(activeJob.trailerBlip, 0.9)
    BeginTextCommandSetBlipName("STRING")
    AddTextComponentString("Fuel Trailer")
    EndTextCommandSetBlipName(activeJob.trailerBlip)

    activeJob.spawning = false
end

local function UnloadFuel()
    if not activeJob or activeJob.state ~= 'deliver' then return end

    FreezeEntityPosition(activeJob.truck, true)

    local success = hlpr.progress({
        duration = 8000,
        label = locale('progress_unload_fuel'),
        useLibClip = true,
        disable = {
            car = true,
            move = true,
            combat = true
        }
    })

    FreezeEntityPosition(activeJob.truck, false)

    if success then
        if activeJob.trailer and DoesEntityExist(activeJob.trailer) then
            DeleteVehicle(activeJob.trailer)
            activeJob.trailer = nil
        end

        TriggerServerEvent('LNS_Fuel:completeDelivery', activeJob.stationId)

        if activeJob.destBlip and DoesBlipExist(activeJob.destBlip) then
            RemoveBlip(activeJob.destBlip)
            activeJob.destBlip = nil
        end

        local retCoords = Settings.ownership.delivery.returnCoords
        activeJob.returnBlip = AddBlipForCoord(retCoords.x, retCoords.y, retCoords.z)
        SetBlipSprite(activeJob.returnBlip, 50)
        SetBlipColour(activeJob.returnBlip, 1)
        SetBlipScale(activeJob.returnBlip, 0.9)
        SetBlipRoute(activeJob.returnBlip, true)
        BeginTextCommandSetBlipName("STRING")
        AddTextComponentString("Depot Return")
        EndTextCommandSetBlipName(activeJob.returnBlip)

        activeJob.state = 'return'
    else
        lib.notify({ type = 'error', description = locale('notify_unloading_cancelled') })
    end
end

local function ReturnTruck()
    if not activeJob or activeJob.state ~= 'return' then return end

    if activeJob.truck and DoesEntityExist(activeJob.truck) then
        DeleteVehicle(activeJob.truck)
    end
    CleanUpJob()
    lib.notify({ type = 'success', description = locale('notify_delivery_completed') })
end

RegisterNetEvent('LNS_Fuel:startDelivery', function(stationId, amount, coords)
    if activeJob then return end

    activeJob = {
        stationId = stationId,
        amount = amount,
        coords = coords,
        state = 'tow',
        truck = nil,
        trailer = nil,
        truckCollected = false,
        truckBlip = nil,
        trailerBlip = nil,
        spawning = true
    }

    SpawnJobVehicles()
end)

RegisterCommand('canceldelivery', function()
    if activeJob then
        if activeJob.truck and DoesEntityExist(activeJob.truck) then
            DeleteVehicle(activeJob.truck)
        end
        if activeJob.trailer and DoesEntityExist(activeJob.trailer) then
            DeleteVehicle(activeJob.trailer)
        end
        CleanUpJob()
        lib.notify({ type = 'info', description = locale('notify_delivery_cancelled') })
    else
        lib.notify({ type = 'error', description = locale('notify_no_active_delivery') })
    end
end, false)

CreateThread(function()
    while true do
        Wait(1000)
        if activeJob and not activeJob.spawning then
            if not activeJob.truck and activeJob.truckNetId then
                if NetworkDoesNetworkIdExist(activeJob.truckNetId) then
                    local tempTruck = NetToVeh(activeJob.truckNetId)
                    if tempTruck ~= 0 and DoesEntityExist(tempTruck) then
                        activeJob.truck = tempTruck
                        SetVehicleHasBeenOwnedByPlayer(tempTruck, true)
                        SetEntityAsMissionEntity(tempTruck, true, true)
                        
                        if Settings.spawnType == 'client' then
                            local plate = GetVehicleNumberPlateText(tempTruck)
                            TriggerServerEvent('LNS_Fuel:giveDeliveryKeys', plate, activeJob.truckNetId)
                        end
                    end
                end
            end

            if not activeJob.trailer and activeJob.trailerNetId then
                if NetworkDoesNetworkIdExist(activeJob.trailerNetId) then
                    local tempTrailer = NetToVeh(activeJob.trailerNetId)
                    if tempTrailer ~= 0 and DoesEntityExist(tempTrailer) then
                        activeJob.trailer = tempTrailer
                        SetEntityAsMissionEntity(tempTrailer, true, true)
                    end
                end
            end

            if activeJob.state == 'tow' then
                local truckExists = true
                if activeJob.truck then
                    truckExists = DoesEntityExist(activeJob.truck)
                end

                local trailerExists = true
                if activeJob.trailer then
                    trailerExists = DoesEntityExist(activeJob.trailer)
                end

                if truckExists and trailerExists then
                    if activeJob.truck and not activeJob.truckCollected and GetPedInVehicleSeat(activeJob.truck, -1) == cache.ped then
                        activeJob.truckCollected = true
                        
                        if activeJob.truckBlip and DoesBlipExist(activeJob.truckBlip) then
                            RemoveBlip(activeJob.truckBlip)
                            activeJob.truckBlip = nil
                        end

                        if activeJob.trailerBlip and DoesBlipExist(activeJob.trailerBlip) then
                            SetBlipRoute(activeJob.trailerBlip, true)
                        end

                        lib.notify({ type = 'info', description = locale('notify_truck_collected') })
                    end

                    if activeJob.truck and IsVehicleAttachedToTrailer(activeJob.truck) then
                        local success, attachedTrailer = GetVehicleTrailerVehicle(activeJob.truck)
                        if success and attachedTrailer ~= 0 then
                            activeJob.trailer = attachedTrailer
                            activeJob.state = 'deliver'
                            
                            if activeJob.truckBlip and DoesBlipExist(activeJob.truckBlip) then
                                RemoveBlip(activeJob.truckBlip)
                                activeJob.truckBlip = nil
                            end
                            if activeJob.trailerBlip and DoesBlipExist(activeJob.trailerBlip) then
                                RemoveBlip(activeJob.trailerBlip)
                                activeJob.trailerBlip = nil
                            end

                            local coords = activeJob.coords
                            activeJob.destBlip = AddBlipForCoord(coords.x, coords.y, coords.z)
                            SetBlipSprite(activeJob.destBlip, 361)
                            SetBlipColour(activeJob.destBlip, 5)
                            SetBlipScale(activeJob.destBlip, 0.9)
                            SetBlipRoute(activeJob.destBlip, true)
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString("Gas Station Delivery")
                            EndTextCommandSetBlipName(activeJob.destBlip)
                            
                            lib.notify({ type = 'success', description = locale('notify_trailer_attached') })
                        end
                    end
                else
                    lib.notify({ type = 'error', description = locale('notify_vehicle_destroyed') })
                    CleanUpJob()
                end
            elseif activeJob.state == 'deliver' then
                if DoesEntityExist(activeJob.truck) and DoesEntityExist(activeJob.trailer) then
                    if not IsVehicleAttachedToTrailer(activeJob.truck) then
                        activeJob.state = 'tow'
                        if activeJob.destBlip and DoesBlipExist(activeJob.destBlip) then
                            RemoveBlip(activeJob.destBlip)
                            activeJob.destBlip = nil
                        end

                        local inTruck = (GetPedInVehicleSeat(activeJob.truck, -1) == cache.ped)
                        activeJob.truckCollected = inTruck

                        if not inTruck then
                            if activeJob.truckBlip and DoesBlipExist(activeJob.truckBlip) then
                                RemoveBlip(activeJob.truckBlip)
                            end
                            local truckPos = GetEntityCoords(activeJob.truck)
                            activeJob.truckBlip = AddBlipForCoord(truckPos.x, truckPos.y, truckPos.z)
                            SetBlipSprite(activeJob.truckBlip, 477)
                            SetBlipColour(activeJob.truckBlip, 5)
                            SetBlipScale(activeJob.truckBlip, 0.9)
                            SetBlipRoute(activeJob.truckBlip, true)
                            BeginTextCommandSetBlipName("STRING")
                            AddTextComponentString("Retrieval Truck")
                            EndTextCommandSetBlipName(activeJob.truckBlip)
                        end

                        if activeJob.trailerBlip and DoesBlipExist(activeJob.trailerBlip) then
                            RemoveBlip(activeJob.trailerBlip)
                        end
                        local trailerPos = GetEntityCoords(activeJob.trailer)
                        activeJob.trailerBlip = AddBlipForCoord(trailerPos.x, trailerPos.y, trailerPos.z)
                        SetBlipSprite(activeJob.trailerBlip, 479)
                        SetBlipColour(activeJob.trailerBlip, 18)
                        SetBlipScale(activeJob.trailerBlip, 0.9)
                        if inTruck then
                            SetBlipRoute(activeJob.trailerBlip, true)
                        end
                        BeginTextCommandSetBlipName("STRING")
                        AddTextComponentString("Fuel Trailer")
                        EndTextCommandSetBlipName(activeJob.trailerBlip)

                        lib.notify({ type = 'warning', description = locale('notify_trailer_detached') })
                    end
                else
                    lib.notify({ type = 'error', description = locale('notify_vehicle_destroyed') })
                    CleanUpJob()
                end
            elseif activeJob.state == 'return' then
                if not DoesEntityExist(activeJob.truck) then
                    lib.notify({ type = 'warning', description = locale('notify_truck_destroyed') })
                    CleanUpJob()
                end
            end
        end
    end
end)

CreateThread(function()
    while true do
        local sleep = 1000
        if activeJob then
            local pedCoords = GetEntityCoords(cache.ped)
            
            if activeJob.state == 'pickup' then
                local depot = Settings.ownership.delivery.depotCoords
                local dist = #(pedCoords - depot)
                if dist < 20.0 then
                    sleep = 0
                    DrawMarker(39, depot.x, depot.y, depot.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.5, 1.5, 1.5, 255, 215, 0, 150, false, true, 2, nil, nil, false)
                    if dist < 2.0 then
                        showDeliveryUI(locale('textui_retrieve_cargo'), { position = 'right-center', icon = 'truck' })
                        if IsControlJustPressed(0, 38) then
                            hideDeliveryUI()
                            SpawnJobVehicles()
                        end
                    else
                        hideDeliveryUI()
                    end
                end
                
            elseif activeJob.state == 'deliver' then
                local dest = activeJob.coords
                local dist = #(pedCoords - dest)
                if dist < 30.0 then
                    sleep = 0
                    DrawMarker(1, dest.x, dest.y, dest.z - 0.95, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 5.0, 4.0, 1.0, 0, 150, 255, 100, false, true, 2, nil, nil, false)
                    if dist < 5.0 then
                        local veh = GetVehiclePedIsIn(cache.ped, false)
                        if veh ~= 0 and veh == activeJob.truck then
                            if IsVehicleAttachedToTrailer(veh) then
                                showDeliveryUI(locale('textui_unload_fuel'), { position = 'right-center', icon = 'gas-pump' })
                                if IsControlJustPressed(0, 38) then
                                    hideDeliveryUI()
                                    UnloadFuel()
                                end
                            else
                                showDeliveryUI(locale('textui_attach_trailer'), { position = 'right-center', icon = 'exclamation-circle' })
                            end
                        else
                            showDeliveryUI(locale('textui_must_be_in_hauler'), { position = 'right-center', icon = 'exclamation-circle' })
                        end
                    else
                        hideDeliveryUI()
                    end
                end
                
            elseif activeJob.state == 'return' then
                local retCoords = Settings.ownership.delivery.returnCoords
                local dist = #(pedCoords - retCoords)
                if dist < 20.0 then
                    sleep = 0
                    DrawMarker(39, retCoords.x, retCoords.y, retCoords.z + 0.5, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.5, 1.5, 1.5, 220, 20, 60, 150, false, true, 2, nil, nil, false)
                    if dist < 4.0 then
                        local veh = GetVehiclePedIsIn(cache.ped, false)
                        if veh ~= 0 and veh == activeJob.truck then
                            showDeliveryUI(locale('textui_return_truck'), { position = 'right-center', icon = 'undo' })
                            if IsControlJustPressed(0, 38) then
                                hideDeliveryUI()
                                ReturnTruck()
                            end
                        else
                            showDeliveryUI(locale('textui_bring_hauler'), { position = 'right-center', icon = 'exclamation-circle' })
                        end
                    else
                        hideDeliveryUI()
                    end
                end
            end
        else
            hideDeliveryUI()
        end
        Wait(sleep)
    end
end)
