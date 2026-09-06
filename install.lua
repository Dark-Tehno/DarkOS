local shell = require("shell")
local fs = require("filesystem")

local REPO = "https://raw.githubusercontent.com/Dark-Tehno/DarkOS/main/"

local files = {
    "autorun.lua",
    "os/init.lua",

    "os/api/theme.lua",
    "os/api/gui.lua",
    "os/api/appapi.lua",
    "os/api/netproto.lua",

    "os/apps/files.lua",
    "os/apps/editor.lua",
    "os/apps/netbrowser.lua",
    "os/apps/sitehost.lua",
    "os/apps/settings.lua",
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

for _, file in ipairs(files) do
    io.write("Downloading " .. file .. " ... ")

    local ok = os.execute(
        "wget -fq " ..
        REPO .. file .. " " ..
        "/" .. file
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
