local M = {}

-- Default configuration
M.config = {
  highlight_duration = 1500,
  remote_branch = "origin/main",
  use_gh_cli = true, -- Use gh pr diff when available
  cache_ttl = 30, -- Seconds before cache expires (0 = always refresh)
  keymaps = {
    local_next = "<leader>gj",
    local_prev = "<leader>gk",
    remote_next = "<leader>gl",
    remote_prev = "<leader>gh",
  },
}

-- Internal state
local state = {
  local_hunks = {},
  remote_hunks = {},
  local_index = 0,
  remote_index = 0,
  local_cache_time = 0,
  remote_cache_time = 0,
  local_refreshing = false,
  remote_refreshing = false,
  ns_id = nil,
}

-- Navigation command definitions (single source of truth)
local NAVIGATION_COMMANDS = {
  { name = "local_next", command = "DiffNavLocalNext", direction = 1, is_remote = false, desc = "Local diff: next hunk" },
  { name = "local_prev", command = "DiffNavLocalPrev", direction = -1, is_remote = false, desc = "Local diff: previous hunk" },
  { name = "remote_next", command = "DiffNavRemoteNext", direction = 1, is_remote = true, desc = "Remote diff: next hunk" },
  { name = "remote_prev", command = "DiffNavRemotePrev", direction = -1, is_remote = true, desc = "Remote diff: previous hunk" },
}

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================

local function get_git_root()
  local result = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil, "Not in a git repository"
  end
  return vim.trim(result), nil
end

local function clamp_line(line, max_line)
  return math.max(1, math.min(line, max_line))
end

local function is_gh_available()
  vim.fn.system("gh auth status 2>/dev/null")
  return vim.v.shell_error == 0
end

local function is_github_remote()
  local result = vim.fn.system("git remote get-url origin 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return false
  end
  return result:match("github%.com") ~= nil
end

local function run_gh_pr_diff()
  local result = vim.fn.system({ "gh", "pr", "diff", "--patch" })
  if vim.v.shell_error ~= 0 then
    return nil, "gh pr diff failed"
  end
  return result, nil
end

local function run_git_diff(diff_target)
  local cmd = { "git", "diff", "--no-color", "--unified=0" }
  if diff_target then
    table.insert(cmd, diff_target)
  end

  local result = vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    return nil, "Git diff failed"
  end
  return result, nil
end

-- Forward declaration for async refresh (parse_diff defined later)
local refresh_cache_async

-- ==========================================
-- DIFF PARSING
-- ==========================================

local function parse_diff(diff_output)
  local hunks = {}
  local current_file = nil

  for line in diff_output:gmatch("[^\r\n]+") do
    local file_match = line:match("^diff %-%-git a/.- b/(.+)$")
    if file_match then
      current_file = file_match
    end

    local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")

    if old_start and current_file then
      old_start = tonumber(old_start)
      old_count = tonumber(old_count) or 1
      new_start = tonumber(new_start)
      new_count = tonumber(new_count) or 1

      local hunk_type, target_line, end_line

      if new_count == 0 then
        hunk_type = "delete"
        target_line = old_start
        end_line = old_start
      else
        -- Both "add" (old_count == 0) and "change" use same line calculation
        hunk_type = old_count == 0 and "add" or "change"
        target_line = new_start
        end_line = new_start + new_count - 1
      end

      table.insert(hunks, {
        file = current_file,
        line = target_line,
        end_line = end_line,
        type = hunk_type,
      })
    end
  end

  return hunks
end

-- Async refresh implementation (runs in background, updates state when done)
refresh_cache_async = function(is_remote)
  local refreshing_key = is_remote and "remote_refreshing" or "local_refreshing"

  -- Don't start another refresh if one is in progress
  if state[refreshing_key] then
    return
  end
  state[refreshing_key] = true

  local diff_type = is_remote and "remote" or "local"
  vim.notify("Refreshing " .. diff_type .. " diff...", vim.log.levels.INFO)

  -- Build command based on config
  local cmd
  if is_remote and M.config.use_gh_cli then
    -- Try gh first, fall back to git diff
    cmd = "gh pr diff --patch 2>/dev/null || git diff --no-color --unified=0 " .. M.config.remote_branch
  elseif is_remote then
    cmd = "git diff --no-color --unified=0 " .. M.config.remote_branch
  else
    cmd = "git diff --no-color --unified=0"
  end

  local output_chunks = {}

  vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data)
      if data then
        output_chunks = data
      end
    end,
    on_exit = function(_, exit_code)
      state[refreshing_key] = false
      if exit_code == 0 then
        local output = table.concat(output_chunks, "\n")
        local hunks = parse_diff(output)
        local now = vim.loop.now() / 1000
        if is_remote then
          state.remote_hunks = hunks
          state.remote_cache_time = now
        else
          state.local_hunks = hunks
          state.local_cache_time = now
        end
      end
    end,
  })
end

-- ==========================================
-- CACHE MANAGEMENT
-- ==========================================

local function refresh_cache(is_remote, force)
  local now = vim.loop.now() / 1000 -- Current time in seconds
  local cache_time_key = is_remote and "remote_cache_time" or "local_cache_time"
  local hunks_key = is_remote and "remote_hunks" or "local_hunks"

  local has_cache = #state[hunks_key] > 0
  local age = now - state[cache_time_key]
  local is_stale = M.config.cache_ttl > 0 and age >= M.config.cache_ttl

  -- Fresh cache: return immediately
  if not force and has_cache and not is_stale then
    return true, nil
  end

  -- Stale cache with data: return stale + trigger background refresh
  if not force and has_cache and is_stale then
    refresh_cache_async(is_remote)
    return true, nil -- Use stale data, refresh happens in background
  end

  -- No cache or forced: must fetch synchronously (blocking)
  local diff_type = is_remote and "remote" or "local"
  vim.notify("Fetching " .. diff_type .. " diff...", vim.log.levels.INFO)

  local output, err

  if is_remote then
    -- Try gh pr diff first if enabled and available
    if M.config.use_gh_cli and is_gh_available() and is_github_remote() then
      output, err = run_gh_pr_diff()
    end
    -- Fall back to git diff
    if not output then
      output, err = run_git_diff(M.config.remote_branch)
    end
  else
    output, err = run_git_diff(nil)
  end

  if err or not output then
    return false, err or "Unknown error"
  end

  local hunks = parse_diff(output)

  if is_remote then
    state.remote_hunks = hunks
    state.remote_cache_time = now
  else
    state.local_hunks = hunks
    state.local_cache_time = now
  end

  return true, nil
end

-- ==========================================
-- HIGHLIGHTING
-- ==========================================

local function highlight_region(bufnr, start_line, end_line)
  if not state.ns_id then
    state.ns_id = vim.api.nvim_create_namespace("diff_navigator")
  end

  vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id, 0, -1)

  local hl_group = "DiffAdd"

  for lnum = start_line, end_line do
    -- Silently ignore highlight errors (e.g., invalid line numbers at buffer edges)
    pcall(vim.api.nvim_buf_add_highlight, bufnr, state.ns_id, hl_group, lnum - 1, 0, -1)
  end

  vim.defer_fn(function()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_clear_namespace(bufnr, state.ns_id, 0, -1)
    end
  end, M.config.highlight_duration)
end

-- ==========================================
-- NAVIGATION
-- ==========================================

local function jump_to_hunk(hunk)
  local git_root, git_err = get_git_root()
  if not git_root then
    vim.notify(git_err, vim.log.levels.ERROR)
    return
  end

  local filepath = git_root .. "/" .. hunk.file

  if vim.fn.filereadable(filepath) == 0 then
    vim.notify("File not found: " .. hunk.file, vim.log.levels.WARN)
    return
  end

  local current_file = vim.fn.expand("%:p")
  if current_file ~= filepath then
    vim.cmd("edit " .. vim.fn.fnameescape(filepath))
  end

  local line_count = vim.api.nvim_buf_line_count(0)
  local target_line = clamp_line(hunk.line, line_count)

  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd("normal! zz")

  local end_line = clamp_line(hunk.end_line, line_count)
  highlight_region(0, target_line, end_line)
end

local function navigate(direction, is_remote)
  local success, err = refresh_cache(is_remote)
  if not success then
    vim.notify("Failed to get diff: " .. (err or ""), vim.log.levels.ERROR)
    return
  end

  local hunks = is_remote and state.remote_hunks or state.local_hunks
  local index_key = is_remote and "remote_index" or "local_index"

  if #hunks == 0 then
    local diff_type = is_remote and "remote" or "local"
    vim.notify("No " .. diff_type .. " diff hunks found", vim.log.levels.INFO)
    return
  end

  local current_index = state[index_key]
  local new_index = current_index + direction
  local wrapped = false

  if new_index > #hunks then
    new_index = 1
    wrapped = true
  elseif new_index < 1 then
    new_index = #hunks
    wrapped = true
  end

  state[index_key] = new_index

  if wrapped then
    local wrap_msg = direction > 0 and "Wrapped to first hunk" or "Wrapped to last hunk"
    vim.notify(wrap_msg, vim.log.levels.INFO)
  end

  local hunk = hunks[new_index]
  jump_to_hunk(hunk)

  vim.notify(string.format("Hunk %d/%d in %s", new_index, #hunks, hunk.file), vim.log.levels.INFO)
end

-- ==========================================
-- PUBLIC API
-- ==========================================

-- Generate public API functions from NAVIGATION_COMMANDS
for _, cmd in ipairs(NAVIGATION_COMMANDS) do
  M[cmd.name] = function()
    navigate(cmd.direction, cmd.is_remote)
  end
end

-- Manual cache refresh functions
function M.refresh_remote()
  local success, err = refresh_cache(true, true)
  if success then
    vim.notify("Remote diff cache refreshed (" .. #state.remote_hunks .. " hunks)", vim.log.levels.INFO)
  else
    vim.notify("Failed to refresh remote cache: " .. (err or ""), vim.log.levels.ERROR)
  end
end

function M.refresh_local()
  local success, err = refresh_cache(false, true)
  if success then
    vim.notify("Local diff cache refreshed (" .. #state.local_hunks .. " hunks)", vim.log.levels.INFO)
  else
    vim.notify("Failed to refresh local cache: " .. (err or ""), vim.log.levels.ERROR)
  end
end

-- ==========================================
-- SETUP
-- ==========================================

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Create user commands from NAVIGATION_COMMANDS
  for _, cmd in ipairs(NAVIGATION_COMMANDS) do
    vim.api.nvim_create_user_command(cmd.command, M[cmd.name], {})
  end

  -- Create refresh commands
  vim.api.nvim_create_user_command("DiffNavRefreshRemote", M.refresh_remote, {})
  vim.api.nvim_create_user_command("DiffNavRefreshLocal", M.refresh_local, {})

  -- Set up keymaps from NAVIGATION_COMMANDS (unless disabled)
  if M.config.keymaps then
    for _, cmd in ipairs(NAVIGATION_COMMANDS) do
      local keymap = M.config.keymaps[cmd.name]
      if keymap then
        vim.keymap.set("n", keymap, M[cmd.name], { desc = cmd.desc })
      end
    end
  end
end

return M
