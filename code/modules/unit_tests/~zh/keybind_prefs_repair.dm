/// 验证键位表清洗（历史遗留的 null 键位条目会让「设置 → 按键绑定」整页报错）：
/// 1) 非 list 的键位值被重置为空 list；2) 正常条目不受影响；3) 非文本元素被剔除；
/// 4) 幂等；5) 输入非 list 不崩；6) 清洗后 JSON 往返仍是数组。
/datum/unit_test/keybind_prefs_repair

/datum/unit_test/keybind_prefs_repair/Run()
	// BYOND 里 `list[key] = null` 会保留键、只清空值 —— 复刻脏数据的形态
	var/list/key_bindings = list()
	key_bindings["stop_interactions"] = null
	key_bindings["pickup"] = list("E")
	key_bindings["give"] = "ShiftG"
	key_bindings["drop"] = list("Q", 7)

	TEST_ASSERT_EQUAL(length(key_bindings), 4, "前置条件：条目数应为 4")
	TEST_ASSERT_NULL(key_bindings["stop_interactions"], "前置条件：该条目的值应为 null")

	TEST_ASSERT(sanitize_key_binding_values(key_bindings), "应当报告修复了坏条目")
	TEST_ASSERT(islist(key_bindings["stop_interactions"]), "null 条目应被重置为 list()")
	TEST_ASSERT_EQUAL(length(key_bindings["stop_interactions"]), 0, "null 条目重置后应为空列表")
	TEST_ASSERT_EQUAL(length(key_bindings), 4, "修复不应增加或减少条目数量")

	TEST_ASSERT_EQUAL(key_bindings["pickup"][1], "E", "正常条目不应被改动")
	TEST_ASSERT(islist(key_bindings["give"]), "字符串值应被重置为 list()")
	TEST_ASSERT_EQUAL(length(key_bindings["give"]), 0, "字符串值重置后应为空列表")
	TEST_ASSERT_EQUAL(length(key_bindings["drop"]), 1, "非文本元素应被剔除")
	TEST_ASSERT_EQUAL(key_bindings["drop"][1], "Q", "保留的文本元素不应变化")

	TEST_ASSERT(!sanitize_key_binding_values(key_bindings), "重复清洗不应再报告改动")
	TEST_ASSERT(!sanitize_key_binding_values(null), "null 输入应安全返回 FALSE")

	// 修好的表 JSON 往返后，客户端拿到的值仍是数组（不再触发 hotkeys.filter 报错）
	var/list/roundtrip = json_decode(json_encode(key_bindings))
	TEST_ASSERT(islist(roundtrip["stop_interactions"]), "JSON 往返后该值仍应为数组")

	// 产生侧的前提：这个动作确实没有任何默认键位（reset 后写出 null 就是从这里来的）
	var/datum/keybinding/stop_interactions = GLOB.keybindings_by_name["stop_interactions"]
	if(!isnull(stop_interactions))
		TEST_ASSERT_NULL(stop_interactions.hotkey_keys, "stop_interactions 不应有默认热键")
		TEST_ASSERT_NULL(stop_interactions.classic_keys, "stop_interactions 不应有默认经典键")
		TEST_ASSERT(islist(LAZYCOPY(stop_interactions.hotkey_keys)), "LAZYCOPY(null) 应归一化为空 list")
