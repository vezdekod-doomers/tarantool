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

local function http_url_add(req)
    local url = req:param('url')
    local router = cartridge.service_get('vshard-router').get()
    local bucket = math.random(1, router:bucket_count())
    local data, error = err_vshard_router:pcall(router.call, router, bucket, 'write', 'url_add', {url}, {timeout = 5})

    local status = verify_response(data, error, req)
    if status ~= true then
        return status
    end
    if req:param('pretty') ~= nil then
        return req:render({url = 'http://89.208.197.145:8081/u/' .. data})
    else
        return {
            status = 200,
            body = 'http://89.208.197.145:8081/u/' .. data
        }
    end
end

local function http_index(req)
    return req:render({url = ''})
end

local function http_url_get(req)
    local id = req:stash('id')
    if id == nil then
        return {
            status = 400,
            body = 'URL required'
        }
    end
    local referer = 'none'
    if req.headers['referer'] ~= nil then
        referer = req.headers['referer']
    end

    local router = cartridge.service_get('vshard-router').get()
    local bucket = router:bucket_id(id)
    local data, error = err_vshard_router:pcall(router.call, router, bucket, 'read', 'url_get', {id, referer}, {timeout = 5})

    local status = verify_response(data, error, req)
    if status ~= true then
        return status
    end

    return {
        status = 301,
        headers = { ['Location'] = data }
    }
end

local function http_url_add_redir(self)
    return self:redirect_to('/index')
end

local function init(opts)
    local httpd = assert(cartridge.service_get('httpd'), "Failed to get httpd service")
    httpd:route({method = 'POST', path = '/set', file = 'index.html'}, http_url_add)
    httpd:route({method = 'GET', path = '/set', file = 'index.html'}, http_url_add_redir)
    httpd:route({method = 'GET', path = '/u/:id'}, http_url_get)
    httpd:route({ path = '/logo.svg', file = 'logo.svg' })
    httpd:route({ path = '/index', file = 'index.html' }, http_index)
    return true
end

return {
    role_name = 'Url front',
    init = init,
    dependencies = {'cartridge.roles.vshard-router'},
}
