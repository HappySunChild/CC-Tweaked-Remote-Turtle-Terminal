local ERR_DOWNLOAD_FAIL = "Unable to download file '%s'"
local ERR_MAX_ATTEMPTS_REACH = "Unable to download %d file(s) after %d attempts.\nFiles:\n%s"

local BASE_URL =
	"https://raw.githubusercontent.com/HappySunChild/CC-Tweaked-Remote-Turtle-Terminal/refs/heads/master/src/terminal/"
local FILES = {
	"main.lua",
}

local MAX_ATTEMPTS = 5

local function downloadFiles(list, attempt)
	attempt = attempt or 1

	if attempt > MAX_ATTEMPTS then
		printError(ERR_MAX_ATTEMPTS_REACH:format(#list, MAX_ATTEMPTS, table.concat(list, "\n")))

		return
	end

	local retry = {}

	for _, file in ipairs(list) do
		if fs.exists(file) then
			fs.delete(file)
		end

		local downloadUrl = BASE_URL .. file
		local success = shell.execute("wget", downloadUrl, file)

		if not success or not fs.exists(file) then
			printError(ERR_DOWNLOAD_FAIL:format(file))

			table.insert(retry, file)
		end
	end

	if #retry > 0 then
		downloadFiles(retry, attempt + 1)
	end
end

downloadFiles(FILES)
