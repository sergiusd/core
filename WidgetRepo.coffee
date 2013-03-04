define [
  'cord!Api'
  'cord!Collection'
  'cord!Context'
  'cord!deferAggregator'
  'cord!Model'
  'cord!ModelRepo'
  'cord!utils/Future'
  'postal'
  'underscore'
], (Api, Collection, Context, deferAggregator, Model, ModelRepo, Future, postal, _) ->

  class WidgetRepo
    widgets: null
    rootWidget: null

    serviceContainer: null
    request: null
    response: null

    _loadingCount: 0
    _initEnd: false
    _widgetOrder: null
    _pushBindings: null

    # list of widgets which build main hierarchy of widget's via #extend template calls
    # begins from the most specific widget (leaf) and ends with most common (root) which doesn't extend another widget
    _currentExtendList: null
    # temporary list of new widgets which are meant to replace several widgets at the beginnign of extend list during
    # page switching process (processing new route)
    _newExtendList: null


    constructor: ->
      @widgets = {}
      @_widgetOrder = []
      @_pushBindings = {}
      @_currentExtendList = []
      @_newExtendList = []


    setServiceContainer: (serviceContainer) =>
      @serviceContainer = serviceContainer


    getServiceContainer: =>
      @serviceContainer


    setRequest: (request) =>
      @request = request


    getRequest: =>
      @request


    setResponse: (response) =>
      @response = response


    getResponse: =>
      @response


    createWidget: () ->
      ###
      Main widget factory.
      All widgets should be created through this call.

      @param String path canonical path of the widget
      @param (optional)String contextBundle calling context bundle to expand relative widget paths
      @param Callback(Widget) callback callback in which resulting widget will be passed as argument
      ###

      # normalizing arguments
      path = arguments[0]
      if _.isFunction arguments[1]
        callback = arguments[1]
        contextBundle = null
      else if _.isFunction arguments[2]
        callback = arguments[2]
        contextBundle = arguments[1]
      else
        throw "Callback should be passed to the widget factory!"

      bundleSpec = if contextBundle then "@#{ contextBundle }" else ''

      require ["cord-w!#{ path }#{ bundleSpec }"], (WidgetClass) =>
        widget = new WidgetClass
          repo: this
          serviceContainer: @serviceContainer

        if widget.getPath() == '/cord/core//Switcher' and contextBundle?
          widget._contextBundle = contextBundle

        @widgets[widget.ctx.id] =
          widget: widget

        callback widget

#      , (err) ->
#        failedId = if err.requireModules? then err.requireModules[0] else null
#        console.log failedId
#        console.log err
#        if failedId == "cord-w!#{ path }#{ bundleSpec }"
#          console.log "found"
#          requirejs.undef failedId
#          require [failedId], ->
#            null
#          , (err) ->
#            console.log "error again", err


    dropWidget: (id) ->
      if @widgets[id]?
#        console.log "drop widget #{ @widgets[id].widget.constructor.name }(#{id})"
        @widgets[id].widget.clean()
        @widgets[id].widget = null
        delete @widgets[id]
      else
        throw "Try to drop unknown widget with id = #{ id }"


    registerParent: (childWidget, parentWidget) ->
      ###
      Register child-parent relationship in the repo
      ###
      info = @widgets[childWidget.ctx.id]
      if info.parent? and info.parent != parentWidget
        info.parent.unbindChild childWidget
      info.parent = parentWidget


    setRootWidget: (widget) ->
      info = @widgets[widget.ctx.id]
      if info.parent?
        info.parent.unbindChild widget
      info.parent = null
      @rootWidget = widget


    _unserializeModelBindings: (serializedBindings, callback) ->
      ###
      Simply replaces serialized links to models and collections to the actual restored instances of those
       models and collections in the given map.
      @param Object serializedBindings
      @param Function(Object) callback "result" callback with the converted map
      ###
      promise = new Future
      result = {}
      for key, value of serializedBindings
        if Collection.isSerializedLink(value)
          promise.fork()
          Collection.unserializeLink value, @serviceContainer, (collection) ->
            result[key] = model: collection
            promise.resolve()
        else if Model.isSerializedLink(value)
          promise.fork()
          Model.unserializeLink value, @serviceContainer, (model) ->
            result[key] = model: model
            promise.resolve()

      promise.done ->
        callback(result)


    initRepo: (repoServiceName, collections, promise) ->
      ###
      Helper method used in generated initialization code to restore models came from server in the browser
      @browser-only
      @param String repoServiceName name of the model repository service name
      @param Object collections list of serialized registered collections keyed with their names
      @param Future promise a promise that must be resolved when collections are initialized
      ###
      @serviceContainer.eval repoServiceName, (repo) ->
        repo.setCollections(collections)
        promise.resolve()


    getModelsInitCode: ->
      ###
      Generates code for passing and initialing of all model repositories from server-side into browser.
      Loops through service container to find all repository services.
      ###
      result = []
      for key, val of @serviceContainer
        if val? and key.substr(0, 9) == '_box_val_' and val.isReady and val.val instanceof ModelRepo
          result.push("wi.initRepo('#{ key.substr(9) }', #{ JSON.stringify(val.val) }, p.fork());")
      result.join("\n")


    getTemplateCode: ->
      """
      <script data-main="/bundles/cord/core/browserInit" src="/vendor/requirejs/require.js"></script>
      <script>
          function cordcorewidgetinitializerbrowser(wi) {
            requirejs(['cord!utils/Future'], function(Future) {
              p = new Future();
              #{ @getModelsInitCode() }
              p.done(function() {
                #{ @rootWidget.getInitCode() }
                wi.endInit();
              });
            });
          };
      </script>
      <script>
        var global = {
          CONFIG: #{ JSON.stringify(global.CONFIG_CLIENT) }
        };
      </script>
      """

    getTemplateCss: ->
      """
        #{ @rootWidget.getInitCss() }
      """

    endInit: ->
      @_initEnd = true


    init: (widgetPath, ctx, namedChilds, childBindings, modelBindings, isExtended, parentId) ->
      ###
      Restores widget's state after transferring from server to browser (initial html-page loading)
      @browser-only
      ###

      @_loadingCount++
      @_widgetOrder.push ctx.id

      for widgetId, bindingMap of childBindings
        @_pushBindings[widgetId] = {}
        for ctxName, paramName of bindingMap
          @_pushBindings[widgetId][ctxName] = paramName

      callbackPromise = new Future

      require ["cord-w!#{ widgetPath }"],       callbackPromise.callback()
      Context.fromJSON ctx, @serviceContainer,  callbackPromise.callback()
      @_unserializeModelBindings modelBindings, callbackPromise.callback()

      callbackPromise.done (WidgetClass, ctx, modelBindings) =>

        widget = new WidgetClass
          context: ctx
          repo: this
          serviceContainer: @serviceContainer
          modelBindings: modelBindings
          extended: isExtended

        if @_pushBindings[ctx.id]?
          for ctxName, paramName of @_pushBindings[ctx.id]
            @subscribePushBinding parentId, ctxName, widget, paramName

        @widgets[ctx.id] =
          widget: widget
          namedChilds: namedChilds

        completeFunc = =>
          @_loadingCount--
          if @_loadingCount == 0 and @_initEnd
            @setupBindings()

        if parentId?
          retryCounter = 0
          timeoutFunc = =>
            if @widgets[parentId]?
              @widgets[parentId].widget.registerChild widget, @widgets[parentId].namedChilds[ctx.id] ? null
              if widgetPath == '/cord/core//Switcher'
                widget._contextBundle = @widgets[parentId].widget.getBundle()
              completeFunc()
            else if retryCounter < 10
              console.log "widget load timeout activated", retryCounter
              setTimeout timeoutFunc, retryCounter++
            else
              throw "Try to use uninitialized parent widget with id = #{ parentId } - couldn't load parent widget within timeout!"
          timeoutFunc()
        else
          @rootWidget = widget
          completeFunc()


    setupBindings: ->
      # organizing extendList in right order
      for id in @_widgetOrder
        widget = @widgets[id].widget
        if widget._isExtended
          @_currentExtendList.push widget
      # initializing DOM bindings of widgets in reverse order (leafs of widget tree - first)
      @bind(id) for id in @_widgetOrder.reverse()


    bind: (widgetId) ->
      if @widgets[widgetId]?
        w = @widgets[widgetId].widget
        w.bindChildEvents()
        w.bindModelEvents()
        w.initBehaviour()
      else
        throw "Try to use uninitialized widget with id = #{ widgetId }"


    getById: (id) ->
      ###
      Returns widget with the given id if it is exists.
      Throws exception otherwise.
      @param String id widget id
      @return Widget
      ###

      if @widgets[id]?
        @widgets[id].widget
      else
        throw "Try to get uninitialized widget with id = #{ id }"


    #
    # Subscribes child widget to the parent widget's context variable change event
    #
    # @param String parentWidgetId id of the parent widget
    # @param String ctxName name of parent's context variable whose changes we are listening to
    # @param Widget childWidget subscribing child widget object
    # @param String paramName child widget's default action input param name which should be set to the context variable
    #                         value
    # @return postal subscription object
    #
    subscribePushBinding: (parentWidgetId, ctxName, childWidget, paramName) ->
      subscription = postal.subscribe
        topic: "widget.#{ parentWidgetId }.change.#{ ctxName }"
        callback: (data, envelope) ->
          if not childWidget.isSentenced()
            params = {}

            # param with name "params" is a special case and we should expand the value as key-value pairs
            # of widget's params
            if paramName == 'params'
              if _.isObject data.value
                for subName, subValue of data.value
                  params[subName] = subValue
              else
                # todo: warning?
            else
              params[paramName] = data.value

            console.log "(wi) push binding event of parent (#{ envelope.topic }) for child widget #{ childWidget.debug(paramName) } -> #{ data.value }"
            deferAggregator.fireAction childWidget, 'default', params
      childWidget.addSubscription subscription
      subscription


    injectWidget: (widgetPath, action, params) ->
      extendWidget = @findAndCutMatchingExtendWidget widgetPath
#      console.log "injectWidget -> current root widget = #{ @rootWidget.constructor.name }"
      _oldRootWidget = @rootWidget
      if extendWidget?
        if _oldRootWidget != extendWidget
          @setRootWidget extendWidget
          extendWidget.getStructTemplate (tmpl) =>
            tmpl.assignWidget tmpl.struct.ownerWidget, extendWidget
            tmpl.replacePlaceholders tmpl.struct.ownerWidget, extendWidget.ctx[':placeholders'], =>
              extendWidget.fireAction action, params
              @dropWidget _oldRootWidget.ctx.id
              @rootWidget.browserInit extendWidget
        else
          extendWidget.fireAction action, params
          #throw 'not supported yet!'
      else
        @createWidget widgetPath, (widget) =>
          @setRootWidget widget
          widget.injectAction action, params, (commonBaseWidget) =>
            @dropWidget _oldRootWidget.ctx.id unless commonBaseWidget == _oldRootWidget
            @rootWidget.browserInit commonBaseWidget


    findAndCutMatchingExtendWidget: (widgetPath) ->
      ###
      Finds common point and reorganizes extend list.
      Finds if the target widget is already somewhere in the current extend list.
      If there is - removes all widgets before it from extend list and adds new ones (if there are) instead of them.
      ###
      result = null
      counter = 0
      for extendWidget in @_currentExtendList
        if widgetPath == extendWidget.getPath()
          # removing all extend tree below found widget
          @_currentExtendList.shift() while counter--
          # ... and prepending extend tree with the new widgets
          @_newExtendList.reverse()
          @_currentExtendList.unshift(wdt) for wdt in @_newExtendList
          @_newExtendList = []

          result = extendWidget
          break
        counter++
      result


    registerNewExtendWidget: (widget) ->
      @_newExtendList.push widget


    replaceExtendTree: ->
      @_currentExtendList = @_newExtendList
      @_newExtendList = []
