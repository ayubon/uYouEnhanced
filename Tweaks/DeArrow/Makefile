ifeq ($(ROOTLESS),1)
THEOS_PACKAGE_SCHEME=rootless
endif

export ARCHS = arm64
TARGET := iphone:clang:17.5:15.0
INSTALL_TARGET_PROCESSES = YouTube

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DeArrow

DeArrow_FILES = Tweak.xm DeArrowClient.m DeArrowPreferences.m
DeArrow_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
DeArrow_FRAMEWORKS = UIKit Foundation Security
DeArrow_PRIVATE_FRAMEWORKS = 

include $(THEOS_MAKE_PATH)/tweak.mk

