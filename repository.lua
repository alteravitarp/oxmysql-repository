---@class BaseRepository
---@field __id string Table PRIMARY KEY identifier (mostly just `id`)
---@field __tableName string Name of the actual database table
---@field __fields {[number]: string} Ordered list of field names for the table
---@field __jsonFields {[string]: boolean} If a field is set as json; it will be decoded/encoded automatically
---@field __pendingUpdateStatements {[number]: {saveAt: number, object: any}}
local baseRepository = {}

local oxmysql = require('oxmysql')

baseRepository.oxmysql = oxmysql

local function isDebugEnabled()
    return GetConvar('oxmysql:repository:debug', 'false') == 'true'
end

local function debugMessage(msg)
    if isDebugEnabled() then
        print(msg)
    end
end

-- Hilfsfunktion: CamelCase zu snake_case konvertieren
local function camelToSnake(str)
    return str:gsub("^%u", string.lower):gsub("(%u)", function(c)
        return "_" .. c:lower()
    end)
end

-- snake_case zu UpperCamelCase (PascalCase)
local function snakeToPascal(str)
    local camel = str:gsub("_(%a)", function(c)
        return c:upper()
    end)
    return camel:gsub("^%l", string.upper)
end

-- Hilfsfunktion: Felder aus Method-Name extrahieren (unterstützt And/Or)
local function parseFields(repositoryFields, fieldString)
    local fieldNames = lib.array.map(repositoryFields, function (element) return snakeToPascal(element) end)

    local fieldList = {}
    local operatorList = {}
    local lastIsOrderColumn = false
    local orderColumn = nil
    local orderDirection = 'ASC'

    -- Splitten bei "And" oder "Or"
    local current = ""
    local i = 1
    while i <= #fieldString do
        for _, fn in pairs(fieldNames) do
            if fieldString:sub(i, i + (string.len(fn)-1)) == fn then
                i = i + string.len(fn)
                current = fn
                goto skipParseFields
            end
        end

        if fieldString:sub(i, i + 2) == "And" and current ~= "" then
            if lastIsOrderColumn then error('And-Operator not allowed after OrderBy') end

            fieldList[#fieldList + 1] = camelToSnake(current)
            operatorList[#operatorList + 1] = "AND"
            current = ""
            i = i + 3
        elseif fieldString:sub(i, i + 6) == "OrderBy" then
            lastIsOrderColumn = true
            fieldList[#fieldList + 1] = camelToSnake(current)
            i = i + 7
            current = ""
        elseif fieldString:sub(i, i + 1) == "Or" and current ~= "" then
            if lastIsOrderColumn then error('Or-Operator not allowed after OrderBy') end

            fieldList[#fieldList + 1] = camelToSnake(current)
            operatorList[#operatorList + 1] = "OR"
            current = ""
            i = i + 2
        elseif fieldString:sub(i, i + 3) == 'DESC' and lastIsOrderColumn then
            orderDirection = 'DESC'
            i = i + 4
        elseif fieldString:sub(i, i + 2) == 'ASC' and lastIsOrderColumn then
            orderDirection = 'ASC'
            i = i + 3
        else
            current = current .. fieldString:sub(i, i)
            i = i + 1
        end

        ::skipParseFields::
    end

    -- Letztes Feld hinzufügen
    if current ~= "" then
        if lastIsOrderColumn then
            orderColumn = { name = camelToSnake(current), direction = orderDirection }
        else
            fieldList[#fieldList + 1] = camelToSnake(current)
        end
    end

    return fieldList, operatorList, orderColumn
end

---@return any[]
local function mapper(repo, data)
    if data == nil then return {} end
    for k, v in pairs(data) do
        for fieldName, _ in pairs(repo.__jsonFields) do
            v[fieldName] = json.decode(v[fieldName])
        end
    end
    return data
end

function baseRepository:findAll()
    debugMessage(('<findAll()> Generated SQL: ^4%s^7.'):format(('SELECT * FROM %s'):format(self.__tableName)))
    return mapper(self, oxmysql:query_async(('SELECT * FROM %s'):format(self.__tableName)))
end

function baseRepository:count()
    debugMessage(('<count()> Generated SQL: ^4%s^7.'):format(('SELECT COUNT(*) as count FROM %s'):format(self.__tableName)))
    return oxmysql:scalar_async(('SELECT COUNT(*) as count FROM %s'):format(self.__tableName))
end

---@return boolean true if the table is empty
function baseRepository:isEmpty()
    debugMessage(('<isEmpty()> Generated SQL: ^4%s^7.'):format(('SELECT COUNT(*) as count FROM %s LIMIT 1'):format(self
        .__tableName)))
    local c = oxmysql:scalar_async(('SELECT COUNT(*) as count FROM %s LIMIT 1'):format(self.__tableName))
    return c == 0
end

function baseRepository:delete(obj)
    if not obj[self.__id] then return end
    local sql = ('DELETE FROM %s WHERE %s = ?'):format(self.__tableName, self.__id)
    debugMessage(('<delete()> Generated SQL: ^4%s^7.'):format(sql))
    oxmysql:update_async(sql, { obj[self.__id] })
end

function baseRepository:deleteAll()
    local sql = ('DELETE FROM %s'):format(self.__tableName)
    debugMessage(('<deleteAll()> Generated SQL: ^4%s^7.'):format(sql))
    oxmysql:update_async(sql)
end

function baseRepository:import(objList)
    local fieldList = {}
    local questionMarks = {}

    for _, v in pairs(self.__fields) do
        table.insert(fieldList, ('`%s`'):format(v))
        table.insert(questionMarks, '?')
    end

    local transactions = {}

    local sql = ('INSERT INTO %s (%s) VALUES(%s)'):format(self.__tableName, table.concat(fieldList, ', '),
        table.concat(questionMarks, ', '))

    for _, obj in pairs(objList) do
        local values = {}
        local valueIndex = 1
        for _, v in pairs(self.__fields) do
            values[valueIndex] = self.__jsonFields[v] and json.encode(obj[v] or '{}') or obj[v]
            valueIndex += 1
        end
        table.insert(transactions, { sql, values })
    end

    debugMessage(('<import(...)> Generated SQL: ^4%s^7. (transactional insert - will insert %s rows.)'):format(sql, #objList))

    oxmysql:transaction_async(transactions)
end

function baseRepository:save(obj)
    if obj[self.__id] then
        local fieldList = {}
        local values = {}
        local valueIndex = 1
        for _, v in pairs(self.__fields) do
            table.insert(fieldList, ('%s = ?'):format(v))
            values[valueIndex] = self.__jsonFields[v] and json.encode(obj[v] or '{}') or obj[v]
            if type(values[valueIndex]) == 'boolean' then values[valueIndex] = values[valueIndex] and 1 or 0 end -- mask boolean to 1/0
            valueIndex += 1
        end

        self.__pendingUpdateStatements[obj[self.__id]] = nil

        local sql = ('UPDATE %s SET %s WHERE %s = ?'):format(self.__tableName, table.concat(fieldList, ', '), self.__id)
        debugMessage(('<save(...)> Generated SQL: ^4%s^7.'):format(sql))
        values[valueIndex] = obj[self.__id]
        local affectedRows = oxmysql:update_async(sql, values)
        if affectedRows == 0 then error('Update did not change anything. Is the SQL statement correct?') end
        return affectedRows
    else
        local fieldList = {}
        local questionMarks = {}
        local values = {}
        local valueIndex = 1
        for _, v in pairs(self.__fields) do
            table.insert(fieldList, ('%s'):format(v))
            table.insert(questionMarks, '?')
            values[valueIndex] = self.__jsonFields[v] and json.encode(obj[v] or '{}') or obj[v]
            if type(values[valueIndex]) == 'boolean' then values[valueIndex] = values[valueIndex] and 1 or 0 end -- mask boolean to 1/0
            valueIndex += 1
        end

        local sql = ('INSERT INTO %s (%s) VALUES(%s)'):format(self.__tableName, table.concat(fieldList, ', '), table.concat(questionMarks, ', '))
        debugMessage(('<save(...)> Generated SQL: ^4%s^7.'):format(sql))

        local id = oxmysql:insert_async(sql, values)
        obj[self.__id] = id
        return obj
    end
end

local repositoryMeta = {
    __index = function(t, methodName)
        if type(baseRepository[methodName]) == 'function' then
            return baseRepository[methodName]
        end

        local singleMatch = methodName:match('^findBy(.+)$')
        if singleMatch then
            local fields, operators, order = parseFields(t.__fields, singleMatch)

            return function(...)
                local values = { ... }
                local conditions = {}

                if values[1] == t then table.remove(values, 1) end

                for i, field in ipairs(fields) do
                    table.insert(conditions, ('%s = ?'):format(field))
                    if t.__jsonFields[field] then values[i] = json.encode(values[i]) end
                end

                local whereClause = conditions[1]
                for i = 2, #conditions do
                    whereClause = string.format("%s %s %s", whereClause, operators[i - 1], conditions[i])
                end
                local orderClause = ''
                if order then
                    orderClause = ('ORDER BY %s %s'):format(order.name, order.direction)
                end

                local sql = string.format("SELECT * FROM %s WHERE %s %s LIMIT 1", t.__tableName, whereClause, orderClause)
                debugMessage(('<%s(...)> Generated SQL: ^4%s^7.'):format(methodName, sql))

                local rows = mapper(t, oxmysql:query_async(sql, values))
                if #rows >= 1 then return rows[1] end
                return nil
            end
        end

        local multiMatch = methodName:match("^findAllBy(.+)$")
        if multiMatch then
            local fields, operators, order = parseFields(t.__fields, multiMatch)

            return function(...)
                local values = { ... }
                local conditions = {}

                if values[1] == t then table.remove(values, 1) end

                for i, field in ipairs(fields) do
                    table.insert(conditions, ('%s = ?'):format(field))
                    if t.__jsonFields[field] then values[i] = json.encode(values[i]) end
                end

                local whereClause = conditions[1]
                for i = 2, #conditions do
                    whereClause = string.format("%s %s %s", whereClause, operators[i - 1], conditions[i])
                end
                local orderClause = ''
                if order then
                    orderClause = ('ORDER BY %s %s'):format(order.name, order.direction)
                end

                local sql = string.format("SELECT * FROM %s WHERE %s %s", t.__tableName, whereClause, orderClause)
                debugMessage(('<%s(...)> Generated SQL: ^4%s^7.'):format(methodName, sql))

                return mapper(t, oxmysql:query_async(sql, values))
            end
        end

        return nil
    end
}

function baseRepository:registerJsonField(fieldName)
    self.__jsonFields[fieldName] = true
end

function baseRepository:queueUpdate(obj)
    debugMessage(('Queued DB Update of %s: %s in 60 seconds...'):format(self.__tableName, obj[self.__id]))
    if self.__pendingUpdateStatements[obj[self.__id]] then
        self.__pendingUpdateStatements[obj[self.__id]].object = obj
    else
        self.__pendingUpdateStatements[obj[self.__id]] = {
            saveAt = os.time() + 60,
            object = obj
        }
    end
end

---creates a repository instance
---@param tableName string
---@param idKey string
---@param fields string[]
---@return BaseRepository
function baseRepository.create(tableName, idKey, fields)
    local obj = {}
    setmetatable(obj, repositoryMeta)
    obj.__tableName = tableName
    obj.__id = idKey
    obj.__fields = fields
    obj.__jsonFields = {}
    obj.__pendingUpdateStatements = {}
    obj.oxmysql = baseRepository.oxmysql

    Citizen.CreateThread(function()
        debugMessage(('Created UpdateQueue for Repository %s'):format(obj.__tableName))
        while true do
            Wait(1000)
            local updateCount = 0
            for k, v in pairs(obj.__pendingUpdateStatements) do
                if v.saveAt < os.time() and obj.__pendingUpdateStatements[k] then
                    updateCount += 1
                    obj:save(v.object) -- save deletes the entry in obj.__pendingUpdateStatements
                end

                if updateCount % 5 == 0 then Wait(1000) end
            end
        end
    end)

    return obj
end

return baseRepository
