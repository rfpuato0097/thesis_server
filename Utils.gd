extends Node

func encode_data(data):
	return var2bytes(data)


func decode_data(data):
	return bytes2var(data)


func _log(msg):
	print(msg)
