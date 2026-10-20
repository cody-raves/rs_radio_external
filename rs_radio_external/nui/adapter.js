// rs_radio_external UI module.
//
// Installs the source adapter that teaches the base radio's NUI how to play
// YouTube (embedded players), SoundCloud (resolved streams, HLS stitched) and
// direct HTTPS audio links. The base ships none of this; every provider
// specific detail lives here.

(function () {
    "use strict";

    let apiRequested = false;

    // ------------------------------------------------------------------
    // HLS playlist -> single playable file.
    //
    // SoundCloud serves most tracks as HLS only (fragmented MP4 audio, VOD).
    // FiveM's browser (Chromium 103) cannot play an .m3u8 playlist: <audio>
    // fails with DEMUXER_ERROR_COULD_NOT_OPEN and Web Audio cannot decode it.
    // We download the init segment plus every media segment, join them into
    // one audio/mp4 Blob and hand the base a local blob: URL that <audio>
    // elements and Howler can play, seek and decode. Each listener stitches
    // on their own client; the broadcast keeps the original playlist URL.
    // ------------------------------------------------------------------
    const HLS_MAX_CACHE_ENTRIES = 12;
    const HLS_MAX_TOTAL_BYTES = 96 * 1024 * 1024;
    const HLS_MAX_PLAYLIST_DEPTH = 3;
    const HLS_FETCH_CONCURRENCY = 6;
    const HLS_FETCH_TIMEOUT_MS = 20000;
    const hlsCache = new Map(); // url -> { promise, blobUrl, usedAt }

    function isHlsPlaylistUrl(rawUrl) {
        const raw = String(rawUrl || "").trim();
        if (!/^https:\/\//i.test(raw)) return false;
        try {
            return /\.m3u8$/i.test(new URL(raw).pathname);
        } catch (_) {
            return /\.m3u8(\?|#|$)/i.test(raw);
        }
    }

    async function hlsFetch(url, kind) {
        const controller = typeof AbortController === "function" ? new AbortController() : null;
        const timer = controller ? setTimeout(() => controller.abort(), HLS_FETCH_TIMEOUT_MS) : null;
        try {
            const response = await fetch(url, controller ? { signal: controller.signal } : undefined);
            if (!response || !response.ok) {
                throw new Error(`hls_${kind}_http_${response ? response.status : 0}`);
            }
            return kind === "playlist" ? await response.text() : new Uint8Array(await response.arrayBuffer());
        } finally {
            if (timer) clearTimeout(timer);
        }
    }

    function hlsAttributes(line) {
        const attrs = {};
        const re = /([A-Z0-9-]+)=("[^"]*"|[^,]*)/g;
        let match;
        while ((match = re.exec(line)) !== null) {
            attrs[match[1]] = match[2].replace(/^"|"$/g, "");
        }
        return attrs;
    }

    async function hlsLoadMediaPlaylist(url, depth) {
        if (depth > HLS_MAX_PLAYLIST_DEPTH) throw new Error("hls_playlist_too_deep");
        const text = await hlsFetch(url, "playlist");
        if (!/^#EXTM3U/.test(text.trim())) throw new Error("hls_not_a_playlist");
        const lines = text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean);
        const abs = (ref) => new URL(ref, url).toString();

        // Master playlist: follow the first variant (audio-only sources list one).
        const variantIndex = lines.findIndex((line) => line.startsWith("#EXT-X-STREAM-INF"));
        if (variantIndex >= 0) {
            const variant = lines.slice(variantIndex + 1).find((line) => !line.startsWith("#"));
            if (!variant) throw new Error("hls_master_without_variant");
            return hlsLoadMediaPlaylist(abs(variant), depth + 1);
        }

        let initUrl = "";
        const segments = [];
        for (const line of lines) {
            if (line.startsWith("#EXT-X-KEY")) {
                const method = String(hlsAttributes(line).METHOD || "").toUpperCase();
                if (method && method !== "NONE") throw new Error("hls_encrypted_unsupported");
            } else if (line.startsWith("#EXT-X-BYTERANGE")) {
                throw new Error("hls_byterange_unsupported");
            } else if (line.startsWith("#EXT-X-MAP")) {
                const attrs = hlsAttributes(line);
                if (attrs.BYTERANGE) throw new Error("hls_byterange_unsupported");
                if (attrs.URI) initUrl = abs(attrs.URI);
            } else if (!line.startsWith("#")) {
                segments.push(abs(line));
            }
        }
        if (segments.length === 0) throw new Error("hls_no_segments");
        // Chromium can demux fragmented MP4 audio but not MPEG-TS segments.
        if (!initUrl && /\.ts$/i.test(new URL(segments[0]).pathname)) {
            throw new Error("hls_mpegts_unsupported");
        }
        return { initUrl, segments };
    }

    async function hlsFetchAll(urls) {
        const parts = new Array(urls.length);
        let next = 0;
        let total = 0;
        async function worker() {
            while (next < urls.length) {
                const index = next;
                next += 1;
                const bytes = await hlsFetch(urls[index], "segment");
                total += bytes.byteLength;
                if (total > HLS_MAX_TOTAL_BYTES) throw new Error("hls_stream_too_large");
                parts[index] = bytes;
            }
        }
        const workers = [];
        for (let i = 0; i < Math.min(HLS_FETCH_CONCURRENCY, urls.length); i += 1) workers.push(worker());
        await Promise.all(workers);
        return { parts, total };
    }

    function hlsEvict() {
        if (hlsCache.size <= HLS_MAX_CACHE_ENTRIES) return;
        const settled = Array.from(hlsCache.entries())
            .filter(([, entry]) => entry.blobUrl)
            .sort((a, b) => a[1].usedAt - b[1].usedAt);
        while (hlsCache.size > HLS_MAX_CACHE_ENTRIES && settled.length > 0) {
            const [key, entry] = settled.shift();
            hlsCache.delete(key);
            try { URL.revokeObjectURL(entry.blobUrl); } catch (_) {}
        }
    }

    function hlsStitch(rawUrl) {
        const url = String(rawUrl || "").trim();
        const existing = hlsCache.get(url);
        if (existing) {
            existing.usedAt = Date.now();
            return existing.promise;
        }
        const entry = { promise: null, blobUrl: "", usedAt: Date.now() };
        entry.promise = (async () => {
            const startedAt = performance.now();
            const playlist = await hlsLoadMediaPlaylist(url, 0);
            const urls = playlist.initUrl ? [playlist.initUrl, ...playlist.segments] : playlist.segments;
            const { parts, total } = await hlsFetchAll(urls);
            entry.blobUrl = URL.createObjectURL(new Blob(parts, { type: "audio/mp4" }));
            if (typeof window.traceConsole === "function") {
                window.traceConsole("info", `[rs_radio_external][hls] stitched segments=${playlist.segments.length} bytes=${total} ms=${Math.round(performance.now() - startedAt)}`);
            }
            hlsEvict();
            return entry.blobUrl;
        })();
        entry.promise.catch((err) => {
            hlsCache.delete(url);
            console.warn(`[rs_radio_external][hls] stitch failed: ${err && err.message ? err.message : err}`);
        });
        hlsCache.set(url, entry);
        return entry.promise;
    }

    function hlsPeek(rawUrl) {
        const entry = hlsCache.get(String(rawUrl || "").trim());
        if (!entry || !entry.blobUrl) return "";
        entry.usedAt = Date.now();
        return entry.blobUrl;
    }

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
            return host === "sndcdn.com" || host.endsWith(".sndcdn.com")
                || host === "soundcloud.cloud" || host.endsWith(".soundcloud.cloud");
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
            if (value.includes("sndcdn.com") || value.includes("soundcloud.com") || value.includes("soundcloud.cloud")) {
                return 1.35;
            }
            return 0;
        },

        // Base seam: URLs the browser cannot play as-is (HLS playlists).
        needsMediaPreparation(rawUrl) {
            return isHlsPlaylistUrl(rawUrl);
        },

        peekPreparedMediaUrl(rawUrl) {
            return hlsPeek(rawUrl);
        },

        prepareMediaUrl(rawUrl) {
            return isHlsPlaylistUrl(rawUrl) ? hlsStitch(rawUrl) : Promise.resolve(rawUrl);
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
