local fs = require("filesystem")

local REPO = "https://raw.githubusercontent.com/Dark-Tehno/DarkOS/main/"

local files = {
    { "autorun.lua",        "/autorun.lua" },

    { "init.lua",            "/os/init.lua" },

    { "api/theme.lua",      "/os/api/theme.lua" },
    { "api/gui.lua",        "/os/api/gui.lua" },
    { "api/appapi.lua",     "/os/api/appapi.lua" },
    { "api/netproto.lua",   "/os/api/netproto.lua" },

    { "apps/files.lua",     "/os/apps/files.lua" },
    { "apps/editor.lua",    "/os/apps/editor.lua" },
    { "apps/netbrowser.lua","/os/apps/netbrowser.lua" },
    { "apps/sitehost.lua",  "/os/apps/sitehost.lua" },
    { "apps/netdir.lua",    "/os/apps/netdir.lua" },
    { "apps/updateserver.lua", "/os/apps/updateserver.lua" },
    { "apps/updater.lua",   "/os/apps/updater.lua" },
    { "apps/settings.lua",  "/os/apps/settings.lua" },
}

local function mkdir(path)
    if not fs.exists(path) then
        fs.makeDirectory(path)
    end
end

print("DarkOS Installer")
print("-----------------")

mkdir("/os")
mkdir("/os/api")
mkdir("/os/apps")
mkdir("/os/sitedata")

for _, item in ipairs(files) do
    local source = item[1]
    local destination = item[2]

    io.write("Downloading " .. source .. " ... ")

    local ok = os.execute(
        "wget -fq " ..
        REPO .. source .. " " ..
        destination
    )

    if ok then
        print("OK")
    else
        print("FAILED")
    end
end

print()
print("Installation finished.")
print("Restart the computer.")
