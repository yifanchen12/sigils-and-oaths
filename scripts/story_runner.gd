extends RefCounted
## A finite authored graph. It never evaluates code or touches battle/UI objects.

var graph: Dictionary = {}
var state: Dictionary = {}
var error_message: String = ""

func _init(source: Dictionary = {}) -> void:
	if not source.is_empty(): configure(source)

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func _whole(value: Variant, minimum: int = 0, maximum: int = 1000000) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and float(value) == floorf(float(value)) and value >= minimum and value <= maximum

static func _flag_value(value: Variant) -> bool:
	return value is bool or (value is String and value.length() <= 256) or _whole(value, -1000000)

static func _same_type(left: Variant, right: Variant) -> bool:
	return (typeof(left) == typeof(right)) or (typeof(left) in [TYPE_INT, TYPE_FLOAT] and typeof(right) in [TYPE_INT, TYPE_FLOAT])

static func _flag_map(value: Variant, defaults: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key: Variant in value:
		if not key is String or not defaults.has(key) or not _flag_value(value[key]) or not _same_type(value[key], defaults[key]): return false
	return true

static func validate(source: Variant) -> String:
	if not source is Dictionary: return "剧情必须是对象。"
	if not _whole(source.get("version"), 1, 1): return "不支持此剧情版本。"
	for key: String in ["id", "title", "start"]:
		if not source.get(key) is String or source[key].is_empty(): return "剧情缺少有效的" + key
	for key: String in ["nodes", "strings", "speakers", "defaults"]:
		if not source.get(key) is Dictionary: return "剧情缺少对象：" + key
	var nodes: Dictionary = source.nodes
	var strings: Dictionary = source.strings
	var defaults: Dictionary = source.defaults
	for speaker: Variant in source.speakers:
		if not speaker is String or not source.speakers[speaker] is String or source.speakers[speaker].is_empty(): return "说话人资料无效。"
	if nodes.is_empty() or not nodes.has(source.start): return "剧情起点不存在。"
	for key: Variant in defaults:
		if not key is String or not _flag_value(defaults[key]): return "剧情标志无效。"
	for key: Variant in strings:
		if not key is String or not strings[key] is String or strings[key].strip_edges().is_empty(): return "剧情文本无效。"
	var references: Dictionary = {}
	var edges: Dictionary = {}
	for id: Variant in nodes:
		if not id is String or not nodes[id] is Dictionary: return "剧情节点无效。"
		var node: Dictionary = nodes[id]
		var links: Array = []
		match node.get("type", ""):
			"dialogue":
				if not node.get("lines") is Array or node.lines.is_empty(): return "对白没有内容：" + id
				var unconditional: bool = false
				for line: Variant in node.lines:
					if not line is Dictionary or not strings.has(line.get("id")): return "对白引用缺失：" + id
					if not source.speakers.has(line.get("speaker")): return "说话人不存在：" + id
					if not _flag_map(line.get("when", {}), defaults): return "对白条件无效：" + id
					if line.get("when", {}).is_empty(): unconditional = true
					references[line.id] = true
				if not unconditional: return "对白至少需要一句无条件文本：" + id
				links.append(node.get("next"))
			"choice":
				if not strings.has(node.get("prompt")): return "选择提示缺失：" + id
				references[node.prompt] = true
				if not node.get("options") is Array or node.options.is_empty(): return "选择没有选项：" + id
				var option_ids: Dictionary = {}
				var unconditional: bool = false
				for option: Variant in node.options:
					if not option is Dictionary or not option.get("id") is String or option.id.is_empty(): return "选项编号无效：" + id
					if option_ids.has(option.id) or not strings.has(option.get("text")): return "选项重复或文本缺失：" + id
					option_ids[option.id] = true
					if not _flag_map(option.get("when", {}), defaults) or not _flag_map(option.get("set", {}), defaults): return "选项标志无效：" + id
					if option.get("when", {}).is_empty(): unconditional = true
					references[option.text] = true
					links.append(option.get("next"))
				if not unconditional: return "选择至少需要一个无条件出口：" + id
			"battle":
				if not node.get("scenario") is String or node.scenario.is_empty(): return "战斗缺少关卡编号：" + id
				if not _flag_map(node.get("win_set", {}), defaults): return "战果标志无效：" + id
				links.append(node.get("win"))
			"end":
				if not strings.has(node.get("text")) or not node.get("ending") is String: return "章末信息缺失：" + id
				references[node.text] = true
			_: return "未知剧情节点类型：" + id
		for target: Variant in links:
			if not target is String or not nodes.has(target): return "剧情跳转不存在：" + id
		edges[id] = links
	for id: Variant in strings:
		if not references.has(id): return "文本未被剧情引用：" + id
	# Kahn traversal rejects loops; a separate walk rejects disconnected content.
	var incoming: Dictionary = {}
	for id: String in nodes: incoming[id] = 0
	for id: String in edges:
		for target: String in edges[id]: incoming[target] += 1
	var ready: Array[String] = []
	for id: String in incoming:
		if incoming[id] == 0: ready.append(id)
	var processed: int = 0
	while not ready.is_empty():
		var id: String = ready.pop_back()
		processed += 1
		for target: String in edges[id]:
			incoming[target] -= 1
			if incoming[target] == 0: ready.append(target)
	if processed != nodes.size(): return "剧情含循环；战败重试应留在战斗节点。"
	var reached: Dictionary = {}
	ready = [source.start]
	while not ready.is_empty():
		var id: String = ready.pop_back()
		if reached.has(id): continue
		reached[id] = true
		for target: String in edges[id]: ready.append(target)
	if reached.size() != nodes.size(): return "存在无法从起点到达的剧情节点。"
	return ""

func configure(source: Dictionary) -> Dictionary:
	var problem: String = validate(source)
	if not problem.is_empty():
		error_message = problem
		return _failure(problem)
	graph = source.duplicate(true)
	state = {"node": graph.start, "line": 0, "revision": 0, "flags": graph.defaults.duplicate(true), "decisions": {}, "history": [], "attempts": {}, "last_outcome": ""}
	_seek_line()
	error_message = ""
	return {"ok": true}

func matches(conditions: Dictionary) -> bool:
	for key: String in conditions:
		if state.flags.get(key) != conditions[key]: return false
	return true

func current() -> Dictionary:
	if graph.is_empty() or state.is_empty(): return _failure("剧情尚未加载。")
	var node: Dictionary = graph.nodes[state.node]
	var result: Dictionary = {"ok": true, "type": node.type, "node": state.node, "revision": int(state.revision), "background": node.get("background", ""), "chapter": graph.title}
	match node.type:
		"dialogue":
			var line: Dictionary = node.lines[int(state.line)]
			result["line_id"] = line.id
			result["speaker_id"] = line.speaker
			result["speaker"] = graph.speakers[line.speaker]
			result["text"] = graph.strings[line.id]
		"choice":
			result["text"] = graph.strings[node.prompt]
			result["options"] = []
			for option: Dictionary in node.options:
				if matches(option.get("when", {})): result.options.append({"id": option.id, "text": graph.strings[option.text]})
		"battle":
			result["scenario"] = node.scenario
			result["attempts"] = int(state.attempts.get(state.node, 0))
			result["last_outcome"] = state.last_outcome
		"end":
			result["text"] = graph.strings[node.text]
			result["ending"] = node.ending
	return result

func _guard(revision: int, kind: String) -> String:
	if state.is_empty(): return "剧情尚未开始。"
	if revision != int(state.revision): return "该操作已过期，请按当前页面操作。"
	if graph.nodes[state.node].type != kind: return "当前剧情不接受此操作。"
	return ""

func _enter(node_id: String) -> void:
	state.node = node_id
	state.line = 0
	state.last_outcome = ""
	_seek_line()

func _seek_line() -> void:
	var node: Dictionary = graph.nodes[state.node]
	if node.type != "dialogue": return
	while state.line < node.lines.size() and not matches(node.lines[int(state.line)].get("when", {})):
		state.line += 1
	if state.line >= node.lines.size(): _enter(node.next)

func advance(revision: int) -> Dictionary:
	var problem: String = _guard(revision, "dialogue")
	if not problem.is_empty(): return _failure(problem)
	var node: Dictionary = graph.nodes[state.node]
	state.history.append(node.lines[int(state.line)].id)
	state.line += 1
	_seek_line()
	state.revision += 1
	return {"ok": true}

func choose(option_id: String, revision: int) -> Dictionary:
	var problem: String = _guard(revision, "choice")
	if not problem.is_empty(): return _failure(problem)
	var node: Dictionary = graph.nodes[state.node]
	for option: Dictionary in node.options:
		if option.id != option_id or not matches(option.get("when", {})): continue
		state.history.append(node.prompt)
		state.history.append(option.text)
		state.decisions[state.node] = option.id
		for key: String in option.get("set", {}): state.flags[key] = option.set[key]
		_enter(option.next)
		state.revision += 1
		return {"ok": true}
	return _failure("该选项当前不可用。")

func resolve_battle(outcome: int, revision: int) -> Dictionary:
	var problem: String = _guard(revision, "battle")
	if not problem.is_empty(): return _failure(problem)
	if outcome not in [0, 1, 2]: return _failure("战斗尚未结束。")
	state.attempts[state.node] = int(state.attempts.get(state.node, 0)) + 1
	if outcome == 0:
		var node: Dictionary = graph.nodes[state.node]
		for key: String in node.get("win_set", {}): state.flags[key] = node.win_set[key]
		_enter(node.win)
	else: state.last_outcome = "defeat" if outcome == 1 else "draw"
	state.revision += 1
	return {"ok": true}

func snapshot() -> Dictionary:
	return state.duplicate(true)

func validate_state(candidate: Variant) -> String:
	if graph.is_empty() or not candidate is Dictionary: return "剧情进度无效。"
	if not candidate.get("node") is String or not graph.nodes.has(candidate.node): return "存档剧情节点不存在。"
	if not _whole(candidate.get("line")) or not _whole(candidate.get("revision")): return "存档剧情位置无效。"
	if not _flag_map(candidate.get("flags"), graph.defaults): return "存档剧情标志无效。"
	var flags: Dictionary = graph.defaults.duplicate(true)
	flags.merge(candidate.flags, true)
	var node: Dictionary = graph.nodes[candidate.node]
	if node.type == "dialogue":
		if candidate.line >= node.lines.size(): return "存档对白行号越界。"
		for key: String in node.lines[int(candidate.line)].get("when", {}):
			if flags[key] != node.lines[int(candidate.line)].when[key]: return "存档停在不可显示的对白。"
	elif candidate.line != 0: return "非对白节点的行号无效。"
	if not candidate.get("decisions") is Dictionary or not candidate.get("attempts") is Dictionary: return "存档记录无效。"
	for id: Variant in candidate.decisions:
		if not graph.nodes.has(id) or graph.nodes[id].type != "choice": return "存档选择节点不存在。"
		var found: bool = false
		for option: Dictionary in graph.nodes[id].options:
			if option.id == candidate.decisions[id]: found = true
		if not found: return "存档选项不存在。"
	for id: Variant in candidate.attempts:
		if not graph.nodes.has(id) or graph.nodes[id].type != "battle" or not _whole(candidate.attempts[id], 1): return "存档战斗记录无效。"
	if candidate.get("last_outcome") not in ["", "defeat", "draw"]: return "存档战果无效。"
	if node.type != "battle" and candidate.last_outcome != "": return "非战斗节点不能保留失败状态。"
	if candidate.last_outcome != "" and int(candidate.attempts.get(candidate.node, 0)) == 0: return "失败记录缺少战斗尝试次数。"
	if not candidate.get("history") is Array or candidate.history.size() > 20000: return "存档回看记录无效。"
	for id: Variant in candidate.history:
		if not id is String or not graph.strings.has(id): return "存档回看文本不存在。"
	return ""

func restore(candidate: Variant) -> Dictionary:
	var problem: String = validate_state(candidate)
	if not problem.is_empty(): return _failure(problem)
	var next_state: Dictionary = {}
	for key: String in ["node", "line", "revision", "flags", "decisions", "history", "attempts", "last_outcome"]: next_state[key] = candidate[key]
	next_state = next_state.duplicate(true)
	var flags: Dictionary = graph.defaults.duplicate(true)
	flags.merge(next_state.flags, true)
	next_state.flags = flags
	next_state.line = int(next_state.line)
	next_state.revision = int(next_state.revision)
	state = next_state
	return {"ok": true}
