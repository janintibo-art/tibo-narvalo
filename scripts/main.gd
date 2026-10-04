extends Node3D

var xr_interface: OpenXRInterface

func _ready() -> void:
    xr_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
    if xr_interface == null or not xr_interface.is_initialized():
        push_error("Tibo Narvalo : OpenXR indisponible ou non initialise.")
        return

    var viewport := get_viewport()
    viewport.use_xr = true
    viewport.transparent_bg = true
    DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

    xr_interface.session_begun.connect(_on_openxr_session_begun)
    call_deferred("_enable_passthrough")


func _on_openxr_session_begun() -> void:
    _enable_passthrough()


func _enable_passthrough() -> void:
    if xr_interface == null:
        return

    var modes := xr_interface.get_supported_environment_blend_modes()

    if XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND in modes:
        xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ALPHA_BLEND
        print("Tibo Narvalo : passthrough alpha actif.")
    elif XRInterface.XR_ENV_BLEND_MODE_ADDITIVE in modes:
        xr_interface.environment_blend_mode = XRInterface.XR_ENV_BLEND_MODE_ADDITIVE
        print("Tibo Narvalo : passthrough additif actif.")
    else:
        push_warning("Tibo Narvalo : passthrough non supporte par ce runtime.")
