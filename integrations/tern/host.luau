--!strict
-- Tern 0.9.12: native host block; TypeScript owns all Beads command semantics.
local ui = tern.ui
local iconSources = tern.json.decode(tern.fs.read(tern.plugin.dir .. "/icons.json"))
local issueTypes = { "task", "bug", "feature", "chore", "epic", "decision", "spike", "story", "milestone" }
local priorities = { "0", "1", "2", "3", "4" }

type Issue = {
	id: string, title: string, description: string, status: string, priority: number,
	type: string, assignee: string, labels: { string }, dependencies: { { id: string, type: string } },
	notes: string?, acceptance: string?, design: string?, updatedAt: string?,
}
type Snapshot = { issues: { Issue }, readyIds: { string }, blockedIds: { string }, fetchedAt: string }
type Field = { name: string, label: string, text: string, baseline: string, cursor: number, anchor: number? }
type Form = { method: string, title: string, id: string?, fields: { Field }, focus: number }
type State = {
	cwd: string?, snapshot: Snapshot?, selected: string?, filter: string, layout: string,
	busy: boolean, refreshing: boolean, generation: number, error: string?, form: Form?, comments: { any }?,
	query: Field, searching: boolean, typeFilter: string, priorityFilter: string,
	assigneeFilter: string, showClosed: boolean, spotlight: boolean, sortKey: string, sortAscending: boolean,
	dependencyId: string, dependencyType: string, comment: Field, commenting: boolean,
	icons: { [string]: string },
}

local function props(node: Node, values: { [string]: any }): Node
	local p = node.p or {}
	for key, value in values do p[key] = value end
	node.p = p
	return node
end

local function running(cx: BlockCx): boolean
	for _, pane in tern.pane.list() do
		if pane.pane == cx.pane then return true end
	end
	return false
end

local function current(state: State): Issue?
	if state.snapshot then
		for _, issue in state.snapshot.issues do
			if issue.id == state.selected then return issue end
		end
	end
	return nil
end

local function statusGroup(snapshot: Snapshot, issue: Issue): string
	if issue.status == "closed" then return "closed" end
	if issue.status == "blocked" or table.find(snapshot.blockedIds, issue.id) ~= nil then return "blocked" end
	if issue.status == "in_progress" or issue.status == "deferred" then return issue.status end
	if table.find(snapshot.readyIds, issue.id) ~= nil then return "ready" end
	return "other"
end

-- UTC timestamps from the bridge use ISO 8601. os.time(table) is local in Tern.
local function epoch(iso: string?): number?
	if not iso then return nil end
	local y, m, d, hh, mm, ss = string.match(iso, "^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
	if not (y and m and d and hh and mm and ss) then return nil end
	local year, month, day = tonumber(y) :: number, tonumber(m) :: number, tonumber(d) :: number
	if month <= 2 then year -= 1 end
	local era = year // 400
	local yoe = year - era * 400
	local doy = (153 * (if month > 2 then month - 3 else month + 9) + 2) // 5 + day - 1
	local days = era * 146097 + yoe * 365 + yoe // 4 - yoe // 100 + doy - 719468
	return days * 86400 + (tonumber(hh) :: number) * 3600 + (tonumber(mm) :: number) * 60 + (tonumber(ss) :: number)
end

local function relativeTime(iso: string?): string
	local time = epoch(iso)
	if not time then return "" end
	local minutes = math.max(0, (os.time() - time) // 60)
	if minutes < 1 then return "just now" end
	if minutes < 60 then return tostring(minutes) .. "m ago" end
	if minutes < 1440 then return tostring(minutes // 60) .. "h ago" end
	return tostring(minutes // 1440) .. "d ago"
end

local function visible(state: State): { Issue }
	local result: { Issue } = {}
	local snapshot = state.snapshot
	if not snapshot then return result end
	local query = string.lower(string.match(state.query.text, "^%s*(.-)%s*$") or "")
	for _, issue in snapshot.issues do
		local group = statusGroup(snapshot, issue)
		local haystack = string.lower(table.concat({ issue.id, issue.title, issue.description, issue.assignee, table.concat(issue.labels, " ") }, " "))
		if (state.showClosed or group ~= "closed")
			and (state.filter == "all"
				or (state.filter == "ready" and group == "ready")
				or (state.filter == "active" and group == "in_progress")
				or state.filter == group)
			and (state.typeFilter == "" or state.typeFilter == issue.type)
			and (state.priorityFilter == "" or state.priorityFilter == tostring(issue.priority))
			and (state.assigneeFilter == "" or state.assigneeFilter == issue.assignee)
			and (query == "" or string.find(haystack, query, 1, true) ~= nil) then
			table.insert(result, issue)
		end
	end
	table.sort(result, function(a, b)
		if a.priority == b.priority then return a.id < b.id end
		return a.priority < b.priority
	end)
	return result
end

local function request(state: State, cx: BlockCx, method: string, input: { [string]: any }?, done: (any) -> (), background: boolean?)
	if state.busy or (background and state.refreshing) or not running(cx) then return end
	if not state.cwd then
		state.error = "This block has no workspace directory. Open it beside a shell in a Beads project."
		return
	end
	if background then
		state.refreshing = true
	else
		state.busy = true
		state.generation += 1
	end
	local generation = state.generation
	local ok, err = pcall(function()
		tern.process.run({ tern.getenv("BEADS_TERN_NODE") or "node", tern.plugin.dir .. "/bridge.mjs" }, {
			cwd = state.cwd,
			stdin = tern.json.encode({ method = method, project = "workspace", input = input }),
			timeout_ms = 120000,
		}, function(result)
			if not running(cx) then return end
			if background then
				state.refreshing = false
				-- A user operation supersedes the read that began before it.
				if state.generation ~= generation then return end
			else
				state.busy = false
			end
			local decoded, body = pcall(tern.json.decode, result.stdout)
			if decoded and type(body) == "table" and body.ok == true and result.status == 0 then
				state.error = nil
				done(body.result)
			else
				state.error = if decoded and type(body) == "table" and type(body.error) == "string" then body.error
					elseif result.timed_out then "Beads request timed out. Refresh before retrying a mutation; it may have completed."
					else "Beads bridge failed (exit " .. tostring(result.status) .. "): " .. result.stderr .. result.stdout
			end
			cx:render()
		end)
	end)
	if not ok then
		if background then state.refreshing = false else state.busy = false end
		state.error = "Cannot start Beads bridge: " .. tostring(err)
	end
end

local function loadComments(state: State, cx: BlockCx)
	local id = state.selected
	if not id then return end
	request(state, cx, "comments", { id = id }, function(result)
		if state.selected == id and type(result) == "table" then state.comments = result end
	end)
end

local function refresh(state: State, cx: BlockCx, withComments: boolean?, background: boolean?)
	request(state, cx, "snapshot", nil, function(snapshot)
		state.snapshot = snapshot
		if not current(state) then state.selected = nil end
		if withComments and state.selected then loadComments(state, cx) end
	end, background)
end

local function selectIssue(state: State, cx: BlockCx, id: string)
	state.selected, state.comments = id, nil
	state.form = nil
	state.dependencyId, state.dependencyType = "", "blocks"
	state.comment.text, state.comment.cursor, state.comment.anchor, state.commenting = "", 0, nil, false
	if current(state) then loadComments(state, cx) end
end

local function mutate(state: State, cx: BlockCx, method: string, input: { [string]: any })
	request(state, cx, method, input, function(_result)
		state.form, state.comments = nil, nil
		state.comment.text, state.comment.cursor, state.comment.anchor, state.commenting = "", 0, nil, false
		state.dependencyId = ""
		cx:frame({ { "focus", tern.json.null } })
		refresh(state, cx, true)
	end)
end

-- Keep all cursor math in UTF-16, the public Tern input contract, not UTF-8 bytes.
local function length16(text: string): number
	local count = 0
	for _, cp in utf8.codes(text) do count += if cp > 65535 then 2 else 1 end
	return count
end

local function byteAt(text: string, offset: number): number
	local units = 0
	for pos, cp in utf8.codes(text) do
		local width = if cp > 65535 then 2 else 1
		if units + width > offset then return pos end
		units += width
	end
	return #text + 1
end

local function replace(field: Field, from: number, to: number, text: string)
	local start = byteAt(field.text, from)
	field.text = string.sub(field.text, 1, start - 1) .. text .. string.sub(field.text, byteAt(field.text, to))
	field.cursor = length16(string.sub(field.text, 1, start - 1)) + length16(text)
	field.anchor = nil
end

local function editField(field: Field, key: any, multiline: boolean): boolean
	local cursor, anchor = field.cursor, field.anchor
	local from, to = math.min(cursor, anchor or cursor), math.max(cursor, anchor or cursor)
	if (key.ctrl or key.meta) and key.name == "a" then
		field.anchor, field.cursor = 0, length16(field.text)
		return true
	end
	local moving = key.name == "home" or key.name == "end" or key.name == "left" or key.name == "right"
	if key.name == "home" then field.cursor = 0
	elseif key.name == "end" then field.cursor = length16(field.text)
	elseif (key.name == "backspace" or key.name == "delete") and from ~= to then replace(field, from, to, "")
	elseif key.name == "left" and from ~= to and not key.shift then field.cursor = from
	elseif key.name == "right" and from ~= to and not key.shift then field.cursor = to
	elseif key.name == "left" or key.name == "backspace" then
		local pos = byteAt(field.text, cursor)
		local previous = if pos > 1 then (utf8.offset(field.text, -1, pos) or 1) else 1
		local offset = length16(string.sub(field.text, 1, previous - 1))
		if key.name == "backspace" then replace(field, offset, cursor, "") else field.cursor = offset end
	elseif key.name == "right" or key.name == "delete" then
		local pos = byteAt(field.text, cursor)
		local nextPos = if pos <= #field.text then (utf8.offset(field.text, 2, pos) or (#field.text + 1)) else (#field.text + 1)
		local offset = length16(string.sub(field.text, 1, nextPos - 1))
		if key.name == "delete" then replace(field, cursor, offset, "") else field.cursor = offset end
	elseif key.name == "enter" and multiline then replace(field, from, to, "\n")
	elseif key.text and not key.ctrl and not key.meta and not key.alt then replace(field, from, to, key.text)
	else return false end
	if moving then field.anchor = if key.shift then (anchor or cursor) else nil end
	return true
end

local function formPrefix(form: Form): string
	return if form.method == "update" then "main.app.detail.edit.body" else "main.form.body"
end

local function fieldChoices(field: Field): { string }?
	return if field.name == "type" then issueTypes elseif field.name == "priority" then priorities else nil
end

local function multilineField(field: Field): boolean
	return field.name == "description" or field.name == "notes" or field.name == "acceptance" or field.name == "design"
end

local function focusForm(state: State, cx: BlockCx)
	local form = state.form
	if form then
		cx:render()
		cx:frame({ { "focus", formPrefix(form) .. ".f" .. tostring(form.focus) .. ".input" } })
	end
end

local function openForm(state: State, cx: BlockCx, method: string)
	local issue = current(state)
	if method ~= "create" and not issue then return end
	state.searching = false
	local fields: { Field } = {}
	local function field(name: string, label: string, value: string?)
		local text = value or ""
		table.insert(fields, { name = name, label = label, text = text, baseline = text, cursor = length16(text) })
	end
	if method == "create" or method == "update" then
		field("title", "Title", if method == "update" and issue then issue.title else "")
		if method == "create" then field("type", "Type", "task") end
		if method == "update" then field("description", "Description", if issue then issue.description else "") end
		field("priority", "Priority", if method == "update" and issue then tostring(issue.priority) else "2")
		if method == "create" then field("description", "Description", "") end
		field("assignee", "Assignee", if method == "update" and issue then issue.assignee else "")
		if method == "create" then
			field("labels", "Labels, comma separated", "")
		elseif issue then
			field("notes", "Notes", issue.notes)
			field("acceptance", "Acceptance criteria", issue.acceptance)
			field("design", "Design", issue.design)
		end
	elseif method == "close" then
		field("reason", "Closing reason (optional)", "")
	end
	local titles = { create = "New issue", update = "Edit issue", close = "Close issue" }
	state.form = { method = method, title = titles[method] or method, id = if method == "create" then nil else (if issue then issue.id else nil), fields = fields, focus = 1 }
	focusForm(state, cx)
end

local function submit(state: State, cx: BlockCx)
	local form = state.form
	if not form or state.busy then return end
	local input: { [string]: any } = { id = form.id }
	local changed = false
	for _, field in form.fields do
		if form.method == "update" and field.text == field.baseline then continue end
		changed = true
		if field.name == "priority" then
			local priority = tonumber(field.text)
			if not priority or priority < 0 or priority > 4 or priority % 1 ~= 0 then
				state.error = "Priority must be an integer from 0 to 4."
				return
			end
			input.priority = priority
		elseif field.name == "labels" then
			local labels: { string } = {}
			for label in string.gmatch(field.text, "[^,]+") do
				local trimmed = string.match(label, "^%s*(.-)%s*$") or ""
				if trimmed ~= "" then table.insert(labels, trimmed) end
			end
			input.labels = tern.json.array(labels)
		else
			input[field.name] = field.text
		end
	end
	if form.method == "update" and not changed then
		state.form, state.error = nil, nil
		cx:frame({ { "focus", tern.json.null } })
		return
	end
	mutate(state, cx, form.method, input)
end

local function graphic(state: State, name: string): Node
	return ui.node("image", { blob = state.icons[name] or state.icons.type_task, alt = "", w = 18, h = 18, role = "beads-icon" })
end

local function button(state: State, label: string, action: string, primary: boolean?, iconName: string?, keycap: string?, disabled: boolean?): Node
	local blocked = state.busy or disabled == true
	local children: { Node } = {}
	if iconName then table.insert(children, graphic(state, iconName)) end
	if label ~= "" then table.insert(children, ui.el("span", { text = label })) end
	if keycap then table.insert(children, ui.el("kbd", { text = keycap })) end
	return ui.el("button", {
		class = "beads-button" .. (if primary then " primary" else ""),
		actions = if blocked then nil else { click = action },
		attrs = { ["aria-disabled"] = blocked },
	}, children)
end

local function act(state: State, cx: BlockCx, action: string, value: string?)
	if state.busy then return end
	if state.searching then state.searching = false; cx:frame({ { "focus", tern.json.null } }) end
	if state.commenting then state.commenting = false; cx:frame({ { "focus", tern.json.null } }) end
	if action == "refresh" then refresh(state, cx)
	elseif action == "filter" and value then
		state.filter = value
		if value == "closed" then state.showClosed = true end
	elseif action == "layout" then state.layout = value or (if state.layout == "board" then "table" else "board")
	elseif action == "spotlight" then state.spotlight = not state.spotlight
	elseif action == "sort" and value then
		state.sortAscending = value ~= state.sortKey or not state.sortAscending
		state.sortKey = value
	elseif action == "select-issue" and value then selectIssue(state, cx, value)
	elseif action == "close-detail" then state.selected, state.comments, state.commenting, state.form = nil, nil, false, nil
	elseif action == "clear-filters" then
		state.query.text, state.query.cursor, state.query.anchor = "", 0, nil
		state.typeFilter, state.priorityFilter, state.assigneeFilter, state.filter, state.showClosed = "", "", "", "all", true
	elseif action == "cancel" then state.form = nil; cx:frame({ { "focus", tern.json.null } })
	elseif action == "submit" then submit(state, cx)
	elseif action == "create" or action == "update" or action == "close" then
		openForm(state, cx, action)
	elseif action == "claim" or action == "reclaim" or action == "reopen" then
		local issue = current(state)
		if issue then mutate(state, cx, action, { id = issue.id }) end
	elseif action == "comments" then loadComments(state, cx)
	elseif action == "link-dependency" and state.dependencyId ~= "" then
		local issue = current(state)
		if issue then mutate(state, cx, "link", { id = issue.id, dependsOn = state.dependencyId, type = state.dependencyType }) end
	elseif action == "unlink-dependency" and value then
		local issue = current(state)
		if issue then mutate(state, cx, "unlink", { id = issue.id, dependsOn = value }) end
	elseif action == "submit-comment" and string.match(state.comment.text, "%S") then
		local issue = current(state)
		if issue then mutate(state, cx, "comment", { id = issue.id, text = state.comment.text }) end
	end
end

local board: BlockDef<State> = {
	font = "sans",
	features = { "edit" },
	init = function(cx, _args, saved)
		local state: State = {
			cwd = cx.cwd, snapshot = nil, selected = nil, filter = "all", layout = "board",
			busy = false, refreshing = false, generation = 0, error = nil, form = nil, comments = nil,
			query = { name = "query", label = "Search", text = "", baseline = "", cursor = 0 },
			searching = false, typeFilter = "", priorityFilter = "", assigneeFilter = "", showClosed = true, spotlight = true,
			sortKey = "status", sortAscending = true,
			dependencyId = "", dependencyType = "blocks",
			comment = { name = "comment", label = "Add a comment", text = "", baseline = "", cursor = 0 }, commenting = false,
			icons = {},
		}
		for name, svg in iconSources do state.icons[name] = cx:blob(svg, "image/svg+xml") end
		if type(saved) == "table" then
			if saved.filter == "ready" or saved.filter == "all" or saved.filter == "active" or saved.filter == "blocked" or saved.filter == "closed" or saved.filter == "deferred" then state.filter = saved.filter end
			if saved.layout == "table" then state.layout = "table" end
		end
		refresh(state, cx)
		local function tick()
			if not running(cx) then return end
			if not state.busy and not state.refreshing and not state.form and not state.commenting and not state.searching then refresh(state, cx, false, true) end
			tern.timer(5000, tick)
		end
		tern.timer(5000, tick)
		return state
	end,
	title = function(_state) return "Beads" end,
	save = function(state) return { filter = state.filter, layout = state.layout } end,
	view = function(state, _cx)
		local snapshot = state.snapshot
		local issues = visible(state)
		local all = if snapshot then snapshot.issues else {}
		local groups = {
			{ "ready", "Ready" }, { "in_progress", "In progress" }, { "blocked", "Blocked" },
			{ "closed", "Closed" }, { "deferred", "Deferred" }, { "other", "Other" },
		}
		local relations: { [string]: string } = {}
		local selectedIssue = current(state)
		if selectedIssue and state.spotlight then
			for _, dep in selectedIssue.dependencies do
				relations[dep.id] = if dep.type == "blocks" then "Dependency · blocks" elseif dep.type == "discovered-from" then "Found in" else dep.type
			end
			for _, other in all do
				for _, dep in other.dependencies do
					if dep.id == selectedIssue.id and not relations[other.id] then
						relations[other.id] = if dep.type == "blocks" then "Depends on this · blocks" else dep.type
					end
				end
			end
		end
		local hasRelations = next(relations) ~= nil
		local function spotlightClass(issue: Issue): string
			if not selectedIssue or not hasRelations or issue.id == selectedIssue.id then return "" end
			return if relations[issue.id] then " chain" else " dimmed"
		end
		local names = { ready = "Ready", in_progress = "In progress", blocked = "Blocked", closed = "Closed", deferred = "Deferred", other = "Other" }
		local function el(class: string, text: string?, children: { Node }?, extra: { [string]: any }?): Node
			local node = ui.el("div", { class = class, text = text }, children)
			return if extra then props(node, extra) else node
		end
		local function text(class: string, value: string): Node
			return ui.el("span", { class = class, text = value })
		end
		local function icon(name: string): Node
			return graphic(state, name)
		end
		local function count(group: string): number
			if group == "all" then return #all end
			local n = 0
			if snapshot then for _, issue in all do if statusGroup(snapshot, issue) == group then n += 1 end end end
			return n
		end
		local function bead(group: string): Node
			return el("beads-dot beads-dot-" .. group)
		end
		local function command(label: string, action: string, class: string, role: string?, iconName: string?): Node
			return props(button(state, label, action, false, iconName), { role = role, mark = class })
		end
		local function priority(issue: Issue): Node
			return text("beads-priority beads-p" .. tostring(issue.priority), "P" .. tostring(issue.priority))
		end
		local function labels(issue: Issue): Node
			local chips: { Node } = {}
			for _, label in issue.labels do table.insert(chips, text("beads-label", label)) end
			return el("beads-labels", nil, chips)
		end
		local function relationships(issue: Issue): string
			local entries: { string } = {}
			for _, dep in issue.dependencies do table.insert(entries, dep.type .. ": " .. dep.id) end
			return table.concat(entries, ", ")
		end
		local function quote(value: string): string
			return "'" .. string.gsub(value, "'", "'\\''") .. "'"
		end
		local function options(kind: string): { any }
			local list: { any } = { { value = "", label = "All " .. kind } }
			local values: { string } = {}
			if kind == "priorities" then
				for i = 0, 4 do table.insert(list, { value = tostring(i), label = "P" .. tostring(i) }) end
			else
				for _, issue in all do
					local value = if kind == "types" then issue.type else issue.assignee
					if value ~= "" and not table.find(values, value) then table.insert(values, value) end
				end
				table.sort(values)
				for _, value in values do table.insert(list, { value = value, label = value }) end
			end
			return list
		end
		local function formView(form: Form, inline: boolean): Node
			local fields: { Node } = {}
			local args = { "bd", "--json", "--no-color", form.method }
			if form.method == "create" then table.insert(args, "--repo=.") end
			for i, field in form.fields do
				local choices = fieldChoices(field)
				local control: Node
				if choices then
					local items = {}
					for _, value in choices do table.insert(items, { value = value, label = if field.name == "priority" then "P" .. value else value }) end
					control = ui.node("select", { key = "input", role = "beads-form-select", value = field.text, options = items, aria = field.label, disabled = state.busy })
				else
					local multiline = multilineField(field)
					control = ui.node(if multiline then "editor" else "input", {
						key = "input", text = field.text, cursor = field.cursor, anchor = field.anchor, aria = field.label,
						maxLines = if multiline then (if inline then 3 else 4) else nil, readonly = state.busy, variant = "field",
						placeholder = if form.method == "create" and field.name == "title" then "What needs to be done?"
							elseif form.method == "create" and field.name == "description" then "Context, links, what done looks like" else nil,
					})
				end
				local half = field.name == "priority" or (form.method == "create" and field.name == "type") or (inline and field.name == "assignee")
				table.insert(fields, el("beads-form-field" .. (if half then " half" else ""), nil, {
					text("beads-field-label", field.label), control,
				}, { key = "f" .. tostring(i), role = "beads-field" }))
				if form.method ~= "update" or field.text ~= field.baseline then
					table.insert(args, "--" .. field.name .. "=" .. quote(field.text))
				end
			end
			if form.id then table.insert(args, "--"); table.insert(args, quote(form.id)) end
			table.insert(fields, text("beads-command", "$ " .. table.concat(args, " ")))
			if state.error then table.insert(fields, text("beads-form-error", state.error)) end
			local save = button(state, if inline then "Save changes" elseif form.method == "create" then "Create issue" else "Close issue", "submit", true)
			local cancel = button(state, "Cancel", "cancel")
			local header = if inline then text("beads-section-title", form.title) else el("beads-form-header", nil, {
				text("beads-form-title", form.title),
				props(button(state, "", "cancel", false, "x"), { mark = "close", aria = "Close" }),
			})
			return el(if inline then "beads-inline-form" else "beads-dialog", nil, {
				header,
				el("beads-form-body", nil, fields, { key = "body" }),
				el(if inline then "beads-detail-actions" else "beads-form-actions", nil, if inline then { save, cancel } else { cancel, save }),
			}, { key = if inline then "edit" else "form", role = if inline then "beads-edit-form" else "beads-form" })
		end
		local bar = el("beads-bar", nil, {
			el("beads-brand", nil, { el("beads-brand-mark", nil, { bead("closed"), bead("in_progress"), bead("ready") }), text("", "beads") }),
			ui.node("input", { key = "query", role = "beads-search", text = state.query.text, cursor = state.query.cursor, anchor = state.query.anchor,
				placeholder = "Search by title, ID or label", aria = "Search by title, ID or label", icon = "search", keys = { "/" }, variant = "field", readonly = state.busy }),
			el("beads-bar-actions", nil, {
				props(button(state, if snapshot then "Synced " .. relativeTime(snapshot.fetchedAt) else "Refresh", "refresh", false, "refresh"), { mark = "refresh" }),
				props(button(state, "New issue", "create", true, "plus", "N"), { role = "beads-create" }),
			}),
		}, { key = "bar", role = "beads-topbar" })
		local workspace = state.cwd or "No workspace"
		local project = string.match(workspace, "([^/]+)/*$") or workspace
		local rail: { Node } = {
			el("beads-workspace", nil, {
				text("beads-workspace-glyph", string.lower(string.sub(project, 1, 2))),
				el("beads-workspace-info", nil, { text("beads-workspace-name", project), text("beads-path", workspace) }),
			}),
			text("beads-rail-heading", "Views"),
		}
		for _, item in { { "all", "All issues", "all" }, { "ready", "Ready", "ready" }, { "active", "In progress", "in_progress" }, { "blocked", "Blocked", "blocked" }, { "closed", "Closed", "closed" }, { "deferred", "Deferred", "deferred" } } do
			local label = item[2]
			local action = if state.busy then nil else { click = "filter=" .. item[1] }
			table.insert(rail, ui.el("button", {
				class = "beads-rail-item" .. (if state.filter == item[1] then " on" else ""),
				key = item[1], role = "beads-view-" .. item[1], aria = label, actions = action,
			}, { if item[1] == "all" then icon("kanban") else bead(item[3]), text("beads-rail-label", label), text("beads-count", tostring(count(item[3]))) }))
		end
		local filterbar = el("beads-filters", nil, {
			ui.node("select", { key = "filtertype", role = "beads-filter-type", value = state.typeFilter, options = options("types"), aria = "Filter by type", disabled = state.busy }),
			ui.node("select", { key = "filterpriority", role = "beads-filter-priority", value = state.priorityFilter, options = options("priorities"), aria = "Filter by priority", disabled = state.busy }),
			ui.node("select", { key = "filterassignee", role = "beads-filter-assignee", value = state.assigneeFilter, options = options("assignees"), aria = "Filter by assignee", disabled = state.busy }),
			command("Clear filters", "clear-filters", "clear"),
			el("beads-filter-spacer"),
			text("beads-count", tostring(#issues) .. " issues"),
			ui.el("label", { class = "beads-check" }, {
				ui.el("input", { key = "showclosed", type = "checkbox", checked = state.showClosed, disabled = state.busy, aria = "Show closed issues" }),
				text("", "Closed"),
			}),
		}, { key = "filters", role = "beads-filter-row" })
		local headChildren: { Node } = {
			el("beads-title-row", nil, {
				text("beads-title", "Board"),
				text("beads-summary", tostring(count("ready")) .. " ready · " .. tostring(count("in_progress")) .. " in progress · " .. tostring(count("blocked")) .. " blocked"),
				el("beads-segmented", nil, {
					props(command("Board", "layout=board", if state.layout == "board" then "active" else "segment", "beads-board-view", "kanban"), { key = "board" }),
					props(command("Table", "layout=table", if state.layout == "table" then "active" else "segment", "beads-table-view", "list"), { key = "table" }),
				}),
				props(button(state, "", "spotlight", false, "link"),
					{ key = "spotlight", role = "beads-spotlight", mark = if state.spotlight then "spotlight-on" else "spotlight", aria = "Toggle dependency highlight" }),
			}),
			filterbar,
		}
		if state.layout == "board" then
			table.insert(headChildren, text("beads-hint", "Open a card for keyboard actions. Reopened issues may still be blocked."))
		end
		local head = el("beads-head", nil, headChildren, { key = "head" })
		local content: { Node } = { head }
		if state.error then table.insert(content, el("beads-error", "Error: " .. state.error, nil, { role = "beads-error" })) end
		if state.busy and not snapshot then table.insert(content, el("beads-empty", "Loading Beads…")) end
		if snapshot and #issues == 0 then
			table.insert(content, el("beads-empty", if #all == 0 then "No issues in this view. Choose All issues or create an issue." else "No matching issues. Try another search or clear the filters."))
		elseif snapshot and state.layout == "table" then
			local function epic(issue: Issue): string
				for _, dep in issue.dependencies do
					if dep.type == "parent-child" then
						for _, parent in all do
							if parent.id == dep.id and parent.type == "epic" then return parent.title end
						end
					end
				end
				return ""
			end
			local function sortValue(issue: Issue): any
				local key = state.sortKey
				if key == "status" then
					local group = statusGroup(snapshot, issue)
					for index, item in groups do if item[1] == group then return index end end
					return #groups
				elseif key == "priority" then return issue.priority
				elseif key == "relationships" then return relationships(issue)
				elseif key == "epic" then return epic(issue)
				elseif key == "labels" then return table.concat(issue.labels, ", ")
				elseif key == "updated" then return epoch(issue.updatedAt) or 0
				elseif key == "id" then return issue.id
				elseif key == "title" then return issue.title
				elseif key == "assignee" then return issue.assignee
				elseif key == "type" then return issue.type end
				return ""
			end
			table.sort(issues, function(a, b)
				local left, right = sortValue(a), sortValue(b)
				if left ~= right then
					return if state.sortAscending then left < right else left > right
				end
				if a.priority ~= b.priority then return a.priority < b.priority end
				return a.id < b.id
			end)
			local headers: { Node } = {}
			for _, item in {
				{ "status", "Status" }, { "id", "ID" }, { "title", "Title" }, { "priority", "Priority" },
				{ "relationships", "Relationships" }, { "assignee", "Assignee" }, { "type", "Type" },
				{ "epic", "Epic" }, { "labels", "Labels" }, { "updated", "Updated" },
			} do
				table.insert(headers, ui.el("th", { class = "beads-cell-" .. item[1] }, {
					command(item[2] .. (if state.sortKey == item[1] then (if state.sortAscending then " ↑" else " ↓") else ""),
						"sort=" .. item[1], "sort", "beads-sort-" .. item[1]),
				}))
			end
			local rows: { Node } = {}
			for _, issue in issues do
				local group, parent = statusGroup(snapshot, issue), epic(issue)
				local titleNodes: { Node } = { command(issue.title, "select-issue=" .. issue.id, "table-link", "beads-issue") }
				if relations[issue.id] and issue.id ~= state.selected then table.insert(titleNodes, text("beads-relation", relations[issue.id])) end
				table.insert(rows, ui.el("tr", { key = issue.id, class = (if state.selected == issue.id then "selected" else "") .. spotlightClass(issue) }, {
					ui.el("td", { class = "beads-cell-status" }, { el("beads-status", nil, { bead(group), text("", names[group]) }) }),
					ui.el("td", { class = "beads-cell-id" }, { text("beads-mono", issue.id) }),
					ui.el("td", { class = "beads-cell-title" }, titleNodes),
					ui.el("td", { class = "beads-cell-priority" }, { priority(issue) }),
					ui.el("td", { class = "beads-cell-relationships" }, { text("beads-mono", if #issue.dependencies == 0 then "—" else relationships(issue)) }),
					ui.el("td", { class = "beads-cell-assignee", text = if issue.assignee == "" then "Unassigned" else issue.assignee }),
					ui.el("td", { class = "beads-cell-type", text = issue.type }),
					ui.el("td", { class = "beads-cell-epic", text = if parent == "" then "—" else parent }),
					ui.el("td", { class = "beads-cell-labels" }, { if #issue.labels == 0 then text("", "—") else labels(issue) }),
					ui.el("td", { class = "beads-cell-updated", text = relativeTime(issue.updatedAt) }),
				}))
			end
			table.insert(content, el("beads-table-wrap", nil, {
				ui.el("table", { class = "beads-table" }, {
					ui.el("thead", nil, { ui.el("tr", nil, headers) }),
					ui.el("tbody", nil, rows),
				}),
			}, { key = "issues", role = "beads-table" }))
		elseif snapshot then
			local columns: { Node } = {}
			for _, group in groups do
				local cards: { Node } = {}
				for _, issue in issues do
					if statusGroup(snapshot, issue) == group[1] then
						local card: { Node } = {
							el("beads-card-top", nil, { icon("type_" .. issue.type), text("beads-mono", issue.id), priority(issue) }),
						}
						if relations[issue.id] and issue.id ~= state.selected then table.insert(card, text("beads-relation", relations[issue.id])) end
						table.insert(card, text("beads-card-title", issue.title))
						if table.find(snapshot.blockedIds, issue.id) then table.insert(card, el("beads-blockers", nil, { icon("lock"), text("", "Blocked by dependencies") })) end
						table.insert(card, el("beads-card-footer", nil, { text("", issue.type), text("", if issue.assignee == "" then "Unassigned" else issue.assignee) }))
						if #issue.labels > 0 then table.insert(card, labels(issue)) end
						table.insert(cards, ui.el("button", {
							class = "beads-card" .. (if state.selected == issue.id then " selected" else "") .. (if group[1] == "closed" then " closed" else "") .. spotlightClass(issue),
							key = issue.id, role = "beads-issue", aria = "Open " .. issue.id .. ": " .. issue.title,
							actions = if state.busy then nil else { click = "select-issue=" .. issue.id },
						}, card))
					end
				end
				if (group[1] ~= "other" or #cards > 0) and (state.showClosed or group[1] ~= "closed")
					and (state.filter == "all" or state.filter == group[1] or (state.filter == "active" and group[1] == "in_progress")) then
					local n = #cards
					if n == 0 then table.insert(cards, text("beads-column-empty", "No issues")) end
					table.insert(columns, el("beads-column", nil, {
						el("beads-column-header", nil, { bead(group[1]), text("beads-column-name", group[2]), text("beads-count", tostring(n)) }),
						el("beads-column-list", nil, cards),
					}, { key = group[1], role = "beads-column" }))
				end
			end
			table.insert(content, el("beads-board", nil, columns, { key = "board", role = "beads-board" }))
		end
		local body = el("beads-body", nil, {
			el("beads-rail", nil, rail, { key = "rail", role = "beads-sidebar" }),
			el("beads-main", nil, content, { key = "content" }),
		}, { key = "body" })
		local app: { Node } = { bar, body }
		local issue = current(state)
		if issue and snapshot then
			local group = statusGroup(snapshot, issue)
			local actions: { Node } = {}
			if group == "closed" then
				table.insert(actions, props(button(state, "Reopen", "reopen", false, "undo"), { role = "beads-reopen" }))
			else
				if group == "ready" then table.insert(actions, props(button(state, "Claim", "claim", true, "play"), { role = "beads-claim" })) end
				if issue.status == "in_progress" then table.insert(actions, props(button(state, "Reclaim lease", "reclaim"), { role = "beads-reclaim" })) end
				table.insert(actions, props(button(state, "Close", "close", #actions == 0, "check"), { role = "beads-close" }))
			end
			local metadata: { Node } = {
				text("beads-meta-label", "Status"), el("beads-status", nil, { bead(group), text("", names[group]) }, { role = "beads-detail-status" }),
				text("beads-meta-label", "Type"), text("", issue.type),
				text("beads-meta-label", "Assignee"), text("", if issue.assignee == "" then "Unassigned" else issue.assignee),
				text("beads-meta-label", "Updated"), text("", if relativeTime(issue.updatedAt) == "" then "Unknown" else relativeTime(issue.updatedAt)),
			}
			if #issue.labels > 0 then
				table.insert(metadata, text("beads-meta-label", "Labels"))
				table.insert(metadata, labels(issue))
			end
			local detail: { Node } = {
				el("beads-detail-top", nil, {
					icon("type_" .. issue.type),
					text("beads-mono", issue.id), priority(issue), el("beads-detail-spacer"),
					props(button(state, "", "close-detail", false, "x"),
						{ mark = "close", role = "beads-close-detail", aria = "Close issue details" }),
				}),
				text("beads-detail-title", issue.title),
				el("beads-detail-actions", nil, actions),
				if state.form and state.form.method == "update" then formView(state.form, true)
					else props(button(state, "Edit issue", "update"), { role = "beads-edit", mark = "edit" }),
				el("beads-metadata", nil, metadata),
			}
			for _, section in { { "Description", issue.description }, { "Acceptance criteria", issue.acceptance }, { "Notes", issue.notes }, { "Design", issue.design } } do
				if section[2] and section[2] ~= "" then table.insert(detail, el("beads-detail-section", nil, { text("beads-section-title", section[1]), text("beads-prose", section[2]) })) end
			end
			local deps: { Node } = { text("beads-section-title", "Dependencies") }
			if #issue.dependencies == 0 then table.insert(deps, text("beads-muted", "No dependencies.")) end
			for _, dep in issue.dependencies do
				local target: Issue? = nil
				for _, candidate in all do if candidate.id == dep.id then target = candidate; break end end
				table.insert(deps, el("beads-dependency", nil, {
					bead(if target then statusGroup(snapshot, target) else "other"),
					el("beads-dependency-info", nil, {
						command(if target then target.title else dep.id, "select-issue=" .. dep.id, "dependency-link"),
						text("beads-mono", dep.id .. " · " .. dep.type),
					}),
					props(button(state, "", "unlink-dependency=" .. dep.id, false, "x"),
						{ mark = "remove-dependency", aria = "Remove dependency " .. dep.id }),
				}))
			end
			local candidates: { any } = { { value = "", label = "Choose an issue" } }
			for _, candidate in all do
				local linked = candidate.id == issue.id
				for _, dep in issue.dependencies do if dep.id == candidate.id then linked = true; break end end
				if not linked then table.insert(candidates, { value = candidate.id, label = candidate.id .. " · " .. candidate.title }) end
			end
			if #candidates > 1 then
				table.insert(deps, el("beads-dependency-form", nil, {
					el("beads-dependency-field", nil, {
						text("beads-field-label", "Link issue"),
						ui.node("select", { key = "depissue", role = "beads-dependency-issue", value = state.dependencyId, options = candidates, aria = "Dependency issue", disabled = state.busy }),
					}),
					el("beads-dependency-field", nil, {
						text("beads-field-label", "Relationship"),
						ui.node("select", { key = "deptype", role = "beads-dependency-type", value = state.dependencyType,
							options = { "blocks", "parent-child", "related", "discovered-from" }, aria = "Dependency relationship", disabled = state.busy }),
					}),
					props(button(state, "Link", "link-dependency", false, nil, nil, state.dependencyId == ""), { role = "beads-link" }),
				}, { key = "dependencyform" }))
				table.insert(deps, text("beads-command", "bd --json --no-color dep add --type=" .. quote(state.dependencyType) .. " -- " .. quote(issue.id) .. " " .. quote(if state.dependencyId == "" then "ISSUE" else state.dependencyId)))
			end
			table.insert(detail, el("beads-detail-section", nil, deps))
			local comments: { Node } = { text("beads-section-title", "Comments") }
			if state.comments then
				if #state.comments == 0 then table.insert(comments, text("beads-muted", "No comments yet.")) end
				for _, comment in state.comments do
					if type(comment) == "table" and type(comment.text) == "string" then
						table.insert(comments, el("beads-comment", nil, {
							text("beads-comment-author", tostring(comment.author or "")),
							text("beads-muted", relativeTime(comment.created_at)),
							text("beads-prose", comment.text),
						}))
					else
						table.insert(comments, ui.code(tern.json.encode(comment, true), "json"))
					end
				end
			elseif state.busy then
				table.insert(comments, text("beads-muted", "Loading comments…"))
			else
				table.insert(comments, command("Load comments", "comments", "load-comments"))
			end
			table.insert(comments, text("beads-field-label", "Add a comment"))
			table.insert(comments, ui.node("editor", { key = "editor", role = "beads-comment-editor", text = state.comment.text,
				cursor = state.comment.cursor, anchor = state.comment.anchor, aria = "Add a comment", maxLines = 3, readonly = state.busy }))
			table.insert(comments, text("beads-command", "bd --json --no-color comment -- " .. quote(issue.id) .. " " .. quote(state.comment.text)))
			table.insert(comments, props(button(state, "Add comment", "submit-comment", false, nil, nil, not string.match(state.comment.text, "%S")), { role = "beads-add-comment" }))
			table.insert(detail, el("beads-detail-section", nil, comments, { key = "comments" }))
			local nextCommand = if group == "ready" then "update --claim" elseif group == "closed" then "reopen" else "close"
			table.insert(detail, text("beads-command", "$ bd --json --no-color " .. nextCommand .. " -- " .. quote(issue.id)))
			table.insert(app, el("beads-drawer", nil, detail, { key = "detail", role = "beads-drawer" }))
		end
		local children: { Node } = { el("beads-app" .. (if issue then " drawer-open" else ""), nil, app, { key = "app" }) }
		local form = state.form
		if form and form.method ~= "update" then
			table.insert(children, el("beads-form-backdrop", nil, nil, { actions = if state.busy then nil else { { name = "cancel" } } }))
			table.insert(children, formView(form, false))
		end
		return { main = ui.col(children) }
	end,
	event = function(state, ev, cx)
		local form = state.form
		if form and ev.id then
			for i, field in form.fields do
				if ev.id == formPrefix(form) .. ".f" .. tostring(i) .. ".input" then
					if ev.ev == "focus" then form.focus = i; focusForm(state, cx)
					elseif ev.ev == "edit" and not state.busy and ev.len == length16(field.text) then
						replace(field, ev.from, ev.to, ev.text)
						field.cursor = ev.cursor
					elseif ev.ev == "change" and not state.busy and type(ev.value) == "string" then
						field.text, field.cursor, field.anchor = ev.value, length16(ev.value), nil
						form.focus = i
					end
					return
				end
			end
		end
		if ev.id == "main.app.detail.comments.editor" and not form then
			if ev.ev == "focus" and not state.busy then
				state.commenting, state.searching = true, false
				cx:frame({ { "focus", "main.app.detail.comments.editor" } })
			elseif ev.ev == "edit" and not state.busy and ev.len == length16(state.comment.text) then
				replace(state.comment, ev.from, ev.to, ev.text)
				state.comment.cursor = ev.cursor
			end
			return
		end
		if ev.id == "main.app.bar.query" and not form then
			if ev.ev == "focus" and not state.busy then
				state.searching, state.commenting = true, false
				cx:frame({ { "focus", "main.app.bar.query" } })
			elseif ev.ev == "edit" and not state.busy and ev.len == length16(state.query.text) then
				replace(state.query, ev.from, ev.to, ev.text)
				state.query.cursor = ev.cursor
			end
			return
		end
		if ev.ev == "action" then act(state, cx, ev.act, ev.value)
		elseif ev.ev == "change" and not state.busy and ev.id then
			if string.match(ev.id, "%.filtertype$") then state.typeFilter = ev.value
			elseif string.match(ev.id, "%.filterpriority$") then state.priorityFilter = ev.value
			elseif string.match(ev.id, "%.filterassignee$") then state.assigneeFilter = ev.value
			elseif string.match(ev.id, "%.showclosed$") then state.showClosed = ev.checked
			elseif string.match(ev.id, "%.depissue$") then state.dependencyId = ev.value
			elseif string.match(ev.id, "%.deptype$") then state.dependencyType = ev.value end
			if state.searching then state.searching = false; cx:frame({ { "focus", tern.json.null } }) end
		end
	end,
	key = function(state, key, cx)
		if state.busy then return false end
		local form = state.form
		if form then
			local field = form.fields[form.focus]
			if key.name == "escape" then act(state, cx, "cancel", nil)
			elseif key.name == "enter" and (key.ctrl or key.meta or not multilineField(field)) then submit(state, cx)
			elseif key.name == "tab" then form.focus = (form.focus - 1 + (if key.shift then #form.fields - 1 else 1)) % #form.fields + 1; focusForm(state, cx)
			elseif fieldChoices(field) then
				local choices = fieldChoices(field) :: { string }
				local index = table.find(choices, field.text) or 1
				if key.name == "up" or key.name == "left" then field.text = choices[math.max(1, index - 1)]
				elseif key.name == "down" or key.name == "right" then field.text = choices[math.min(#choices, index + 1)]
				else return false end
			elseif not editField(field, key, multilineField(field)) then return false end
			return true
		end
		if state.commenting then
			if key.name == "escape" or key.name == "tab" then
				state.commenting = false
				cx:frame({ { "focus", tern.json.null } })
				return true
			elseif key.name == "enter" and (key.ctrl or key.meta) then
				act(state, cx, "submit-comment", nil)
				return true
			end
			return editField(state.comment, key, true)
		end
		if state.searching then
			if key.name == "escape" then
				state.query.text, state.query.cursor, state.query.anchor, state.searching = "", 0, nil, false
				cx:frame({ { "focus", tern.json.null } })
				return true
			elseif key.name == "enter" then
				state.searching = false
				cx:frame({ { "focus", tern.json.null } })
				return true
			end
			return editField(state.query, key, false)
		end
		if key.ctrl or key.meta or key.alt then return false end
		if key.name == "/" then
			state.searching = true
			cx:frame({ { "focus", "main.app.bar.query" } })
			return true
		end
		if key.name == "j" or key.name == "down" or key.name == "k" or key.name == "up" then
			local issues = visible(state)
			local index = 0
			for i, issue in issues do if issue.id == state.selected then index = i end end
			index = math.clamp(index + (if key.name == "k" or key.name == "up" then -1 else 1), 1, math.max(1, #issues))
			if issues[index] then selectIssue(state, cx, issues[index].id) end
		elseif key.name == "1" then state.filter = "ready"
		elseif key.name == "2" then state.filter = "active"
		elseif key.name == "3" then state.filter = "blocked"
		elseif key.name == "r" then refresh(state, cx)
		elseif key.name == "n" then openForm(state, cx, "create")
		elseif key.name == "c" then act(state, cx, "claim", nil)
		elseif key.name == "x" then
			local issue = current(state)
			if issue then act(state, cx, if issue.status == "closed" then "reopen" else "close", nil) end
		elseif key.name == "escape" then state.selected, state.comments, state.commenting = nil, nil, false
		else return false end
		return true
	end,
}

tern.block.define("board", board)
