# Biketunes Flutter build/test container.
# Includes Flutter SDK, Android SDK and Java.
# Source: https://github.com/cirruslabs/docker-images-flutter
FROM ghcr.io/cirruslabs/flutter:stable

# Treat the mounted repo as a trusted git worktree (avoids "dubious ownership" errors).
RUN git config --global --add safe.directory /app

# Disable Flutter analytics/telemetry inside the container.
RUN flutter config --no-analytics

# Default working directory matches the compose volume mount.
WORKDIR /app
