define [
  'jquery'
  'postal'
], ($, postal) ->

  class Behaviour

    constructor: (widget) ->
      @_widgetSubscriptions = []
      @widget = widget
      @id = widget.ctx.id

      @el  = $('#' + @widget.ctx.id ) unless @el
      @el  = $(@el)
      @$el = @el

      @el.addClass(@cssClass) if @cssClass
      @el.attr(@attributes) if @attributes

      @events       = @constructor.events unless @events
      @widgetEvents = @constructor.widgetEvents unless @widgetEvents
      @elements     = @constructor.elements unless @elements

      @delegateEvents(@events)          if @events
      @initWidgetEvents(@widgetEvents)  if @widgetEvents
      @refreshElements()                if @elements

    $: (selector) ->
      $(selector, @el)

    delegateEvents: (events) ->
      for key, method of events

        method     = @_getMethod method
        match      = key.match(/^(\S+)\s*(.*)$/)
        eventName  = match[1]
        selector   = match[2]

        if selector is ''
          @el.on(eventName, method)
        else
          @el.on(eventName, selector, method)

    initWidgetEvents: (events) ->
      for fieldName, method of events
        subscription = postal.subscribe
          topic: "widget.#{ @id }.change.#{ fieldName }"
          callback: @_getMethod method
        @_widgetSubscriptions.push subscription

    _getMethod: (method) ->
      if typeof(method) is 'function'
      # Always return true from event handlers
        method = do (method) => =>
          method.apply(this, arguments)
          true
      else
        unless @[method]
          throw new Error("#{method} doesn't exist")

        method = do (method) => =>
          @[method].apply(this, arguments)
          true
      method

    refreshElements: ->
      for key, value of @elements
        @[value] = @$(key)

    clean: ->
      subscription.unsubscribe() for subscription in @_widgetSubscriptions
      @_widgetSubscriptions = []
      @el.off()#.remove()

    html: (element) ->
      @el.html(element.el or element)
      @refreshElements()
      @el

    append: (elements...) ->
      elements = (e.el or e for e in elements)
      @el.append(elements...)
      @refreshElements()
      @el

    appendTo: (element) ->
      @el.appendTo(element.el or element)
      @refreshElements()
      @el

    prepend: (elements...) ->
      elements = (e.el or e for e in elements)
      @el.prepend(elements...)
      @refreshElements()
      @el

    replace: (element) ->
      [previous, @el] = [@el, $(element.el or element)]
      previous.replaceWith(@el)
      @delegateEvents(@events) if @events
      @refreshElements()
      @el

    render: ->
      @widget.renderTemplate (err, output) =>
        if err then throw err
        $('#'+@widget.ctx.id).html output
        @widget.browserInit()