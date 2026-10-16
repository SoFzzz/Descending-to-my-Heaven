extends Node
## Autoload "AttackTokens": fichas de ataque de los esbirros (spec §8.1). Máximo 2 atacando a la vez.
## Amenazas compartidas (§8.2): mientras el jefe avisa o ejecuta un ataque cerca de Kaelen
## (`set_boss_threat`), no se reparten fichas nuevas (SquadTactics.token_slots).

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


## El jefe amenaza (aviso o ataque activo). `near`: a ≤ SquadTactics.THREAT_RADIUS m de Kaelen.
func set_boss_threat(on: bool, near: bool) -> void:
	boss_threat = on
	boss_threat_near = on and near


## Fichas que se pueden tener ahora mismo (0 mientras el jefe amenaza cerca).
func slots() -> int:
	return SquadTactics.token_slots(boss_threat, boss_threat_near, MAX_TOKENS)


## true si `enemy` tiene ficha ahora (tras reset() o liberar al esbirro, ya no).
func is_holder(enemy: Node) -> bool:
	_prune()
	return _holders.has(enemy)


func holders_count() -> int:
	_prune()
	return _holders.size()


# Un esbirro liberado devuelve su ficha solo.
func _prune() -> void:
	_holders = _holders.filter(func(h) -> bool: return is_instance_valid(h))
