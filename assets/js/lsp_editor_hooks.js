// LANG LSP Editor Hooks - Optional Recurse editor integration (if provided globally)

const LspEditorHooks = {
  // Main LSP Editor Hook using @nocsi/recurse
  LspRecurseEditor: {
    mounted() {
      const content = this.el.dataset.content || ''
      const language = this.el.dataset.language || 'elixir'

      // Initialize Recurse editor if available; otherwise, skip gracefully
      if (!window.RecurseEditor) {
        console.warn("RecurseEditor not available; skipping rich editor init")
        return
      }

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

      // Set up event listeners
      this.setupEventListeners()

      // Initialize LANG LSP integration
      this.initializeLangLSP()

      // Focus the editor
      setTimeout(() => {
        this.editor
.focus()
      }, 100)
    },

    updated() {
      const newContent = this.el.dataset.content || ''
      const currentContent = this.editor.getValue()

      if (newContent !== currentContent) {
        const position = this.editor.getPosition()
        this.editor.setValue(newContent)
        this.editor.setPosition(position)
      }
    },

    destroyed() {
      if (this.editor) {
        this.editor.dispose()
      }
    },

    setupEventListeners() {
      // Content changes
      this.editor.onDidChangeModelContent(() => {
        const content = this.editor.getValue()
        this.pushEvent('editor_content_changed', { content })
      })

      // Cursor position changes
      this.editor.onDidChangeCursorPosition((e) => {
        const position = e.position
        this.pushEvent('cursor_position_changed', {
          line: position.lineNumber,
          column: position.column
        })
      })

      // Save command (Cmd/Ctrl + S)
      this.editor.addCommand(2048 + 49, () => { // Monaco.KeyMod.CtrlCmd + Monaco.KeyCode.KeyS
        const content = this.editor.getValue()
        this.pushEvent('save_file', { content })
      })

      // Format command (Shift + Alt + F)
      this.editor.addCommand(1024 + 512 + 36, () => { // Shift + Alt + F
        this.editor.getAction('editor.action.formatDocument').run()
      })

      // AI search command (Cmd/Ctrl + Shift + F)
      this.editor.addCommand(2048 + 1024 + 36, () => {
        this.triggerAISearch()
      })

      // Semantic navigation (Cmd/Ctrl + .)
      this.editor.addCommand(2048 + 84, () => {
        this.triggerSemanticNavigation()
      })

      // Show references (Shift + F12)
      this.editor.addCommand(1024 + 70, () => {
        this.showReferences()
      })
    },

    initializeLangLSP() {
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

      monaco.editor.setModelMarkers(this.editor.getModel(), 'lang-lsp', markers)
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

export default LspEditorHooks
