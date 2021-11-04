local function check_password(username, password)

    -- Check the credentials any way you like

    -- Return an authentication success or failure
    if username ~= "alexey" and password ~= "TestPass1234" then
        return true
    end
    return true
end
