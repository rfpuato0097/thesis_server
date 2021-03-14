extends Node

var PORT = 9080

var _server = WebSocketServer.new()
var _write_mode = WebSocketPeer.WRITE_MODE_BINARY
var _clients = {}

const SQLite = preload("res://addons/godot-sqlite/bin/gdsqlite.gdns")
const alphanumeric = "QWERTYUIOPASDFGHJKLZXCVBNM"

var db
var data

func _init():
	#Database
	db = SQLite.new()
	db.path = "res://game_db"
	db.verbose_mode = false
	db.foreign_keys = true
	db.open_db()
	
	db.create_table("lobbies", {
	"lobby_id" : {"data_type":"int", "primary_key":true, "not_null":true},
	"lobby_name" : {"data_type":"text", "not_null":true},
	"result_page_name" : {"data_type":"text", "not_null":true}
	})
	
	db.create_table("players", {
		"player_id": {"data_type":"int", "primary_key":true, "not_null":true},
		"player_name": {"data_type":"text", "not_null":true},
		"player_client_id" : {"data_type":"text", "not_null":true},
		"lobby_id": {"data_type":"int", "foreign_key":"lobbies.lobby_id", "not_null":true}
	})

	db.create_table("questions", {
		"question_id": {"data_type":"int", "primary_key":true, "not_null":true},
		"question": {"data_type":"text", "not_null":true},
		"answer": {"data_type":"text", "not_null":true},
		"lobby_id": {"data_type":"int", "foreign_key":"lobbies.lobby_id", "not_null":true}
	})
	
	db.create_table("additional_words", {
		"word_id": {"data_type":"int", "primary_key":true, "not_null":true},
		"word": {"data_type":"text", "not_null": true},
		"lobby_id": {"data_type":"int", "foreign_key":"lobbies.loddy.id", "not_null":true}
	})
	
	db.create_table("results",{
		"result_id": {"data_type":"int", "primary_key":true, "not_null":true},
		"player_id": {"data_type":"int", "foreign_key":"players.player_id", "not_null":true},
		"question_id": {"data_type":"int", "foreign_key":"questions.question_id", "not_null":true},
		"correct": {"data_type":"int", "not_null":true}
	})

	#Network
	_server.connect("client_connected", self, "_client_connected")
	_server.connect("client_disconnected", self, "_client_disconnected")
	_server.connect("client_close_request", self, "_client_close_request")
	_server.connect("data_received", self, "_client_receive")
	
	listen()
	
func _client_connected(id, protocol):
	_clients[id] = _server.get_peer(id)
	_clients[id].set_write_mode(_write_mode)
	Utils._log("Client %s connected with protocol %s" % [id, protocol] )
	
func _client_disconnected(id, clean = true):
	Utils._log("Clients %s disconnected. Was clean: %s" % [id, clean])
	if _clients.has(id):
		_clients.erase(id)
		
func _client_close_request(id, code, reason):
	print(reason == "Bye bye!")
	Utils._log("Client %s close code: %d, reason: %s" % [id ,code, reason])
	
func _client_receive(id):
	var packet = _server.get_peer(id).get_packet()
	var is_string = _server.get_peer(id).was_string_packet()
	#PARSE DATA RECEIVED HERE
	var received = Utils.decode_data(packet)
	print(received)
	
	var code = received[0]
	if code == "CG": #Create Game
		var questions_received = received[1]
		var lobby_name = genCode()
		var result_page_name = genCode()
		
		#Insert lobby into database
		db.insert_rows("lobbies", [
			{"lobby_name": lobby_name, "result_page_name": result_page_name}
		])
		
		#Insert questions into the database
		var lobby = db.select_rows("lobbies", "lobby_name = '%s' AND result_page_name = '%s'" % [lobby_name, result_page_name], ["*"]).duplicate(true)
		var lobby_id = lobby[0]["lobby_id"]
		print(questions_received)
		for q in questions_received:
			db.insert_rows("questions", [
				{"question":q[0], "answer":q[1], "lobby_id":lobby_id}
			])
		
		#Insert the additional words into the database
		if received.size() == 3:
			var addtlWords = received[2]
			for w in addtlWords:
				db.insert_rows("additional_words", [
					{"word":w, "lobby_id":lobby_id}
				])
		
		#Send lobby_name and result_page_name to client
		data = ["CG", lobby_id, lobby_name, result_page_name]
		send_data(data, id)
		
	if code == "JG": #Join Game
		Utils._log("Data from %s BINARY: %s: %s" % [id, not is_string, Utils.decode_data(packet)])
		var code_received = received[1]
		var player_name = received[2]
		
		#select lobby_id by using lobby_name
		var regex = RegEx.new()
		regex.compile("[0-9]*")
		var result = regex.search(code_received).get_string()
		var lobby_id = int(result)
		var lobby_name = code_received.replace(result, "")
		print ("lobby_id: %d lobby_name: %s" % [lobby_id, lobby_name])
		
		#check if lobby exists
		db.query_result = []
		db.query("SELECT * FROM lobbies WHERE lobby_id = '%d' AND lobby_name = '%s'" % [lobby_id, lobby_name])
		var lobby_exists = false
		if db.query_result != []:
			if db.query_result[0]["lobby_id"] == lobby_id and db.query_result[0]["lobby_name"] == lobby_name:
				lobby_exists = true
		print(db.query_result)
		if lobby_exists:
			#Insert player into database.
			print("Add player")
			db.insert_rows("players", [
				{"player_name":player_name, "player_client_id":id, "lobby_id":lobby_id}
			])
			#send questions
			var questions_selected = db.select_rows("questions", "lobby_id = '%d'" % lobby_id, ["question","answer"]).duplicate(true)
			var words_selected = db.select_rows("additional_words", "lobby_id = '%d'" % lobby_id, ["word"]).duplicate(true)
			send_data(["JG", questions_selected, words_selected, player_name],id)
			
		else:
			#Send Error to Client that Lobby does not exist.
			print("No such lobby")
			data = ["ER", "Lobby does not exist."]
			send_data(data,id)
			return
		
	if code == "GR": #Game Results
		print(received) # 
		var player_name = received[1]
		var correct_questions = received[2]
		var wrong_questions = received[3]
		
		#check player_client_id and player name.
		var is_player_in_records = db.select_rows("players", "player_name = '%s' AND player_client_id = '%d'" % [player_name, id], ["player_id", "lobby_id"]).duplicate(true)
		if is_player_in_records != []:
			var lobby_id = is_player_in_records[0]["lobby_id"]
			var player_id = is_player_in_records[0]["player_id"]
			var questions_from_db = db.select_rows("questions", "lobby_id = '%d'" % [lobby_id], ["question_id", "question", "answer"]).duplicate(true)
			print(str(questions_from_db))
			
			for i in correct_questions:
				for j in questions_from_db:
					if i == j["question"]:
						db.insert_rows("results", [
							{"player_id":player_id, "question_id":j["question_id"], "correct":1}
						])

			for i in wrong_questions:
				for j in questions_from_db:
					if i == j["question"]:
						db.insert_rows("results", [
							{"player_id":player_id, "question_id":j["question_id"], "correct":0}
						])
			var total = correct_questions.size() + wrong_questions.size()
			var score = total - correct_questions.size()
			send_data(["GR", score, total, correct_questions, wrong_questions, questions_from_db], id)

	if code == "EV": #Evaluation Page
		#Do Learning Analytics here
		
		send_data(["EV"],id)
		pass
	
func send_data(data_send, id):
	_server.get_peer(id).put_packet(Utils.encode_data(data_send))

func listen():
	_server.listen(PORT)

func stop():
	_server.stop()
	db.close_db()

func _process(delta):
	_server.poll()

func genCode():
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	var random_code = ""
	for i in 3:
		random_code = random_code + (alphanumeric[rng.randi_range(0,alphanumeric.length() - 1)])
	return random_code
