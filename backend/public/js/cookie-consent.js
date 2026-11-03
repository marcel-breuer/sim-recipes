const CONSENT_KEY = 'simrecipes.analytics-consent';

export function startConsentManager(documentRef = document, windowRef = window) {
    const root = documentRef.querySelector('#consent-root');

    if (!root) {
        return;
    }

    const banner = root.querySelector('#consent-banner');
    const preferences = root.querySelector('#consent-preferences');
    const statisticsCheckbox = root.querySelector('[data-consent-statistics]');
    const gtmContainerId = root.dataset.gtmContainerId || '';
    const ga4MeasurementId = root.dataset.ga4MeasurementId || '';
    const consentVersion = root.dataset.consentVersion || '1';
    let savedConsent = readConsent(windowRef);
    let pageViewSent = false;

    windowRef.dataLayer = windowRef.dataLayer || [];
    windowRef.gtag = windowRef.gtag || function gtag() {
        windowRef.dataLayer.push(arguments);
    };
    windowRef.gtag('consent', 'default', {
        analytics_storage: 'denied',
        ad_storage: 'denied',
        ad_user_data: 'denied',
        ad_personalization: 'denied',
    });

    if (savedConsent?.version === consentVersion) {
        if (savedConsent.statistics === true) {
            enableStatistics();
        }
    } else {
        showBanner(false);
    }

    root.querySelector('[data-consent-accept]').addEventListener('click', () => saveConsent(true));
    root.querySelector('[data-consent-reject]').addEventListener('click', () => saveConsent(false));
    root.querySelector('[data-consent-configure]').addEventListener('click', (event) => {
        preferences.hidden = !preferences.hidden;
        event.currentTarget.setAttribute('aria-expanded', String(!preferences.hidden));
    });
    root.querySelector('[data-consent-save]').addEventListener('click', () => saveConsent(statisticsCheckbox.checked));
    documentRef.querySelector('[data-consent-settings]').addEventListener('click', () => {
        statisticsCheckbox.checked = savedConsent?.version === consentVersion && savedConsent.statistics;
        showBanner(true);
    });

    documentRef.querySelectorAll('[data-analytics-event]').forEach((element) => {
        element.addEventListener('click', () => {
            const eventName = element.dataset.analyticsEvent;

            if (eventName === 'feature_cta_click' || eventName === 'app_download_click') {
                sendAnalyticsEvent(eventName);
            }
        });
    });

    function showBanner(openPreferences) {
        root.hidden = false;
        banner.hidden = false;
        preferences.hidden = !openPreferences;
        statisticsCheckbox.checked = savedConsent?.version === consentVersion && savedConsent.statistics;
        root.querySelector('[data-consent-configure]').setAttribute('aria-expanded', String(openPreferences));
    }

    function saveConsent(statistics) {
        savedConsent = {
            version: consentVersion,
            necessary: true,
            statistics,
            updatedAt: new Date().toISOString(),
        };

        try {
            windowRef.localStorage.setItem(CONSENT_KEY, JSON.stringify(savedConsent));
        } catch {
            // The current-page choice still applies when browser storage is unavailable.
        }

        windowRef.gtag('consent', 'update', {
            analytics_storage: statistics ? 'granted' : 'denied',
            ad_storage: 'denied',
            ad_user_data: 'denied',
            ad_personalization: 'denied',
        });

        if (statistics) {
            enableStatistics();
        } else {
            disableStatistics();
        }

        banner.hidden = true;
        preferences.hidden = true;
        root.hidden = true;
    }

    function enableStatistics() {
        if (ga4MeasurementId) {
            windowRef[`ga-disable-${ga4MeasurementId}`] = false;
        }

        windowRef.gtag('consent', 'update', {
            analytics_storage: 'granted',
            ad_storage: 'denied',
            ad_user_data: 'denied',
            ad_personalization: 'denied',
        });

        if (gtmContainerId) {
            loadScript(`https://www.googletagmanager.com/gtm.js?id=${encodeURIComponent(gtmContainerId)}`);
            windowRef.dataLayer.push({
                event: 'simrecipes_analytics_ready',
                ga4_measurement_id: ga4MeasurementId,
            });
        } else if (ga4MeasurementId) {
            loadScript(`https://www.googletagmanager.com/gtag/js?id=${encodeURIComponent(ga4MeasurementId)}`);
            windowRef.gtag('js', new Date());
            windowRef.gtag('config', ga4MeasurementId, {
                send_page_view: false,
                allow_google_signals: false,
                allow_ad_personalization_signals: false,
                page_referrer: '',
            });
        }

        if (!pageViewSent && (gtmContainerId || ga4MeasurementId)) {
            sendAnalyticsEvent('page_view');
            pageViewSent = true;
        }
    }

    function disableStatistics() {
        if (ga4MeasurementId) {
            windowRef[`ga-disable-${ga4MeasurementId}`] = true;
        }

        clearGoogleAnalyticsCookies(documentRef, windowRef.location.hostname);
    }

    function sendAnalyticsEvent(eventName) {
        if (savedConsent?.version !== consentVersion || savedConsent.statistics !== true) {
            return;
        }

        const url = new URL(windowRef.location.href);
        const event = {
            event: eventName,
            page_path: url.pathname,
            page_location: `${url.origin}${url.pathname}`,
            page_referrer: '',
            page_title: documentRef.title,
        };

        if (gtmContainerId) {
            windowRef.dataLayer.push(event);
        } else if (ga4MeasurementId) {
            windowRef.gtag('event', eventName, {
                page_path: event.page_path,
                page_location: event.page_location,
                page_referrer: event.page_referrer,
                page_title: event.page_title,
            });
        }
    }

    function loadScript(src) {
        if (documentRef.querySelector(`script[src="${src}"]`)) {
            return;
        }

        const script = documentRef.createElement('script');
        script.async = true;
        script.src = src;
        documentRef.head.append(script);
    }
}

function readConsent(windowRef) {
    try {
        const consent = JSON.parse(windowRef.localStorage.getItem(CONSENT_KEY));

        return consent && typeof consent === 'object' ? consent : null;
    } catch {
        return null;
    }
}

function clearGoogleAnalyticsCookies(documentRef, hostname) {
    const cookieNames = documentRef.cookie.split(';').map((cookie) => cookie.trim().split('=')[0]);

    cookieNames.filter((name) => name === '_ga' || name.startsWith('_ga_')).forEach((name) => {
        documentRef.cookie = `${name}=; Max-Age=0; path=/; SameSite=Lax`;

        if (hostname.includes('.')) {
            documentRef.cookie = `${name}=; Max-Age=0; path=/; domain=.${hostname}; SameSite=Lax`;
        }
    });
}

if (typeof document !== 'undefined' && document.querySelector('#consent-root')) {
    startConsentManager();
}
