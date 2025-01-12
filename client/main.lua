local config = require 'config.client'
local sharedConfig = require 'config.shared'

local isMelting = false ---@type boolean
local canTake = false ---@type boolean
local meltTimeSeconds = 0 ---@type number
local meltedItem = {} ---@type {item: string, amount: number}[]

---@param id number
---@param shopConfig {coords: vector3, size: vector3, heading: number, debugPoly: boolean, distance: number}
local function addPawnShop(id, shopConfig)
    if not config.useTarget then
        lib.zones.box({
            name = 'PawnShop' .. id,
            coords = shopConfig.coords,
            size = shopConfig.size,
            rotation = shopConfig.heading,
            debug = shopConfig.debugPoly,
            onEnter = function()
                lib.registerContext({
                    id = 'open_pawnShopMain',
                    title = locale('info.title'),
                    options = {
                        {
                            title = locale('info.open_pawn'),
                            event = 'qb-pawnshop:client:openMenu'
                        }
                    }
                })
                lib.showContext('open_pawnShopMain')
            end,
            onExit = function()
                lib.hideContext(false)
            end
        })
        return
    end

    exports.ox_target:addBoxZone({
        coords = shopConfig.coords,
        size = shopConfig.size,
        rotation = shopConfig.heading,
        debug = shopConfig.debugPoly,
        options = {
            {
                name = 'PawnShop' .. id,
                event = 'qb-pawnshop:client:openMenu',
                icon = 'fas fa-ring',
                label = 'PawnShop ' .. id,
                distance = shopConfig.distance
            }
        }
    })
end

CreateThread(function()
    for id, shopConfig in pairs(sharedConfig.pawnLocation) do
        local blip = AddBlipForCoord(shopConfig.coords.x, shopConfig.coords.y, shopConfig.coords.z)
        SetBlipSprite(blip, 431)
        SetBlipDisplay(blip, 4)
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, true)
        SetBlipColour(blip, 5)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(locale('info.title'))
        EndTextCommandSetBlipName(blip)

        addPawnShop(id, shopConfig)
    end
end)

RegisterNetEvent('qb-pawnshop:client:openMenu', function()
    if not config.useTimes then
        local pawnShop = {
            {
                title = locale('info.sell'),
                description = locale('info.sell_pawn'),
                event = 'qb-pawnshop:client:openPawn',
                args = {
                    items = config.pawnItems
                }
            }
        }
        if not isMelting then
            pawnShop[#pawnShop + 1] = {
                title = locale('info.melt'),
                description = locale('info.melt_pawn'),
                event = 'qb-pawnshop:client:openMelt',
                args = {
                    items = config.meltingItems
                }
            }
        end
        if canTake then
            pawnShop[#pawnShop + 1] = {
                title = locale('info.melt_pickup'),
                serverEvent = 'qb-pawnshop:server:pickupMelted',
                args = {
                    items = meltedItem
                }
            }
        end
        lib.registerContext({
            id = 'open_pawnShop',
            title = locale('info.title'),
            options = pawnShop
        })
        lib.showContext('open_pawnShop')
        return
    end

    local gameHour = GetClockHours()
    if gameHour < config.timeOpen or gameHour > config.timeClosed then
        exports.qbx_core:Notify(locale('info.pawn_closed', config.timeOpen, config.timeClosed))
        return
    end

    local pawnShop = {
        {
            title = locale('info.sell'),
            description = locale('info.sell_pawn'),
            event = 'qb-pawnshop:client:openPawn',
            args = {
                items = config.pawnItems
            }
        }
    }
    if not isMelting then
        pawnShop[#pawnShop + 1] = {
            title = locale('info.melt'),
            description = locale('info.melt_pawn'),
            event = 'qb-pawnshop:client:openMelt',
            args = {
                items = config.meltingItems
            }
        }
    end
    if canTake then
        pawnShop[#pawnShop + 1] = {
            title = locale('info.melt_pickup'),
            serverEvent = 'qb-pawnshop:server:pickupMelted',
            args = {
                items = meltedItem
            }
        }
    end
    lib.registerContext({
        id = 'open_pawnShop',
        title = locale('info.title'),
        options = pawnShop
    })
    lib.showContext('open_pawnShop')
end)

---@param item string
---@param meltingAmount number
---@param _meltTimeSeconds number
RegisterNetEvent('qb-pawnshop:client:startMelting', function(item, meltingAmount, _meltTimeSeconds)
    if isMelting then
        return
    end

    isMelting = true
    meltTimeSeconds = _meltTimeSeconds
    meltedItem = {}
    CreateThread(function()
        while isMelting and LocalPlayer.state.isLoggedIn and meltTimeSeconds > 0 do
            meltTimeSeconds = meltTimeSeconds - 1
            Wait(1000)
        end

        canTake = true
        isMelting = false
        table.insert(meltedItem, { item = item, amount = meltingAmount })

        if not config.sendMeltingEmail then
            exports.qbx_core:Notify(locale('info.message'), 'success')
            return
        end

        TriggerServerEvent('qb-phone:server:sendNewMail', {
            sender = locale('info.title'),
            subject = locale('info.subject'),
            message = locale('info.message'),
            button = {}
        })
    end)
end)

RegisterNetEvent('qb-pawnshop:client:resetPickup', function()
    canTake = false
end)

RegisterNetEvent('qb-pawnshop:client:openMelt', function(data)
	lib.callback('qb-pawnshop:server:getInv', false, function(inventory)
		local PlyInv = inventory
		local meltMenu = {}

		for _, v in pairs(PlyInv) do
			for i = 1, #data.items do
				if v.name == data.items[i].item then
					meltMenu[#meltMenu + 1] = {
						title = exports.ox_inventory:Items()[v.name].label,
						description = locale('info.melt_item', exports.ox_inventory:Items()[v.name].label),
						event = 'qb-pawnshop:client:meltItems',
						args = {
							label = exports.ox_inventory:Items()[v.name].label,
							reward = data.items[i].rewards,
							name = v.name,
							amount = v.amount,
							time = data.items[i].meltTime
						}
					}
				end
			end
		end
		lib.registerContext({
			id = 'open_meltMenu',
			menu = 'open_pawnShop',
			title = locale('info.title'),
			options = meltMenu
		})
		lib.showContext('open_meltMenu')
	end)
end)

RegisterNetEvent('qb-pawnshop:client:pawnitems', function(item)
	local sellingItem = lib.inputDialog(locale('info.title'), {
		{
			type = 'number',
			label = 'amount',
			placeholder = locale('info.max', item.amount)
		}
	})
	if sellingItem then
		if not sellingItem[1] or sellingItem[1] <= 0 then return end
		TriggerServerEvent('qb-pawnshop:server:sellPawnItems', item.name, sellingItem[1], item.price)
	else
		exports.qbx_core:Notify(locale('error.negative'), 'error')
	end
end)

RegisterNetEvent('qb-pawnshop:client:meltItems', function(item)
	local meltingItem = lib.inputDialog(locale('info.melt'), {
		{
			type = 'number',
			label = 'amount',
			placeholder = locale('info.max', item.amount)
		}
	})
	if meltingItem then
		if not meltingItem[1] or meltingItem[1] <= 0 then return end
		TriggerServerEvent('qb-pawnshop:server:meltItemRemove', item.name, meltingItem[1], item)
	else
		exports.qbx_core:Notify(locale('error.no_melt'), 'error')
	end
end)

RegisterNetEvent('qb-pawnshop:client:openPawn', function(data)
	lib.callback('qb-pawnshop:server:getInv', false, function(inventory)
		local PlyInv = inventory
		local pawnMenu = {}

		for _, v in pairs(PlyInv) do
			for i = 1, #data.items do
				if v.name == data.items[i].item then
					pawnMenu[#pawnMenu + 1] = {
						title = exports.ox_inventory:Items()[v.name].label,
						description = locale('info.sell_items', data.items[i].price),
						event = 'qb-pawnshop:client:pawnitems',
						args = {
							label = exports.ox_inventory:Items()[v.name].label,
							price = data.items[i].price,
							name = v.name,
							amount = v.amount
						}
					}
				end
			end
		end
		lib.registerContext({
			id = 'open_pawnMenu',
			menu = 'open_pawnShop',
			title = locale('info.title'),
			options = pawnMenu
		})
		lib.showContext('open_pawnMenu')
	end)
end)