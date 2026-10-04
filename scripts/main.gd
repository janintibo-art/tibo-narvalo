extends Node3D

func _ready( -> void:
    var xr_interface := XRServer.find_interface("OpenXR")
    if xr_interface == null:
        push_warning("OpenXR indisponible.")
        return
    if not xr_interface.is_initialized():
        push_warning("OpenXR non initialise.")
        return
    get_viewport().use_xr = true
    print("Tibo Narvalo : OpenXR actif.")
