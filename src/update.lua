function download_update(sha)

    local sha_file = "annas_last_sha.txt"


    local function save_sha(sha)
        local file = io.open(sha_file, "w")
        if file then
            file:write(sha)
            file:close()
        end
    end

    local resp = {}

    local owner = "fischer-hub"    -- GitHub repo owner
    local repo = "annas.koplugin"      -- GitHub repo name
    local branch = "main"         -- branch to check
    local zip_url = string.format("https://github.com/%s/%s/archive/refs/heads/%s.zip", owner, repo, branch)
    print("Downloading latest version...")

    -- Download ZIP
    local command = string.format('curl -L -s -o latest.zip "%s"', zip_url)
    local handle = io.popen(command)

    if not handle then
        resp.err = 1
        resp.msg = "Failed to download update files."
        return resp
    end

    local result = handle:read("*a")
    handle:close()

    -- Make temp folder
    handle = io.popen('mkdir -p temp_update')

    handle = io.popen('unzip -q latest.zip -d temp_update')
    -- Unzip into temp folder
    handle = io.popen('rm latest.zip')

    -- The extracted folder is usually repo-branch
    local folder_name = string.format("temp_update/%s-%s", repo, branch)

    -- Copy all files from extracted folder to current directory
    -- -r = recursive, -u = update only if newer
    handle = io.popen(string.format('cp -ru "%s/"* .', folder_name))
    

    -- Clean up temp folder
    handle = io.popen('rm -rf temp_update')


    save_sha(sha)
    resp.err = 0
    resp.msg = "Update installed sucessfully! Please restart."
    return resp

end

function check_version(plugin_path)

    local owner = "fischer-hub"    -- GitHub repo owner
    local repo = "annas.koplugin"      -- GitHub repo name
    local branch = "main"         -- branch to check
    local sha_file = "annas_last_sha.txt"

    local url = string.format("https://api.github.com/repos/%s/%s/commits/%s", owner, repo, branch)

    -- Read last saved SHA
    local function read_last_sha()
        local file = io.open(sha_file, "r")
        if file then
            local sha = file:read("*l")
            file:close()
            print("found sha in local file: " .. sha)
            return sha
        end
        print('no local sha saved')
        return nil
    end

    -- Save SHA to file
    local function save_sha(sha)
        local file = io.open(sha_file, "w")
        if file then
            file:write(sha)
            file:close()
        end
    end

    -- Use curl to get latest commit JSON from GitHub API
    local function get_latest_sha()
        local command = string.format('curl -s -H "User-Agent: Lua Script" "%s"', url)
        local handle = io.popen(command)
        if not handle then return nil end
        local result = handle:read("*a")
        handle:close()
    
        -- Extract the first "sha":"..." from JSON
        -- The %x+ pattern matches a sequence of hex digits
        local sha = result:match('"sha"%s*:%s*"(%x+)"')
        return sha
    end

    -- Main logic
    local last_sha = read_last_sha()
    local latest_sha = get_latest_sha()

    local resp = {}
    if not latest_sha then
        print("Could not get latest commit SHA")
        resp.msg ="Failed, could not get latest commit SHA"
        resp.err = 1
        return resp
    end
    if last_sha == nil then
        print("No previous SHA found. Saving current SHA:", latest_sha)
        save_sha(latest_sha)
        resp.msg = 'Failed, no previous SHA found, please try again.'
        resp.err = 1
        return resp
    elseif last_sha ~= latest_sha then
        resp.msg = "Update available, trying to install ..."
        resp.sha = latest_sha
        resp.err = 0
        return  resp
        --download_update(latest_sha)
        --save_sha(latest_sha)
    else
        print("No updates. Latest commit SHA:", latest_sha)
        resp.msg = "Already Up to Date!"
        resp.err = 2
        return resp
    end
end



if ... == nil then
    -- This block runs only if executed directly:
    result = check_version('.')
    print(result)
end