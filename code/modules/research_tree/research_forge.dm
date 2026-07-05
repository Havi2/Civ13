// ============================================================
// Research Tree - resource forge (Phase 3)
// ------------------------------------------------------------
// A faction's research bench cap rises automatically with era, but
// can also be raised further by feeding COINS here. Copper, silver
// and gold coins are accepted, contributing their value in silver-
// equivalents (copper 0.1, silver 1, gold 4). One forge serves the
// whole faction (not tied to a single bench). No world scans: the
// silver-equivalent flows into the map metadata's per-faction forge
// progress, which accumulates across feedings.
// ============================================================

/obj/structure/research_forge
	name = "resource forge"
	desc = "A forge for melting down coins to expand what your faction's research infrastructure can support. Feed it copper, silver or gold coins to raise your faction's research bench limit."
	icon = 'icons/obj/structures.dmi'
	icon_state = "safe"
	density = TRUE
	anchored = TRUE
	not_movable = FALSE
	not_disassemblable = TRUE

/obj/structure/research_forge/attackby(obj/item/W as obj, mob/living/human/user as mob)
	if (!istype(W) || !ishuman(user))
		return ..()
	if (!user.civilization || user.civilization == "none")
		to_chat(user, SPAN_WARNING("You must belong to a faction to use a resource forge."))
		return
	if (!map)
		return
	// Only the three metal coin types (and their subtypes) -- NOT the money
	// base, which also covers rubles/francs/euros/pounds/etc.
	if (!istype(W, /obj/item/stack/money/coppercoin) && !istype(W, /obj/item/stack/money/silvercoin) && !istype(W, /obj/item/stack/money/goldcoin))
		to_chat(user, SPAN_WARNING("The resource forge only accepts copper, silver or gold coins."))
		return
	var/obj/item/stack/money/coins = W
	var/count = coins.amount
	var/coinname = coins.name
	// Silver-equivalent: coin.value is already 0.1 (copper) / 1 (silver) / 4
	// (gold), so value * amount is the silver-denominated contribution.
	var/silver_equiv = coins.value * count
	qdel(W)
	// Accumulates cumulatively; a slot costing more than one full 500-coin
	// stack is paid off over several feedings, overshoot rolling forward.
	if (map.add_forge_value(user.civilization, silver_equiv))
		to_chat(user, SPAN_NOTICE("You melt down [count] [coinname] ([silver_equiv] in silver). Your faction's research bench limit has increased to [map.get_bench_cap(user.civilization)]!"))
	else
		var/bonus = map.faction_bench_cap_bonus[user.civilization]
		var/progress = map.faction_forge_progress[user.civilization]
		to_chat(user, SPAN_NOTICE("You melt down [count] [coinname] ([silver_equiv] in silver). Bench cap upgrade progress: [round(progress, 0.1)]/[FORGE_CAP_UPGRADE_COST(bonus ? bonus : 0)] silver."))
