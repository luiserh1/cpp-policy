set(LAYERS "backend;cli;gui")
# gui stopped including zlib.h and is still named.
set(CONFINED_INCLUDES "httplib.h|backend|;zlib.h|backend,cli,gui|sources")
