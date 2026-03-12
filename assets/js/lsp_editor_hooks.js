// LANG LSP Editor Hooks - Optional Recurse editor integration (if provided globally)

const LspEditorHooks = {
  // Main LSP Editor Hook using @nocsi/recurse
  LspRecurseEditor: {
    mounted() {
      try {
        const id = this.el?.id || '(no-id)'
        const lang = this.el?.dataset?.language || 'unknown'
        const fp = this.el?.dataset?.filePath || this.el?.dataset?.file_path || '(no-file)'
        console.info('[LspRecurseEditor] mounted:', { id, language: lang, filePath: fp })
      } catch (_) {}
      // kick off async init to optionally load editor on-demand
      this.__initialized = false
      // safety fallback: if nothing initialized after 1500ms, use textarea
      try {
        this.__fallbackTimer = setTimeout(() => {
          if (!this.__initialized && !this.__fallbackTextarea) {
            console.warn('[LspRecurseEditor] init timeout; switching to fallback textarea')
            try { this.__setupFallbackEditor() } catch (_) {}
          }
        }, 1500)
      } catch (_) {}
      this.__initRecurseEditor().catch((err) => {
        console.warn('[LspRecurseEditor] init error; falling back:', err)
        // Graceful fallback editor if dynamic import fails
        try { this.__setupFallbackEditor() } catch (_) {}
      })
    },

    async __initRecurseEditor() {
      const content = this.el.dataset.content || ''
      const language = this.el.dataset.language || 'elixir'

      // Try dynamic import if global isn't present
      if (!window.RecurseEditor) {
        try {
          console.debug('[LspRecurseEditor] attempting dynamic import of @nocsi/recurse')
          const mod = await import('@nocsi/recurse/dist/recurse/shadcn/index.js')
          window.RecurseEditor = window.RecurseEditor || mod.RecurseEditor || mod.default
        } catch (e) {
          console.warn('[LspRecurseEditor] package import failed, trying CDN')
          try {
            const cdn = 'https://esm.sh/@nocsi/recurse@1/dist/recurse/shadcn/index.js'
            const modCdn = await import(/* @vite-ignore */ cdn)
            window.RecurseEditor = window.RecurseEditor || modCdn.RecurseEditor || modCdn.default
          } catch (cdnErr) {
            console.warn('[LspRecurseEditor] CDN import failed; using fallback textarea editor')
            this.__setupFallbackEditor()
            return
          }
        }
      }

      if (!window.RecurseEditor) {
        console.warn('[LspRecurseEditor] RecurseEditor global missing; using fallback textarea editor')
        this.__setupFallbackEditor()
        return
      }

      // Instantiate provided editor; try direct signature first
      let constructed = false
      try {
        this.editor = new window.RecurseEditor({
        element: this.el,
        content: content,
        language: language,
        theme: 'nocsi-dark',
        fontSize: 14,
        lineNumbers: true,
        minimap: true,
        wordWrap: 'on',
        tabSize: 2,
        insertSpaces: true,
        autoIndent: 'full',
        formatOnType: true,
        formatOnPaste: true,
        bracketMatching: 'always',
        autoClosingBrackets: 'always',
        autoClosingQuotes: 'always',
        folding: true,
        foldingStrategy: 'indentation',
        showFoldingControls: 'always',
        renderWhitespace: 'selection',
        renderControlCharacters: true,
        rulers: [80, 100],
        cursorStyle: 'line',
        cursorBlinking: 'blink',
        matchBrackets: 'always',
        selectOnLineNumbers: true,
        scrollBeyondLastLine: false,
        automaticLayout: true,
        readOnly: false,
        contextmenu: true,
        quickSuggestions: true,
        suggestOnTriggerCharacters: true,
        acceptSuggestionOnEnter: 'on',
        acceptSuggestionOnCommitCharacter: true,
        snippetSuggestions: 'top',
        wordBasedSuggestions: true,
        semanticHighlighting: {
          enabled: true
        },
        // LSP-specific configuration
        lsp: {
          enabled: true,
          serverUrl: window.location.protocol === 'https:' ? 'wss://' : 'ws://' + window.location.host + '/lsp',
          capabilities: {
            hover: true,
            completion: true,
            signatureHelp: true,
            definition: true,
            references: true,
            documentHighlight: true,
            documentSymbol: true,
            codeAction: true,
            codeLens: true,
            formatting: true,
            rangeFormatting: true,
            rename: true,
            foldingRange: true,
            diagnostics: true
          }
        },
        // LANG-specific extensions
        langExtensions: {
          aiSearch: true,
          semanticNavigation: true,
          contextualHelp: true,
          intelligentRefactoring: true,
          realTimeAnalysis: true
        }
      })
        constructed = true
      } catch (errDirect) {
        console.warn('[LspRecurseEditor] direct construction failed, trying Svelte signature', errDirect)
        // Try Svelte component signature: new RecurseEditor({ target, props })
        try {
          this.el.innerHTML = ''
          const self = this
          this.__recurseComponent = new window.RecurseEditor({
            target: this.el,
            props: {
              content,
              language,
              onUpdate: (evt) => {
                try { self.editor = evt?.editor || evt?.detail?.editor || self.editor } catch (_) {}
              },
            }
          })
          // Shim a minimal editor API if needed
          if (!this.editor) {
            this.editor = {
              getValue: () => {
                try { return self.__recurseComponent?.getContent?.() } catch (_) {}
                try { return self.el?.textContent || '' } catch (_) { return '' }
              },
              setValue: (v) => { try { self.__recurseComponent?.setContent?.(v) } catch (_) {} },
              focus: () => {},
              dispose: () => { try { self.__recurseComponent?.$destroy?.() } catch (_) {} }
            }
          }
          constructed = true
        } catch (errSvelte) {
          console.warn('[LspRecurseEditor] Svelte construction failed; falling back', errSvelte)
          try { this.__setupFallbackEditor() } catch (_) {}
          return
        }
      }

      // Set up event listeners (if editor exposes required API)
      this.setupEventListeners?.()

      // Initialize LANG LSP integration (only if supported by editor)
      try { this.initializeLangLSP?.() } catch (_) {}

      // Focus the editor when ready
      setTimeout(() => {
        try { this.editor?.focus?.(); console.debug('[LspRecurseEditor] editor focused') } catch (_) {}
      }, 100)

      this.__initialized = true
      try { console.info('[LspRecurseEditor] initialized successfully') } catch (_) {}
      try { this.pushEvent('editor_status', { engine: 'recurse', host: this.el?.id || null }) } catch (_) {}
      try { clearTimeout(this.__fallbackTimer) } catch (_) {}
    },

    updated() {
      // Keep content in sync when LiveView updates data-content
      const newContent = this.el.dataset.content || ''
      if (this.editor?.getValue && typeof this.editor.getValue === 'function') {
        const cur = this.editor.getValue()
        if (typeof cur === 'string' && cur !== newContent) {
          const pos = this.editor.getPosition?.()
          this.editor.setValue?.(newContent)
          if (pos) this.editor.setPosition?.(pos)
        }
      } else if (this.__fallbackTextarea) {
        if (this.__fallbackTextarea.value !== newContent) {
          this.__fallbackTextarea.value = newContent
        }
      }
    },

    // (consolidated in single updated() above)

    destroyed() {
      try { this.editor?.dispose?.() } catch (_) {}
    },

    setupEventListeners() {
      // Content changes
      this.editor?.onDidChangeModelContent?.(() => {
        const content = this.editor.getValue()
        const isMarkdown = this.el.dataset.language === 'markdown'
        if (isMarkdown) {
          this.pushEvent('update_raw_markdown', { content })
        } else {
          this.pushEvent('update_file_content', { content })
        }
      })

      // Cursor position changes
      this.editor?.onDidChangeCursorPosition?.((e) => {
        const position = e.position
        this.pushEvent('cursor_position_changed', {
          line: position.lineNumber,
          column: position.column
        })
      })

      // Save command (Cmd/Ctrl + S)
      this.editor?.addCommand?.(2048 + 49, () => { // Ctrl/Cmd + S
        const content = this.editor.getValue()
        const isMarkdown = this.el.dataset.language === 'markdown'
        if (isMarkdown) {
          this.pushEvent('save_all_changes', { content })
        } else {
          this.pushEvent('save_file', { content })
        }
      })

      // Format command (Shift + Alt + F)
      this.editor?.addCommand?.(1024 + 512 + 36, () => { // Shift + Alt + F
        try { this.editor?.getAction?.('editor.action.formatDocument')?.run?.() } catch (_) {}
      })

      // AI search command (Cmd/Ctrl + Shift + F)
      this.editor?.addCommand?.(2048 + 1024 + 36, () => {
        this.triggerAISearch()
      })

      // Semantic navigation (Cmd/Ctrl + .)
      this.editor?.addCommand?.(2048 + 84, () => {
        this.triggerSemanticNavigation()
      })

      // Show references (Shift + F12)
      this.editor?.addCommand?.(1024 + 70, () => { this.showReferences() })
    },

    initializeLangLSP() {
      if (!this.editor || typeof this.editor.connectToLSP !== 'function') return
      // Connect to LANG LSP server for AI-powered features
      this.lspConnection = this.editor.connectToLSP({
        serverUrl: this.getLSPServerUrl(),
        capabilities: [
          'lang.think.explain_intent',
          'lang.think.find_semantic',
          'lang.spatial.map',
          'lang.spatial.traverse',
          'lang.generate.complete_partial'
        ]
      })

      // Handle LSP notifications
      this.lspConnection.onNotification('lang/analysis/complete', (params) => {
        this.handleAnalysisComplete(params)
      })

      this.lspConnection.onNotification('lang/spatial/updated', (params) => {
        this.handleSpatialUpdate(params)
      })
    },

    getContent() {
      return this.editor ? this.editor.getValue() : ''
    },

    getPosition() {
      return this.editor ? this.editor.getPosition() : { lineNumber: 1, column: 1 }
    },

    setContent(content) {
      if (this.editor) {
        this.editor.setValue(content)
      }
    },

    insertText(text, _position = null) {
      if (this.editor) {
        const pos = _position || this.editor.getPosition()
        this.editor.executeEdits('insert-text', [{
          range: {
            startLineNumber: pos.lineNumber,
            startColumn: pos.column,
            endLineNumber: pos.lineNumber,
            endColumn: pos.column
          },
          text: text
        }])
      }
    },

    triggerAISearch() {
      const selection = this.editor.getSelection()
      const selectedText = this.editor.getModel().getValueInRange(selection)
      const query = selectedText || prompt('Enter AI search query:')

      if (query) {
        this.pushEvent('ai_search', { query, position: this.getPosition() })
      }
    },

    triggerSemanticNavigation() {
      const position = this.editor.getPosition()
      const word = this.editor.getModel().getWordAtPosition(position)

      if (word) {
        this.pushEvent('semantic_navigate', {
          word: word.word,
          position: position
        })
      }
    },

    showReferences() {
      const position = this.editor.getPosition()
      this.editor.getAction('editor.action.goToReferences').run()
    },

    handleAnalysisComplete(params) {
      // Show analysis results in the editor
      this.editor.deltaDecorations([], params.decorations || [])

      if (params.diagnostics) {
        this.updateDiagnostics(params.diagnostics)
      }
    },

    handleSpatialUpdate(params) {
      // Update spatial navigation hints
      this.pushEvent('spatial_updated', params)
    },

    updateDiagnostics(diagnostics) {
      const markers = diagnostics.map(diag => ({
        severity: this.getSeverity(diag.severity),
        startLineNumber: diag.range.start.line + 1,
        startColumn: diag.range.start.character + 1,
        endLineNumber: diag.range.end.line + 1,
        endColumn: diag.range.end.character + 1,
        message: diag.message,
        source: 'LANG LSP'
      }))

      try { monaco.editor.setModelMarkers(this.editor.getModel(), 'lang-lsp', markers) } catch (_) {}
    },

    getSeverity(severity) {
      switch (severity) {
        case 1: return monaco.MarkerSeverity.Error
        case 2: return monaco.MarkerSeverity.Warning
        case 3: return monaco.MarkerSeverity.Info
        case 4: return monaco.MarkerSeverity.Hint
        default: return monaco.MarkerSeverity.Info
      }
    },

    getLSPServerUrl() {
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      return `${protocol}//${window.location.host}/lsp`
    },

    __setupFallbackEditor() {
      // Minimal textarea-based editor with keyboard shortcuts
      const textarea = document.createElement('textarea')
      textarea.className = 'w-full h-full bg-gray-900 text-gray-100 p-4 font-mono text-sm border-none focus:outline-none focus:ring-2 focus:ring-purple-500 resize-none'
      textarea.value = this.el.dataset.content || ''
      this.el.innerHTML = ''
      this.el.appendChild(textarea)
      this.__fallbackTextarea = textarea
      try {
        console.info('[LspRecurseEditor] using fallback textarea editor', {
          id: this.el?.id,
          language: this.el?.dataset?.language,
          filePath: this.el?.dataset?.filePath || this.el?.dataset?.file_path
        })
      } catch (_) {}
      try { this.pushEvent('editor_status', { engine: 'fallback', host: this.el?.id || null }) } catch (_) {}
      try { clearTimeout(this.__fallbackTimer) } catch (_) {}

      const isMarkdown = this.el.dataset.language === 'markdown'

      textarea.addEventListener('input', (e) => {
        const content = e.target.value
        if (isMarkdown) {
          this.pushEvent('update_raw_markdown', { content })
        } else {
          this.pushEvent('update_file_content', { content })
        }
      })

      textarea.addEventListener('keydown', (e) => {
        if (e.metaKey || e.ctrlKey) {
          if (e.key.toLowerCase() === 's') {
            e.preventDefault()
            const content = textarea.value
            if (isMarkdown) {
              this.pushEvent('save_all_changes', { content })
            } else {
              this.pushEvent('save_file', { content })
            }
          }
        }
        if (e.key === 'Escape') {
          e.preventDefault()
          if (this.el.id === 'sticky-recurse-editor') {
            this.pushEvent('toggle_sticky_editor', {})
          } else {
            this.pushEvent('close_editor', {})
          }
        }
      })
    }
  },

  // Enhanced table editor for LSP methods
  LspTableEditor: {
    mounted() {
      this.setupEditableTable()
      this.setupKeyboardShortcuts()
    },

    setupEditableTable() {
      // Make table cells editable on double-click
      this.el.addEventListener('dblclick', (e) => {
        const cell = e.target.closest('td')
        if (cell && cell.dataset.editable !== 'false') {
          this.makeEditable(cell)
        }
      })

      // Handle inline editing
      this.el.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' && e.target.contentEditable === 'true') {
          e.preventDefault()
          this.finishEditing(e.target)
        } else if (e.key === 'Escape' && e.target.contentEditable === 'true') {
          e.preventDefault()
          this.cancelEditing(e.target)
        }
      })

      // Handle status dropdowns
      this.el.addEventListener('change', (e) => {
        if (e.target.matches('select[data-field="status"]')) {
          const row = e.target.closest('tr')
          const methodName = row.dataset.method
          this.updateStatus(methodName, e.target.value)
        }
      })
    },

    setupKeyboardShortcuts() {
      this.el.addEventListener('keydown', (e) => {
        // Quick status updates
        if (e.ctrlKey || e.metaKey) {
          switch (e.key) {
            case '1':
              e.preventDefault()
              this.bulkUpdateStatus('not_started')
              break
            case '2':
              e.preventDefault()
              this.bulkUpdateStatus('in_progress')
              break
            case '3':
              e.preventDefault()
              this.bulkUpdateStatus('implemented')
              break
            case 's':
              e.preventDefault()
              this.saveAllChanges()
              break
          }
        }
      })
    },

    makeEditable(cell) {
      const originalValue = cell.textContent.trim()
      cell.contentEditable = true
      cell.focus()
      cell.dataset.originalValue = originalValue

      // Select all text
      const range = document.createRange()
      range.selectNodeContents(cell)
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    },

    finishEditing(cell) {
      const newValue = cell.textContent.trim()
      const originalValue = cell.dataset.originalValue
      const row = cell.closest('tr')
      const methodName = row.dataset.method
      const field = cell.dataset.field

      cell.contentEditable = false
      delete cell.dataset.originalValue

      if (newValue !== originalValue) {
        this.updateField(methodName, field, newValue)
      }
    },

    cancelEditing(cell) {
      const originalValue = cell.dataset.originalValue
      cell.textContent = originalValue
      cell.contentEditable = false
      delete cell.dataset.originalValue
    },

    updateStatus(methodName, newStatus) {
      this.pushEvent('update_status', { method: methodName, status: newStatus })
    },

    updateField(methodName, field, value) {
      const eventName = `update_${field}`
      this.pushEvent(eventName, { method: methodName, [field]: value })
    },

    bulkUpdateStatus(status) {
      const selectedRows = this.el.querySelectorAll('tr.selected')
      if (selectedRows.length === 0) {
        // No selection, prompt for confirmation
        if (confirm(`Update all visible methods to ${status}?`)) {
          this.pushEvent('bulk_update_status', { to: status })
        }
      } else {
        selectedRows.forEach(row => {
          const methodName = row.dataset.method
          this.updateStatus(methodName, status)
        })
      }
    },

    saveAllChanges() {
      this.pushEvent('save_all_changes', {})
    }
  },

  // Progress visualization hook
  LspProgressChart: {
    mounted() {
      this.initChart()
      this.updateChart()
    },

    updated() {
      this.updateChart()
    },

    initChart() {
      const canvas = this.el.querySelector('canvas')
      if (!canvas) {
        const canvasEl = document.createElement('canvas')
        canvasEl.width = 200
        canvasEl.height = 200
        this.el.appendChild(canvasEl)
        this.canvas = canvasEl
      } else {
        this.canvas = canvas
      }

      this.ctx = this.canvas.getContext('2d')
    },

    updateChart() {
      if (!this.ctx) return

      const stats = JSON.parse(this.el.dataset.stats || '{}')
      const { implemented = 0, in_progress = 0, not_started = 0 } = stats
      const total = implemented + in_progress + not_started

      if (total === 0) return

      this.drawDonutChart(implemented, in_progress, not_started, total)
    },

    drawDonutChart(implemented, inProgress, notStarted, total) {
      const centerX = this.canvas.width / 2
      const centerY = this.canvas.height / 2
      const outerRadius = Math.min(centerX, centerY) - 10
      const innerRadius = outerRadius * 0.6

      // Clear canvas
      this.ctx.clearRect(0, 0, this.canvas.width, this.canvas.height)

      let currentAngle = -Math.PI / 2

      // Draw segments
      const segments = [
        { value: implemented, color: '#10B981', label: 'Implemented' },
        { value: inProgress, color: '#F59E0B', label: 'In Progress' },
        { value: notStarted, color: '#EF4444', label: 'Not Started' }
      ]

      segments.forEach(segment => {
        const segmentAngle = (segment.value / total) * 2 * Math.PI

        if (segmentAngle > 0) {
          this.drawSegment(
            centerX, centerY,
            innerRadius, outerRadius,
            currentAngle, segmentAngle,
            segment.color
          )
          currentAngle += segmentAngle
        }
      })

      // Draw center text
      this.drawCenterText(centerX, centerY, implemented, total)
    },

    drawSegment(centerX, centerY, innerRadius, outerRadius, startAngle, segmentAngle, color) {
      this.ctx.beginPath()
      this.ctx.arc(centerX, centerY, outerRadius, startAngle, startAngle + segmentAngle)
      this.ctx.arc(centerX, centerY, innerRadius, startAngle + segmentAngle, startAngle, true)
      this.ctx.closePath()
      this.ctx.fillStyle = color
      this.ctx.fill()
      this.ctx.strokeStyle = '#1F2937'
      this.ctx.lineWidth = 2
      this.ctx.stroke()
    },

    drawCenterText(centerX, centerY, implemented, total) {
      const percentage = Math.round((implemented / total) * 100)

      this.ctx.fillStyle = '#FFFFFF'
      this.ctx.font = 'bold 24px system-ui'
      this.ctx.textAlign = 'center'
      this.ctx.fillText(`${percentage}%`, centerX, centerY - 5)

      this.ctx.font = '12px system-ui'
      this.ctx.fillText('Complete', centerX, centerY + 15)
    }
  },

  // CSV export hook
  CsvExportHook: {
    mounted() {
      this.handleEvent('download_csv', ({ content, filename }) => {
        this.downloadCsv(content, filename)
      })
    },

    downloadCsv(content, filename) {
      const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' })
      const link = document.createElement('a')

      if (link.download !== undefined) {
        const url = URL.createObjectURL(blob)
        link.setAttribute('href', url)
        link.setAttribute('download', filename)
        link.style.visibility = 'hidden'
        document.body.appendChild(link)
        link.click()
        document.body.removeChild(link)
      }
    }
  },

  // Auto-save functionality
  AutoSaveHook: {
    mounted() {
      this.saveTimer = null
      this.lastContent = ''

      this.el.addEventListener('input', () => {
        this.scheduleAutoSave()
      })
    },

    destroyed() {
      if (this.saveTimer) {
        clearTimeout(this.saveTimer)
      }
    },

    scheduleAutoSave() {
      if (this.saveTimer) {
        clearTimeout(this.saveTimer)
      }

      this.saveTimer = setTimeout(() => {
        const currentContent = this.getContent()
        if (currentContent !== this.lastContent) {
          this.pushEvent('auto_save', { content: currentContent })
          this.lastContent = currentContent
        }
      }, 2000) // Auto-save after 2 seconds of inactivity
    },

    getContent() {
      return this.el.textContent || this.el.value || ''
    }
  }
}

// Global keyboard shortcuts for editor controls
document.addEventListener('keydown', (e) => {
  // ESC to close any open modals/editors
  if (e.key === 'Escape') {
    const stickyEditor = document.getElementById('sticky-recurse-editor');
    if (stickyEditor) {
      // Trigger the toggle sticky editor event
      const event = new CustomEvent('phx:toggle_sticky_editor');
      stickyEditor.dispatchEvent(event);
    }
  }
});

// Markdown-LD Semantic Processor
const MarkdownLDProcessor = {
  extractEntities(content) {
    const entities = [];

    // Extract LSP method entities
    const methodPattern = /`([^`]+)`\s*-\s*([^❌🔄✅]*)/g;
    let match;

    while ((match = methodPattern.exec(content)) !== null) {
      entities.push({
        type: 'lsp_method',
        name: match[1],
        description: match[2].trim(),
        line: this.getLineNumber(content, match.index)
      });
    }

    // Extract status entities
    const statusPattern = /([❌🔄✅])\s*`([^`]+)`/g;
    while ((match = statusPattern.exec(content)) !== null) {
      const status = match[1] === '✅' ? 'implemented' :
                    match[1] === '🔄' ? 'in_progress' : 'not_started';
      entities.push({
        type: 'status',
        status: status,
        method: match[2],
        line: this.getLineNumber(content, match.index)
      });
    }

    return entities;
  },

  getLineNumber(content, index) {
    return content.substring(0, index).split('\n').length;
  },

  highlightEntities(editor, entities) {
    entities.forEach(entity => {
      if (entity.type === 'lsp_method') {
        this.addEntityHighlight(editor, entity.name, 'lsp-method');
      } else if (entity.type === 'status') {
        this.addEntityHighlight(editor, entity.method, `status-${entity.status}`);
      }
    });
  },

  addEntityHighlight(editor, text, className) {
    // Add semantic highlighting for entities
    const pattern = new RegExp(`\`${text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\``, 'g');
    // This would integrate with the editor's highlighting system
  }
};

// TipTap Editor Hook for LSP Markdown editing
const TipTapEditor = {
  mounted() {
    this.initTipTap();
  },

  async initTipTap() {
    // Resolve a CDN URL for a given module specifier
    const cdnFor = (spec) => {
      switch (spec) {
        case '@tiptap/core': return 'https://esm.sh/@tiptap/core@2?bundle'
        case '@tiptap/starter-kit': return 'https://esm.sh/@tiptap/starter-kit@2?bundle'
        case '@tiptap/extension-table': return 'https://esm.sh/@tiptap/extension-table@2?bundle'
        case '@tiptap/extension-task-list': return 'https://esm.sh/@tiptap/extension-task-list@2?bundle'
        case '@tiptap/extension-task-item': return 'https://esm.sh/@tiptap/extension-task-item@2?bundle'
        case '@tiptap/extension-highlight': return 'https://esm.sh/@tiptap/extension-highlight@2?bundle'
        case '@tiptap/extension-typography': return 'https://esm.sh/@tiptap/extension-typography@2?bundle'
        case '@tiptap/extension-code-block-lowlight': return 'https://esm.sh/@tiptap/extension-code-block-lowlight@2?bundle'
        case 'lowlight': return 'https://esm.sh/lowlight@3?bundle'
        case 'highlight.js/lib/languages/elixir': return 'https://esm.sh/highlight.js@11/lib/languages/elixir'
        case 'highlight.js/lib/languages/javascript': return 'https://esm.sh/highlight.js@11/lib/languages/javascript'
        case 'highlight.js/lib/languages/markdown': return 'https://esm.sh/highlight.js@11/lib/languages/markdown'
        case 'highlight.js/lib/languages/json': return 'https://esm.sh/highlight.js@11/lib/languages/json'
        default: return null
      }
    }

    // Helper to attempt dynamic import and gracefully handle absence; falls back to CDN
    const tryImport = async (spec) => {
      try {
        return await import(spec)
      } catch (err) {
        const cdn = cdnFor(spec)
        if (cdn) {
          try {
            return await import(/* @vite-ignore */ cdn)
          } catch (cdnErr) {
            console.warn(`TipTap CDN fallback failed for: ${spec}`, cdnErr)
            return null
          }
        }
        console.warn(`TipTap dependency missing: ${spec}`, err)
        return null
      }
    }

    // Import TipTap modules dynamically (optional)
    const core = await tryImport('@tiptap/core')
    const starter = await tryImport('@tiptap/starter-kit')
    const table = await tryImport('@tiptap/extension-table')
    const taskList = await tryImport('@tiptap/extension-task-list')
    const taskItem = await tryImport('@tiptap/extension-task-item')
    const highlight = await tryImport('@tiptap/extension-highlight')
    const typography = await tryImport('@tiptap/extension-typography')
    const codeBlockLowlight = await tryImport('@tiptap/extension-code-block-lowlight')

    // If core modules are unavailable, skip TipTap initialization
    if (!core || !starter) {
      console.warn('TipTap core/starter not available; skipping TipTap editor init')
      return
    }

    // Get initial content
    const initialContent = this.el.dataset.content || '';
    const filePath = this.el.dataset.filePath || '';

    // Create TipTap editor
    const { Editor } = core
    this.editor = new Editor({
      element: this.el,
      extensions: [
        (starter && starter.StarterKit ? starter.StarterKit : starter?.default)?.configure?.({
          codeBlock: false, // We'll use CodeBlockLowlight instead
        }) || starter?.StarterKit || starter?.default,
        table && (table.Table?.configure ? table.Table.configure({
          resizable: true,
        }) : table?.default?.configure?.({ resizable: true })),
        taskList && (taskList.TaskList || taskList.default),
        taskItem && (taskItem.TaskItem?.configure ? taskItem.TaskItem.configure({
          nested: true,
        }) : taskItem?.default?.configure?.({ nested: true })),
        highlight && (highlight.Highlight?.configure ? highlight.Highlight.configure({
          multicolor: true,
        }) : highlight?.default?.configure?.({ multicolor: true })),
        typography && (typography.Typography || typography.default),
        codeBlockLowlight && (codeBlockLowlight.CodeBlockLowlight?.configure ? codeBlockLowlight.CodeBlockLowlight.configure({
          lowlight: await this.setupLowlight(),
        }) : codeBlockLowlight?.default?.configure?.({ lowlight: await this.setupLowlight() })),
      ],
      content: initialContent,
      editorProps: {
        attributes: {
          class: 'prose prose-invert max-w-none p-4 focus:outline-none min-h-[500px] bg-gray-900 text-gray-100',
        },
      },
      onUpdate: ({ editor }) => {
        const content = editor.getHTML();
        this.processMarkdownLD(content);
        this.pushEventTo(this.el, "update_raw_markdown", { content: content });
      },
    });

    // Setup keyboard shortcuts and semantic features
    this.setupTipTapShortcuts();
    this.setupSemanticFeatures();
  },

  async setupLowlight() {
    const safeImport = async (spec) => {
      try {
        return await import(spec)
      } catch (err) {
        // Try CDN fallback for highlight/lowlight
        const cdn = (() => {
          switch (spec) {
            case 'lowlight': return 'https://esm.sh/lowlight@3?bundle'
            case 'highlight.js/lib/languages/elixir': return 'https://esm.sh/highlight.js@11/lib/languages/elixir'
            case 'highlight.js/lib/languages/javascript': return 'https://esm.sh/highlight.js@11/lib/languages/javascript'
            case 'highlight.js/lib/languages/markdown': return 'https://esm.sh/highlight.js@11/lib/languages/markdown'
            case 'highlight.js/lib/languages/json': return 'https://esm.sh/highlight.js@11/lib/languages/json'
            default: return null
          }
        })()
        if (cdn) {
          try { return await import(/* @vite-ignore */ cdn) } catch (cdnErr) {}
        }
        console.warn(`Lowlight/HLJS dependency missing: ${spec}`, err)
        return null
      }
    }

    const low = await safeImport('lowlight')
    if (!low) return null

    const elixir = await safeImport('highlight.js/lib/languages/elixir')
    const javascript = await safeImport('highlight.js/lib/languages/javascript')
    const markdown = await safeImport('highlight.js/lib/languages/markdown')
    const json = await safeImport('highlight.js/lib/languages/json')

    try { elixir && low.lowlight?.registerLanguage?.('elixir', elixir.default || elixir) } catch (_) {}
    try { javascript && low.lowlight?.registerLanguage?.('javascript', javascript.default || javascript) } catch (_) {}
    try { markdown && low.lowlight?.registerLanguage?.('markdown', markdown.default || markdown) } catch (_) {}
    try { json && low.lowlight?.registerLanguage?.('json', json.default || json) } catch (_) {}

    return low.lowlight || low.default || low
  },

  setupTipTapShortcuts() {
    // Add custom keyboard shortcuts for LSP editing
    document.addEventListener('keydown', (e) => {
      if (e.metaKey || e.ctrlKey) {
        switch (e.key) {
          case 's':
            e.preventDefault();
            this.saveContent();
            break;
          case 'b':
            e.preventDefault();
            this.editor?.chain().focus().toggleBold().run();
            break;
          case 'i':
            e.preventDefault();
            this.editor?.chain().focus().toggleItalic().run();
            break;
        }
      }

      // Escape key to close sticky editor
      if (e.key === 'Escape' && this.el.id === 'sticky-tiptap-editor') {
        e.preventDefault();
        this.pushEventTo(this.el, "toggle_sticky_editor", {});
      }
    });
  },

  saveContent() {
    if (this.editor) {
      const content = this.editor.getHTML();
      this.pushEventTo(this.el, "save_all_changes", { content: content });
    }
  },

  updated() {
    if (this.editor && this.el.dataset.content) {
      this.editor.commands.setContent(this.el.dataset.content);
    }
  },

  processMarkdownLD(content) {
    // Extract and process markdown_ld entities
    const entities = MarkdownLDProcessor.extractEntities(content);
    this.entities = entities;

    // Highlight semantic entities
    if (this.editor) {
      MarkdownLDProcessor.highlightEntities(this.editor, entities);
    }

    // Send semantic data to LiveView
    this.pushEventTo(this.el, "update_semantic_data", {
      entities: entities,
      entity_count: entities.length
    });
  },

  setupSemanticFeatures() {
    // Add semantic navigation shortcuts
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.shiftKey) {
        switch (e.key) {
          case 'E':
            e.preventDefault();
            this.jumpToNextEntity();
            break;
          case 'S':
            e.preventDefault();
            this.showSemanticSummary();
            break;
        }
      }
    });
  },

  jumpToNextEntity() {
    if (this.entities && this.entities.length > 0) {
      // Cycle through entities
      this.currentEntityIndex = (this.currentEntityIndex + 1) % this.entities.length;
      const entity = this.entities[this.currentEntityIndex];

      // Jump to entity location in editor
      if (this.editor && entity.line) {
        this.editor.commands.setTextSelection({ from: entity.line, to: entity.line });
      }
    }
  },

  showSemanticSummary() {
    if (this.entities) {
      const summary = {
        total_entities: this.entities.length,
        lsp_methods: this.entities.filter(e => e.type === 'lsp_method').length,
        statuses: this.entities.filter(e => e.type === 'status').length
      };

      this.pushEventTo(this.el, "show_semantic_summary", summary);
    }
  },

  destroyed() {
    if (this.editor) {
      this.editor.destroy();
    }
  }
};

// Recurse Editor Hook for markdown and Elixir file editing
const RecurseEditor = {
  mounted() {
    console.log('RecurseEditor hook mounted!', this.el.id);
    this.initRecurseEditor();
    this.setupKeyboardShortcuts();
  },

  async initRecurseEditor() {
    console.log('Initializing RecurseEditor...', this.el.dataset);
    const language = (this.el.dataset.language || '').toLowerCase();

    // For now, prefer the reliable raw textarea for Markdown to preserve exact content
    if (language === 'markdown') {
      this.setupFallbackEditor();
      return;
    }
    // Prefer real RecurseEditor if globally available, otherwise attempt dynamic import + CDN fallback
    try {
      if (!window.RecurseEditor || !window.RecurseEditor.Editor) {
        await this.loadRecurseAdapter();
      }

      if (window.RecurseEditor && window.RecurseEditor.Editor) {
        this.setupRecurseEditor();
      } else {
        console.warn('RecurseEditor adapter not available; falling back to textarea');
        this.setupFallbackEditor();
      }
    } catch (e) {
      console.warn('Failed to initialize RecurseEditor; using fallback', e);
      this.setupFallbackEditor();
    }
  },

  async loadRecurseAdapter() {
    // If another part of the app already provided an Editor adapter, skip
    if (window.RecurseEditor && window.RecurseEditor.Editor) return;

    // Try local ESM dynamic import first (will work when bundled or resolvable)
    let mod = null;
    let mdMod = null;
    try {
      mod = await import('@nocsi/recurse/dist/recurse/shadcn/index.js');
    } catch (_) {
      // Fallback to CDN if local import not resolvable in the browser
      try {
        mod = await import(/* @vite-ignore */ 'https://esm.sh/@nocsi/recurse@1/dist/recurse/shadcn/index.js');
      } catch (cdnErr) {
        console.warn('CDN fallback for RecurseEditor failed', cdnErr);
        // If we can't get the editor, abort early
        return;
      }
    }

    const SvelteRecurseEditor = mod?.RecurseEditor || mod?.default;
    if (!SvelteRecurseEditor) return;

    // Try to load Markdown serializer (optional)
    try {
      mdMod = await import('@nocsi/recurse/dist/recurse/extensions/auto-save/MarkdownSerializer.js');
    } catch (_) {
      try {
        mdMod = await import(/* @vite-ignore */ 'https://esm.sh/@nocsi/recurse@1/dist/recurse/extensions/auto-save/MarkdownSerializer.js');
      } catch (e) {
        console.warn('MarkdownSerializer not available; markdown mode will emit HTML');
      }
    }

    // Create a thin adapter that exposes Editor-like API used by our hook
    class EditorAdapter {
      constructor(opts) {
        const {
          element,
          content = '',
          language = 'markdown',
          theme = 'dark',
          onChange,
          onSave
        } = opts || {};

        this._target = element;
        this._language = language;
        this._theme = theme;
        this._editor = null; // tiptap editor instance captured from onUpdate
        this._mode = (language || '').toLowerCase() === 'markdown' ? 'markdown' : 'html';
        this._MarkdownSerializer = mdMod?.MarkdownSerializer || null;

        try { this._target.innerHTML = '' } catch (_) {}

        // Instantiate the Svelte component
        this._component = new SvelteRecurseEditor({
          target: this._target,
          props: {
            content,
            onUpdate: ({ editor }) => {
              this._editor = editor;
              if (typeof onChange === 'function') {
                try { onChange(this.getContent()); } catch (_) {}
              }
            }
          }
        });

        // Basic save shortcut wiring (Cmd/Ctrl+S)
        this._keydown = (e) => {
          if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 's') {
            e.preventDefault();
            if (typeof onSave === 'function') {
              try { onSave(this.getContent()); } catch (_) {}
            }
          }
        };
        this._target.addEventListener('keydown', this._keydown);
      }

      getContent() {
        try {
          if (this._mode === 'markdown' && this._MarkdownSerializer && this._editor?.getJSON) {
            const json = this._editor.getJSON();
            return this._MarkdownSerializer.serialize(json);
          }
          return this._editor?.getHTML?.() ?? '';
        } catch (_) { return ''; }
      }

      setContent(content) {
        try {
          // For markdown mode we accept markdown text and set as plain text for now
          // A richer path would parse markdown to tiptap JSON, but that requires additional libs.
          this._editor?.commands?.setContent?.(content, false);
        } catch (_) {}
      }

      destroy() {
        try { this._target.removeEventListener('keydown', this._keydown); } catch (_) {}
        try { this._component?.$destroy?.(); } catch (_) {}
        this._editor = null;
      }
    }

    window.RecurseEditor = window.RecurseEditor || {};
    window.RecurseEditor.Editor = EditorAdapter;
  },

  setupRecurseEditor() {
    const initialContent = this.el.dataset.content || '';
    const filePath = this.el.dataset.filePath || '';
    const language = this.el.dataset.language || 'elixir';
    const isSticky = this.el.id === 'sticky-recurse-editor';

    this.recurseInstance = new window.RecurseEditor.Editor({
      element: this.el,
      content: initialContent,
      language: language,
      theme: 'dark',
      features: {
        lineNumbers: true,
        autoComplete: true,
        syntaxHighlighting: true,
        lspIntegration: language === 'elixir',
        aiAssist: true
      },
      lsp: language === 'elixir' ? {
        serverUrl: 'ws://localhost:4001/lsp',
        capabilities: ['completion', 'hover', 'diagnostics', 'gotoDefinition']
      } : null,
      onChange: (content) => {
        if (isSticky) {
          this.pushEventTo(this.el, "update_raw_markdown", { content: content });
        } else {
          this.pushEventTo(this.el, "update_file_content", { content: content });
        }
      },
      onSave: (content) => {
        if (isSticky) {
          this.pushEventTo(this.el, "save_all_changes", { content: content });
        } else {
          this.pushEventTo(this.el, "save_file", { content: content });
        }
      }
    });
  },

  setupFallbackEditor() {
    console.log('Setting up fallback editor...');
    // Create fallback textarea if Recurse is not available
    const textarea = document.createElement('textarea');
    textarea.className = 'w-full h-full bg-gray-900 text-gray-100 p-4 font-mono text-sm border-none focus:outline-none focus:ring-2 focus:ring-purple-500 resize-none';
    textarea.value = this.el.dataset.content || '';
    textarea.placeholder = this.el.dataset.language === 'markdown' ? 'Edit your LSP markdown here...' : 'Loading file content...';
    
    console.log('Content to load:', textarea.value.substring(0, 100) + '...');
    
    // Clear the loading message and add the textarea
    this.el.innerHTML = '';
    this.el.appendChild(textarea);
    
    console.log('Textarea added to DOM');

    if (this.el.dataset.language === 'markdown') {
      this.setupMarkdownHighlighting(textarea);
    } else {
      this.setupElixirHighlighting(textarea);
    }

    this.setupTextareaShortcuts(textarea);
  },

  setupElixirHighlighting(textarea) {
    // Add basic Elixir syntax highlighting classes
    textarea.addEventListener('input', (e) => {
      this.pushEventTo(this.el, "update_file_content", {
        content: e.target.value
      });
    });

    // Add line numbers
    this.addLineNumbers(textarea);
  },

  setupMarkdownHighlighting(textarea) {
    // Add markdown-specific handling
    textarea.addEventListener('input', (e) => {
      this.pushEventTo(this.el, "update_raw_markdown", {
        content: e.target.value
      });
    });

    // Add line numbers
    this.addLineNumbers(textarea);
  },

  addLineNumbers(textarea) {
    const lineNumbers = document.createElement('div');
    lineNumbers.className = 'absolute left-0 top-0 w-12 bg-gray-800 text-gray-500 text-right pr-2 py-4 font-mono text-sm select-none';

    const updateLineNumbers = () => {
      const lines = textarea.value.split('\n').length;
      lineNumbers.innerHTML = Array.from({ length: lines }, (_, i) =>
        `<div class="leading-6">${i + 1}</div>`
      ).join('');
    };

    textarea.addEventListener('input', updateLineNumbers);
    updateLineNumbers();

    // Make textarea container relative and add line numbers
    this.el.style.position = 'relative';
    textarea.style.paddingLeft = '3rem';
    this.el.appendChild(lineNumbers);
  },

  setupTextareaShortcuts(textarea) {
    textarea.addEventListener('keydown', (e) => {
      if (e.metaKey || e.ctrlKey) {
        switch (e.key) {
          case 's':
            e.preventDefault();
            this.saveContent();
            break;
          case 'f':
            e.preventDefault();
            if (this.el.dataset.language === 'elixir') {
              this.formatElixirCode();
            }
            break;
        }
      }

      // Escape key to close editor
      if (e.key === 'Escape') {
        e.preventDefault();
        if (this.el.id === 'sticky-recurse-editor') {
          this.pushEventTo(this.el, "toggle_sticky_editor", {});
        } else {
          this.pushEventTo(this.el, "close_editor", {});
        }
      }

      // Auto-indent for Elixir
      if (e.key === 'Enter' && this.el.dataset.language === 'elixir') {
        this.handleElixirAutoIndent(e, textarea);
      }
    });
  },

  setupKeyboardShortcuts() {
    // Global shortcuts for the sticky editor
    if (this.el.id === 'sticky-recurse-editor') {
      document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') {
          e.preventDefault();
          this.pushEventTo(this.el, "toggle_sticky_editor", {});
        }
      });
    }
  },

  handleElixirAutoIndent(e, textarea) {
    const lines = textarea.value.substring(0, textarea.selectionStart).split('\n');
    const currentLine = lines[lines.length - 1];
    const indent = currentLine.match(/^\s*/)[0];

    // Add extra indent for common Elixir constructs
    if (currentLine.match(/(def |defp |if |case |cond |with |do$)/)) {
      setTimeout(() => {
        const start = textarea.selectionStart;
        textarea.setRangeText('  ' + indent, start, start);
        textarea.selectionStart = textarea.selectionEnd = start + indent.length + 2;
      }, 0);
    } else {
      setTimeout(() => {
        const start = textarea.selectionStart;
        textarea.setRangeText(indent, start, start);
        textarea.selectionStart = textarea.selectionEnd = start + indent.length;
      }, 0);
    }
  },

  saveContent() {
    if (this.recurseInstance) {
      const content = this.recurseInstance.getContent();
      if (this.el.id === 'sticky-recurse-editor') {
        this.pushEventTo(this.el, "save_all_changes", { content: content });
      } else {
        this.pushEventTo(this.el, "save_file", { content: content });
      }
    } else {
      const textarea = this.el.querySelector('textarea');
      if (textarea) {
        if (this.el.id === 'sticky-recurse-editor') {
          this.pushEventTo(this.el, "save_all_changes", { content: textarea.value });
        } else {
          this.pushEventTo(this.el, "save_file", { content: textarea.value });
        }
      }
    }
  },

  formatElixirCode() {
    if (this.recurseInstance) {
      const content = this.recurseInstance.getContent();
      this.pushEventTo(this.el, "format_file", { content: content });
    } else {
      const textarea = this.el.querySelector('textarea');
      if (textarea) {
        this.pushEventTo(this.el, "format_file", { content: textarea.value });
      }
    }
  },

  updated() {
    // Update content when LiveView assigns change
    if (this.recurseInstance && this.el.dataset.content) {
      this.recurseInstance.setContent(this.el.dataset.content);
    } else {
      const textarea = this.el.querySelector('textarea');
      if (textarea && this.el.dataset.content) {
        textarea.value = this.el.dataset.content;
      }
    }
  },

  setupLSPIntegration(textarea) {
    // Setup LSP client connection for real-time feedback
    this.lspClient = {
      serverUrl: 'ws://localhost:4001/lsp',
      connected: false,

      connect() {
        if (typeof WebSocket !== 'undefined') {
          this.socket = new WebSocket(this.serverUrl);

          this.socket.onopen = () => {
            this.connected = true;
            console.log('LSP client connected');
          };

          this.socket.onmessage = (event) => {
            const message = JSON.parse(event.data);
            this.handleLSPMessage(message);
          };

          this.socket.onerror = (error) => {
            console.error('LSP connection error:', error);
          };
        }
      },

      handleLSPMessage(message) {
        // Handle LSP responses (completion, diagnostics, etc.)
        switch (message.method) {
          case 'textDocument/completion':
            this.showCompletions(message.result);
            break;
          case 'textDocument/publishDiagnostics':
            this.showDiagnostics(message.params.diagnostics);
            break;
        }
      },

      sendRequest(method, params) {
        if (this.connected) {
          const request = {
            jsonrpc: '2.0',
            id: Date.now(),
            method: method,
            params: params
          };
          this.socket.send(JSON.stringify(request));
        }
      },

      showCompletions(completions) {
        // Display completion suggestions
        console.log('LSP completions:', completions);
      },

      showDiagnostics(diagnostics) {
        // Show diagnostics (errors, warnings)
        console.log('LSP diagnostics:', diagnostics);
      }
    };

    // Connect to LSP server
    this.lspClient.connect();

    // Setup text change notifications
    textarea.addEventListener('input', (e) => {
      if (this.lspClient.connected) {
        this.lspClient.sendRequest('textDocument/didChange', {
          textDocument: {
            uri: this.el.dataset.filePath || 'untitled.ex',
            version: Date.now()
          },
          contentChanges: [{
            text: e.target.value
          }]
        });
      }
    });
  },

  destroyed() {
    if (this.recurseInstance) {
      this.recurseInstance.destroy();
    }
    if (this.lspClient && this.lspClient.socket) {
      this.lspClient.socket.close();
    }
  }
};

// Add new hooks to the LspEditorHooks object
LspEditorHooks.TipTapEditor = TipTapEditor;
LspEditorHooks.RecurseEditor = RecurseEditor;

export default LspEditorHooks;
