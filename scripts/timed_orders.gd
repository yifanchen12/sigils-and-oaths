extends RefCounted
## Public field orders occupy a card zone until the issuing side next acts.

static func for_side(battle: RefCounted, side: int) -> Dictionary:
	for order: Dictionary in battle.pending_orders:
		if order.side == side: return order
	return {}

static func targets(battle: RefCounted, side: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if not for_side(battle, side).is_empty(): return cells
	for cell: Vector2i in battle.casting_cells(side):
		if battle.passable(cell): cells.append(cell)
	return cells

static func place(battle: RefCounted, instance: Dictionary, card: Dictionary, center: Vector2i) -> void:
	battle.pending_orders.append({"side": battle.active_side, "card": instance, "pos": center, "due_turn": battle.turn + 2})
	battle._record("「%s」标在 %s，将于第 %d 回合开始生效。" % [card.name, battle.cell_name(center), battle.turn + 2])

static func footprint(battle: RefCounted, order: Dictionary) -> Array[Vector2i]:
	var card: Dictionary = battle.definition(order.card.card_id)
	return battle.Formation.footprint(battle, order.pos, int(card.radius), str(card.get("shape", "")))

static func resolve(battle: RefCounted) -> bool:
	var order: Dictionary = for_side(battle, battle.active_side)
	if order.is_empty() or order.due_turn != battle.turn: return false
	var card: Dictionary = battle.definition(order.card.card_id)
	battle.pending_orders.erase(order)
	battle.players[order.side].discard.append(order.card)
	battle._record("「%s」在 %s 生效。" % [card.name, battle.cell_name(order.pos)])
	battle.last_order_event = {"card_id": card.id, "name": card.name, "pos": order.pos, "cells": footprint(battle, order), "support": card.target_side == "ally"}
	battle.last_order_event["impacts"] = battle.Formation.resolve(battle, card, order.pos, order.side, true)
	return true

static func incoming(battle: RefCounted, unit: Dictionary) -> int:
	var order: Dictionary = for_side(battle, 1 - unit.side)
	if order.is_empty(): return 0
	var card: Dictionary = battle.definition(order.card.card_id)
	if card.target_side != "enemy" or not battle.Formation.covers(order.pos, unit.pos, int(card.radius), str(card.get("shape", ""))): return 0
	return battle.Formation.damage(battle, card, order.side, unit.kind == "commander")
