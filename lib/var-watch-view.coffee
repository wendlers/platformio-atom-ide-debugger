{View, $} = require 'atom-space-pen-views'

class VarItemView extends View
    initialize: (@gdb, {@name}) ->

    @content: (gdb, item) ->
        if item.numchild > 0 then cls = 'collapsable'
        @tr name: item.name, parent: item.parent, class: cls, =>
            @td class: 'expand-column', click: 'toggleCollapse', =>
                @span item.exp,
                    style: "margin-left: #{item.nest}em"
            if +item.numchild == 0
                @td =>
                    @input
                        id: 'wp-toggle'
                        class: 'input-toggle'
                        type: 'checkbox'
                        click: '_toggleWP'
            else
                @td()
            @td item.value, id: 'value'
            @td click: '_remove', =>
                @span class: 'delete'

    _hideTree: (id) ->
        children = $(this).parent().find("tr[parent='#{id}']")
        children.hide()
        for child in children
            @_hideTree child.getAttribute('name')

    _showTree: (id) ->
        children = $(this).parent().find("tr[parent='#{id}']")
        children.show()
        for child in children
            $child = $(child)
            if not $child.hasClass 'collapsed'
                @_showTree $child.attr 'name'

    _remove: ->
        @gdb.varobj.remove @name

    _toggleWP: (ev) ->
        if ev.target.checked
            @gdb.varobj.getExpression @name
                .then (expr) =>
                    @gdb.breaks.insertWatch expr
                .then (wp) =>
                    @attr 'wp', wp
                    @wp = wp
                .catch (err) =>
                    atom.notifications.addError err.toString()
                    ev.target.checked = false
        else
            @gdb.breaks.remove @wp
                .then =>
                    @attr 'wp', null
                    delete @wp
                .catch (err) =>
                    atom.notifications.addError err.toString()
                    ev.target.checked = true

    toggleCollapse: ->
        if @hasClass 'collapsable'
            @toggleClass 'collapsed'
            if @hasClass 'collapsed'
                @_hideTree @name
            else
                @_showTree @name

module.exports =
class VarWatchView extends View
    initialize: (@gdb) ->
        @varviews = {}
        @gdb.varobj.observe @_varObserver.bind(this)
        @gdb.breaks.observe @_breakObserver.bind(this)
        @gdb.exec.onStateChanged @_execStateChanged.bind(this)

    @content: (gdb) ->
        @div class: 'var-watch-view', =>
            @div class: 'block', =>
                @label 'Add expression to watch:'
                @input
                    class: 'input-textarea native-key-bindings'
                    keypress: '_addExpr'
                    outlet: 'expr'
            @div class: 'block', =>
                @div class: 'error-message', outlet: 'error'
            @div class: 'block', =>
                @div class: 'tree-view', =>
                    @table outlet: 'table', =>
                        @tr =>
                            @th 'Expression'
                            @th 'WP', style: 'text-align: center'
                            @th 'Value'

    getTitle: -> 'Watch Variables'

    _addExpr: (ev) ->
        if ev.charCode != 13 then return
        @gdb.varobj.add @expr.val()
            .then =>
                @error.text ''
            .catch (err) =>
                @error.text err
        @expr.val ''

    _findLast: (name) ->
        children = @find("tr[parent='#{name}']")
        if children.length
            nextName = children[children.length-1].getAttribute('name')
            return @_findLast nextName
        return name

    _addItem: (id, val) ->
        view = @varviews[id] = new VarItemView(@gdb, val)
        if not val.parent?
            return @table.append view
        lastName = @_findLast val.parent
        view.insertAfter @varviews[lastName]

    _varObserver: (id, val) ->
        view = @varviews[id]
        if not view? and val?
            return @_addItem id, val
        if not val?
            view.remove()
            delete @varviews[id]
            return
        v = view.find('#value')
        v.text(val.value)
        v.addClass 'changed'

    _breakObserver: (id, bkpt) ->
        if not bkpt?
            m = @find("tr[wp='#{id}']")
            m.attr 'wp', null
            cb = m.find("input#wp-toggle")
            cb.attr 'checked', false

    _execStateChanged: ([state, frame]) ->
        if state == 'RUNNING'
            v = @find('#value.changed')
            v.removeClass 'changed'