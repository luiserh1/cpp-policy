# Copies the AddressSanitizer runtime next to a program on Windows (cpp_policy_apply() runs it
# after each link).
#
#   cmake -DSOURCE=<dll> -DDESTINATION=<folder> -P copy_runtime.cmake
#
# Programs in one folder link in parallel, and each copies the same file there. Without a lock,
# one copy could read the file while another was writing it, find it different and fail to
# overwrite it ("Permission denied"); the lock makes them take turns.

cmake_minimum_required(VERSION 3.29)
cmake_path(GET SOURCE FILENAME name)
file(LOCK "${DESTINATION}/.cpp_policy_runtime.lock" GUARD PROCESS TIMEOUT 300)
file(COPY_FILE "${SOURCE}" "${DESTINATION}/${name}" ONLY_IF_DIFFERENT)
