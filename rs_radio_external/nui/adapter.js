// rs_radio_external UI module.
//
// Installs the source adapter that teaches the base radio's NUI how to play
// YouTube (embedded players), SoundCloud (resolved progressive streams) and
// direct HTTPS audio links. The base ships none of this; every provider
// specific detail lives here.

(function () {
    "use strict";

    let apiRequested = false;

    function hostOf(rawUrl) {
        try {
            const parsed = new URL(String(rawUrl || "").trim());
            if (parsed.protocol !== "https:") return "";
            return String(parsed.hostname || "").toLowerCase().replace(/^www\./, "");
        } catch (_) {
            return "";
        }
    }

    function embedApiReady() {
        return !!(window.YT && window.YT.Player);
    }

    function signalReadyWhenApiArrives() {
        const previous = window.onYouTubeIframeAPIReady;
        window.onYouTubeIframeAPIReady = function () {
            if (typeof previous === "function") {
                try { previous(); } catch (_) {}
            }
            if (typeof window.rsRadioEmbedApiBecameReady === "function") {
                try { window.rsRadioEmbedApiBecameReady(); } catch (_) {}
            }
        };
    }

    const adapter = {
        name: "rs_radio_external",
        embedFrameSelector: 'iframe[src*="youtube.com/embed"]',

        // ------------------------------------------------------------------
        // Embed player runtime (YouTube iframe API)
        // ------------------------------------------------------------------
        embedApiReady,

        ensureEmbedApi() {
            if (embedApiReady()) return true;
            if (apiRequested || document.querySelector('script[src*="youtube.com/iframe_api"]')) {
                return false;
            }
            apiRequested = true;
            signalReadyWhenApiArrives();
            try {
                const script = document.createElement("script");
                script.src = "https://www.youtube.com/iframe_api";
                script.async = true;
                document.head.appendChild(script);
            } catch (_) {}
            return false;
        },

        createEmbedPlayer(divId, options) {
            if (!embedApiReady()) return null;
            const spec = { ...(options || {}) };
            // The base runtime calls the media id "mediaId" in some paths.
            if (spec.mediaId && !spec.videoId) {
                spec.videoId = spec.mediaId;
                delete spec.mediaId;
            }
            // Hidden runtime hosts request minimal chrome.
            if (spec.hidden) {
                delete spec.hidden;
                spec.width = spec.width || "2";
                spec.height = spec.height || "2";
                spec.origin = spec.origin || window.location.origin;
                spec.enablejsapi = 1;
                spec.playerVars = spec.playerVars || { autoplay: 0, controls: 0, playsinline: 1, quality: "auto" };
                const onReady = spec.onReady;
                const onStateChange = spec.onStateChange;
                delete spec.onReady;
                delete spec.onStateChange;
                spec.events = spec.events || {};
                if (onReady) spec.events.onReady = onReady;
                if (onStateChange) spec.events.onStateChange = onStateChange;
            }
            try {
                return new window.YT.Player(divId, spec);
            } catch (_) {
                return null;
            }
        },

        embedStateIs(state, name) {
            const states = window.YT && window.YT.PlayerState;
            if (!states) return false;
            if (name === "ended") return state === states.ENDED;
            if (name === "playing") return state === states.PLAYING;
            if (name === "paused") return state === states.PAUSED;
            if (name === "buffering") return state === states.BUFFERING;
            return false;
        },

        // ------------------------------------------------------------------
        // Classification
        // ------------------------------------------------------------------
        isEmbedPageUrl(rawUrl) {
            const host = hostOf(rawUrl);
            // Must accept every host the server-side rules accept — a link the
            // server resolves but the client refuses loads with a title and
            // then silently ignores Play (m.youtube.com was that bug).
            return host === "youtube.com" || host === "youtu.be"
                || host === "music.youtube.com" || host === "m.youtube.com";
        },

        isStreamPageUrl(rawUrl) {
            const host = hostOf(rawUrl);
            return host === "soundcloud.com" || host.endsWith(".soundcloud.com");
        },

        isStreamCdnUrl(rawUrl) {
            const value = String(rawUrl || "").toLowerCase();
            if (value.includes("sndcdn.com") || value.includes("soundcloud.com")) return true;
            const host = hostOf(rawUrl);
            return host === "sndcdn.com" || host.endsWith(".sndcdn.com");
        },

        // Finer page-kind detection for the base's listener URL classifier:
        // "video" | "live" | "playlist". Provider URL shapes stay here.
        classifyPageKind(rawUrl) {
            const raw = String(rawUrl || "");
            if (/youtube\.com\/live\//i.test(raw)) return "live";
            if (!this.extractMediaId(raw)
                && (/[?&]list=/.test(raw) || /youtube\.com\/playlist\?/i.test(raw))) {
                return "playlist";
            }
            return "video";
        },

        extractMediaId(rawUrl) {
            const raw = String(rawUrl || "").trim();
            if (!raw) return "";
            try {
                const parsed = new URL(raw);
                const host = String(parsed.hostname || "").toLowerCase().replace(/^www\./, "");
                if (host === "youtu.be") {
                    return parsed.pathname.replace(/^\/+/, "").split("/")[0] || "";
                }
                const watchId = parsed.searchParams.get("v");
                if (watchId) return watchId;
                const pathMatch = parsed.pathname.match(/\/(?:embed|shorts|live)\/([^/?#]+)/i);
                return pathMatch ? pathMatch[1] : "";
            } catch (_) {
                const loose = raw.match(/[?&]v=([A-Za-z0-9_-]+)/)
                    || raw.match(/youtu\.be\/([A-Za-z0-9_-]+)/i)
                    || raw.match(/youtube\.com\/(?:embed|shorts|live)\/([A-Za-z0-9_-]+)/i);
                return loose ? loose[1] : "";
            }
        },

        // ------------------------------------------------------------------
        // Delivery endpoints and media URLs
        // ------------------------------------------------------------------
        isBlockedDeliveryUrl(rawUrl) {
            try {
                const parsed = new URL(String(rawUrl || "").trim());
                const host = String(parsed.hostname || "").toLowerCase();
                return (host === "googlevideo.com" || host.endsWith(".googlevideo.com"))
                    && parsed.pathname.toLowerCase().includes("/videoplayback");
            } catch (_) {
                return false;
            }
        },

        isDeliveryMediaUrl(rawUrl) {
            return adapter.isBlockedDeliveryUrl(rawUrl);
        },

        isDeliveryResourceUrl(lowerUrl) {
            const value = String(lowerUrl || "");
            return value.includes("googlevideo.com/videoplayback");
        },

        normalizeEmbedMediaDecodeUrl(cleanUrl) {
            try {
                const parsed = new URL(String(cleanUrl || ""));
                const host = String(parsed.hostname || "").toLowerCase();
                if (host === "googlevideo.com" || host.endsWith(".googlevideo.com")) {
                    parsed.searchParams.delete("range");
                    parsed.searchParams.delete("rn");
                    parsed.searchParams.delete("rbuf");
                    parsed.searchParams.delete("alr");
                }
                return parsed.toString();
            } catch (_) {
                return String(cleanUrl || "");
            }
        },

        autoPreampGain(lowerUrl) {
            const value = String(lowerUrl || "");
            if (value.includes("sndcdn.com") || value.includes("soundcloud.com")) {
                return 1.35;
            }
            return 0;
        },

        publicTitleEndpoints(cleanUrl) {
            const encoded = encodeURIComponent(String(cleanUrl || ""));
            return [
                `https://www.youtube.com/oembed?format=json&url=${encoded}`,
                `https://noembed.com/embed?url=${encoded}`
            ];
        }
    };

    if (typeof window.rsRadioInstallSourceAdapter === "function") {
        window.rsRadioInstallSourceAdapter(adapter);
    } else {
        window.RSSourceAdapter = adapter;
    }
})();
