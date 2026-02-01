# Makefile for Flutter Playground with CR-SQLite

FLUTTER := /home/lmanrique/.local/flutter/flutter/bin/flutter
CRSQLITE_SRC := cr-sqlite/core/dist/crsqlite.so
LINUX_BUNDLE := build/linux/x64/debug/bundle
ANDROID_JNILIBS := android/app/src/main/jniLibs

# Default target
.PHONY: help
help:
	@echo "Available targets:"
	@echo "  make run-linux       - Build and run on Linux with CR-SQLite"
	@echo "  make build-linux     - Build Linux app and copy CR-SQLite library"
	@echo "  make build-crsqlite  - Build CR-SQLite for Linux"
	@echo "  make build-android   - Build CR-SQLite for Android (all architectures)"
	@echo "  make analyze         - Run Flutter analyze"
	@echo "  make test            - Run Flutter tests"
	@echo "  make clean           - Clean build artifacts"

# Build CR-SQLite for Linux
.PHONY: build-crsqlite
build-crsqlite:
	@if [ ! -f $(CRSQLITE_SRC) ]; then \
		echo "Building CR-SQLite for Linux..."; \
		cd cr-sqlite && make; \
		echo "✓ CR-SQLite built successfully"; \
	else \
		echo "✓ CR-SQLite already built at $(CRSQLITE_SRC)"; \
	fi

# Build CR-SQLite for Android (all architectures)
.PHONY: build-android
build-android:
	@echo "Building CR-SQLite for Android ARM64..."
	cd cr-sqlite && \
		export ANDROID_NDK_HOME=/home/lmanrique/Android/Sdk/ndk/28.2.13676358 && \
		export ANDROID_TARGET=aarch64-linux-android && \
		make loadable && \
		mkdir -p ../$(ANDROID_JNILIBS)/arm64-v8a && \
		cp core/dist/crsqlite.so ../$(ANDROID_JNILIBS)/arm64-v8a/libcrsqlite.so
	@echo "✓ Android ARM64 build complete"

	@echo "Building CR-SQLite for Android x86_64..."
	cd cr-sqlite && \
		export ANDROID_NDK_HOME=/home/lmanrique/Android/Sdk/ndk/28.2.13676358 && \
		export ANDROID_TARGET=x86_64-linux-android && \
		make loadable && \
		mkdir -p ../$(ANDROID_JNILIBS)/x86_64 && \
		cp core/dist/crsqlite.so ../$(ANDROID_JNILIBS)/x86_64/libcrsqlite.so
	@echo "✓ Android x86_64 build complete"

	@echo "Building CR-SQLite for Android ARMv7..."
	cd cr-sqlite && \
		export ANDROID_NDK_HOME=/home/lmanrique/Android/Sdk/ndk/28.2.13676358 && \
		export ANDROID_TARGET=armv7-linux-androideabi && \
		make loadable && \
		mkdir -p ../$(ANDROID_JNILIBS)/armeabi-v7a && \
		cp core/dist/crsqlite.so ../$(ANDROID_JNILIBS)/armeabi-v7a/libcrsqlite.so
	@echo "✓ Android ARMv7 build complete"
	@echo "✓ All Android architectures built successfully"

# Build Linux app only (without running)
.PHONY: build-linux
build-linux:
	@echo "Building Linux application..."
	$(FLUTTER) build linux --debug
	@echo "Copying CR-SQLite library to bundle..."
	mkdir -p $(LINUX_BUNDLE)/lib
	cp $(CRSQLITE_SRC) $(LINUX_BUNDLE)/lib/libcrsqlite.so
	@echo "✓ Build complete! Library copied to $(LINUX_BUNDLE)/lib/"

# Build and run on Linux
.PHONY: run-linux
run-linux: build-crsqlite
	@echo "Building and running on Linux..."
	@# Build the app
	$(FLUTTER) build linux --debug
	@# Copy the library
	@mkdir -p $(LINUX_BUNDLE)/lib
	@cp $(CRSQLITE_SRC) $(LINUX_BUNDLE)/lib/libcrsqlite.so
	@echo "✓ CR-SQLite library copied"
	@# Run the app
	@echo "Starting application..."
	cd $(LINUX_BUNDLE) && ./playground

analyze:
	flutter analyze

test:
	flutter test

install:
	flutter pub get

# Clean build artifacts
.PHONY: clean
clean:
	$(FLUTTER) clean
	cd cr-sqlite && make clean
	rm -rf $(ANDROID_JNILIBS)
	@echo "✓ Cleaned build artifacts"

# Hot reload helper (for development with flutter run)
.PHONY: dev-linux
dev-linux:
	@echo "Starting development mode..."
	@echo "Note: CR-SQLite library must be manually copied after hot reload"
	@mkdir -p $(LINUX_BUNDLE)/lib
	@cp $(CRSQLITE_SRC) $(LINUX_BUNDLE)/lib/libcrsqlite.so 2>/dev/null || true
	$(FLUTTER) run -d linux