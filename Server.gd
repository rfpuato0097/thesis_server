extends Node

var PORT = 9080

var _server = WebSocketServer.new()
var _write_mode = WebSocketPeer.WRITE_MODE_BINARY
var _clients = {}
var lobbies = []

func _init():
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
	var code = received[0]
	if code == "CG": #Create Game
		pass
		
	if code == "GR": #Game Results
		pass
		
	if code == "JG": #Join Game
		pass
		
	if code == "EV": #Evaluation
		pass
	
	#Utils._log("Data from %s BINARY: %s: %s" % [id, not is_string, Utils.decode_data(packet)])
	
func send_data(data):
	for id in _clients:
		_server.get_peer(id).put_packet(Utils.encode_data(data))

func listen():
	_server.listen(PORT)

func stop():
	_server.stop()

func _process(delta):
	_server.poll()
