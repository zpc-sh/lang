// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//
// If you have dependencies that try to import CSS, esbuild will generate a separate `app.css` file.
// To load it, simply add a second `<link>` to your `root.html.heex` file.

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/lang"
import topbar from "../vendor/topbar"

// RecurseEditor integration is optional and loaded externally when available.
// Do not import here to avoid bundling issues; hooks will check window.RecurseEditor.


// Import Stripe integration
import "./stripe"

// Import LSP Editor hooks
import LspEditorHooks from "./lsp_editor_hooks"

// Get Stripe publishable key from environment
window.stripePublishableKey = document.querySelector("meta[name='stripe-publishable-key']")?.getAttribute("content");

// Optional: RecurseEditor integration (loaded externally when available)
// If you integrate @nocsi/recurse via a separate build step, you can set
// window.RecurseEditor there. We avoid bundling it here to keep esbuild simple.

// Custom hooks for LANG landing page
const langHooks = {
  MatrixRain: {
    mounted() {
      this.createMatrixRain();
    },
    
    createMatrixRain() {
      const container = this.el;
      const chars = '⟨~⟩▷⇒🎯✅⚠️💡LANG01';
      const columns = Math.floor(container.offsetWidth / 20);
      
      for (let i = 0; i < columns; i++) {
        const column = document.createElement('div');
        column.className = 'matrix-column';
        column.style.left = `${i * 20}px`;
        column.style.animationDuration = `${Math.random() * 10 + 5}s`;
        column.style.animationDelay = `${Math.random() * 5}s`;
        
        // Generate random characters
        let text = '';
        for (let j = 0; j < 50; j++) {
          text += chars[Math.floor(Math.random() * chars.length)] + '\n';
        }
        column.textContent = text;
        
        container.appendChild(column);
      }
    }
  },
  
  TypeWriter: {
    mounted() {
      const text = this.el.dataset.text;
      const speed = parseInt(this.el.dataset.speed) || 50;
      let index = 0;
      
      const type = () => {
        if (index < text.length) {
          this.el.textContent = text.substring(0, index + 1);
          index++;
          setTimeout(type, speed);
        }
      };
      
      type();
    }
  },
  
  RotatingText: {
    mounted() {
      const words = [
        'Text',
        'Document',
        'Contract',
        'Code',
        'Email',
        'Recipe',
        'Medical',
        'Legal',
        'Network',
        'FileSystem',
        'API',
        'Database',
        'Markdown',
        'JSON',
        'YAML',
        'Config',
        'Log',
        'Chat',
        'Report',
        'Knowledge'
      ];
      
      let currentIndex = 0;
      const element = this.el;
      
      // Create wrapper for smooth transitions
      const wrapper = document.createElement('span');
      wrapper.className = 'rotating-text-wrapper';
      wrapper.style.position = 'relative';
      wrapper.style.display = 'inline-block';
      wrapper.textContent = words[0];
      
      element.textContent = '';
      element.appendChild(wrapper);
      
      setInterval(() => {
        // Fade out
        wrapper.style.opacity = '0';
        wrapper.style.transform = 'translateY(-20px)';
        wrapper.style.transition = 'all 0.5s ease-out';
        
        setTimeout(() => {
          currentIndex = (currentIndex + 1) % words.length;
          wrapper.textContent = words[currentIndex];
          
          // Reset position below
          wrapper.style.transition = 'none';
          wrapper.style.transform = 'translateY(20px)';
          
          // Force reflow
          wrapper.offsetHeight;
          
          // Fade in
          wrapper.style.transition = 'all 0.5s ease-out';
          wrapper.style.opacity = '1';
          wrapper.style.transform = 'translateY(0)';
        }, 500);
      }, 3000);
    }
  },

  ClipboardHook: {
    mounted() {
      this.handleEvent("copy-to-clipboard", ({text}) => {
        if (navigator.clipboard && window.isSecureContext) {
          navigator.clipboard.writeText(text).then(() => {
            this.showToast("Copied!");
          }).catch(err => {
            console.error("Failed to copy text: ", err);
            this.fallbackCopy(text);
          });
        } else {
          const ok = this.fallbackCopy(text);
          if (ok) this.showToast("Copied!");
        }
      });
    },

    fallbackCopy(text) {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.left = '-999999px';
      textArea.style.top = '-999999px';
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();

      try {
        document.execCommand('copy');
        return true;
      } catch (err) {
        console.error("Fallback copy failed: ", err);
        return false;
      }

      textArea.remove();
    },

    showToast(message) {
      try {
        const el = document.createElement('div');
        el.textContent = message || 'Copied!';
        el.style.position = 'fixed';
        el.style.top = '12px';
        el.style.right = '12px';
        el.style.zIndex = '2147483647';
        el.style.background = 'rgba(0,0,0,0.82)';
        el.style.color = 'white';
        el.style.padding = '6px 10px';
        el.style.borderRadius = '6px';
        el.style.fontSize = '12px';
        el.style.boxShadow = '0 2px 8px rgba(0,0,0,0.3)';
        el.style.transition = 'opacity 300ms ease';
        document.body.appendChild(el);
        setTimeout(() => {
          el.style.opacity = '0';
          setTimeout(() => { if (el.parentNode) el.parentNode.removeChild(el); }, 350);
        }, 900);
      } catch (_) {}
    }
  }
  ,
  MdldSession: {
    mounted() {
      this.csrf = document.querySelector("meta[name='csrf-token']")?.getAttribute("content") || null;
      this.terminalEl = this.el.querySelector('[data-terminal]');
      this.connectBtn = this.el.querySelector('[data-action="connect"]');
      this.renderer = (this.el.dataset.renderer || 'rio').toLowerCase();
      this.ws = null;
      this.cols = parseInt(this.el.dataset.cols || '100', 10);
      this.rows = parseInt(this.el.dataset.rows || '28', 10);
      this.mode = this.el.dataset.mode || 'pty';

      try {
        const ro = new ResizeObserver(() => {
          if (!this.terminalEl) return;
          const w = this.terminalEl.clientWidth || 800;
          const h = this.terminalEl.clientHeight || 400;
          // crude cell size estimate; real impl should query renderer metrics
          const cw = 8, ch = 16;
          const cols = Math.max(40, Math.floor(w / cw));
          const rows = Math.max(10, Math.floor(h / ch));
          if (cols !== this.cols || rows !== this.rows) {
            this.cols = cols; this.rows = rows;
            if (this.term && this.term.resize) {
              try { this.term.resize(cols, rows); } catch (_) {}
            }
            this.send({ type: 'resize', cols, rows });
          }
        });
        ro.observe(this.terminalEl);
        this._ro = ro;
      } catch(_) {}

      if (this.connectBtn) {
        this.connectBtn.addEventListener('click', () => this.connect());
      }
    },

    write(data) {
      if (this.term && typeof this.term.write === 'function') {
        this.term.write(data);
      } else {
        this.log(data);
      }
    },
    disable() {
      if (this.connectBtn) this.connectBtn.disabled = true;
      try { this._ro && this._ro.disconnect(); } catch(_) {}
    },

    openSocket(url) {
      try {
        this.ws = new WebSocket((new URL(url, window.location.href)).href);
      } catch (e) {
        this.log(`WS error: ${e.message}`);
        return;
      }
      this.ws.onopen = () => {
        this.log('WS connected');
        this.send({ type: 'hello', cols: this.cols, rows: this.rows, mode: this.mode });
      };
      this.ws.onmessage = (ev) => {
        try {
          const msg = JSON.parse(ev.data);
          if (msg.type === 'stdout') {
            this.write(msg.data);
            this._bytesOut = (this._bytesOut || 0) + (msg.data ? msg.data.length : 0);
            this.updateStats();
          } else if (msg.type === 'exit') {
            this.log(`Session exit: ${msg.status}`);
            this.disable();
          }
        } catch (_) {
          this.write(ev.data);
        }
      };
      this.ws.onclose = () => this.log('WS closed');
      this.ws.onerror = () => this.log('WS error');
    },
    send(obj) {
      try { this.ws && this.ws.readyState === 1 && this.ws.send(JSON.stringify(obj)); } catch (_) {}
    },
    async initRenderer() {
      if (!this.terminalEl) return;
      if (this.renderer === 'rio') {
        await this.loadRio();
        if (window.Rio && typeof window.Rio.Terminal === 'function') {
          this.term = new window.Rio.Terminal({
            parent: this.terminalEl,
            width: this.cols,
            height: this.rows,
            sixel: true,
            onData: (data) => this.send({ type: 'stdin', data })
          });
          return;
        }
      }
      this.renderPlaceholder();
    },
    async loadRio() {
      const tryUrl = async (u) => {
        try { await import(/* @vite-ignore */ u); return true; } catch (_) { return false; }
      };
      const ok = await tryUrl('/vendor/rio/rio.js') || await tryUrl('https://cdn.example.com/rio/rio.js');
      if (!ok) this.log('RIO not available; falling back.');
    },
    async connect() {
      const connectPath = this.el.dataset.connect || '';
      if (!connectPath) {
        this.log("No connect endpoint defined.");
        return;
      }
      const payload = {
        session_id: this.el.dataset.sessionId,
        cap: this.el.dataset.cap || 'interactive',
        cols: parseInt(this.el.dataset.cols || '100', 10),
        rows: parseInt(this.el.dataset.rows || '28', 10),
        mode: this.el.dataset.mode || 'pty',
        proto: this.el.dataset.proto || 'ssh'
      };
      // Optional upstream params for proxy authorization
      const extras = ['host','port','user','fingerprint','path','url','policy'];
      extras.forEach((k) => {
        const v = this.el.dataset[k];
        if (v !== undefined) {
          payload[k] = v;
        }
      });
      try {
        const resp = await fetch(connectPath, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            ...(this.csrf ? { 'x-csrf-token': this.csrf } : {})
          },
          body: JSON.stringify(payload),
          credentials: 'same-origin'
        });
        if (!resp.ok) throw new Error(`Connect failed: ${resp.status}`);
        const data = await resp.json();
        this.log(`Ticket minted. Proxy: ${data.wss_url || 'n/a'}`);
        await this.initRenderer();
        this.openSocket(data.wss_url);
      } catch (e) {
        this.log(`Error: ${e.message}`);
      }
    },
    renderPlaceholder() {
      if (this.terminalEl) {
        this.terminalEl.textContent = '';
        const pre = document.createElement('pre');
        pre.className = 'text-green-400';
        pre.textContent = '[mdld] Connected (stub). WebSocket proxy not implemented yet.';
        this.terminalEl.appendChild(pre);
        this.term = { write: (d) => { pre.textContent += d; pre.scrollTop = pre.scrollHeight; } };
      }
      if (this.connectBtn) {
        this.connectBtn.textContent = 'Connected';
        this.connectBtn.disabled = true;
        this.connectBtn.classList.remove('btn-primary');
        this.connectBtn.classList.add('btn-disabled');
      }
    },

    updateStats() {
      if (!this.terminalEl) return;
      let badge = this.el.querySelector('[data-session-stats]');
      if (!badge) {
        badge = document.createElement('div');
        badge.dataset.sessionStats = '1';
        badge.className = 'mt-1 text-[11px] text-gray-500 flex gap-2';
        this.terminalEl.parentElement.appendChild(badge);
      }
      const mb = (this._bytesOut||0)/ (1024*1024);
      badge.textContent = `Transferred: ${mb.toFixed(2)} MB`;
    },
    log(msg) {
      if (this.terminalEl) {
        const div = document.createElement('div');
        div.className = 'text-gray-400 text-xs';
        div.textContent = msg;
        this.terminalEl.appendChild(div);
      } else {
        console.log('[MdldSession]', msg);
      }
    }
  }
};

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, ...langHooks, ...LspEditorHooks},
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

// The lines below enable quality of life phoenix_live_reload
// development features:
//
//     1. stream server logs to the browser console
//     2. click on elements to jump to their definitions in your code editor
//
if (process.env.NODE_ENV === "development") {
  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    // Enable server log streaming to client.
    // Disable with reloader.disableServerLogs()
    reloader.enableServerLogs()

    // Open configured PLUG_EDITOR at file:line of the clicked element's HEEx component
    //
    //   * click with "c" key pressed to open at caller location
    //   * click with "d" key pressed to open at function component definition location
    let keyDown
    window.addEventListener("keydown", e => keyDown = e.key)
    window.addEventListener("keyup", e => keyDown = null)
    window.addEventListener("click", e => {
      if(keyDown === "c"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtCaller(e.target)
      } else if(keyDown === "d"){
        e.preventDefault()
        e.stopImmediatePropagation()
        reloader.openEditorAtDef(e.target)
      }
    }, true)

    window.liveReloader = reloader
  })
}
