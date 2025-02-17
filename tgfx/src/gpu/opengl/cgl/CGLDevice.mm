/////////////////////////////////////////////////////////////////////////////////////////////////
//
//  Tencent is pleased to support the open source community by making libpag available.
//
//  Copyright (C) 2021 THL A29 Limited, a Tencent company. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file
//  except in compliance with the License. You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  unless required by applicable law or agreed to in writing, software distributed under the
//  license is distributed on an "as is" basis, without warranties or conditions of any kind,
//  either express or implied. see the license for the specific language governing permissions
//  and limitations under the license.
//
/////////////////////////////////////////////////////////////////////////////////////////////////

#include "CGLDevice.h"
#include "CGLProcGetter.h"
#include "gpu/opengl/GLContext.h"

namespace pag {
std::shared_ptr<CGLDevice> CGLDevice::Current() {
  return CGLDevice::Wrap(CGLGetCurrentContext(), true);
}

std::shared_ptr<CGLDevice> CGLDevice::MakeAdopted(CGLContextObj cglContext) {
  return CGLDevice::Wrap(cglContext, true);
}

std::shared_ptr<CGLDevice> CGLDevice::Make(CGLContextObj sharedContext) {
  CGLPixelFormatObj format = nullptr;
  if (sharedContext == nullptr) {
    const CGLPixelFormatAttribute attributes[] = {
        kCGLPFAStencilSize,        (CGLPixelFormatAttribute)8,
        kCGLPFAAccelerated,        kCGLPFADoubleBuffer,
        kCGLPFAOpenGLProfile,      (CGLPixelFormatAttribute)kCGLOGLPVersion_3_2_Core,
        (CGLPixelFormatAttribute)0};
    GLint npix = 0;
    CGLChoosePixelFormat(attributes, &format, &npix);
  } else {
    format = CGLGetPixelFormat(sharedContext);
  }
  CGLContextObj cglContext = nullptr;
  CGLCreateContext(format, sharedContext, &cglContext);
  if (sharedContext == nullptr) {
    CGLDestroyPixelFormat(format);
  }
  if (cglContext == nullptr) {
    return nullptr;
  }
  GLint opacity = 0;
  CGLSetParameter(cglContext, kCGLCPSurfaceOpacity, &opacity);
  auto device = CGLDevice::Wrap(cglContext, false);
  CGLReleaseContext(cglContext);
  return device;
}

std::shared_ptr<CGLDevice> CGLDevice::Wrap(CGLContextObj cglContext, bool isAdopted) {
  if (cglContext == nil) {
    return nullptr;
  }
  auto glDevice = GLDevice::Get(cglContext);
  if (glDevice) {
    return std::static_pointer_cast<CGLDevice>(glDevice);
  }
  auto oldCGLContext = CGLGetCurrentContext();
  if (oldCGLContext != cglContext) {
    CGLSetCurrentContext(cglContext);
    if (CGLGetCurrentContext() != cglContext) {
      return nullptr;
    }
  }

  static CGLProcGetter glProcGetter = {};
  static GLInterfaceCache glInterfaceCache = {};
  auto glInterface = GLInterface::GetNative(&glProcGetter, &glInterfaceCache);
  std::shared_ptr<CGLDevice> device = nullptr;
  if (glInterface != nullptr) {
    auto context = std::make_unique<GLContext>(glInterface);
    device = std::shared_ptr<CGLDevice>(new CGLDevice(std::move(context), cglContext));
    device->isAdopted = isAdopted;
    device->weakThis = device;
  }

  if (oldCGLContext != cglContext) {
    CGLSetCurrentContext(oldCGLContext);
  }
  return device;
}

CGLDevice::CGLDevice(std::unique_ptr<Context> context, CGLContextObj cglContext)
    : GLDevice(std::move(context), cglContext) {
  glContext = [[NSOpenGLContext alloc] initWithCGLContextObj:cglContext];
}

CGLDevice::~CGLDevice() {
  releaseAll();
  if (textureCache != nil) {
    CFRelease(textureCache);
    textureCache = nil;
  }
  [glContext release];
}

bool CGLDevice::sharableWith(void* nativeContext) const {
  if (nativeContext == nullptr) {
    return false;
  }
  auto shareContext = static_cast<CGLContextObj>(nativeContext);
  return CGLGetShareGroup(shareContext) == CGLGetShareGroup(glContext.CGLContextObj);
}

CGLContextObj CGLDevice::cglContext() const {
  return glContext.CGLContextObj;
}

CVOpenGLTextureCacheRef CGLDevice::getTextureCache() {
  if (!textureCache) {
    auto pixelFormatObj = CGLGetPixelFormat(glContext.CGLContextObj);
    CVOpenGLTextureCacheCreate(kCFAllocatorDefault, NULL, glContext.CGLContextObj, pixelFormatObj,
                               NULL, &textureCache);
  }
  return textureCache;
}

void CGLDevice::releaseTexture(CVOpenGLTextureRef texture) {
  if (texture == nil || textureCache == nil) {
    return;
  }
  CFRelease(texture);
  CVOpenGLTextureCacheFlush(textureCache, 0);
}

bool CGLDevice::onMakeCurrent() {
  oldContext = CGLGetCurrentContext();
  CGLRetainContext(oldContext);
  [glContext makeCurrentContext];
  return [NSOpenGLContext currentContext] == glContext;
}

void CGLDevice::onClearCurrent() {
  CGLSetCurrentContext(oldContext);
  CGLReleaseContext(oldContext);
}
}  // namespace pag