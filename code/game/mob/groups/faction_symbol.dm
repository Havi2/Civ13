// ============================================================
// Faction custom symbols
// ------------------------------------------------------------
// A 32x32 pixel-art editor (NanoUI) that lets a faction's Leader draw a
// bespoke banner emblem instead of only picking from the fixed shape list
// chosen at faction creation (see create_faction_pr() in factions.dm). 32x32
// is not arbitrary: it's the exact size of the existing "b_[symbol]" states
// in icons/obj/banners.dmi (confirmed by reading the .dmi's own metadata),
// so a saved custom symbol drops into the SAME banner overlay slot with no
// scaling or repositioning -- it coexists with, rather than replaces, the
// original mechanism.
//
// The two starting-point tools:
//   - Stamp one of the 6 existing shapes (reads real pixel data out of the
//     shipped banners.dmi via icon.GetPixel(), confirmed supported by this
//     BYOND build) as an editable starting point.
//   - Bucket-fill, starting from the plain white background.
// Both just seed/mutate the same editable grid -- nothing is locked.
//
// custom_civs[faction][7]/[8] (main/secondary color, already consumed by the
// banner, faction posters and official paper) are re-derived from the
// drawing itself on save, so nothing downstream needs to change.
// ============================================================

#define FACTION_SYMBOL_SIZE 32
var/global/list/faction_symbol_shapes = list("star", "sun", "moon", "cross", "big cross", "saltire")

/obj/map_metadata
	var/list/faction_symbol_grid = list()        // faction => flat list of SIZE*SIZE hex strings, row-major top-to-bottom
	var/list/faction_symbol_icon = list()        // faction => finalized /icon (null until first save)
	var/list/faction_symbol_tool = list()        // faction => "paint" or "bucket"
	var/list/faction_symbol_color = list()       // faction => current active paint color

/obj/map_metadata/proc/faction_symbol_index(x, y)
	return (y - 1) * FACTION_SYMBOL_SIZE + x

/obj/map_metadata/proc/ensure_faction_symbol_grid(faction)
	var/list/grid = faction_symbol_grid[faction]
	if (!grid)
		grid = new/list(FACTION_SYMBOL_SIZE * FACTION_SYMBOL_SIZE)
		for (var/i = 1, i <= grid.len, i++)
			grid[i] = "#FFFFFF"
		faction_symbol_grid[faction] = grid
	return grid

/obj/map_metadata/proc/get_faction_symbol_pixel(faction, x, y)
	var/list/grid = ensure_faction_symbol_grid(faction)
	return grid[faction_symbol_index(x, y)]

/obj/map_metadata/proc/set_faction_symbol_pixel(faction, x, y, color)
	if (x < 1 || x > FACTION_SYMBOL_SIZE || y < 1 || y > FACTION_SYMBOL_SIZE)
		return
	var/list/grid = ensure_faction_symbol_grid(faction)
	grid[faction_symbol_index(x, y)] = color

// Reads the shipped 32x32 shape art pixel-by-pixel and drops it into the
// editable grid as a starting point (fully editable afterward -- a stamp,
// not a lock). BYOND's icon.GetPixel() addresses row 1 as the BOTTOM row;
// our grid addresses row 1 as the visual TOP (matching the UI's top-down
// rendering), so the y axis is flipped here.
/obj/map_metadata/proc/stamp_faction_symbol(faction, shape)
	if (!(shape in faction_symbol_shapes))
		return
	var/icon/source = icon('icons/obj/banners.dmi', "b_[shape]")
	var/list/grid = ensure_faction_symbol_grid(faction)
	for (var/y = 1, y <= FACTION_SYMBOL_SIZE, y++)
		for (var/x = 1, x <= FACTION_SYMBOL_SIZE, x++)
			grid[faction_symbol_index(x, y)] = source.GetPixel(x, FACTION_SYMBOL_SIZE - y + 1)

/obj/map_metadata/proc/clear_faction_symbol(faction)
	var/list/grid = ensure_faction_symbol_grid(faction)
	for (var/i = 1, i <= grid.len, i++)
		grid[i] = "#FFFFFF"
	faction_symbol_icon[faction] = null

// 4-connected iterative flood fill from (x,y), replacing every contiguous
// same-colored pixel with new_color. Iterative (own stack), not recursive --
// a 32x32 grid can be up to 1024 cells deep in a pathological case, more
// than comfortably safe for DM's call stack.
/obj/map_metadata/proc/bucket_fill_faction_symbol(faction, x, y, new_color)
	var/list/grid = ensure_faction_symbol_grid(faction)
	var/target = get_faction_symbol_pixel(faction, x, y)
	if (!target || target == new_color)
		return
	var/list/stack = list(list(x, y))
	var/list/visited = list()
	while (stack.len)
		var/list/point = stack[stack.len]
		stack.len--
		var/px = point[1]
		var/py = point[2]
		if (px < 1 || px > FACTION_SYMBOL_SIZE || py < 1 || py > FACTION_SYMBOL_SIZE)
			continue
		var/key = "[px],[py]"
		if (visited[key])
			continue
		visited[key] = TRUE
		if (grid[faction_symbol_index(px, py)] != target)
			continue
		grid[faction_symbol_index(px, py)] = new_color
		stack += list(list(px + 1, py))
		stack += list(list(px - 1, py))
		stack += list(list(px, py + 1))
		stack += list(list(px, py - 1))

// Bakes the grid into a real PNG via rust_g (the same primitive already used
// by the -- currently non-functional -- painting canvas feature), loads it
// as a usable /icon, and re-derives the faction's two display colors from
// the drawing. Returns TRUE on success.
/obj/map_metadata/proc/finalize_faction_symbol(faction)
	var/list/grid = ensure_faction_symbol_grid(faction)
	// text2file() into a not-yet-existing directory creates the missing
	// parent folders as a side effect (standard, reliable DM file I/O
	// behaviour) -- do this first so rust_g always has somewhere to write,
	// since its own directory-creation behaviour isn't something we can
	// verify from here (compiled native library, no source to check).
	if (!fexists("data/faction_symbols"))
		text2file("", "data/faction_symbols/.keep")
	var/list/data = list()
	for (var/i = 1, i <= grid.len, i++)
		data += grid[i]
	var/png_filename = "data/faction_symbols/[ckey(faction)].png"
	var/result = rustg_dmi_create_png(png_filename, "[FACTION_SYMBOL_SIZE]", "[FACTION_SYMBOL_SIZE]", data.Join(""))
	if (result)
		log_debug("faction_symbol: rustg_dmi_create_png failed for [faction]: [result]")
		return FALSE
	faction_symbol_icon[faction] = new/icon(png_filename)
	apply_faction_symbol_colors(faction)
	return TRUE

/obj/map_metadata/proc/get_faction_symbol_icon(faction)
	return faction_symbol_icon[faction]

// Admin moderation action: blanks the grid AND bakes+saves a genuinely blank
// white icon as the faction's active custom symbol (rather than just
// clearing it back to null, which would fall through to re-displaying
// whatever fixed shape they originally picked at creation -- not what an
// admin wiping an offending drawing wants). The faction's colors are left
// alone; only the symbol art itself is reset.
/obj/map_metadata/proc/admin_reset_faction_symbol(faction)
	clear_faction_symbol(faction)
	if (!fexists("data/faction_symbols"))
		text2file("", "data/faction_symbols/.keep")
	var/list/grid = ensure_faction_symbol_grid(faction)
	var/list/data = list()
	for (var/i = 1, i <= grid.len, i++)
		data += grid[i]
	var/png_filename = "data/faction_symbols/[ckey(faction)].png"
	var/result = rustg_dmi_create_png(png_filename, "[FACTION_SYMBOL_SIZE]", "[FACTION_SYMBOL_SIZE]", data.Join(""))
	if (result)
		log_debug("faction_symbol: admin reset failed to bake blank png for [faction]: [result]")
		return FALSE
	faction_symbol_icon[faction] = new/icon(png_filename)
	return TRUE

// ------------------------------------------------------------
// Color extraction: pick the two colors that best represent the drawing,
// biased toward genuinely DIFFERENT colors (not two near-identical shades of
// the same hue) unless the drawing itself only really uses one hue family.
// ------------------------------------------------------------

/proc/hex2rgb_list(hex)
	if (copytext(hex, 1, 2) == "#")
		hex = copytext(hex, 2)
	return list(hex2num(copytext(hex, 1, 3)), hex2num(copytext(hex, 3, 5)), hex2num(copytext(hex, 5, 7)))

// Hue in degrees (0-360). Avoids DM's % operator on negative operands
// (sign behaviour there isn't worth relying on) by adjusting with plain ifs.
/proc/hex2hue(hex)
	var/list/c = hex2rgb_list(hex)
	var/r = c[1] / 255
	var/g = c[2] / 255
	var/b = c[3] / 255
	var/cmax = max(r, g, b)
	var/cmin = min(r, g, b)
	var/delta = cmax - cmin
	if (delta == 0)
		return 0 // grayscale: hue is undefined, treat as 0 (red bucket)
	var/hue
	if (cmax == r)
		hue = 60 * ((g - b) / delta)
	else if (cmax == g)
		hue = 60 * (((b - r) / delta) + 2)
	else
		hue = 60 * (((r - g) / delta) + 4)
	if (hue < 0)
		hue += 360
	if (hue >= 360)
		hue -= 360
	return hue

// Shifts a color toward white (factor > 0) or black (factor < 0).
/proc/shift_color_lightness(hex, factor)
	var/list/c = hex2rgb_list(hex)
	var/r = c[1]
	var/g = c[2]
	var/b = c[3]
	if (factor >= 0)
		r += (255 - r) * factor
		g += (255 - g) * factor
		b += (255 - b) * factor
	else
		r += r * factor
		g += g * factor
		b += b * factor
	return rgb(clamp(round(r), 0, 255), clamp(round(g), 0, 255), clamp(round(b), 0, 255))

// Re-derives custom_civs[faction][7]/[8] (main/secondary color -- the SAME
// fields the banner, faction posters and official paper already read) from
// the saved grid. Buckets by hue (15-degree buckets) so near-identical exact
// shades of one color count as the same color for this purpose, takes the
// heaviest bucket as primary, then the heaviest OTHER bucket that's at least
// ~40 degrees of hue away as secondary. If nothing is far enough away (the
// drawing is genuinely one hue family), falls back to a lighter shade of
// that same hue instead of forcing an unrelated color.
/obj/map_metadata/proc/apply_faction_symbol_colors(faction)
	var/list/grid = ensure_faction_symbol_grid(faction)
	var/list/freq = list()
	for (var/i = 1, i <= grid.len, i++)
		var/c = uppertext(grid[i])
		if (c == "#FFFFFF")
			continue // ignore the blank background so an empty drawing doesn't skew this
		freq[c] = (freq[c] ? freq[c] : 0) + 1
	if (!freq.len)
		return // nothing but background was drawn -- leave existing colors alone

	var/list/bucket_weight = list()
	var/list/bucket_color = list()
	var/list/bucket_color_count = list()
	for (var/c in freq)
		var/hue = round(hex2hue(c) / 15) * 15
		bucket_weight[hue] = (bucket_weight[hue] ? bucket_weight[hue] : 0) + freq[c]
		if (!bucket_color_count[hue] || freq[c] > bucket_color_count[hue])
			bucket_color_count[hue] = freq[c]
			bucket_color[hue] = c

	var/best_hue = null
	var/best_weight = 0
	for (var/h in bucket_weight)
		if (bucket_weight[h] > best_weight)
			best_weight = bucket_weight[h]
			best_hue = h
	var/primary_color = bucket_color[best_hue]

	var/second_hue = null
	var/second_weight = 0
	for (var/h in bucket_weight)
		if (h == best_hue)
			continue
		var/diff = abs(h - best_hue)
		if (diff > 180)
			diff = 360 - diff
		if (diff < 40)
			continue // too close to primary to read as a genuinely different color
		if (bucket_weight[h] > second_weight)
			second_weight = bucket_weight[h]
			second_hue = h

	var/secondary_color = second_hue ? bucket_color[second_hue] : shift_color_lightness(primary_color, 0.4)

	var/list/civ_data = custom_civs[faction]
	if (civ_data && civ_data.len >= 8)
		civ_data[7] = primary_color
		civ_data[8] = secondary_color

// ------------------------------------------------------------
// Editor UI (Leader-only; see design_faction_symbol() below). Uses the
// existing /datum/nano_module pattern (see appearance_changer.dm) rather
// than a physical structure: created fresh per verb call, all real state
// lives on map_metadata so re-opening or auto-refreshing always reflects the
// current saved grid, no separate per-instance state to lose track of.
// ------------------------------------------------------------

/datum/nano_module/faction_symbol_editor
	name = "Faction Symbol Editor"
	var/mob/living/human/owner
	var/faction

/datum/nano_module/faction_symbol_editor/New(var/location, var/mob/living/human/H)
	..(location)
	owner = H
	faction = H.civilization

/datum/nano_module/faction_symbol_editor/ui_interact(mob/user, ui_key = "main", var/datum/nanoui/ui = null, var/force_open = TRUE)
	if (!map || !faction || faction == "none")
		return
	var/list/data = host.initial_data()

	var/list/grid = map.ensure_faction_symbol_grid(faction)
	data["grid"] = grid.Copy()
	var/tool = map.faction_symbol_tool[faction]
	data["tool"] = tool ? tool : "paint"
	var/color = map.faction_symbol_color[faction]
	data["color"] = color ? color : "#000000"
	data["shapes"] = faction_symbol_shapes
	data["has_saved_icon"] = map.get_faction_symbol_icon(faction) ? TRUE : FALSE

	ui = GLOB.nanomanager.try_update_ui(user, src, ui_key, ui, data, force_open)
	if (!ui)
		ui = new(user, src, ui_key, "faction_symbol.tmpl", name, 620, 760)
		ui.add_stylesheet("civ13_theme.css")
		ui.add_stylesheet("faction_symbol.css")
		ui.add_script("faction_symbol.js")
		ui.set_initial_data(data)
		ui.open()

/datum/nano_module/faction_symbol_editor/Topic(href, href_list)
	if (!istype(owner) || owner.stat)
		return
	if (!map || !faction || faction == "none" || owner.civilization != faction)
		return
	if (!map.is_faction_leader(owner, faction))
		to_chat(owner, SPAN_WARNING("Only your faction's Leader may redesign its symbol."))
		return

	if (href_list["set_tool"])
		map.faction_symbol_tool[faction] = href_list["set_tool"]
	else if (href_list["pick_color"])
		var/newcolor = input(owner, "Choose the active paint color:", "Faction Symbol", map.faction_symbol_color[faction] || "#000000") as color
		if (newcolor)
			map.faction_symbol_color[faction] = newcolor
	else if (href_list["paint"])
		var/x = text2num(href_list["x"])
		var/y = text2num(href_list["y"])
		var/tool = map.faction_symbol_tool[faction]
		var/color = map.faction_symbol_color[faction] || "#000000"
		if (tool == "bucket")
			map.bucket_fill_faction_symbol(faction, x, y, color)
		else
			map.set_faction_symbol_pixel(faction, x, y, color)
	else if (href_list["stamp"])
		var/choice = WWinput(owner, "Stamp which shape onto the canvas? This OVERWRITES the current drawing.", "Faction Symbol", "Cancel", list("Cancel") + faction_symbol_shapes)
		if (choice && choice != "Cancel")
			map.stamp_faction_symbol(faction, choice)
	else if (href_list["clear"])
		map.clear_faction_symbol(faction)
	else if (href_list["save"])
		if (map.finalize_faction_symbol(faction))
			to_chat(owner, SPAN_NOTICE("Your faction's new symbol is saved. It'll appear on any banner you build from now on."))
		else
			to_chat(owner, SPAN_WARNING("Something went wrong saving the symbol. Try again."))
	GLOB.nanomanager.update_uis(src)

/mob/living/human/proc/design_faction_symbol()
	set name = "Design Faction Symbol"
	set category = "Faction"
	set desc = "Draw a custom symbol for your faction's banners, replacing the default shape."

	if (!civilization || civilization == "none")
		to_chat(src, SPAN_WARNING("You are not part of any faction."))
		return
	if (!map || !map.is_faction_leader(src, civilization))
		to_chat(src, SPAN_WARNING("Only the Leader of your faction may redesign its symbol."))
		return
	var/datum/nano_module/faction_symbol_editor/editor = new(src, src)
	editor.ui_interact(src)
