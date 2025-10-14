local db = { }

setmetatable(db, {
    __index = function (t, ...)
        local args = { ... }

        local methodName = args[1]

        return function(...)
            local methodArgs = { ... }
            methodArgs[1] = exports.oxmysql -- overwrite first parameter to oxmysql export ref
            local _, result = pcall(function() return exports.oxmysql[methodName]( table.unpack(methodArgs) ) end)
            return result
        end
    end
})

return db