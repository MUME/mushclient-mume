require("mystdlib")
local getch = require("getch")
local json = require("dkjson")
local lfs = require("lfs")

local RELEASE_INFO_FILE = "update_info.ignore"
local ZIP_FILE = "mapper_proxy.zip"


local function load_last_info()
	local release_data = {}
	if os.isFile(RELEASE_INFO_FILE) then
		local fileObj = io.open(RELEASE_INFO_FILE, "rb")
		release_data = json.decode(fileObj:read("*all"), 1, nil)
		fileObj:close()
	end
	release_data.tag_name = release_data.tag_name or ""
	release_data.download_url = release_data.download_url or ""
	release_data.updated_at = release_data.updated_at or ""
	return release_data
end

local function save_last_info(tbl)
	local orderedKeys = {}
	for k, v in pairs(tbl) do
		table.insert(orderedKeys, k)
	end
	table.sort(orderedKeys)
	local handle = io.open(RELEASE_INFO_FILE, "wb")
	handle:write(json.encode(tbl, {indent=true, level=0, keyorder=orderedKeys}))
	handle:close()
end

local function latest_release_information(user, repo)
	local command = string.format("curl.exe --silent --location --retry 999 --retry-max-time 0 --continue-at - \"https://api.github.com/repos/%s/%s/releases/latest\"", user, repo)
	local handle = io.popen(command)
	local result = handle:read("*all")
	local gh = json.decode(result, 1, nil)
	handle:close()
	local release_data = {}
	if gh then
		release_data.tag_name = gh.tag_name
		for i, asset in ipairs(gh.assets) do
			if string.startswith(asset.name, "Mapper_Proxy_V") and string.endswith(asset.name, ".zip") then
				release_data.download_url = asset.browser_download_url
				release_data.size = asset.size
				release_data.updated_at = asset.updated_at
			elseif string.startswith(asset.name, "Mapper_Proxy_V") and string.endswith(asset.name, ".zip.sha256") then
				release_data.sha256_url = asset.browser_download_url
			end
		end
	end
	release_data.tag_name = release_data.tag_name or ""
	release_data.download_url = release_data.download_url or ""
	release_data.size = release_data.size or 0
	release_data.updated_at = release_data.updated_at or ""
	release_data.sha256_url = release_data.sha256_url or ""
	return release_data
end

local function prompt_for_update()
	io.write("Update now? (Y to update, N to skip this release in future, Q to exit and do nothing) ")
	local response = string.lower(string.strip(getch.getch()))
	io.write("\n")
	if response == "" then
		return prompt_for_update()
	elseif response == "y" then
		return "y"
	elseif response == "n" then
		return "n"
	elseif response == "q" then
		return "q"
	else
		print("Invalid response. Please try again.")
		return prompt_for_update()
	end
end

local function do_download(release)
	local hash
	print(string.format("Downloading Mapper Proxy %s (%s).", release.tag_name, release.updated_at))
	if release.sha256_url ~= "" then
		local handle = io.popen(string.format("curl.exe --silent --location --retry 999 --retry-max-time 0 --continue-at - \"%s\"", release.sha256_url))
		hash = string.lower(string.strip(handle:read("*all")))
		handle:close()
		if not string.endswith(hash, ".zip") then
			print(string.format("Invalid checksum '%s'", hash))
			return false
		end
		hash = string.match(hash, "^%S+")
	end
	os.execute(string.format("curl.exe --silent --location --retry 999 --retry-max-time 0 --continue-at - --output %s \"%s\"", ZIP_FILE, release.download_url))
	local downloaded_size , error = os.fileSize(ZIP_FILE)
	if downloaded_size and downloaded_size > 0 and downloaded_size == release.size then
		print("Verifying download.")
		local zip_file_hash = sha256sum_file(ZIP_FILE)
		if not hash then
			print("Error: file size verified but no checksum available. Aborting.")
		elseif zip_file_hash == hash then
			save_last_info(release)
			print("OK.")
			return true
		else
			print("Error: checksums do not match. Aborting.")
		end
	elseif error then
		print(error)
	else
		print("Error downloading release: Downloaded file size and reported size from GitHub do not match.")
	end
	if os.isFile(ZIP_FILE) then
		os.remove(ZIP_FILE)
	end
	return false
end

function do_extract()
	local pwd = lfs.currentdir()
	print("Extracting files.")
	os.execute(string.format("unzip.exe -qq \"%s\" -d \"tempmapper\"", ZIP_FILE))
	if os.isFile(ZIP_FILE) then
		os.remove(ZIP_FILE)
	end
	if not lfs.chdir(pwd .. "\\tempmapper") then
		return print(string.format("Error: failed to change directory to '%s\\tempmapper'", pwd))
	end
	local copy_from
	for item in lfs.dir(lfs.currentdir()) do
		if lfs.attributes(item, "mode") == "directory" and string.startswith(string.lower(item), "mapper_proxy_v") then
			copy_from = string.format("tempmapper\\%s", item)
			break
		end
	end
	lfs.chdir(pwd)
	os.execute(string.format("xcopy \"%s\" \"mapper_proxy\" /E /V /I /Q /R /Y", copy_from))
	os.execute("rd /S /Q \"tempmapper\"")
	print("Done.")
end

local function pause()
	io.write("Press any key to continue.")
	getch.getch()
	io.write("\n")
end

local function called_by_script()
	for i, a in ipairs(arg) do
		if string.strip(string.lower(a)) == "/calledbyscript" then
			return true
		end
	end
	return false
end


local last = load_last_info()
local latest = latest_release_information("nstockton", "mapperproxy-mume")

-- Clean up previously left junk.
if os.isFile(ZIP_FILE) then
	os.remove(ZIP_FILE)
end
if os.isDir("tempmapper") then
	os.execute("rd /S /Q \"tempmapper\"")
end

if os.isDir("mapper_proxy") and not called_by_script() then
	print("Checking for updates to the mapper.")
end

if not os.isDir("mapper_proxy") then
	print("Mapper Proxy not found. This is normal for new installations.")
	if do_download(latest) then
		do_extract()
	end
elseif last.skipped_release and last.skipped_release == latest.tag_name .. latest.updated_at then
	print(string.format("The update to %s dated %s was previously skipped.", latest.tag_name, latest.updated_at))
	if called_by_script() then
		os.exit(0)
	end
elseif last.tag_name .. last.updated_at == latest.tag_name .. latest.updated_at then
	print(string.format("You are currently running the latest Mapper Proxy (%s) dated %s.", latest.tag_name, latest.updated_at))
	if called_by_script() then
		os.exit(0)
	end
else
	print(string.format("A new version of Mapper Proxy (%s) dated %s was found.", latest.tag_name, latest.updated_at))
	local user_choice = prompt_for_update()
	if user_choice == "y" then
		if do_download(latest) then
			do_extract()
		end
	elseif user_choice == "n" then
		print("You will no longer be prompted to download this version of Mapper Proxy.")
		last.skipped_release = latest.tag_name .. latest.updated_at
		save_last_info(last)
	end
end

pause()
os.exit(0)