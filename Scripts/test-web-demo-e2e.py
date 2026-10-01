#!/usr/bin/env python3
import threading
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[1]


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def set_storage(page, value):
    page.locator("#storage").evaluate(
        "(el, value) => { el.value = value; el.dispatchEvent(new Event('input', { bubbles: true })); }",
        str(value),
    )


def open_demo(browser, url, **context_options):
    context = browser.new_context(**context_options)
    context.route("**/*.mp4", lambda route: route.abort())
    page = context.new_page()
    console_errors = []
    page_errors = []

    def record_console_error(message):
        location = message.location
        expected_media_abort = (
            str(location.get("url", "")).endswith(".mp4")
            and "ERR_FAILED" in message.text
        )
        if message.type == "error" and not expected_media_abort:
            console_errors.append(message.text)

    page.on("console", record_console_error)
    page.on("pageerror", lambda error: page_errors.append(str(error)))
    page.goto(url)
    page.wait_for_load_state("networkidle")
    return context, page, console_errors, page_errors


def run_e2e(url):
    with sync_playwright() as playwright:
        print("E2E: desktop", flush=True)
        browser = playwright.chromium.launch(channel="chrome", headless=True)
        context, page, console_errors, page_errors = open_demo(
            browser,
            url,
            viewport={"width": 1440, "height": 1000},
        )

        assert page.locator("[data-storage-console]").is_visible()
        page_text = page.locator("body").inner_text()
        assert "Codex" in page_text
        assert "Claude Code" in page_text
        assert "CCleaner" in page_text
        assert "agentes de programação" in page_text.lower()
        assert "um clique" in page_text.lower()
        assert "backoff" in page_text.lower()
        assert "discos externos não selecionados" in page_text.lower()
        assert page.locator("[data-percent]").inner_text() == "72%"
        assert page.locator("[data-state]").inner_text() == "NORMAL"
        set_storage(page, 74.9)
        assert page.locator("[data-state]").inner_text() == "NORMAL"
        set_storage(page, 75)
        assert page.locator("[data-state]").inner_text() == "ALERTA 75%"

        auto_clean = page.locator("[data-auto-clean]")
        auto_clean.focus()
        page.keyboard.press("Enter")
        assert auto_clean.get_attribute("aria-pressed") == "false"
        set_storage(page, 81)
        page.wait_for_timeout(1200)
        assert float(page.locator("#storage").input_value()) == 81
        assert page.locator("[data-state]").inner_text() == "LIMPEZA 78%"

        page.keyboard.press("Enter")
        expect(page.locator("[data-state]")).to_have_text("ALIVIADO", timeout=10_000)
        assert float(page.locator("#storage").input_value()) == 72
        assert page.locator(".cleanup-timeline li.is-done").count() == 4
        assert page.locator('[data-download-cta][href="#download"]').count() == 2
        assert page.locator('a[href*="releases/latest/download"]').count() == 0

        download_url = "https://github.com/luisroquette-labs/ai-leave-my-mac-alone/releases/latest/download/AI-Leave-My-Mac-Alone.zip"
        page.route(
            "https://cfgauss.com.br/api/lead/clean-my-mac",
            lambda route: route.fulfill(status=200, content_type="application/json", body=f'{{"success":true,"downloadUrl":"{download_url}"}}'),
        )
        page.locator('[data-lead-form] input[name="name"]').fill("Ana Silva")
        page.locator('[data-lead-form] input[name="whatsapp"]').fill("11999998888")
        page.locator('[data-lead-form] input[name="email"]').fill("ana@example.com")
        page.locator('[data-lead-form] button[type="submit"]').click()
        expect(page.locator("[data-download-ready]")).to_be_visible()
        expect(page.locator("[data-download-link]")).to_have_attribute("href", download_url)
        assert not console_errors, console_errors
        assert not page_errors, page_errors
        context.close()

        print("E2E: lead failure", flush=True)
        failed, page, _, _ = open_demo(browser, url, viewport={"width": 1440, "height": 1000})
        page.route(
            "https://cfgauss.com.br/api/lead/clean-my-mac",
            lambda route: route.fulfill(status=503, content_type="application/json", body='{"error":"Trello unavailable"}'),
        )
        page.locator('[data-lead-form] input[name="name"]').fill("Ana Silva")
        page.locator('[data-lead-form] input[name="whatsapp"]').fill("11999998888")
        page.locator('[data-lead-form] input[name="email"]').fill("ana@example.com")
        page.locator('[data-lead-form] button[type="submit"]').click()
        expect(page.locator("[data-form-status]")).to_have_text("Trello unavailable")
        expect(page.locator("[data-download-ready]")).to_be_hidden()
        failed.close()

        print("E2E: lead timeout", flush=True)
        timed_out, page, _, _ = open_demo(browser, url, viewport={"width": 1440, "height": 1000})
        page.evaluate("""(() => {
            window.fetch = (_url, options) => new Promise((_resolve, reject) => {
              options.signal.addEventListener('abort', () => {
                reject(new DOMException('Aborted', 'AbortError'));
              }, { once: true });
            });
            return null;
        })()""")
        page.locator('[data-lead-form] input[name="name"]').fill("Ana Silva")
        page.locator('[data-lead-form] input[name="whatsapp"]').fill("11999998888")
        page.locator('[data-lead-form] input[name="email"]').fill("ana@example.com")
        page.locator('[data-lead-form] button[type="submit"]').click()
        expect(page.locator("[data-form-status]")).to_have_text(
            "O servidor demorou para responder. Tente novamente.",
            timeout=15_000,
        )
        expect(page.locator('[data-lead-form] button[type="submit"]')).to_be_enabled()
        timed_out.close()

        print("E2E: reduced motion", flush=True)
        reduced, page, _, _ = open_demo(
            browser,
            url,
            viewport={"width": 1440, "height": 1000},
            reduced_motion="reduce",
        )
        set_storage(page, 81)
        expect(page.locator("[data-state]")).to_have_text("ALIVIADO", timeout=3_000)
        assert float(page.locator("#storage").input_value()) == 72
        reduced.close()

        print("E2E: mobile", flush=True)
        mobile, page, mobile_console_errors, mobile_page_errors = open_demo(
            browser,
            url,
            viewport={"width": 390, "height": 844},
            device_scale_factor=1,
        )
        dimensions = page.evaluate("({ client: document.documentElement.clientWidth, scroll: document.documentElement.scrollWidth })")
        assert dimensions["scroll"] == dimensions["client"], dimensions
        box = page.locator("[data-storage-console]").bounding_box()
        assert box and box["x"] >= 0 and box["x"] + box["width"] <= 390.5, box
        assert not mobile_console_errors, mobile_console_errors
        assert not mobile_page_errors, mobile_page_errors
        mobile.close()
        browser.close()


def main():
    handler = partial(QuietHandler, directory=str(ROOT / "docs"))
    server = ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        run_e2e(f"http://127.0.0.1:{server.server_port}/#proof")
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=3)
    print("Storage Control E2E: OK")


if __name__ == "__main__":
    main()
