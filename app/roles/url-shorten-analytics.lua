local cartridge = require('cartridge')
local errors = require('errors')

local err_vshard_router = errors.new_class("Vshard routing error")

local function verify_response(response, error, req)
    if error then
        local resp = req:render({json = {
            info = "Internal error",
            error = error
        }})
        resp.status = 500
        return resp
    end

    if response == nil then
        local resp = req:render({json = {
            info = "Not Found",
            error = error
        }})
        resp.status = 404
        return resp
    end

    if response == -1 then
        local resp = req:render({json = {
            info = "Invalid field",
        }})
        resp.status = 400
        return resp
    end

    if response == false then
        local resp = req:render({json = {
            info = "Conflict",
        }})
        resp.status = 409
        return resp
    end

    return true
end

local function http_url_stat(req)
    local id = req:stash('id')
    local router = cartridge.service_get('vshard-router').get()
    local bucket = router:bucket_id(id)
    local data, error = err_vshard_router:pcall(router.call, router, bucket, 'write', 'url_stats', {id}, {timeout = 5})

    local status = verify_response(data, error, req)
    if status ~= true then
        return status
    end
    return req:render({url = id .. ' - ' .. data.url, count = data.count, refs = data.refs})
end

local function init(opts)
    local httpd = assert(cartridge.service_get('httpd'), "Failed to get httpd service")
    httpd:route({method = 'GET', path = '/stat/:id', file = 'stat.html'}, http_url_stat)
    return true
end

return {
    role_name = 'Url analytics',
    init = init,
    dependencies = {'cartridge.roles.vshard-router'},
}
