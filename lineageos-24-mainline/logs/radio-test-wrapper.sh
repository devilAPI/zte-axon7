#!/system/bin/sh
# Temporary bind-mount test wrapper: the image on the main phone predates the
# messaging/voice V4 NDK libraries, so resolve them from /data/local/tmp.
export LD_LIBRARY_PATH=/data/local/tmp${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
exec /data/local/tmp/radio-axon7m-test
