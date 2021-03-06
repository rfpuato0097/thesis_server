extends Node

var PORT = 11100

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
	db.path = "user://game_db"
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
		"player_game_score": {"data_type":"real"},
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
		"correct": {"data_type":"int", "not_null":true},
		"player_answer": {"data_type":"text", "not_null":true}
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
	#print(reason == "Bye bye!")
	Utils._log("Client %s close code: %d, reason: %s" % [id ,code, reason])
	
func _client_receive(id):
	var packet = _server.get_peer(id).get_packet()
	var is_string = _server.get_peer(id).was_string_packet()
	#PARSE DATA RECEIVED HERE
	var received = Utils.decode_data(packet)
	#print(received)
	
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
		#print(questions_received)
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
		#print ("lobby_id: %d lobby_name: %s" % [lobby_id, lobby_name])
		
		#check if lobby exists
		db.query_result = []
		db.query("SELECT * FROM lobbies WHERE lobby_id = '%d' AND lobby_name = '%s'" % [lobby_id, lobby_name])
		var lobby_exists = false
		if db.query_result != []:
			if db.query_result[0]["lobby_id"] == lobby_id and db.query_result[0]["lobby_name"] == lobby_name:
				lobby_exists = true
		#print(db.query_result)
		if lobby_exists:
			#Insert player into database.
			#print("Add player")
			db.insert_rows("players", [
				{"player_name":player_name, "player_client_id":id, "lobby_id":lobby_id}
			])
			#send questions
			var questions_selected = db.select_rows("questions", "lobby_id = '%d'" % lobby_id, ["question","answer"]).duplicate(true)
			var words_selected = db.select_rows("additional_words", "lobby_id = '%d'" % lobby_id, ["word"]).duplicate(true)
			send_data(["JG", questions_selected, words_selected, player_name],id)
			
		else:
			#Send Error to Client that Lobby does not exist.
			#print("No such lobby")
			data = ["ER", "Lobby does not exist."]
			send_data(data,id)
			return
		
	if code == "GR": #Game Results
		#print(received) # 
		var player_name = received[1]
		var correct_questions = received[2]
		var wrong_questions = received[3]
		var player_game_score = received[4]
		
		#check player_client_id and player name.
		var is_player_in_records = db.select_rows("players", "player_name = '%s' AND player_client_id = '%d'" % [player_name, id], ["player_id", "lobby_id"]).duplicate(true)
		if is_player_in_records != []:
			var lobby_id = is_player_in_records[0]["lobby_id"]
			var player_id = is_player_in_records[0]["player_id"]
			var questions_from_db = db.select_rows("questions", "lobby_id = '%d'" % [lobby_id], ["question_id", "question", "answer"]).duplicate(true)
			#print(str(questions_from_db))
			
			for i in correct_questions:
				for j in questions_from_db:
					if i["question"] == j["question"]:
						db.insert_rows("results", [
							{"player_id":player_id, "question_id":j["question_id"], "correct":1, "player_answer":i["player_answer"]}
						])

			for i in wrong_questions:
				for j in questions_from_db:
					if i["question"] == j["question"]:
						db.insert_rows("results", [
							{"player_id":player_id, "question_id":j["question_id"], "correct":0, "player_answer": i["player_answer"]}
						])
			
			db.query("UPDATE players SET player_game_score = '%f' WHERE player_id = '%d'" % [player_game_score, player_id])
			var total = correct_questions.size() + wrong_questions.size()
			var score = correct_questions.size()
			send_data(["GR", score, total, correct_questions, wrong_questions, questions_from_db, player_game_score], id)

	if code == "EV": #Evaluation Page
		#Do Learning Analytics here
		var code_received = received[1]
		var analytics = []
		
		#Clean players db
		db.query("SELECT * FROM players WHERE player_id NOT IN (SELECT player_id FROM results)")
		var to_delete = db.query_result.duplicate(true)
		for i in to_delete:
			db.delete_rows("players","player_id = '%d'" % [i["player_id"]])

		#select lobby_id by using lobby_name
		var regex = RegEx.new()
		regex.compile("[0-9]*")
		var result = regex.search(code_received).get_string()
		var lobby_id = int(result)
		var lobby_name = code_received.replace(result, "")
		#print ("lobby_id: %d lobby_name: %s" % [lobby_id, lobby_name])
		
		#check if lobby exists
		db.query_result = []
		db.query("SELECT * FROM lobbies WHERE lobby_id = '%d' AND result_page_name = '%s'" % [lobby_id, lobby_name])
		var lobby_exists = false
		if db.query_result != []:
			if db.query_result[0]["lobby_id"] == lobby_id and db.query_result[0]["result_page_name"] == lobby_name:
				lobby_exists = true
		#print(db.query_result)
		if lobby_exists:
			#No. of Players
			db.query("SELECT COUNT(player_id) AS 'player_count' FROM players WHERE lobby_id = '%d'" % [lobby_id] )
			#print("No of Players")
			#print(db.query_result)
			#print("")
			analytics.append(db.query_result.duplicate(true))
			
			#Ave. Score
			db.query("SELECT AVG(results.correct) AS 'average' FROM players INNER JOIN results ON players.player_id = results.player_id WHERE players.lobby_id = '%d'" % [lobby_id] )
			#print("AVE SCORE")
			#print(db.query_result)
			#print("")
			analytics.append(db.query_result.duplicate(true))
			
			#Most Difficult Questions
			db.query("SELECT results.question_id, questions.question, SUM(results.correct) AS 'no_of_correct' FROM players INNER JOIN results ON players.player_id = results.player_id INNER JOIN questions ON results.question_id = questions.question_id WHERE players.lobby_id = '%d' GROUP BY results.question_id ORDER BY SUM(results.correct) ASC" % [lobby_id])
			#print("DIFF QUESTIONS")
			#print(db.query_result)
			#print("")
			analytics.append(db.query_result.duplicate(true))
			
			#Students that need further assistance
			db.query("SELECT players.player_id, players.player_name, SUM(results.correct) AS correct_ans FROM players INNER JOIN results ON players.player_id = results.player_id WHERE lobby_id = '%d' GROUP BY results.player_id ORDER BY SUM(results.correct) ASC" % [lobby_id])
			#print("NEED HELP")
			#print(db.query_result)
			#print("")
			analytics.append(db.query_result.duplicate(true))
			
			#Easiest Questions
			db.query("SELECT results.question_id, questions.question, SUM(results.correct) AS 'no_of_correct' FROM players INNER JOIN results ON players.player_id = results.player_id INNER JOIN questions ON results.question_id = questions.question_id WHERE players.lobby_id = '%d' GROUP BY results.question_id ORDER BY SUM(results.correct) DESC" % [lobby_id])
			#print("EASY QUESTIONS")
			#print(db.query_result)
			#print("")
			analytics.append(db.query_result.duplicate(true))
			
			#Top Students
			db.query("SELECT players.player_id, players.player_name, SUM(results.correct) AS correct_ans FROM players INNER JOIN results ON players.player_id = results.player_id WHERE lobby_id = '%d' GROUP BY results.player_id ORDER BY SUM(results.correct) DESC" % [lobby_id])
			#print("TOP STUDENTS")
			#print(db.query_result)
			#print("")
			analytics.append(db.query_result.duplicate(true))
			
			#Get player_ids
			db.query("SELECT * FROM players WHERE lobby_id = '%d'" % [lobby_id])
			#print("PLAYER IDS")
			#print(db.query_result)
			#print("")
			var player_ids = db.query_result.duplicate(true)
			
			#Get question_ids
			db.query("SELECT * FROM questions WHERE lobby_id = '%d'" % [lobby_id])
			#print("QUESTION IDS")
			#print(db.query_result)
			#print("")
			var question_ids = db.query_result.duplicate(true)

			
			#Get Person
			#print("PLAYER")
			var player_result = []
			for i in player_ids:
				db.query("SELECT players.player_id, players.player_name, questions.question, questions.answer, results.correct, results.player_answer, players.player_game_score FROM players INNER JOIN results ON players.player_id = results.player_id INNER JOIN questions ON questions.question_id = results.question_id WHERE players.player_id = '%d'" % [i["player_id"]])
				#print(db.query_result)
				#print("")
				player_result.append(db.query_result.duplicate(true))
			analytics.append(player_result.duplicate(true))
			
			var question_result = []
			#Get Question
			for i in question_ids:
				db.query("SELECT questions.question, players.player_name, results.correct, questions.answer, results.player_answer FROM players INNER JOIN results ON players.player_id = results.player_id INNER JOIN questions ON results.question_id = questions.question_id WHERE results.question_id = '%d'" % [i["question_id"]])
				#db.query("SELECT * FROM (SELECT questions.question, players.player_name, results.correct, questions.answer, results.player_answer FROM players INNER JOIN results ON players.player_id = results.player_id INNER JOIN questions ON results.question_id = questions.question_id WHERE results.question_id = '%d') AS a CROSS JOIN (SELECT player_answer, COUNT(player_answer) AS freq FROM results WHERE question_id = '%d' GROUP BY player_answer) as b WHERE a.player_answer = b.player_answer" % [i["question_id"], i["question_id"]])
				#print(db.query_result)
				#print("")
				question_result.append(db.query_result.duplicate(true))
			analytics.append(question_result.duplicate(true))
			
			db.query("SELECT * FROM lobbies WHERE lobby_id = '%d'" % [lobby_id])
			#print(db.query_result)
			var lobby_page = str(db.query_result[0]["lobby_id"]) + db.query_result[0]["lobby_name"]
			var evaluation_page = str(db.query_result[0]["lobby_id"]) + db.query_result[0]["result_page_name"]

			send_data(["EV", analytics, lobby_page, evaluation_page],id)
		else:
			send_data(["ER", "Lobby does not exist."], id)

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
