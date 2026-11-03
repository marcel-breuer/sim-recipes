import assert from 'node:assert/strict';
import test from 'node:test';
import { chromium } from 'playwright';

const baseUrl = process.env.PLAYWRIGHT_BASE_URL ?? 'http://127.0.0.1:8765';

test('consent choices gate Google requests and analytics events in the browser', async () => {
    const browser = await chromium.launch({ headless: true });

    try {
        const context = await browser.newContext({ locale: 'de-DE' });
        const page = await context.newPage();
        const googleRequests = [];

        page.on('request', (request) => {
            if (/google-analytics\.com|googletagmanager\.com/.test(request.url())) {
                googleRequests.push(request.url());
            }
        });
        await page.route('https://www.googletagmanager.com/**', (route) => route.fulfill({
            status: 200,
            contentType: 'application/javascript',
            body: '',
        }));

        await page.goto(`${baseUrl}/?token=private-value`);
        assert.equal(await page.title(), 'SimRecipes — Recipes for the way you see.');
        assert.equal(await page.locator('html').getAttribute('lang'), 'de');
        assert.equal(await page.getByRole('button', { name: 'Alle akzeptieren' }).isVisible(), true);
        assert.equal(await page.getByRole('button', { name: 'Ablehnen' }).isVisible(), true);
        assert.deepEqual(googleRequests, []);
        await page.setViewportSize({ width: 390, height: 844 });
        const rejectBounds = await page.getByRole('button', { name: 'Ablehnen' }).boundingBox();
        assert.ok(rejectBounds.y >= 0 && rejectBounds.y + rejectBounds.height <= 844);
        await page.setViewportSize({ width: 1280, height: 800 });
        await page.getByRole('button', { name: 'Einstellungen', exact: true }).click();
        assert.equal(await page.locator('[data-consent-statistics]').isVisible(), true);
        assert.equal(await page.locator('[data-consent-statistics]').isChecked(), false);
        await page.getByRole('button', { name: 'Einstellungen', exact: true }).click();

        await page.getByRole('button', { name: 'Ablehnen' }).click();
        assert.equal(await page.getByRole('dialog').isVisible(), false);
        assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('simrecipes.analytics-consent')).statistics), false);
        await page.reload();
        assert.equal(await page.getByRole('dialog').isVisible(), false);
        assert.deepEqual(googleRequests, []);

        await page.getByRole('button', { name: 'Cookie-Einstellungen' }).click();
        const statistics = page.locator('[data-consent-statistics]');
        await statistics.check();

        const gtmRequest = page.waitForRequest((request) => request.url().includes('/gtm.js?id=GTM-ABC123'));
        await page.getByRole('button', { name: 'Auswahl speichern' }).click();
        await gtmRequest;
        assert.equal(await page.getByRole('dialog').isVisible(), false);

        const analyticsState = await page.evaluate(() => ({
            pageViews: window.dataLayer.filter((entry) => entry?.event === 'page_view'),
            consentUpdates: window.dataLayer.filter((entry) => entry?.[0] === 'consent' && entry?.[1] === 'update'),
        }));
        assert.equal(analyticsState.pageViews.length, 1);
        assert.equal(analyticsState.pageViews[0].page_location, new URL(baseUrl).origin + '/');
        assert.ok(!JSON.stringify(analyticsState.pageViews).includes('token=private-value'));
        assert.equal(analyticsState.consentUpdates.at(-1)[2].analytics_storage, 'granted');
        assert.equal(analyticsState.consentUpdates.at(-1)[2].ad_storage, 'denied');

        await page.getByRole('link', { name: /Get the app/ }).click();
        assert.equal(await page.evaluate(() => window.dataLayer.filter((entry) => entry?.event === 'feature_cta_click').length), 1);

        await page.getByRole('button', { name: 'Cookie-Einstellungen' }).click();
        await statistics.uncheck();
        await page.getByRole('button', { name: 'Auswahl speichern' }).click();
        const eventCountAfterWithdrawal = await page.evaluate(() => window.dataLayer.filter((entry) => entry?.event === 'feature_cta_click').length);
        await page.getByRole('link', { name: /Explore recipes/ }).click();
        assert.equal(await page.evaluate(() => window.dataLayer.filter((entry) => entry?.event === 'feature_cta_click').length), eventCountAfterWithdrawal);
        assert.equal(await page.evaluate(() => JSON.parse(localStorage.getItem('simrecipes.analytics-consent')).statistics), false);
    } finally {
        await browser.close();
    }
});
