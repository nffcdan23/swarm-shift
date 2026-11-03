class_name LeaderboardService
extends RefCounted
## Where challenge scores would go. Today nothing leaves the device: the default
## backend only remembers the latest submissions (for tests and for a future
## "your best" view). A Game Center backend can replace it later without
## touching ChallengeService: board ids come from retention.json
## ("leaderboard"), each submission carries the challenge's period id, so
## recurring daily and weekly boards map onto it directly.
##
## A real ranking also needs what this build does not have: an authoritative
## shared schedule, so everyone plays the same challenge, and server-side
## validation of scores. Until then, nothing here should be presented as a
## fair global ranking.

const KEPT := 20

## Newest last: {"board", "period", "score", "context"}.
var submitted: Array[Dictionary] = []


func submit(board: String, period: String, score: int, context: Dictionary = {}) -> void:
	if board.is_empty():
		return
	submitted.append({"board": board, "period": period, "score": score, "context": context.duplicate()})
	while submitted.size() > KEPT:
		submitted.pop_front()
