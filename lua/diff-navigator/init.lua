local M = {}

-- Default configuration
M.config = {
  highlight_duration = 1500,
  remote_branch = "origin/main",
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
  ns_id = nil,
}

-- ==========================================
-- UTILITY FUNCTIONS
-- ==========================================

local function get_git_root()
  local result = vim.fn.system("git rev-parse --show-toplevel 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
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
      elseif old_count == 0 then
        hunk_type = "add"
        target_line = new_start
        end_line = new_start + new_count - 1
      else
        hunk_type = "change"
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

-- ==========================================
-- CACHE MANAGEMENT
-- ==========================================

local function refresh_cache(is_remote)
  local diff_target = is_remote and M.config.remote_branch or nil
  local output, err = run_git_diff(diff_target)

  if err or not output then
    return false, err or "Unknown error"
  end

  local hunks = parse_diff(output)

  if is_remote then
    state.remote_hunks = hunks
  else
    state.local_hunks = hunks
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
  local git_root = get_git_root()
  if not git_root then
    vim.notify("Not in a git repository", vim.log.levels.ERROR)
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

  local target_line = math.max(1, hunk.line)
  local line_count = vim.api.nvim_buf_line_count(0)
  target_line = math.min(target_line, line_count)

  vim.api.nvim_win_set_cursor(0, { target_line, 0 })
  vim.cmd("normal! zz")

  local end_line = math.min(hunk.end_line, line_count)
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

function M.local_next()
  navigate(1, false)
end

function M.local_prev()
  navigate(-1, false)
end

function M.remote_next()
  navigate(1, true)
end

function M.remote_prev()
  navigate(-1, true)
end

-- ==========================================
-- SETUP
-- ==========================================

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})

  -- Create user commands
  vim.api.nvim_create_user_command("DiffNavLocalNext", M.local_next, {})
  vim.api.nvim_create_user_command("DiffNavLocalPrev", M.local_prev, {})
  vim.api.nvim_create_user_command("DiffNavRemoteNext", M.remote_next, {})
  vim.api.nvim_create_user_command("DiffNavRemotePrev", M.remote_prev, {})

  -- Set up keymaps (unless disabled)
  if M.config.keymaps then
    local keymaps = M.config.keymaps
    if keymaps.local_next then
      vim.keymap.set("n", keymaps.local_next, M.local_next, { desc = "Local diff: next hunk" })
    end
    if keymaps.local_prev then
      vim.keymap.set("n", keymaps.local_prev, M.local_prev, { desc = "Local diff: previous hunk" })
    end
    if keymaps.remote_next then
      vim.keymap.set("n", keymaps.remote_next, M.remote_next, { desc = "Remote diff: next hunk" })
    end
    if keymaps.remote_prev then
      vim.keymap.set("n", keymaps.remote_prev, M.remote_prev, { desc = "Remote diff: previous hunk" })
    end
  end
end

return M
