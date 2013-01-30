define [
  'cord!Module'
  'cord!Collection'
  'cord!Model'
  'underscore'
  'monologue' + (if document? then '' else '.js')
], (Module, Collection, Model, _, Monologue) ->

  class ModelRepo extends Module
    @include Monologue.prototype

    model: Model

    _collections: null

    restResource: ''

    fieldTags: null


    constructor: (@container) ->
      throw new Error("'model' property should be set for the repository!") if not @model?
      @_collections = {}


    createCollection: (options) ->
      ###
      Just creates, registers and returns a new collection instance of existing collection if there is already
       a registered collection with the same options.
      @param Object options
      @return Collection
      ###
      name = Collection.generateName(options)
      if @_collections[name]?
        collection = @_collections[name]
      else
        collection = new Collection(this, name, options)
        @_registerCollection(name, collection)
      collection


    buildCollection: (options, syncMode, callback) ->
      ###
      Creates, syncs and returns in callback a new collection of this model type by the given options.
       If collection with the same options is already registered than this collection is returned
       instead of creating the new one.

      @see Collection::constructor()

      @param Object options should contain options accepted by collection constructor
      @param (optional)String syncMode desired sync and return mode, defaults to :sync
      @param Function(Collection) callback
      @return Collection
      ###

      if _.isFunction(syncMode)
        callback = syncMode
        syncMode = ':sync'

      collection = @createCollection(options)
      collection.sync(syncMode, callback)
      collection


    buildSingleModel: (id, fields, syncMode, callback) ->
      ###
      Creates and syncs single-model collection by id and field list. In callback returns resulting model.
       Method returns single-model collection.

      :now sync mode is not available here since we need to return the resulting model.

      @param Integer id
      @param Array[String] fields list of fields names for the collection
      @param (optional)String syncMode desired sync and return mode, default to :cache
      @param Function(Model) callback
      @return Collection
      ###
      if _.isFunction(syncMode)
        callback = syncMode
        syncMode = ':cache'

      options =
        id: id
        fields: fields

      collection = @createCollection(options)
      collection.sync syncMode, ->
        callback(collection.get(id))
      collection


    getCollection: (name, returnMode, callback) ->
      ###
      Returns registered collection by name. Returns collection immediately anyway regardless of
       that given in returnMode and callback. If returnMode is given than callback is required and called
       according to the returnMode value. If only callback is given, default returnMode is :now.

      @param String name collection's unique (in the scope of the repository) registered name
      @param (optional)String returnMode defines - when callback should be called
      @param (optional)Function(Collection) callback function with the resulting collection as an argument
                                                     to be called when returnMode decides
      ###
      if @_collections[name]?
        if _.isFunction(returnMode)
          callback = returnMode
          returnMode = ':now'
        else
          returnMode or= ':now'

        collection = @_collections[name]

        if returnMode == ':now'
          callback?(collection)
        else if callback?
          collection.sync(returnMode, callback)
        else
          throw new Error("Callback can be omitted only in case of :now return mode!")

        collection
      else
        throw new Error("There is no registered collection with name '#{ name }'!")


    _registerCollection: (name, collection) ->
      ###
      Validates and registers the given collection
      ###
      if @_collections[name]?
        throw new Error("Collection with name '#{ name }' is already registered in #{ @constructor.name }!")
      if not (collection instanceof Collection)
        throw new Error("Collection should be inherited from the base Collection class!")

      @_collections[name] = collection


    _fieldHasTag: (fieldName, tag) ->
      @fieldTags[fieldName]? and _.isArray(@fieldTags[fieldName]) and @fieldTags[fieldName].indexOf(tag) != -1


    # serialization related:

    toJSON: ->
      @_collections


    setCollections: (collections) ->
      for name, info of collections
        collection = Collection.fromJSON(this, name, info)
        @_registerCollection(name, collection)


    # REST related

    query: (params, callback) ->
      @container.eval 'api', (api) =>
        api.get @_buildApiRequestUrl(params), (response) =>
          result = []
          if _.isArray(response)
            result.push(new @model(item)) for item in response
          else
            result.push(new @model(response))
          callback(result)


    _buildApiRequestUrl: (params) ->
      #apiRequestUrl = 'discuss/?_sortby=-timeUpdated&_page=1&_pagesize=50&_fields=owner.id,subject,content&_calc=commentsStat,accessRights'
      #apiRequestUrl = 'discuss/' + talkId + '/?_fields=subject,content,timeCreated,owner.id,userCreated.employee.name,userCreated.employee.smallPhoto,participants.employee.id,attaches&_calc=accessRights'
      urlParams = []
      if not params.id?
        urlParams.push("_filter=#{ params.filterId }") if params.filterId?
        urlParams.push("_sortby=#{ params.orderBy }") if params.orderBy?
        urlParams.push("_page=#{ params.page }") if params.page?
        urlParams.push("_pagesize=#{ params.pageSize }") if params.pageSize?

      commonFields = []
      calcFields = []
      for field in params.fields
        if @_fieldHasTag(field, ':backendCalc')
          calcFields.push(field)
        else
          commonFields.push(field)
      urlParams.push("_fields=#{ commonFields.join(',') }")
      urlParams.push("_calc=#{ calcFields.join(',') }") if calcFields.length > 0

      @restResource + (if params.id? then ('/' + params.id) else '') + '/?' + urlParams.join('&')


    save: (models...) ->
      ###
      Persists list of given models to the backend
      ###
      for model in models
        do (model) =>
          @container.eval 'api', (api) =>
            @emit 'change', model
            api.put @restResource + '/' + model.id, model.getChangedFields(), (response, error) =>
              if error
                @emit 'error', error
              else
                model.resetChangedFields()
                @emit 'sync', model


    debug: (method) ->
      ###
      Return identification string of the current repository for debug purposes
      @param (optional) String method include optional "::method" suffix to the result
      @return String
      ###
      methodStr = if method? then "::#{ method }" else ''
      "#{ @constructor.name }#{ methodStr }"
