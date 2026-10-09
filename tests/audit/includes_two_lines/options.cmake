set(LAYERS "settings;inputs,gui")
# One module may use the library in its interface, another in its source files only.
set(CONFINED_INCLUDES "nlohmann/|settings|;nlohmann/|inputs|sources")
