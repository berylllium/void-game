@tool
extends ConcavePolygonShape3D

class_name ConcaveArrayMeshShape3D

@export var array_mesh: ArrayMesh:
	set(value):
		array_mesh = value
		update_polygon()


func update_polygon() -> void:
	set_faces(array_mesh.get_faces())
