#define MAX_HOTKEY_SLOTS 3

/// Middleware to handle keybindings
/datum/preference_middleware/keybindings
	action_delegations = list(
		"reset_all_keybinds" = PROC_REF(reset_all_keybinds),
		"reset_keybinds_to_defaults" = PROC_REF(reset_keybinds_to_defaults),
		"set_keybindings" = PROC_REF(set_keybindings),
	)

/datum/preference_middleware/keybindings/get_ui_static_data(mob/user)
	if (preferences.current_window == PREFERENCE_TAB_CHARACTER_PREFERENCES)
		return list()

	var/list/keybindings = list()
	for (var/keybind_name in preferences.key_bindings)
		if(!istext(keybind_name))
			continue
		keybindings[keybind_name] = sanitize_key_binding_entry(preferences.key_bindings[keybind_name])

	return list(
		"keybindings" = keybindings,
	)

/datum/preference_middleware/keybindings/get_ui_assets()
	return list(
		get_asset_datum(/datum/asset/json/keybindings)
	)

/datum/preference_middleware/keybindings/proc/reset_all_keybinds(list/params, mob/user)
	preferences.key_bindings = deep_copy_list(GLOB.default_hotkeys)
	preferences.key_bindings_by_key = preferences.get_key_bindings_by_key(preferences.key_bindings)
	preferences.update_static_data(user)
	user.client.update_special_keybinds()

	return TRUE

/datum/preference_middleware/keybindings/proc/reset_keybinds_to_defaults(list/params, mob/user)
	var/keybind_name = params["keybind_name"]
	var/datum/keybinding/keybinding = GLOB.keybindings_by_name[keybind_name]

	if (isnull(keybinding))
		return FALSE

	// 对没有默认键位的动作（如 stop_interactions），hotkey_keys/classic_keys 为 null；
	// 直接赋值会把 null 写进偏好，让 TGUI 按键绑定页读到 null 后整页报错。
	// LAZYCOPY 顺便拷一份，避免把 /datum/keybinding 上的默认列表引用直接存进玩家偏好。
	var/list/default_keys = preferences.parent.hotkeys ? keybinding.hotkey_keys : keybinding.classic_keys
	preferences.key_bindings[keybind_name] = LAZYCOPY(default_keys)
	preferences.key_bindings_by_key = preferences.get_key_bindings_by_key(preferences.key_bindings)

	preferences.update_static_data(user)
	user.client.update_special_keybinds()

	return TRUE

/datum/preference_middleware/keybindings/proc/set_keybindings(list/params, mob/user)
	var/keybind_name = params["keybind_name"]

	if (isnull(GLOB.keybindings_by_name[keybind_name]))
		return FALSE

	var/list/raw_hotkeys = params["hotkeys"]
	if (!istype(raw_hotkeys))
		return FALSE

	if (raw_hotkeys.len > MAX_HOTKEY_SLOTS)
		return FALSE

	// There's no optimal, easy way to check if something is an array
	// and not an object in BYOND, so just sanitize it to make sure.
	var/list/hotkeys = list()
	for (var/hotkey in raw_hotkeys)
		if (!istext(hotkey))
			return FALSE

		// Fairly arbitrary number, it's just so you don't save enormous fake keybinds.
		if (length(hotkey) > 100)
			return FALSE

		hotkeys += hotkey

	preferences.key_bindings[keybind_name] = hotkeys
	preferences.key_bindings_by_key = preferences.get_key_bindings_by_key(preferences.key_bindings)

	user.client.update_special_keybinds()

	return TRUE

/datum/asset/json/keybindings
	name = "keybindings"

/datum/asset/json/keybindings/generate()
	var/list/keybindings = list()

	for (var/name in GLOB.keybindings_by_name)
		var/datum/keybinding/keybinding = GLOB.keybindings_by_name[name]

		if (!(keybinding.category in keybindings))
			keybindings[keybinding.category] = list()

		keybindings[keybinding.category][keybinding.name] = list(
			"name" = keybinding.full_name,
			"description" = keybinding.description,
			"can_edit" = keybinding.can_edit,
			"default" = keybinding.hotkey_keys,
		)

	return keybindings

#undef MAX_HOTKEY_SLOTS

/// 清洗单条键位值为纯文本顺序列表（非 list 或关联表/JSON 对象会被重置为空 list）。
/proc/sanitize_key_binding_entry(raw_keys)
	if(!islist(raw_keys))
		return list()
	var/list/keys = raw_keys
	var/list/text_keys = list()
	for (var/key in keys)
		if(!istext(key))
			continue
		if(!isnull(keys[key]))
			return list()
		text_keys += key
	return text_keys

/// 就地清洗键位表，返回是否有条目被修复。
///
/// 历史遗留数据：对**没有默认键位**的动作（`stop_interactions` /「Cancel Interactions」）
/// 点「Reset to Defaults」时，旧代码会把 `null` 写进 `preferences.key_bindings`；
/// 而 BYOND 的 `list[key] = null` 只清空关联值、不删键，`(key in list)` 仍为真，
/// 于是 `check_keybindings()` 永远跳过它、`save_preferences()` 每次登录原样写回。
/// TGUI 的按键绑定页会把每个值当数组用（`hotkeys.filter(...)`），读到 null 就整页崩。
///
/// 这里把非 list 或关联表（JSON 对象）重置为空 list，并剔除非文本元素。
/proc/sanitize_key_binding_values(list/key_bindings)
	if(!islist(key_bindings))
		return FALSE

	var/repaired = FALSE
	for (var/keybind_name in key_bindings)
		if(!istext(keybind_name))
			continue
		var/list/keys = key_bindings[keybind_name]
		if(!islist(keys))
			key_bindings[keybind_name] = list()
			repaired = TRUE
			continue

		var/list/text_keys = list()
		var/is_assoc = FALSE
		for (var/key in keys)
			if(!istext(key))
				continue
			if(!isnull(keys[key]))
				is_assoc = TRUE
				break
			text_keys += key
		if(is_assoc)
			key_bindings[keybind_name] = list()
			repaired = TRUE
			continue
		if(length(text_keys) != length(keys))
			repaired = TRUE
		key_bindings[keybind_name] = text_keys
	return repaired

