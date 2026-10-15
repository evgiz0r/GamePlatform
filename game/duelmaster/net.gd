extends Node
## A tiny Firebase Realtime Database client over plain REST (HTTPRequest), so it runs the
## same in the browser, on desktop and headless. No SDK, no plugin.
##
## Every call is `await net.req("GET", "pool")` and comes back as {"ok": bool, "data": the
## parsed JSON}. Several can be in flight at once; each carries its own answer.
## Sign-in is Firebase's anonymous auth: nobody makes an account, each device just gets an
## id for as long as it plays.
##
## The config below is public by design -- every web game that uses Firebase ships it to
## the browser. What protects the data is the database's security rules, not this key.

const API_KEY := "AIzaSyBx6tMWVZbMPlNcyT7QD-Uyfy1CnWCDc9I"
const DB_URL := "https://duelmaster-f126f-default-rtdb.europe-west1.firebasedatabase.app"
const TIMEOUT := 8.0

var base := DB_URL
var key := API_KEY
var uid := ""
var _token := ""
var _refresh := ""
var _token_until := 0              ## ticks msec
## Requests to send as soon as this node is in the tree, after which it frees itself.
## That is how a game that is closing still says goodbye: see courier().
var _parting: Array = []

## Point at a different database (a local stand-in for testing) with DUELMASTER_DB.
## Without a key there is no sign-in and the id is made up locally.
func _ready() -> void:
	var over := OS.get_environment("DUELMASTER_DB")
	if over != "":
		base = over.trim_suffix("/")
		key = ""
	if not _parting.is_empty():
		for r in _parting:
			req(r[0], r[1], r[2])
		get_tree().create_timer(6.0).timeout.connect(queue_free)

## A copy of this client, signed in as the same player, that sends `requests` from the
## root of the tree -- so they still go out after the game's scene has been freed.
func courier(requests: Array) -> void:
	var c: Node = (get_script() as GDScript).new()
	c.uid = uid
	c._token = _token
	c._refresh = _refresh
	c._token_until = _token_until
	c._parting = requests
	# Engine.get_main_loop(), not get_tree(): this runs while the game is being freed, and
	# by then this node may already be out of the tree.
	(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(c)

static func random_id(n: int = 6) -> String:
	return Crypto.new().generate_random_bytes(n).hex_encode()

func sign_in() -> bool:
	if key == "":
		uid = "local" + random_id()
		return true
	var a: Dictionary = await _http("POST",
		"https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=" + key,
		{"returnSecureToken": true})
	var r: Variant = a.data
	if not a.ok or not (r is Dictionary) or not r.has("idToken"):
		return false
	_take_token(r.idToken, r.refreshToken, r.expiresIn)
	uid = r.localId
	return true

func _take_token(id_token: String, refresh: String, expires_in: Variant) -> void:
	_token = id_token
	_refresh = refresh
	# refresh five minutes early; tokens last an hour
	_token_until = Time.get_ticks_msec() + (int(expires_in) - 300) * 1000

func _fresh_token() -> void:
	if key == "" or _refresh == "" or Time.get_ticks_msec() < _token_until:
		return
	var a: Dictionary = await _http("POST",
		"https://securetoken.googleapis.com/v1/token?key=" + key,
		{"grant_type": "refresh_token", "refresh_token": _refresh})
	var r: Variant = a.data
	if a.ok and r is Dictionary and r.has("id_token"):
		_take_token(r.id_token, r.refresh_token, r.expires_in)

## method is GET PUT PATCH DELETE; path has no leading slash and no ".json".
func req(method: String, path: String, body: Variant = null) -> Dictionary:
	await _fresh_token()
	var url := "%s/%s.json" % [base, path]
	if _token != "":
		url += "?auth=" + _token
	return await _http(method, url, body)

## The database fills this in with its own clock when it stores it.
static func now_stamp() -> Dictionary:
	return {".sv": "timestamp"}

func _http(method: String, url: String, body: Variant) -> Dictionary:
	var h := HTTPRequest.new()
	h.timeout = TIMEOUT
	add_child(h)
	var m := HTTPClient.METHOD_GET
	match method:
		"PUT": m = HTTPClient.METHOD_PUT
		"PATCH": m = HTTPClient.METHOD_PATCH
		"DELETE": m = HTTPClient.METHOD_DELETE
		"POST": m = HTTPClient.METHOD_POST
	var data := "" if body == null else JSON.stringify(body)
	var err := h.request(url, ["Content-Type: application/json"], m, data)
	if err != OK:
		h.queue_free()
		return {"ok": false, "data": null}
	var res: Array = await h.request_completed
	h.queue_free()
	var code: int = res[1]
	if res[0] != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return {"ok": false, "data": null}
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	return {"ok": true, "data": JSON.parse_string(text) if text != "" else null}
