extends Node
## Autoload "AttackTokens": fichas de ataque de los esbirros (spec §8.1). Máximo 2 atacando a la vez.

const MAX_TOKENS := 2

var _holders: Array = []


func request(enemy: Node) -> bool:
	_prune()
	if _holders.has(enemy):
		return true
	if _holders.size() >= MAX_TOKENS:
		return false
	_holders.append(enemy)
	return true


func release(enemy: Node) -> void:
	_holders.erase(enemy)


func reset() -> void:
	_holders.clear()


func holders_count() -> int:
	_prune()
	return _holders.size()


# Un esbirro liberado devuelve su ficha solo.
func _prune() -> void:
	_holders = _holders.filter(func(h) -> bool: return is_instance_valid(h))
