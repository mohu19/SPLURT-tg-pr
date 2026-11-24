/// 验证键位表清洗（历史遗留的 null 键位条目或脏数据会让「设置 → 按键绑定」整页报错）：
/// 1) 非 list / 关联表（JSON 对象）被重置为空 list；2) 正常条目不受影响；3) 非文本元素被剔除；
/// 4) 幂等；5) 输入非 list 不崩；6) 清洗后 JSON 往返均为数组；7) LAZYCOPY 正确归一化并拷贝。
/datum/unit_test/keybind_prefs_repair

/datum/unit_test/keybind_prefs_repair/Run()
	// BYOND 里 `list[key] = null` 会保留键、只清空值 —— 复刻脏数据的形态
	var/list/key_bindings = list()
	key_bindings["stop_interactions"] = null
	key_bindings["pickup"] = list("E")
	key_bindings["give"] = "ShiftG"
	key_bindings["drop"] = list("Q", 7)
	key_bindings["corrupt_object"] = list("a" = 1, "b" = 2)
	key_bindings["corrupt_false_object"] = list("a" = FALSE)
	var/list/null_assoc = list()
	null_assoc["X"] = null
	key_bindings["null_object"] = null_assoc

	TEST_ASSERT_EQUAL(length(key_bindings), 7, "前置条件：条目数应为 7")
	TEST_ASSERT_NULL(key_bindings["stop_interactions"], "前置条件：该条目的值应为 null")

	TEST_ASSERT(sanitize_key_binding_values(key_bindings), "应当报告修复了坏条目")
	TEST_ASSERT(islist(key_bindings["stop_interactions"]), "null 条目应被重置为 list()")
	TEST_ASSERT_EQUAL(length(key_bindings["stop_interactions"]), 0, "null 条目重置后应为空列表")
	TEST_ASSERT_EQUAL(length(key_bindings), 7, "修复不应增加或减少条目数量")

	TEST_ASSERT_EQUAL(key_bindings["pickup"][1], "E", "正常条目不应被改动")
	TEST_ASSERT(islist(key_bindings["give"]), "字符串值应被重置为 list()")
	TEST_ASSERT_EQUAL(length(key_bindings["give"]), 0, "字符串值重置后应为空列表")
	TEST_ASSERT_EQUAL(length(key_bindings["drop"]), 1, "非文本元素应被剔除")
	TEST_ASSERT_EQUAL(key_bindings["drop"][1], "Q", "保留的文本元素不应变化")
	TEST_ASSERT(islist(key_bindings["corrupt_object"]), "关联表对象应被重置为 list()")
	TEST_ASSERT_EQUAL(length(key_bindings["corrupt_object"]), 0, "关联表对象重置后应为空列表")
	TEST_ASSERT(islist(key_bindings["corrupt_false_object"]), "含假值关联项的对象应被重置为 list()")
	TEST_ASSERT_EQUAL(length(key_bindings["corrupt_false_object"]), 0, "含假值关联项的对象重置后应为空列表")

	TEST_ASSERT(!sanitize_key_binding_values(key_bindings), "重复清洗不应再报告改动")
	TEST_ASSERT(!sanitize_key_binding_values(null), "null 输入应安全返回 FALSE")

	// 单条兜底（get_ui_static_data 使用）同样拦截非 list、关联表和非文本元素
	TEST_ASSERT_EQUAL(length(sanitize_key_binding_entry(null)), 0, "单条清洗 null 应返回空列表")
	TEST_ASSERT_EQUAL(length(sanitize_key_binding_entry(list("a" = 1))), 0, "单条清洗关联表应返回空列表")
	TEST_ASSERT_EQUAL(length(sanitize_key_binding_entry(list("a" = FALSE))), 0, "单条清洗假值关联表应返回空列表")
	var/list/cleaned_drop = sanitize_key_binding_entry(list("Q", 7))
	TEST_ASSERT_EQUAL(length(cleaned_drop), 1, "单条清洗应剔除非文本元素")
	TEST_ASSERT_EQUAL(cleaned_drop[1], "Q", "单条清洗应保留合法文本键位")

	// 修好的表 JSON 往返后，客户端拿到的值均为数组（不再触发 hotkeys.filter 报错）
	var/encoded = json_encode(key_bindings)
	var/list/roundtrip = json_decode(encoded)
	TEST_ASSERT(islist(roundtrip["stop_interactions"]), "JSON 往返后 null 条目应为数组")
	TEST_ASSERT_EQUAL(length(roundtrip["corrupt_object"]), 0, "JSON 往返后关联表条目应为空数组")
	TEST_ASSERT(findtext(encoded, "\"null_object\":\[\"X\"\]"), "带 null 关联值的表清洗后应序列化为数组而非对象")

	// 产生侧：LAZYCOPY(null) 归一化为空 list，且对非空默认列表返回独立拷贝
	var/list/empty_default = null
	var/list/copied_empty = LAZYCOPY(empty_default)
	TEST_ASSERT(islist(copied_empty), "LAZYCOPY(null) 应归一化为空 list")
	TEST_ASSERT_EQUAL(length(copied_empty), 0, "LAZYCOPY(null) 长度应为 0")
	var/list/sample_default = list("E")
	var/list/copied_default = LAZYCOPY(sample_default)
	copied_default += "F"
	TEST_ASSERT_EQUAL(length(sample_default), 1, "修改拷贝不应影响默认键位列表")

	var/datum/keybinding/stop_interactions = GLOB.keybindings_by_name["stop_interactions"]
	if(!isnull(stop_interactions))
		TEST_ASSERT(islist(LAZYCOPY(stop_interactions.hotkey_keys)), "stop_interactions 热键经 LAZYCOPY 后应为 list")
		TEST_ASSERT(islist(LAZYCOPY(stop_interactions.classic_keys)), "stop_interactions 经典键经 LAZYCOPY 后应为 list")
