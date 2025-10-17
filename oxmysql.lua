local db = { }

local function removeColorCodes(str)
    -- replace ^[0-9] with nothing
    str = string.gsub(str, "%^%d", "")
    -- replace ^#[0-9A-F]{3,6} with nothing
    str = string.gsub(str, "%^#[%dA-Fa-f]+", "")
    -- replace ~[a-z]~ with nothing
    str = string.gsub(str, "~[%a%d]~", "")

    return str
end

local function removeNewLine(str)
    -- replace ^[0-9] with nothing
    str = string.gsub(str, "[\n\r]", " ")

    return str
end

local function errorHandler(...)
    local args = { ... }
    local debugInfo = debug.getinfo(8) -- 7 seems to be the repository; so the actual oxmysql:* call

    if Loki then
        Citizen.Trace('[^1ERROR^7] A database error occured. Please check Grafana or enable debug print for more information!\n')
        Loki.log(nil, 'error', removeNewLine(removeColorCodes(args[1] or '(undefined error message)')), {
            level = 'ERROR',
            stacktrace = debug.traceback(),
            file = debugInfo.short_src,
            line = debugInfo.currentline,
        })
    end
end

setmetatable(db, {
    __index = function (t, ...)
        local args = { ... }

        local methodName = args[1]

        return function(...)
            local methodArgs = { ... }
            methodArgs[1] = exports.oxmysql -- overwrite first parameter to oxmysql export ref
            local _, result = xpcall(function()
                return exports.oxmysql[methodName]( table.unpack(methodArgs) )
            end, errorHandler)
            return result
        end
    end
})

return db