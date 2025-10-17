# OxMySQL - Repository Extension

This module provides a [JPA-repository](https://docs.spring.io/spring-data/jpa/reference/index.html) like base for accessing a database table.

## Changelogs

### 0.2.0 - countBy-Methods

You can now get the count from your tables using `countBy{expression}(...)`.

Example:
```lua
---@class OwnedVehicleRepository : BaseRepository
---@field countByPlate fun(r: OwnedVehicleRepository, plate: string): number
local repository = baseRepository.create('owned_vehicles_v2', 'id', {...})
```

## Requirements

- oxmysql
- ox_lib

## How to use the extension?

I'll describe the how-to with an example. Imagine a Garage-Script which access the table `owned_vehicles`. You need to query the data and/or update it and your script contains like 20 SQL statements. This is very messy and can lead to various issues or errors later on. To prevent this, we delegate the SQL generation to a abstract layer and concentrate on working with the entity itself.

To get started, we create a "repository" by defining it in a new lua file in our project:

```lua
-- ownedVehiclesRepository.lua

---@alias OwnedVehicle {id: number, owner: string, plate: string, model_name: string, stored: boolean}

local baseRepository = require('@oxmysql-repository.repository')

---@class OwnedVehiclesRepository : BaseRepository
---@field findAll fun(r: OwnedVehiclesRepository): OwnedVehicle[]
---@field findAllByIdentifier fun(r: OwnedVehiclesRepository, societyName: string): OwnedVehicle[]
---@field save fun(r: OwnedVehiclesRepository, obj: OwnedVehicle): OwnedVehicle
local repository = baseRepository.create('owned_vehicles', 'id', {'owner', 'plate', 'model_name', 'stored'})

return repository
```

Using our repository, we can now access the database using:

```lua
local vehicleRepository = require('ownedVehiclesRepository')

local vehicles = vehicleRepository:findAll()

for k, v in pairs(vehicles) do
    if v.plate == 'MC PK 43' then
        v.owner = 'new owner identifier'
        vehicleRepository:save(v) -- calls `UPDATE` immediately, we could also use `queueUpdate` which puts the update in a queue - is only recommended if the data is cached locally and wont be fetched from the database any more.
    end
end
```

## API

| Function         | Parameters                     | Description                                                                                       |
| ---------------- | ------------------------------ | ------------------------------------------------------------------------------------------------- |
| findAll()        | -                              | Returns the full table content                                                                    |
| delete(obj)      | Object to delete               | Deletes the element from the database                                                             |
| deleteAll()      | -                              | Clears the table using `DELETE FROM`                                                              |
| queueUpdate(obj) | Object to save to the database | Queues the update of an entity to be saved 60 seconds from now and delegates the call to `save()` |
| save(obj)        | Object to save to the database | Creates or updates the entity. If the primary key field is not set, it will insert the data       |
| count()          | -                              | Counts the elements in the table `SELECT count(*) FROM`                                           |
| isEmpty()        | -                              | Checks if the table is empty using a `SELECT count(*) FROM ... LIMIT 1`-Statement                 |
| import(objList)  | Array of objects to import     | Uses a transaction with INSERT-Statements to insert many data. Mainly used to seed the table.     |

Additional there are dynamic methods to the repository which will be resolved automatically. See the following table for examples.


| Function                              | SQL                                                                |
| ------------------------------------- | ------------------------------------------------------------------ |
| findAllByOwner('ABC')                 | `SELECT * FROM owned_vehicles WHERE owner = ?`                     |
| findAllByOwnerAndJob('ABC', 'police') | `SELECT * FROM owned_vehicles WHERE owner = ? AND job = ?`         |
| findAllByOwnerOrderByPlateDESC('ABC') | `SELECT * FROM owned_vehicles WHERE owner = ? ORDER BY plate DESC` |
| findByPlate('WW HN 84')               | `SELECT * FROM owned_vehicles WHERE plate = ? LIMIT 1`             |
| findAllByOwnerOrJob('ABC', 'police')  | `SELECT * FROM owned_vehicles WHERE owner = ? OR job = ?`          |

### JSON Fields

In case you do have JSON fields in your tables, you can tell the repository so by calling `:registerJsonField(fieldName)` in the repository file after creating the repository:

```lua
-- ownedVehiclesRepository.lua

local baseRepository = require('@oxmysql-repository.repository')

local repository = baseRepository.create(...)

repository:registerJsonField('trunk') -- will json encode/decode the data in the trunk field on save/read

return repository
```

## TODOs

- [x] Only select fields set in `baseRepository.create(...)`
- [ ] Only update modified fields
- [x] Added `countBy` dynamic methods
