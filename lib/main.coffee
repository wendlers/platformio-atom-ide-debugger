{CompositeDisposable, Emitter} = require 'atom'
GDB = require './mi/gdb'
DebugPanelView = require './debug-panel-view'
StatusView = require './status-view'
Resizable = require './resizable'
GdbCliView = require './gdb-cli-view'
EditorIntegration = require './editor-integration'

module.exports = PlatformIOIDEDebugger =
    subscriptions: null
    gdb: null

    activate: (state) ->
        @provider = new Emitter()
        @provider.stop = @stop.bind this
        @provider.debug = @debug.bind this

        @panelVisible = state.panelVisible
        @panelVisible ?= true
        @cliVisible = state.cliVisible
        @cliSize = state.cliSize
        @panelSize = state.panelSize

    debug: (config) ->
        @gdb = new GDB()
        @statusBarTile = @statusBar?.addLeftTile
            item: new StatusView(@gdb)
            priority: 1000
        @cliPanel = atom.workspace.addBottomPanel
            item: new Resizable 'top', @cliSize or 150, new GdbCliView(@gdb)
            visible: false
        @panel = atom.workspace.addRightPanel
            item: new Resizable 'left', @panelSize or 300, new DebugPanelView(@gdb)
            visible: false

        @subscriptions = new CompositeDisposable
        @subscriptions.add atom.commands.add 'atom-workspace',
            'platformio-ide-debugger:disconnect': => @deactivate()
            'platformio-ide-debugger:continue': => @cmdWrap => @gdb.exec.continue()
            'platformio-ide-debugger:interrupt': => @cmdWrap => @gdb.exec.interrupt()
            'platformio-ide-debugger:next': => @cmdWrap => @gdb.exec.next()
            'platformio-ide-debugger:step': => @cmdWrap => @gdb.exec.step()
            'platformio-ide-debugger:finish': => @cmdWrap => @gdb.exec.finish()
            'platformio-ide-debugger:toggle-panel': => @toggle(@panel, 'panelVisible')
            'platformio-ide-debugger:toggle-cli': => @toggle(@cliPanel, 'cliVisible')

        @editorIntegration = new EditorIntegration(@gdb)

        @gdb.connect(config.gdb_executable)
        .then =>
            @gdb.set 'confirm', 'off'
        .then =>
            @gdb.setCwd atom.project.getPaths()[0]
        .then =>
            @gdb.setFile config.path
        .then =>
            Promise.all(@gdb.send_cli cmd for cmd in config.gdb_commands)
        .then =>
            if @panelVisible then @panel.show()
            if @cliVisible then @cliPanel.show()
        .then =>
            @gdb.exec.continue()
        .catch (err) =>
            x = atom.notifications.addError 'Error launching GDB',
                description: err.toString()

    cmdWrap: (cmd) ->
        cmd()
            .catch (err) ->
                atom.notifications.addError err.toString()

    toggle: (panel, visibleFlag) ->
      if panel.isVisible()
        panel.hide()
      else
        panel.show()
      this[visibleFlag] = panel.isVisible()

    stop: ->
        @gdb?.disconnect()
        @panelSize = @panel?.getItem().size()
        @cliSize = @cliPanel?.getItem().size()
        @editorIntegration?.destroy()
        @panel?.destroy()
        @cliPanel?.destroy()
        @statusBarTile?.destroy()
        @subscriptions?.dispose()
        if @gdb
            @gdb = null
            @provider.emit 'stop'

    deactivate: ->
        @stop()

    consumeStatusBar: (statusBar) ->
        @statusBar = statusBar

    serialize: ->
        panelVisible: @panelVisible
        cliVisible: @cliVisible
        panelSize: @panel?.getItem().size()
        cliSize: @cliPanel?.getItem().size()

    provideDebugger: ->
    		return @provider