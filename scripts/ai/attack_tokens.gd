extends Node
## Autoload "AttackTokens": attack tokens for the minions (spec 8.1). At most 2 attack at once.
## Shared threats (8.2): while the boss warns of or executes an attack near Kaelen
## (`set_boss_threat`), no new tokens are handed out (SquadTactics.token_slots).

const MAX_TOKENS := 2

var boss_threat := false
var boss_threat_near := false

var _holders: Array = []


func request(enemy: Node) -> bool:
	_prune()
	if _holders.has(enemy):
		return true
	if _holders.size() >= slots():
		return false
	_holders.append(enemy)
	return true


func release(enemy: Node) -> void:
	_holders.erase(enemy)


func reset() -> void:
	_holders.clear()
	boss_threat = false
	boss_threat_near = false


## The boss is threatening (warning or active attack). `near`: within SquadTactics.THREAT_RADIUS m of Kaelen.
func set_boss_threat(on: bool, near: bool) -> void:
	boss_threat = on
	boss_threat_near = on and near


## Tokens that can be held right now (0 while the boss threatens nearby).
func slots() -> int:
	return SquadTactics.token_slots(boss_threat, boss_threat_near, MAX_TOKENS)


## true if `enemy` holds a token right now (after reset() or releasing the minion, it does not).
func is_holder(enemy: Node) -> bool:
	_prune()
	return _holders.has(enemy)


func holders_count() -> int:
	_prune()
	return _holders.size()


## A freed minion gives its token back by itself.
func _prune() -> void:
	for i in range(_holders.size() - 1, -1, -1):
		if not is_instance_valid(_holders[i]):
			_holders.remove_at(i)
