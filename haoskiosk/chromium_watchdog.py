#!/usr/bin/env python3
"""Keep Chromium signed in through Home Assistant's own login form."""

from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from urllib.parse import urlsplit

from browser_ctl import ChromiumController, ChromiumPageSession


logger = logging.getLogger(__name__)
POLL_INTERVAL = 2
RELOAD_INTERVAL = 15
SUBMIT_INTERVAL = 60

CHECK_PAGE = """
(expectedUrl, credentials) => {
  if (location.href !== expectedUrl) return;
  if (performance.getEntriesByType("navigation")[0]?.responseStatus >= 500) {
    return "unavailable";
  }
  if (location.pathname !== "/auth/authorize") return;

  const query = new URLSearchParams(location.search);
  if (query.get("response_type") !== "code" ||
      query.get("client_id") !== location.origin + "/" ||
      new URL(query.get("redirect_uri") || "about:blank").origin !== location.origin) {
    return;
  }

  const authorize = document.querySelector("ha-authorize");
  const form = authorize?.querySelector("ha-auth-flow form");
  if (authorize?.querySelector('ha-alert[alert-type="error"]')) {
    // A failed request can leave HA on a login page that cannot recover by itself.
    // Leave authentication errors (including a banned client) visible for manual use.
    const request = performance.getEntriesByType("resource").findLast(entry =>
      entry.name === location.origin + "/auth/providers" ||
      entry.name.startsWith(location.origin + "/auth/login_flow")
    );
    if (!request || request.responseStatus === 0 || request.responseStatus >= 500) {
      return "unavailable";
    }
  }
  if (!credentials || !form) return;
  if (document.documentElement.hasAttribute("data-haos-kiosk-login-attempted")) {
    return "submitted";
  }

  const username = form.querySelector('input[autocomplete="username"]');
  const password = form.querySelector('input[autocomplete="current-password"][type="password"]');
  const submit = form.querySelector(".action ha-button");
  if (!username || !password || !submit || username.disabled || password.disabled ||
      submit.disabled || submit.loading) return;

  username.value = credentials[0];
  password.value = credentials[1];
  username.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
  password.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
  const remember = form.querySelector("ha-checkbox");
  if (remember) {
    remember.checked = true;
    remember.dispatchEvent(new Event("change", { bubbles: true }));
  }
  document.documentElement.setAttribute("data-haos-kiosk-login-attempted", "");
  submit.click();
  return "submitted";
}
"""


def origin(url: str) -> tuple[str, str | None, int | None]:
    """Compare origins with explicit and implicit default ports treated alike."""
    parts = urlsplit(url)
    default_port = {"http": 80, "https": 443}.get(parts.scheme)
    return parts.scheme, parts.hostname, parts.port or default_port


async def main() -> None:
    username = os.getenv("HA_USERNAME")
    password = os.getenv("HA_PASSWORD")
    if not username or not password:
        return

    ha_origin = origin(os.getenv("HA_URL") or "http://localhost:8123")
    login_delay = float(os.getenv("LOGIN_DELAY") or "1")
    controller = ChromiumController()
    current_document = ""
    document_seen_at = 0.0
    submitted_document = ""
    next_submit_at = 0.0
    next_reload_at = 0.0

    async def check_page(page: ChromiumPageSession, target: dict) -> None:
        nonlocal current_document, document_seen_at, submitted_document
        nonlocal next_submit_at, next_reload_at

        target_url = target.get("url", "")
        if not target_url.startswith("chrome-error:") and origin(target_url) != ha_origin:
            return

        frame = (await page.call("Page.getFrameTree"))["frameTree"]["frame"]
        unreachable_url = frame.get("unreachableUrl")
        url = unreachable_url or (frame["url"] + frame.get("urlFragment", ""))
        if origin(url) != ha_origin:
            return

        loader_id = frame["loaderId"]
        now = time.monotonic()
        if loader_id != current_document:
            current_document = loader_id
            document_seen_at = now

        if unreachable_url:
            status = "unavailable"
        else:
            credentials = None
            if (urlsplit(url).path == "/auth/authorize"
                    and loader_id != submitted_document
                    and now >= next_submit_at
                    and now - document_seen_at >= login_delay):
                credentials = (username, password)

            # The script checks the current URL again in case navigation raced CDP.
            # Never report evaluation exceptions or echo the command payload.
            result = await page.call("Runtime.evaluate", {
                "expression": f"({CHECK_PAGE})({json.dumps(url)}, {json.dumps(credentials)})",
                "returnByValue": True,
                "silent": True,
            })
            status = result.get("result", {}).get("value")

        if status == "submitted":
            submitted_document = loader_id
            next_submit_at = now + SUBMIT_INTERVAL
            logger.info("Submitted the Home Assistant login form")
        elif status == "unavailable" and now >= next_reload_at:
            next_reload_at = now + RELOAD_INTERVAL
            await page.call("Page.reload", {"loaderId": loader_id, "ignoreCache": True})

    logger.info("Chromium automatic login enabled")
    while True:
        try:
            await asyncio.wait_for(controller.with_page(check_page), timeout=8)
        except Exception:
            # Chromium may still be starting, navigating, or suspending its renderer.
            # CDP errors can contain request data, so only report a fixed message.
            logger.debug("Chromium page temporarily unavailable")
        await asyncio.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="[Chromium auto-login] %(message)s")
    asyncio.run(main())
