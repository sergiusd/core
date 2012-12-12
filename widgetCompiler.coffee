define [
  'underscore'
  'dustjs-linkedin'
  'cord!configPaths'
  'fs'
], (_, dust, configPaths, fs) ->

  class WidgetCompiler

    structure: {}

    _extend: null
    _widgets: null
    _widgetsByName: null

    _extendPhaseFinished: false

    registerWidget: (widget, name) ->
      if not @_widgets[widget.ctx.id]?
        wdt =
          uid: widget.ctx.id
          path: widget.getPath()
          placeholders: {}
        if name?
          wdt.name = name
          @_widgetsByName[name] = wdt.uid
        @_widgets[widget.ctx.id] = wdt
      @_widgets[widget.ctx.id]


    reset: (ownerWidget) ->
      ###
      Resets compiler's state
      ###

      @_extendPhaseFinished = false
      @_extend = null
      @_widgets = {}
      @_widgetsByName = {}

      ownerInfo = @registerWidget ownerWidget

      @structure =
        ownerWidget: ownerInfo.uid
        extend: @_extend
        widgets: @_widgets
        widgetsByName: @_widgetsByName


    addExtendCall: (widget, params) ->
      if @_extendPhaseFinished
        throw "'#extend' appeared in wrong place (extending widget #{ widget.constructor.name })!"
      if @_extend?
        throw "Only one '#extend' is allowed per template (#{ widget.constructor.name })!"

      widgetRef = @registerWidget widget, params.name

      cleanParams = _.clone params
      delete cleanParams.type
      delete cleanParams.name

      @_extend =
        widget: widgetRef.uid
        params: cleanParams
      @_extend.name = params.name if params.name

      @structure.extend = @_extend


    addPlaceholderContent: (surroundingWidget, placeholderName, widget, params, timeoutTemplateName) ->
      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget, params.name

      swRef.placeholders[placeholderName] ?= []

      cleanParams = _.clone params
      delete cleanParams.type
      delete cleanParams.placeholder
      delete cleanParams.name
      delete cleanParams.class
      delete cleanParams.timeout

      info =
        widget: widgetRef.uid
        params: cleanParams
      info.class = params.class if params.class
      info.name = params.name if params.name
      info.timeout = parseInt(params.timeout) if params.timeout
      info.timeoutTemplate = timeoutTemplateName if timeoutTemplateName?

      swRef.placeholders[placeholderName].push info



    addPlaceholderInline: (surroundingWidget, placeholderName, widget, templateName, name, tag, cls) ->
      @extendPhaseFinished = true

      swRef = @registerWidget surroundingWidget
      widgetRef = @registerWidget widget

      swRef.placeholders[placeholderName] ?= []
      swRef.placeholders[placeholderName].push
        inline: widgetRef.uid
        template: templateName
        name: name
        tag: tag
        class: cls


    getStructureCode: (compact = true) ->
      if @structure.widgets? and Object.keys(@structure.widgets).length > 1
        res = @structure
      else
        res = {}
      if compact
        JSON.stringify res
      else
        JSON.stringify res, null, 2

    printStructure: ->
      console.log @getStructureCode false


    extractBodiesAsStringList: (compiledSource) ->
      ###
      Divides full compiled source of the template into substrings of individual body function strings
      This function is needed while composing inline's sub-template file

      @return Object(String, String) key-value pairs of function names and corresponding function definition string
      ###
      startIdx = compiledSource.indexOf 'function body_0(chk,ctx){return chk'
      endIdx = compiledSource.lastIndexOf 'return body_0;})();'
      bodiesPart = compiledSource.substr startIdx, endIdx - startIdx
      result = {}
      startIdx = 0
      bodyId = 0
      while startIdx != -1
        endIdx = bodiesPart.indexOf "function body_#{ bodyId + 1 }(chk,ctx){return chk"
        len = if endIdx == -1 then compiledSource.length else endIdx - startIdx
        result['body_'+bodyId] = bodiesPart.substr startIdx, len
        bodyId++
        startIdx = endIdx
      result

    bodyRe: /(body_[0-9]+)/g
    saveBodyTemplate: (bodyFn, compiledSource, tmplPath) ->

      bodyStringList = null
      collectBodies = (name, bodyString, bodies = {}) =>
        bodies[name] = bodyString
        matchBodies = bodyString.match @bodyRe
        for depName in matchBodies
          if not bodies[depName]?
            bodies[depName] = bodyStringList[depName]
            collectBodies depName, bodyStringList[depName], bodies
        bodies

      # todo: detect bundles or vendor dir correctly
      tmplFullPath = "./#{ configPaths.PUBLIC_PREFIX }/bundles/#{ tmplPath }"

      bodyFnName = bodyFn.name
      bodyStringList = @extractBodiesAsStringList compiledSource
      bodyList = collectBodies bodyFnName, bodyFn.toString()

      tmplString = "(function(){dust.register(\"#{ tmplPath }\", #{ bodyFnName }); " \
                 + "#{ _.values(bodyList).join '' }; return #{ bodyFnName };})();"

      fs.writeFile tmplFullPath, tmplString, (err)->
        if err then throw err
        console.log "template saved #{ tmplFullPath }"



  #
  # Preventing loading of partials during widget compilation
  #
  dust.onLoad = (tmplPath, callback) ->
    dust.cache[tmplPath] = ''
    callback null, ''

  new WidgetCompiler
