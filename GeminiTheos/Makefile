# =============================================================================
# GeminiTheos — Makefile
# Нативный Gemini-клиент на чистом Objective-C (MRC, iOS 3.0+)
# =============================================================================
#
# Сборка для arm64 (iOS 15.8, тест):  make package ARCHS=arm64
# Сборка для armv6 (iOS 3.0, реальный): нужен iPhoneOS3.0.sdk в $THEOS/sdks
#   и старый clang: TARGET=iphone:clang:3.1.3:3.0 ARCHS=armv6 make package
#
# Установка .deb на устройство:
#   make package ARCHS=arm64 && scp .theos/obj/com.github.geminiclient_1.0_iphoneos-arm64.deb mobile@127.0.0.1:/tmp/
#   ssh mobile@127.0.0.1 "sudo dpkg -i /tmp/com.github.geminiclient_1.0_iphoneos-arm64.deb"
# =============================================================================

# --- Тулчейн ---
# Для arm64 (современный iOS): TARGET = iphone:clang:latest:15.0
# Для armv6 (iOS 3.0):         TARGET = iphone:clang:3.1.3:3.0
TARGET := iphone:clang:latest:9.0

# Архитектуры. Переопределяй из CLI: make ARCHS=armv6
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := GeminiClient

# --- Исходники ---
GeminiClient_FILES := \
    src/main.m \
    src/AppDelegate.m \
    src/GeminiNetworkClient.m \
    src/cJSON/cJSON.c

# --- Фреймворки и библиотеки ---
GeminiClient_FRAMEWORKS := UIKit Foundation CoreGraphics SystemConfiguration CFNetwork Security
GeminiClient_LIBRARIES  :=

# --- Флаги компилятора ---
# -fno-objc-arc:   Выключить ARC — строгий MRC по всему проекту.
# -std=gnu99:      Совместимость с C99 (cJSON, сокеты).
# -Wno-deprecated: Убрать ворнинги о deprecated API (NSURLConnection, UILineBreakMode).
# -isystem:        Путь к cJSON
GeminiClient_CFLAGS := \
    -fno-objc-arc \
    -std=gnu99 \
    -Wno-deprecated-declarations \
    -Wno-deprecated \
    -Isrc/cJSON \
    -Isrc

GeminiClient_OBJCFLAGS := \
    -fno-objc-arc \
    -Wno-deprecated-declarations \
    -Wno-deprecated \
    -Isrc/cJSON \
    -Isrc

# --- Ресурсы и Info.plist ---
GeminiClient_RESOURCE_DIRS := Resources

include $(THEOS_MAKE_PATH)/application.mk

# --- Пост-сборка: паковка .ipa (для TrollStore / sideload) ---
after-stage::
	@echo "--- Packaging .ipa for sideload ---"
	@mkdir -p $(THEOS_STAGING_DIR)/Payload
	@cp -r $(THEOS_STAGING_DIR)/Applications/GeminiClient.app \
	        $(THEOS_STAGING_DIR)/Payload/
	@cd $(THEOS_STAGING_DIR) && zip -qr ../GeminiClient.ipa Payload/
	@echo "IPA ready: $(THEOS_BUILD_DIR)/GeminiClient.ipa"
