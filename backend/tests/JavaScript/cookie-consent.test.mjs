import assert from 'node:assert/strict';
import test from 'node:test';
import { startConsentManager } from '../../public/js/cookie-consent.js';

class Element {
    constructor(dataset = {}) {
        this.dataset = dataset;
        this.hidden = true;
        this.checked = false;
        this.attributes = {};
        this.listeners = {};
        this.children = [];
        this.elements = {};
    }

    querySelector(selector) {
        return this.elements[selector];
    }

    addEventListener(type, callback) {
        this.listeners[type] = callback;
    }

    setAttribute(name, value) {
        this.attributes[name] = value;
    }

    click() {
        this.listeners.click?.({ currentTarget: this });
    }
}

function createPage({ gtm = 'GTM-ABC123', ga4 = 'G-ABC123', storedConsent = null } = {}) {
    const root = new Element({
        gtmContainerId: gtm,
        ga4MeasurementId: ga4,
        consentVersion: '1',
    });
    const banner = new Element();
    const preferences = new Element();
    const statistics = new Element();
    const accept = new Element();
    const reject = new Element();
    const configure = new Element();
    const save = new Element();
    const settings = new Element();
    const cta = new Element({ analyticsEvent: 'feature_cta_click' });
    const scripts = [];
    const elements = {
        '#consent-banner': banner,
        '#consent-preferences': preferences,
        '[data-consent-statistics]': statistics,
        '[data-consent-accept]': accept,
        '[data-consent-reject]': reject,
        '[data-consent-configure]': configure,
        '[data-consent-save]': save,
    };
    root.elements = elements;

    const documentRef = {
        title: 'SimRecipes',
        cookie: '_ga=abc; _ga_TEST=def; session=1',
        head: { append: (script) => scripts.push(script) },
        querySelector: (selector) => {
            if (selector === '#consent-root') return root;
            if (selector.startsWith('script[src="')) {
                const src = selector.slice('script[src="'.length, -2);
                return scripts.find((script) => script.src === src) ?? null;
            }

            return settings;
        },
        querySelectorAll: () => [cta],
        createElement: () => ({}),
    };
    const storage = new Map();

    if (storedConsent) {
        storage.set('simrecipes.analytics-consent', JSON.stringify(storedConsent));
    }

    const windowRef = {
        dataLayer: [],
        location: new URL('https://simrecipes.example/recipe?token=secret#private'),
        localStorage: {
            getItem: (key) => storage.get(key) ?? null,
            setItem: (key, value) => storage.set(key, value),
        },
    };

    return { root, banner, preferences, statistics, accept, reject, configure, save, settings, cta, documentRef, windowRef, scripts, storage };
}

test('shows consent and sends no Google request before a choice or after rejection', () => {
    const page = createPage();
    startConsentManager(page.documentRef, page.windowRef);

    assert.equal(page.root.hidden, false);
    assert.equal(page.banner.hidden, false);
    assert.deepEqual(page.scripts, []);
    assert.equal(page.windowRef.dataLayer[0][0], 'consent');
    assert.deepEqual(page.windowRef.dataLayer[0][2], {
        analytics_storage: 'denied',
        ad_storage: 'denied',
        ad_user_data: 'denied',
        ad_personalization: 'denied',
    });

    page.cta.click();
    page.reject.click();

    assert.equal(page.banner.hidden, true);
    assert.equal(page.root.hidden, true);
    assert.deepEqual(page.scripts, []);
    assert.equal(page.windowRef.dataLayer.filter((event) => event?.event === 'feature_cta_click').length, 0);
    assert.equal(JSON.parse(page.storage.get('simrecipes.analytics-consent')).statistics, false);
});

test('loads GTM and sends one sanitized page view only after opt-in', () => {
    const page = createPage();
    startConsentManager(page.documentRef, page.windowRef);
    page.accept.click();
    page.settings.click();
    page.statistics.checked = true;
    page.save.click();

    assert.equal(page.scripts.length, 1);
    assert.equal(page.scripts[0].src, 'https://www.googletagmanager.com/gtm.js?id=GTM-ABC123');
    const analyticsEvents = page.windowRef.dataLayer.filter((entry) => entry && entry.event);
    assert.equal(analyticsEvents.filter((event) => event.event === 'page_view').length, 1);
    assert.ok(analyticsEvents.every((event) => !JSON.stringify(event).includes('token=secret')));
    const pageView = analyticsEvents.find((event) => event.event === 'page_view');
    assert.equal(pageView.page_location, 'https://simrecipes.example/recipe');

    page.cta.click();
    assert.equal(page.windowRef.dataLayer.filter((event) => event?.event === 'feature_cta_click').length, 1);
});

test('restores a previous opt-in on reload without loading a duplicate script', () => {
    const page = createPage({ storedConsent: { version: '1', necessary: true, statistics: true } });
    startConsentManager(page.documentRef, page.windowRef);

    assert.equal(page.banner.hidden, true);
    assert.equal(page.root.hidden, true);
    assert.equal(page.scripts.length, 1);
    assert.equal(page.windowRef.dataLayer.filter((event) => event?.event === 'page_view').length, 1);
});

test('loads the direct GA4 tag only after opt-in when no GTM container is configured', () => {
    const page = createPage({ gtm: '', ga4: 'G-ABC123' });
    startConsentManager(page.documentRef, page.windowRef);

    assert.deepEqual(page.scripts, []);
    page.accept.click();

    assert.equal(page.scripts.length, 1);
    assert.equal(page.scripts[0].src, 'https://www.googletagmanager.com/gtag/js?id=G-ABC123');
    assert.equal(page.windowRef.dataLayer.filter((entry) => entry?.[0] === 'config').length, 1);
    assert.equal(page.windowRef.dataLayer.filter((entry) => entry?.[0] === 'event' && entry[1] === 'page_view').length, 1);
});

test('supports consent withdrawal from settings and keeps advertising consent denied', () => {
    const page = createPage({ storedConsent: { version: '1', necessary: true, statistics: true } });
    startConsentManager(page.documentRef, page.windowRef);
    page.settings.click();
    assert.equal(page.banner.hidden, false);
    assert.equal(page.statistics.checked, true);
    page.statistics.checked = false;
    page.save.click();

    const updates = page.windowRef.dataLayer.filter((entry) => entry?.[0] === 'consent' && entry?.[1] === 'update');
    assert.deepEqual(updates.at(-1)[2], {
        analytics_storage: 'denied',
        ad_storage: 'denied',
        ad_user_data: 'denied',
        ad_personalization: 'denied',
    });
    assert.equal(JSON.parse(page.storage.get('simrecipes.analytics-consent')).statistics, false);
    assert.equal(page.scripts.length, 1);
});
