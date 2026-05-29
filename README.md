<div align="center">
  <h1>LNS Fuel</h1>

  [![Version](https://img.shields.io/badge/Version-1.0.3-6fd2f3?style=for-the-badge)](https://github.com/LumaNodeStudios/LNS_Fuel)
  [![Frameworks](https://img.shields.io/badge/Frameworks-ESX%20%7C%20QBCore-6fd2f3?style=for-the-badge)](#-framework-compatibility)
  [![Author](https://img.shields.io/badge/Author-LumaNode%20Studios-6fd2f3?style=for-the-badge)](https://github.com/LumaNodeStudios)
  [![License](https://img.shields.io/badge/License-GPL--3.0-6fd2f3?style=for-the-badge)](LICENSE)
</div>

---

## Preview

<img src="https://r2.fivemanage.com/ikenZGXRwE4faTVyko8MZ/image_2026-05-22_230101655.png" alt="LNS Fuel Banner" width="100%" style="border-radius: 12px; margin-top: 20px; margin-bottom: 20px; box-shadow: 0 4px 20px rgba(0,0,0,0.4);"/>

---

## Overview

**LNS Fuel** by **LumaNode Studios** is a state-of-the-art, feature-complete fuel management system designed to completely replace legacy fuel scripts (like `cdn-fuel` or standard `ox_fuel`). 

Rather than just filling up vehicles, **LNS Fuel** introduces a deep, player-driven economy with **gas station ownership**, **logistics operations**, **employee management**, and an exceptionally sleek **Svelte UI Dashboard** that will leave your players amazed.

---

## Features

### Dynamic Fuel System & Jerry Cans
* **Accurate Consumptions:** Custom consumption rates applied globally, per vehicle class (0-22), or overridden by specific vehicle model hashes (e.g., Super cars consume more, pedal bikes consume none).
* **Jerry Can Support:** Custom jerry cans with durability-based usage, customizable purchase prices, and interactive refill rates.
* **Statebag Synchronization:** High-performance, desync-free fuel level syncing using native routing and entity statebags (`Entity(entity).state.fuel`).

### Player Station Ownership
* **Purchase Stations:** Over 25 pre-configured gas stations spanning Los Santos, Blaine County, and Paleto Bay available for players to acquire.
* **Financial Management:** Deposit and withdraw cash directly to/from the station's balance sheet.
* **Flexible Pricing:** Owners can dynamically adjust their station's fuel pricing (within limits set in configuration).
* **Station Customization:** Personalize station names (protected by an automated blacklist word filter).
* **Live Statistics:** Track station metrics like lifetime sales, total revenue, and unique clients.

### Fuel Logistics & Jobs
* **Manual Delivery Runs:** Station owners and employees can head to the commercial fuel depot, hook up a heavy truck and fuel tanker, and complete logistics deliveries to manually refill their station's stock.
* **AI Driver Contracts (Automated Dispatch):** Don't want to drive? Hire AI professional truck drivers to fetch and deliver your stock orders automatically in real-time.
* **Three Order Tiers:** Purchase and ship fuel in small (500L), medium (1000L), or large (2000L) batches.

### Station Upgrades System
Invest station revenue into persistent station upgrades to maximize profits:
1. **Fuel Tank Capacity:** Upgrade maximum fuel storage capacity (from 2,000L up to 20,000L).
2. **Supplier Partnership:** Negotiate bulk shipping rates to get up to a **35% discount** on stock orders.
3. **Logistics Dispatch Contract:** Hire faster dispatchers to cut down AI delivery times (from 10 minutes down to 5 minutes).

### Employee & Hiring Mechanics
* **Hire Employees:** Recruit other players on the server using their Server ID.
* **Shared Workload:** Employees can manage stock orders and run physical logistics deliveries.
* **Role System:** Distinct roles (Owner vs. Employee) to control access and protect station assets.
* **Fire System:** Release employees instantly with real-time framework notifications.

### Sleek Svelte UI & Modern Design
* **Theme Customization:** Easily adjust the dashboard's accent color (primary, hover, text) directly in the shared settings to match your server's branding.

---

## Framework Compatibility

LNS Fuel features auto-detection of server environments and functions out of the box with:
* **ESX** (`es_extended`)
* **Qbox** (via `qbx_core` and `qbx_vehiclekeys`)

---

## Requirements

Ensure you have the following resources installed and started before running LNS Fuel:
* [ox_lib](https://github.com/overextended/ox_lib) (version 3.22.0 or higher)
* [ox_inventory](https://github.com/overextended/ox_inventory) (version 2.30.0 or higher)
* [oxmysql](https://github.com/overextended/oxmysql) (for database integrations)

---

## Database Setup

LNS Fuel will automatically attempt to create its required tables on startup. If you prefer to manually run the SQL schema, import the following into your database:

```sql
CREATE TABLE IF NOT EXISTS `lns_fuel_stations` (
    `station_id` VARCHAR(50) NOT NULL,
    `owner` VARCHAR(50) DEFAULT NULL,
    `name` VARCHAR(100) DEFAULT 'Gas Station',
    `balance` INT NOT NULL DEFAULT 0,
    `stock` INT NOT NULL DEFAULT 1000,
    `capacity` INT NOT NULL DEFAULT 2000,
    `price` INT NOT NULL DEFAULT 5,
    `upgrades` TEXT DEFAULT '{}',
    `statistics` TEXT DEFAULT '{}',
    PRIMARY KEY (`station_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `lns_fuel_employees` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `station_id` VARCHAR(50) NOT NULL,
    `identifier` VARCHAR(50) NOT NULL,
    `name` VARCHAR(100) NOT NULL,
    `role` VARCHAR(50) DEFAULT 'employee',
    UNIQUE KEY `station_emp` (`station_id`, `identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

---

## Installation

1. Drag and drop the `LNS_Fuel` folder into your server's `resources` directory (preferably under a folder like `[scripts]`).
2. Ensure you have configured your dependencies (`ox_lib`, `ox_inventory`, and `oxmysql`) inside your `server.cfg`.
3. Add the following to your `server.cfg` to start the resource:
   ```cfg
   ensure LNS_Fuel
   ```
4. Adjust your preferences, prices, consumptions, and station points in [shared/settings.lua](file:///shared/settings.lua).

---

## Developer Exports & Docs

### Interacting with Fuel Levels (Statebags)

Rather than calling slow exports, get and set vehicle fuel levels instantly via statebags:

#### Get Fuel Level
```lua
local fuelLevel = Entity(vehicle).state.fuel
-- or fall back to native function
local nativeLevel = GetVehicleFuelLevel(vehicle)
```

#### Set Fuel Level
```lua
Entity(vehicle).state.fuel = 75.0 -- Set fuel to 75%
```

---

### Custom Framework / Economy Bridges (Exports)

If you're using custom framework extensions or unique item systems, use our built-in API exports to redirect logic:

#### `setPaymentMethod` (Server)
Overrides the default money-removal system when purchasing fuel.
```lua
exports.LNS_Fuel:setPaymentMethod(function(playerId, amount)
    local xPlayer = ESX.GetPlayerFromId(playerId)
    local bankAmount = xPlayer.getAccount('bank').money

    if bankAmount >= amount then
        xPlayer.removeAccountMoney('bank', amount)
        return true -- Purchase successful
    end

    TriggerClientEvent('ox_lib:notify', playerId, {
        type = 'error',
        description = 'You do not have enough money in your bank account!'
    })
    return false -- Purchase failed
end)
```

#### `setMoneyCheck` (Client)
Overrides how the client verifies player funds before showing gas options or initiating refill indicators.
```lua
exports.LNS_Fuel:setMoneyCheck(function()
    local accounts = ESX.GetPlayerData().accounts

    for i = 1, #accounts do
        if accounts[i].name == 'bank' then
            return accounts[i].money
        end
    end
    return 0
end)
```

---

## Credits & Acknowledgements

**LNS Fuel** is built upon and heavily modifies the core foundation of **[ox_fuel](https://github.com/overextended/ox_fuel)** by the **[Overextended](https://github.com/overextended)** team. We express our utmost gratitude to them for providing a highly optimized open-source base that allowed us to build this script.

**LNS Fuel** uses **[cdn-fuel](https://github.com/CodineDev/cdn-fuel)** for the **electric nozzle** and **[cdn-fuel](https://github.com/CodineDev/cdn-fuel)** for the **electric charger**.

---

<div align="center">
  <p><i>A premium resource developed by <a href="https://github.com/LumaNodeStudios">LumaNode Studios</a></i></p>
</div>