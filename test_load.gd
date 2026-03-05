extends SceneTree

func _init():
    var scene = ResourceLoader.load("res://scenes/ships/hulls/panokseon_hull.tscn")
    if scene:
        print("Success! ", scene)
        var inst = scene.instantiate()
        print("Instantiated: ", inst)
        print("Child count: ", inst.get_child_count())
    else:
        print("FAILED to load scene.")
    quit()
