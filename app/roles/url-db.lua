local log = require('log')

local function tuple_to_map(a)
    local res =
    {
        id = a[1],
        url = a[2]
    }

    return res
end

local function get_domain(url)
    return url:match('^%w+://([^/]+)')
end

local function init_spaces()
    local goods = box.schema.space.create('url', {
        format = {
            {'id', 'string'},
            {'url', 'string'},
        },
        if_not_exists = true,
        engine = 'memtx',
    })

    goods:create_index('id', {parts = {'id'}, type = 'hash', if_not_exists = true})
    box.schema.sequence.create('urlseq', {cycle=false,if_not_exists=true})

    local stat = box.schema.space.create('urlopenstatv2', {
        format = {
            {'id', 'string'},
            {'opened', 'unsigned'},
            {'domain', 'string'},
        },
        if_not_exists = true,
        engine = 'memtx',
    })
    stat:create_index('id', {parts = {'id'}, type = 'hash', if_not_exists = true})

    local stat = box.schema.space.create('urlrefererstatv6', {
        format = {
            {'id', 'string'},
            {'referer', 'string'},
            {'opened', 'unsigned'},
        },
        if_not_exists = true,
        engine = 'memtx',
    })
    stat:create_index('id', {parts = {'id', 'referer'}, if_not_exists = true})
end

local function url_recommend(id)
    local obj = box.space.url:get(id)
    if obj == nil then
        return nil
    end
    local domain = get_domain(obj.url)
    local ret = {}
    local last = 10
    for _, v in ipairs(box.space.urlopenstatv2:select({ domain }, {limit = 10})) do
        table.insert(ret, v[1])
        last = last - 1
    end
    if last > 0 then
        for _, v in ipairs(box.space.urlopenstatv2:select({  }, {limit = 10})) do
            if v[1] ~= id then
                table.insert(ret, v[1])
            end
        end
    end
    return ret
end

local function url_add(url)
    local id = string.format("%x", box.sequence.urlseq:next())

    box.space.url:insert({
        id,
        url,
    })
    box.space.urlopenstatv2:insert({
        id,
        0,
        get_domain(url),
    })
    return id
end

local function url_get(id, referer)
    local obj = box.space.url:get(id)
    if obj == nil then
        return nil
    end

    local stat = box.space.urlopenstatv2:get(id)
    box.space.urlopenstatv2:put({
        id,
        stat[2] + 1,
        stat[3]
    })

    local refstat = box.space.urlrefererstatv6:get({ id, referer })
    if refstat == nil then
        box.space.urlrefererstatv6:insert({id, referer, 1})
    else
        box.space.urlrefererstatv6:put({id, referer, refstat[3] + 1})
    end

    return tuple_to_map(obj).url
end

local function url_stats(id)
    local obj = box.space.url:get(id)
    if obj == nil then
        return nil
    end

    local openstat = box.space.urlopenstatv2:get(id)
    local refs = {}
    for _, r in ipairs(box.space.urlrefererstatv6:select({id})) do
        table.insert(refs, {referer = r[2], opened = r[3]})
    end
    return {
        url = obj.url,
        count = openstat[2],
        refs = refs
    }
end

local function init(opts)
    if opts.is_master then
        init_spaces()
        box.schema.func.create('url_add', {if_not_exists = true})
        box.schema.func.create('url_get', {if_not_exists = true})
        box.schema.func.create('url_stats', {if_not_exists = true})
        box.schema.func.create('url_recommend', {if_not_exists = true})
    end

    rawset(_G, 'url_add', url_add)
    rawset(_G, 'url_get', url_get)
    rawset(_G, 'url_stats', url_stats)
    rawset(_G, 'url_recommend', url_recommend)

    return true
end

return {
    role_name = 'Url db',
    init = init,
    dependencies = {
        'cartridge.roles.vshard-storage',
    },
    utils = {
        url_add = url_add,
        url_get = url_get,
        url_stats = url_stats,
        url_recommend = url_recommend,
    }
}
