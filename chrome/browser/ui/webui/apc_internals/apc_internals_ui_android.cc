// Copyright 2022 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#include "chrome/browser/ui/webui/apc_internals/apc_internals_ui.h"

#include "content/public/browser/web_ui.h"

// APC Internals is a desktop diagnostics page. Android still references its
// controller factory through shared Chrome WebUI code, so provide the
// controller lifecycle without pulling desktop-only resources into the APK.
APCInternalsUI::APCInternalsUI(content::WebUI* web_ui)
    : content::WebUIController(web_ui) {}

APCInternalsUI::~APCInternalsUI() = default;
